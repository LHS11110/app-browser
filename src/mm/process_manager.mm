#include "process_manager.h"
#include "app.h"

#import <Cocoa/Cocoa.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>
#include <chrono>
#include <ctime>
#include <iomanip>
#include <sstream>

namespace app_browser {

namespace {

std::string GetCurrentTimestamp() {
  auto now = std::chrono::system_clock::now();
  auto in_time_t = std::chrono::system_clock::to_time_t(now);
  std::stringstream ss;
  ss << std::put_time(std::localtime(&in_time_t), "%H:%M:%S");
  return ss.str();
}

std::string EscapeJsonString(const std::string& input) {
  std::ostringstream ss;
  for (char c : input) {
    switch (c) {
      case '"': ss << "\\\""; break;
      case '\\': ss << "\\\\"; break;
      case '\b': ss << "\\b"; break;
      case '\f': ss << "\\f"; break;
      case '\n': ss << "\\n"; break;
      case '\r': ss << "\\r"; break;
      case '\t': ss << "\\t"; break;
      default:
        if ('\x00' <= c && c <= '\x1f') {
          ss << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (int)c;
        } else {
          ss << c;
        }
    }
  }
  return ss.str();
}

NSString* GetSessionFilePath() {
  NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString* appDataDir = [appSupport stringByAppendingPathComponent:@"AppBrowser"];
  return [appDataDir stringByAppendingPathComponent:@"session_apps.json"];
}

}  // namespace

ProcessManager::ProcessManager() = default;

ProcessManager::~ProcessManager() {
  TerminateAll();
}

ProcessManager* ProcessManager::GetInstance() {
  static ProcessManager instance;
  return &instance;
}

static NSMutableArray<NSTask*>* g_activeTasks = nil;

int ProcessManager::SpawnChild(const std::string& url, bool visible) {
  int new_pid = -1;
  {
    std::lock_guard<std::mutex> lock(mutex_);

    @autoreleasepool {
      if (!g_activeTasks) {
        g_activeTasks = [[NSMutableArray alloc] init];
      }

      NSURL* executableURL = [[NSBundle mainBundle] executableURL];
      if (!executableURL) {
        return -1;
      }

      NSString* urlNs = [NSString stringWithUTF8String:url.c_str()];
      if (!urlNs) {
        urlNs = [NSString stringWithCString:url.c_str() encoding:NSISOLatin1StringEncoding];
      }
      NSString* urlArg = [NSString stringWithFormat:@"--url=%@", urlNs];
      NSString* parentPidArg = [NSString stringWithFormat:@"--parent-pid=%d", getpid()];
      NSMutableArray<NSString*>* arguments =
          [NSMutableArray arrayWithObjects:@"--child", urlArg, parentPidArg, nil];
      if (!visible) {
        [arguments addObject:@"--hidden"];
      }

      NSTask* task = [[NSTask alloc] init];
      [task setExecutableURL:executableURL];
      [task setArguments:arguments];

      NSURL* bundleURL = [[NSBundle mainBundle] bundleURL];
      if (bundleURL) {
        [task setCurrentDirectoryURL:bundleURL];
      }

      NSError* error = nil;
      BOOL success = [task launchAndReturnError:&error];
      if (!success || error) {
        NSLog(@"Failed to spawn child process: %@", error);
        return -1;
      }

      pid_t pid = [task processIdentifier];
      if (pid <= 0) {
        return -1;
      }

      [g_activeTasks addObject:task];

      ChildProcessInfo info;
      info.pid = static_cast<int>(pid);
      info.url = url;
      info.title = url;
      info.visible = visible;
      info.start_time = GetCurrentTimestamp();

      processes_.push_back(info);
      new_pid = info.pid;

      if (visible) {
        // Ensure macOS brings newly spawned child browser to the foreground
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
          NSRunningApplication* childApp =
              [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
          if (childApp) {
            [childApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
          }
        });
      } else {
        // If spawned hidden, guarantee it remains hidden
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
          NSRunningApplication* childApp =
              [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
          if (childApp) {
            [childApp hide];
          }
        });
      }
    }
  }

  SaveSession();
  NotifyManagerUI();
  return new_pid;
}

bool ProcessManager::TerminateChild(int pid) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    kill(pid, SIGTERM);

    for (auto it = processes_.begin(); it != processes_.end(); ++it) {
      if (it->pid == pid) {
        processes_.erase(it);
        break;
      }
    }
  }

  SaveSession();
  NotifyManagerUI();
  return true;
}

void ProcessManager::TerminateAll() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& proc : processes_) {
      kill(proc.pid, SIGTERM);
    }
    processes_.clear();

    if (search_child_pid_ > 0) {
      kill(search_child_pid_, SIGTERM);
      search_child_pid_ = -1;
    }

    if (g_activeTasks) {
      for (NSTask* t in g_activeTasks) {
        if ([t isRunning]) {
          [t terminate];
        }
      }
      [g_activeTasks removeAllObjects];
    }
  }

  NotifyManagerUI();
}

bool ProcessManager::FocusChild(int pid) {
  SetChildVisibility(pid, true);
  @autoreleasepool {
    NSRunningApplication* app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app) {
      return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
  }
  return false;
}

void ProcessManager::SetChildVisibility(int pid, bool visible) {
  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& proc : processes_) {
      if (proc.pid == pid) {
        if (proc.visible != visible) {
          proc.visible = visible;
          changed = true;
        }
        break;
      }
    }
  }

  @autoreleasepool {
    NSRunningApplication* app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app) {
      if (!visible) {
        [app hide];
      } else {
        [app unhide];
        [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      }
    }
    SendVisibilityNotificationToChild(pid, visible);
  }

  if (changed) {
    SaveSession();
    NotifyManagerUI();
  }
}

void ProcessManager::SetGroupVisibility(const std::string& group_id, bool visible) {
  std::vector<int> target_pids;
  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& proc : processes_) {
      if (proc.group_id == group_id || (group_id == "default" && proc.group_id.empty())) {
        target_pids.push_back(proc.pid);
        if (proc.visible != visible) {
          proc.visible = visible;
          changed = true;
        }
      }
    }
  }

  for (int pid : target_pids) {
    @autoreleasepool {
      NSRunningApplication* app =
          [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
      if (app) {
        if (!visible) {
          [app hide];
        } else {
          [app unhide];
          [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
      }
      SendVisibilityNotificationToChild(pid, visible);
    }
  }

  if (changed) {
    SaveSession();
    NotifyManagerUI();
  }
}

void ProcessManager::RefreshProcesses() {
  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto it = processes_.begin(); it != processes_.end();) {
      // Check if process still alive
      if (kill(it->pid, 0) != 0) {
        it = processes_.erase(it);
        changed = true;
      } else {
        ++it;
      }
    }

    if (search_child_pid_ > 0 && kill(search_child_pid_, 0) != 0) {
      search_child_pid_ = -1;
    }

    if (g_activeTasks) {
      for (NSInteger i = (NSInteger)[g_activeTasks count] - 1; i >= 0; --i) {
        NSTask* t = g_activeTasks[i];
        if (![t isRunning]) {
          [g_activeTasks removeObjectAtIndex:i];
        }
      }
    }
  }

  if (changed) {
    SaveSession();
    NotifyManagerUI();
  }
}

std::vector<ChildProcessInfo> ProcessManager::GetProcesses() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return processes_;
}

std::string ProcessManager::ToJson() const {
  std::lock_guard<std::mutex> lock(mutex_);
  std::ostringstream ss;
  ss << "{\"parentPid\":" << getpid() << ",\"processes\":[";

  for (size_t i = 0; i < processes_.size(); ++i) {
    const auto& p = processes_[i];
    if (i > 0) ss << ",";
    ss << "{\"pid\":" << p.pid
       << ",\"url\":\"" << EscapeJsonString(p.url) << "\""
       << ",\"title\":\"" << EscapeJsonString(p.title) << "\""
       << ",\"name\":\"" << EscapeJsonString(p.name) << "\""
       << ",\"groupId\":\"" << EscapeJsonString(p.group_id.empty() ? "default" : p.group_id) << "\""
       << ",\"visible\":" << (p.visible ? "true" : "false")
       << ",\"startTime\":\"" << EscapeJsonString(p.start_time) << "\"}";
  }

  ss << "]}";
  return ss.str();
}

void ProcessManager::SetManagerBrowser(CefRefPtr<CefBrowser> browser) {
  manager_browser_ = browser;
}

void ProcessManager::NotifyManagerUI() {
  if (!manager_browser_)
    return;

  std::string json = ToJson();
  std::string script = "if (window.updateProcessList) { window.updateProcessList(" + json + "); }";

  if (auto frame = manager_browser_->GetMainFrame()) {
    frame->ExecuteJavaScript(script, frame->GetURL(), 0);
  }
}

void ProcessManager::SetSearchWindow(CefRefPtr<CefWindow> window) {
  std::lock_guard<std::mutex> lock(mutex_);
  search_window_ = window;
}

void ProcessManager::OnSearchWindowClosed() {
  std::lock_guard<std::mutex> lock(mutex_);
  search_window_ = nullptr;
}

void ProcessManager::SetSearchUrl(const std::string& url) {
  std::lock_guard<std::mutex> lock(mutex_);
  search_url_ = url;
}

void ProcessManager::SetBookmarksWindow(CefRefPtr<CefWindow> window) {
  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_window_ = window;
}

void ProcessManager::OnBookmarksWindowClosed() {
  std::lock_guard<std::mutex> lock(mutex_);
  bookmarks_window_ = nullptr;
}

void ProcessManager::ShowBookmarksWindow() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (bookmarks_window_) {
    PositionWindowAtBottom(bookmarks_window_->GetWindowHandle(), 540, 420, 36);
    bookmarks_window_->Show();
    bookmarks_window_->Activate();
    bookmarks_window_->BringToTop();
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp activateIgnoringOtherApps:YES];
    });
  }
}

void ProcessManager::HideBookmarksWindow() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (bookmarks_window_) {
    bookmarks_window_->Hide();
  }
}

void ProcessManager::CloseAllWindows() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (search_window_) {
    search_window_->Close();
    search_window_ = nullptr;
  }
  if (bookmarks_window_) {
    bookmarks_window_->Close();
    bookmarks_window_ = nullptr;
  }
}

void ProcessManager::ToggleSearchWindow() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!search_window_)
    return;

  if (search_window_->IsVisible()) {
    search_window_->Hide();
  } else {
    search_window_->Show();
    search_window_->Activate();
  }
}

int ProcessManager::SpawnSearchChild() {
  @autoreleasepool {
    if (!g_activeTasks) {
      g_activeTasks = [[NSMutableArray alloc] init];
    }

    NSURL* executableURL = [[NSBundle mainBundle] executableURL];
    if (!executableURL) {
      return -1;
    }

    std::string s_url = search_url_;
    if (s_url.empty()) {
      NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
      NSString* startHtmlPath = [resourcePath stringByAppendingPathComponent:@"web/search/index.html"];
      s_url = std::string("file://") + [startHtmlPath UTF8String];
    }

    NSString* urlNs = [NSString stringWithUTF8String:s_url.c_str()];
    if (!urlNs) {
      urlNs = [NSString stringWithCString:s_url.c_str() encoding:NSISOLatin1StringEncoding];
    }
    NSString* urlArg = [NSString stringWithFormat:@"--url=%@", urlNs];
    NSString* parentPidArg = [NSString stringWithFormat:@"--parent-pid=%d", getpid()];
    NSArray<NSString*>* arguments = @[@"--search", urlArg, parentPidArg];

    NSTask* task = [[NSTask alloc] init];
    [task setExecutableURL:executableURL];
    [task setArguments:arguments];

    NSURL* bundleURL = [[NSBundle mainBundle] bundleURL];
    if (bundleURL) {
      [task setCurrentDirectoryURL:bundleURL];
    }

    NSError* error = nil;
    BOOL success = [task launchAndReturnError:&error];
    if (!success || error) {
      NSLog(@"Failed to spawn child search process: %@", error);
      return -1;
    }

    pid_t pid = [task processIdentifier];
    if (pid <= 0) {
      return -1;
    }

    [g_activeTasks addObject:task];
    search_child_pid_ = static_cast<int>(pid);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
      NSRunningApplication* childApp =
          [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
      if (childApp) {
        [childApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
      }
    });

    return search_child_pid_;
  }
}

void ProcessManager::ShowSearchWindow() {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (search_window_) {
      search_window_->Show();
      search_window_->Activate();
      search_window_->BringToTop();
      dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
      });
      return;
    }

    if (search_child_pid_ > 0 && kill(search_child_pid_, 0) == 0) {
      FocusChild(search_child_pid_);
      return;
    }
  }

  // If search window was closed, spawn a new process for it!
  SpawnSearchChild();
}

void ProcessManager::InitIpc() {
  @autoreleasepool {
    pid_t currentPid = getpid();
    NSString* notifName = [NSString stringWithFormat:@"AppBrowser_Spawn_%d", currentPid];
    [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:notifName
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                  NSString* urlStr = note.userInfo[@"url"];
                  if (urlStr && [urlStr length] > 0) {
                    ProcessManager::GetInstance()->SpawnChild([urlStr UTF8String]);
                  }
                }];

    NSString* urlChangeNotifName = [NSString stringWithFormat:@"AppBrowser_UrlChange_%d", currentPid];
    [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:urlChangeNotifName
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                  NSNumber* pidNum = note.userInfo[@"pid"];
                  NSString* urlStr = note.userInfo[@"url"];
                  NSString* titleStr = note.userInfo[@"title"];
                  if (pidNum && urlStr && [urlStr length] > 0) {
                    int childPid = [pidNum intValue];
                    std::string newUrl = [urlStr UTF8String];
                    std::string newTitle = titleStr ? [titleStr UTF8String] : "";
                    ProcessManager::GetInstance()->UpdateProcessUrl(childPid, newUrl, newTitle);
                  }
                }];
  }
}

void SendSpawnNotificationToParent(int parent_pid, const std::string& target_url) {
  @autoreleasepool {
    NSString* notifName = [NSString stringWithFormat:@"AppBrowser_Spawn_%d", parent_pid];
    NSString* urlNs = [NSString stringWithUTF8String:target_url.c_str()];
    if (!urlNs) {
      urlNs = [NSString stringWithCString:target_url.c_str() encoding:NSISOLatin1StringEncoding];
    }
    NSDictionary* userInfo = @{@"url": urlNs ? urlNs : @""};
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:notifName
                      object:nil
                    userInfo:userInfo
          deliverImmediately:YES];
  }
}

void SendUrlUpdateToParent(int parent_pid, int child_pid, const std::string& target_url, const std::string& title) {
  @autoreleasepool {
    NSString* notifName = [NSString stringWithFormat:@"AppBrowser_UrlChange_%d", parent_pid];
    NSString* urlNs = [NSString stringWithUTF8String:target_url.c_str()];
    if (!urlNs) {
      urlNs = [NSString stringWithCString:target_url.c_str() encoding:NSISOLatin1StringEncoding];
    }
    NSString* titleNs = [NSString stringWithUTF8String:title.c_str()];
    if (!titleNs) {
      titleNs = [NSString stringWithCString:title.c_str() encoding:NSISOLatin1StringEncoding];
    }
    NSDictionary* userInfo = @{
      @"pid": @(child_pid),
      @"url": urlNs ? urlNs : @"",
      @"title": titleNs ? titleNs : @""
    };
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:notifName
                      object:nil
                    userInfo:userInfo
          deliverImmediately:YES];
  }
}

void SendVisibilityNotificationToChild(int child_pid, bool visible) {
  @autoreleasepool {
    NSString* notifName = [NSString stringWithFormat:@"AppBrowser_Visibility_%d", child_pid];
    NSDictionary* userInfo = @{@"visible": @(visible)};
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:notifName
                      object:nil
                    userInfo:userInfo
          deliverImmediately:YES];
  }
}

void RegisterChildVisibilityIpc(CefRefPtr<CefWindow> window) {
  @autoreleasepool {
    pid_t currentPid = getpid();
    NSString* notifName = [NSString stringWithFormat:@"AppBrowser_Visibility_%d", currentPid];
    [[NSDistributedNotificationCenter defaultCenter]
        addObserverForName:notifName
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
                  NSNumber* visibleNum = note.userInfo[@"visible"];
                  BOOL visible = visibleNum ? [visibleNum boolValue] : YES;
                  if (!visible) {
                    if (window) {
                      window->Hide();
                    }
                    [NSApp hide:nil];
                  } else {
                    [NSApp unhideWithoutActivation];
                    if (window) {
                      window->Show();
                      window->BringToTop();
                    }
                    [NSApp activateIgnoringOtherApps:YES];
                  }
                }];
  }
}

void HideCurrentAppProcess(CefRefPtr<CefWindow> window) {
  @autoreleasepool {
    if (window) {
      window->Hide();
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp hide:nil];
    });
  }
}

void ProcessManager::SaveSession() {
  std::vector<ChildProcessInfo> procs_copy;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    procs_copy = processes_;
  }

  @autoreleasepool {
    NSMutableArray* arr = [NSMutableArray array];
    for (const auto& p : procs_copy) {
      if (p.url.empty()) continue;
      NSMutableDictionary* item = [NSMutableDictionary dictionary];
      item[@"url"] = [NSString stringWithUTF8String:p.url.c_str()];
      if (!p.name.empty()) {
        item[@"name"] = [NSString stringWithUTF8String:p.name.c_str()];
      }
      if (!p.group_id.empty()) {
        item[@"groupId"] = [NSString stringWithUTF8String:p.group_id.c_str()];
      }
      item[@"visible"] = @(p.visible);
      [arr addObject:item];
    }

    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:arr
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&error];
    if (data && !error) {
      NSString* path = GetSessionFilePath();
      [data writeToFile:path atomically:YES];
    }
  }
}

void ProcessManager::RestoreSession() {
  @autoreleasepool {
    NSString* path = GetSessionFilePath();
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
      return;
    }

    NSData* data = [NSData dataWithContentsOfFile:path];
    if (!data) return;

    NSError* error = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (!json || ![json isKindOfClass:[NSArray class]] || error) {
      return;
    }

    NSArray* arr = (NSArray*)json;
    for (NSDictionary* item in arr) {
      if (![item isKindOfClass:[NSDictionary class]]) continue;
      NSString* urlNs = item[@"url"];
      if (!urlNs || [urlNs length] == 0) continue;

      std::string url = [urlNs UTF8String];
      std::string name = item[@"name"] ? [item[@"name"] UTF8String] : "";
      std::string groupId = item[@"groupId"] ? [item[@"groupId"] UTF8String] : "default";
      BOOL visible = (item[@"visible"] != nil) ? [item[@"visible"] boolValue] : YES;

      int new_pid = SpawnChild(url, visible);
      if (new_pid > 0) {
        if (!name.empty() || !groupId.empty()) {
          UpdateProcessMeta(new_pid, name, groupId);
        }
        if (!visible) {
          SetChildVisibility(new_pid, false);
        }
      }
    }
  }
}

void ProcessManager::ClearSavedSession() {
  @autoreleasepool {
    NSString* path = GetSessionFilePath();
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
  }
}

void ProcessManager::UpdateProcessMeta(int pid, const std::string& name, const std::string& group_id) {
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& proc : processes_) {
      if (proc.pid == pid) {
        if (!name.empty()) proc.name = name;
        if (!group_id.empty()) proc.group_id = group_id;
        break;
      }
    }
  }
  SaveSession();
}

void ProcessManager::UpdateProcessUrl(int pid, const std::string& url, const std::string& title) {
  bool changed = false;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& proc : processes_) {
      if (proc.pid == pid) {
        if (!url.empty() && proc.url != url) {
          proc.url = url;
          changed = true;
        }
        if (!title.empty() && proc.title != title) {
          proc.title = title;
          changed = true;
        }
        break;
      }
    }
  }

  if (changed) {
    SaveSession();
    NotifyManagerUI();
  }
}

}  // namespace app_browser

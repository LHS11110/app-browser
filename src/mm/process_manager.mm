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

int ProcessManager::SpawnChild(const std::string& url) {
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
      NSArray<NSString*>* arguments = @[@"--child", urlArg];

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
      info.start_time = GetCurrentTimestamp();

      processes_.push_back(info);
      new_pid = info.pid;

      // Ensure macOS brings newly spawned child browser to the foreground
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        NSRunningApplication* childApp =
            [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (childApp) {
          [childApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
      });
    }
  }

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
  @autoreleasepool {
    NSRunningApplication* app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app) {
      return [app activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    }
  }
  return false;
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

}  // namespace app_browser

#include "app.h"
#include "client.h"
#include "process_manager.h"

#include <dispatch/dispatch.h>

#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_fill_layout.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

namespace app_browser {

static bool g_is_quitting = false;

void QuitAppCleanly() {
  if (g_is_quitting) return;
  g_is_quitting = true;
  ProcessManager::GetInstance()->TerminateAll();
  ProcessManager::GetInstance()->CloseAllWindows();
  if (auto client = AppBrowserClient::GetInstance()) {
    client->CloseAllBrowsers(true);
  }
  CefPostTask(TID_UI, base::BindOnce([]() {
    CefQuitMessageLoop();
  }));
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    exit(0);
  });
}

namespace {

class AppBrowserWindowDelegate : public CefWindowDelegate {
 public:
  AppBrowserWindowDelegate(CefRefPtr<CefBrowserView> browser_view,
                           const WindowConfig& config,
                           bool is_manager = false,
                           bool is_search = false,
                           bool is_bookmarks = false)
      : browser_view_(browser_view),
        config_(config),
        is_manager_(is_manager),
        is_search_(is_search),
        is_bookmarks_(is_bookmarks) {}

  AppBrowserWindowDelegate(const AppBrowserWindowDelegate&) = delete;
  AppBrowserWindowDelegate& operator=(const AppBrowserWindowDelegate&) = delete;

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->SetToFillLayout();
    window->AddChildView(browser_view_);
    window->Layout();
    if (is_bookmarks_) {
      PositionWindowAtBottom(window->GetWindowHandle(), config_.width, config_.height, 36);
    } else {
      window->CenterWindow(CefSize(config_.width, config_.height));
    }
    if (is_search_ || is_bookmarks_) {
      window->SetBackgroundColor(CefColorSetARGB(0, 0, 0, 0));
      browser_view_->SetBackgroundColor(CefColorSetARGB(0, 0, 0, 0));
    }
    window->Show();
    window->Activate();
    window->BringToTop();
    ActivateApplication();
    if (config_.is_translucent) {
      SetWindowTranslucent(window->GetWindowHandle(), config_.alpha);
    }
  }

  bool IsFrameless(CefRefPtr<CefWindow> window) override {
    return is_search_ || is_bookmarks_;
  }

  bool CanResize(CefRefPtr<CefWindow> window) override {
    return !is_search_ && !is_bookmarks_;
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    browser_view_ = nullptr;
    if (is_manager_) {
      QuitAppCleanly();
    }
    if (is_search_) {
      ProcessManager::GetInstance()->OnSearchWindowClosed();
    }
    if (is_bookmarks_) {
      ProcessManager::GetInstance()->OnBookmarksWindowClosed();
    }
  }

  bool CanClose(CefRefPtr<CefWindow> window) override {
    if (g_is_quitting) {
      return true;
    }
    if (is_manager_) {
      QuitAppCleanly();
      return true;
    }
    if (is_bookmarks_) {
      window->Hide();
      return false;
    }
    if (browser_view_) {
      CefRefPtr<CefBrowser> browser = browser_view_->GetBrowser();
      if (browser) {
        return browser->GetHost()->TryCloseBrowser();
      }
    }
    return true;
  }

  CefSize GetPreferredSize(CefRefPtr<CefView> view) override {
    return CefSize(config_.width, config_.height);
  }

  CefSize GetMinimumSize(CefRefPtr<CefView> view) override {
    return CefSize(config_.min_width, config_.min_height);
  }

 private:
  CefRefPtr<CefBrowserView> browser_view_;
  WindowConfig config_;
  bool is_manager_ = false;
  bool is_search_ = false;
  bool is_bookmarks_ = false;

  IMPLEMENT_REFCOUNTING(AppBrowserWindowDelegate);
};

class AppBrowserViewDelegate : public CefBrowserViewDelegate {
 public:
  AppBrowserViewDelegate() = default;

  AppBrowserViewDelegate(const AppBrowserViewDelegate&) = delete;
  AppBrowserViewDelegate& operator=(const AppBrowserViewDelegate&) = delete;

  bool OnPopupBrowserViewCreated(CefRefPtr<CefBrowserView> browser_view,
                                 CefRefPtr<CefBrowserView> popup_browser_view,
                                 bool is_devtools) override {
    return false;
  }

 private:
  IMPLEMENT_REFCOUNTING(AppBrowserViewDelegate);
};

void ScheduleProcessLivenessCheck() {
  CefPostDelayedTask(TID_UI, base::BindOnce([]() {
    ProcessManager::GetInstance()->RefreshProcesses();
    ScheduleProcessLivenessCheck();
  }), 1000);
}

}  // namespace

AppBrowserApp::AppBrowserApp(const WindowConfig& config) : config_(config) {}

void AppBrowserApp::OnContextInitialized() {
  CEF_REQUIRE_UI_THREAD();

  CefBrowserSettings browser_settings;
  browser_settings.background_color = CefColorSetARGB(255, 255, 255, 255);

  CefBrowserSettings transparent_settings;
  transparent_settings.background_color = CefColorSetARGB(0, 0, 0, 0);

  CefRefPtr<AppBrowserClient> client(new AppBrowserClient(config_));

  // 1. Child Browser Process Mode
  if (config_.is_child) {
    CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
        client, config_.url, browser_settings, nullptr, nullptr,
        new AppBrowserViewDelegate());

    CefRefPtr<CefWindow> window = CefWindow::CreateTopLevelWindow(
        new AppBrowserWindowDelegate(browser_view, config_));
    window->SetTitle(config_.title);
    return;
  }

  // 2. Child Search Bar Process Mode
  if (config_.is_search) {
    WindowConfig search_config = config_;
    search_config.title = "App Browser - 검색";
    search_config.width = 640;
    search_config.height = 64;
    search_config.min_width = 300;
    search_config.min_height = 50;
    search_config.is_translucent = true;
    search_config.alpha = 1.0f;

    CefRefPtr<CefBrowserView> search_browser_view = CefBrowserView::CreateBrowserView(
        client, search_config.url, transparent_settings, nullptr, nullptr,
        new AppBrowserViewDelegate());

    CefRefPtr<CefWindow> window = CefWindow::CreateTopLevelWindow(
        new AppBrowserWindowDelegate(search_browser_view, search_config, false, true));
    window->SetTitle(search_config.title);
    return;
  }

  // 3. Parent Process Mode:
  // Initialize IPC listener for child search processes
  ProcessManager::GetInstance()->InitIpc();
  ProcessManager::GetInstance()->SetSearchUrl(config_.search_url);

  // Create Process Manager Dashboard Window
  WindowConfig manager_config;
  manager_config.title = "App Browser - 프로세스 관리자";
  manager_config.url = config_.manager_url.empty() ? config_.url : config_.manager_url;
  manager_config.width = 440;
  manager_config.height = 740;
  manager_config.min_width = 380;
  manager_config.min_height = 480;
  manager_config.is_translucent = true;
  manager_config.alpha = 0.88f;

  CefRefPtr<CefBrowserView> manager_browser_view = CefBrowserView::CreateBrowserView(
      client, manager_config.url, transparent_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> manager_window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(manager_browser_view, manager_config, true, false));
  manager_window->SetTitle(manager_config.title);

  // Create Search Bar Window
  WindowConfig search_config;
  search_config.title = "App Browser - 검색";
  search_config.url = config_.search_url.empty() ? config_.url : config_.search_url;
  search_config.width = 640;
  search_config.height = 64;
  search_config.min_width = 300;
  search_config.min_height = 50;
  search_config.is_translucent = true;
  search_config.alpha = 1.0f;

  CefRefPtr<CefBrowserView> search_browser_view = CefBrowserView::CreateBrowserView(
      client, search_config.url, transparent_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> search_window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(search_browser_view, search_config, false, true));
  search_window->SetTitle(search_config.title);

  ProcessManager::GetInstance()->SetSearchWindow(search_window);

  // Create Bookmarks Window
  WindowConfig bookmarks_config;
  bookmarks_config.title = "App Browser - 즐겨찾기";
  bookmarks_config.url = config_.bookmarks_url.empty() ? config_.url : config_.bookmarks_url;
  bookmarks_config.width = 540;
  bookmarks_config.height = 420;
  bookmarks_config.min_width = 360;
  bookmarks_config.min_height = 300;
  bookmarks_config.is_translucent = true;
  bookmarks_config.alpha = 1.0f;

  CefRefPtr<CefBrowserView> bookmarks_browser_view = CefBrowserView::CreateBrowserView(
      client, bookmarks_config.url, transparent_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> bookmarks_window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(bookmarks_browser_view, bookmarks_config, false, false, true));
  bookmarks_window->SetTitle(bookmarks_config.title);

  ProcessManager::GetInstance()->SetBookmarksWindow(bookmarks_window);

  // Schedule periodic child process liveness checking
  ScheduleProcessLivenessCheck();
}

}  // namespace app_browser

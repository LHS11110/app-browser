#include "app.h"
#include "client.h"
#include "process_manager.h"

#include "include/base/cef_callback.h"
#include "include/cef_browser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_fill_layout.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

namespace app_browser {

namespace {

class AppBrowserWindowDelegate : public CefWindowDelegate {
 public:
  AppBrowserWindowDelegate(CefRefPtr<CefBrowserView> browser_view,
                           const WindowConfig& config)
      : browser_view_(browser_view), config_(config) {}

  AppBrowserWindowDelegate(const AppBrowserWindowDelegate&) = delete;
  AppBrowserWindowDelegate& operator=(const AppBrowserWindowDelegate&) = delete;

  void OnWindowCreated(CefRefPtr<CefWindow> window) override {
    window->SetToFillLayout();
    window->AddChildView(browser_view_);
    window->Layout();
    window->CenterWindow(CefSize(config_.width, config_.height));
    window->Show();
    window->Activate();
    window->BringToTop();
    ActivateApplication();
    if (config_.is_translucent) {
      SetWindowTranslucent(window->GetWindowHandle(), config_.alpha);
    }
  }

  void OnWindowDestroyed(CefRefPtr<CefWindow> window) override {
    browser_view_ = nullptr;
  }

  bool CanClose(CefRefPtr<CefWindow> window) override {
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
  CefRefPtr<AppBrowserClient> client(new AppBrowserClient());

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

  // 2. Parent Process Mode:
  // Create Process Manager Dashboard Window
  WindowConfig manager_config;
  manager_config.title = "App Browser - 프로세스 관리자";
  manager_config.url = config_.manager_url.empty() ? config_.url : config_.manager_url;
  manager_config.width = 440;
  manager_config.height = 740;
  manager_config.min_width = 380;
  manager_config.min_height = 480;
  manager_config.is_translucent = true;
  manager_config.alpha = 0.94f;

  CefRefPtr<CefBrowserView> manager_browser_view = CefBrowserView::CreateBrowserView(
      client, manager_config.url, browser_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> manager_window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(manager_browser_view, manager_config));
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
  search_config.alpha = 0.96f;

  CefRefPtr<CefBrowserView> search_browser_view = CefBrowserView::CreateBrowserView(
      client, search_config.url, browser_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> search_window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(search_browser_view, search_config));
  search_window->SetTitle(search_config.title);

  ProcessManager::GetInstance()->SetSearchWindow(search_window);

  // Schedule periodic child process liveness checking
  ScheduleProcessLivenessCheck();
}

}  // namespace app_browser

#include "app.h"
#include "client.h"

#include "include/cef_browser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
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
    window->AddChildView(browser_view_);
    window->Show();
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

}  // namespace

AppBrowserApp::AppBrowserApp(const WindowConfig& config) : config_(config) {}

void AppBrowserApp::OnContextInitialized() {
  CEF_REQUIRE_UI_THREAD();

  CefBrowserSettings browser_settings;
  CefRefPtr<AppBrowserClient> client(new AppBrowserClient());

  CefRefPtr<CefBrowserView> browser_view = CefBrowserView::CreateBrowserView(
      client, config_.url, browser_settings, nullptr, nullptr,
      new AppBrowserViewDelegate());

  CefRefPtr<CefWindow> window = CefWindow::CreateTopLevelWindow(
      new AppBrowserWindowDelegate(browser_view, config_));
  window->SetTitle(config_.title);
}

}  // namespace app_browser

#pragma once

#include "include/cef_app.h"
#include "config.h"

namespace app_browser {

// Native macOS window helper to set window opacity / translucency
void SetWindowTranslucent(CefWindowHandle handle, float alpha);
void ActivateApplication();
void QuitAppCleanly();

class AppBrowserApp : public CefApp, public CefBrowserProcessHandler {
 public:
  explicit AppBrowserApp(const WindowConfig& config);

  // CefApp methods:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  // CefBrowserProcessHandler methods:
  void OnContextInitialized() override;

  const WindowConfig& GetConfig() const { return config_; }

 private:
  WindowConfig config_;

  IMPLEMENT_REFCOUNTING(AppBrowserApp);
  DISALLOW_COPY_AND_ASSIGN(AppBrowserApp);
};

}  // namespace app_browser

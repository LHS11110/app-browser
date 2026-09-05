#include "client.h"

#include <sstream>
#include <string>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

namespace app_browser {

namespace {

AppBrowserClient* g_instance = nullptr;

}  // namespace

AppBrowserClient::AppBrowserClient() {
  DCHECK(!g_instance);
  g_instance = this;
}

AppBrowserClient::~AppBrowserClient() {
  g_instance = nullptr;
}

AppBrowserClient* AppBrowserClient::GetInstance() {
  return g_instance;
}

void AppBrowserClient::OnAfterCreated(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();
  browser_list_.push_back(browser);
}

bool AppBrowserClient::DoClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();

  // Closing the main window should initiate application termination
  if (browser_list_.size() == 1) {
    is_closing_ = true;
  }

  return false;
}

void AppBrowserClient::OnBeforeClose(CefRefPtr<CefBrowser> browser) {
  CEF_REQUIRE_UI_THREAD();

  for (auto it = browser_list_.begin(); it != browser_list_.end(); ++it) {
    if ((*it)->IsSame(browser)) {
      browser_list_.erase(it);
      break;
    }
  }

  if (browser_list_.empty()) {
    // All browser windows have closed, quit message loop.
    CefQuitMessageLoop();
  }
}

bool AppBrowserClient::OnBeforePopup(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    int popup_id,
    const CefString& target_url,
    const CefString& target_frame_name,
    CefLifeSpanHandler::WindowOpenDisposition target_disposition,
    bool user_gesture,
    const CefPopupFeatures& popupFeatures,
    CefWindowInfo& windowInfo,
    CefRefPtr<CefClient>& client,
    CefBrowserSettings& settings,
    CefRefPtr<CefDictionaryValue>& extra_info,
    bool* no_javascript_access) {
  CEF_REQUIRE_UI_THREAD();

  // Load popup / target=_blank links directly into the current window for an app-like experience
  std::string url = target_url.ToString();
  if (!url.empty()) {
    browser->GetMainFrame()->LoadURL(url);
  }
  return true;  // Cancel default popup window creation
}

void AppBrowserClient::OnTitleChange(CefRefPtr<CefBrowser> browser,
                                     const CefString& title) {
  CEF_REQUIRE_UI_THREAD();

  if (auto browser_view = CefBrowserView::GetForBrowser(browser)) {
    if (auto window = browser_view->GetWindow()) {
      window->SetTitle(title);
    }
  }
}

void AppBrowserClient::OnBeforeContextMenu(
    CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefFrame> frame,
    CefRefPtr<CefContextMenuParams> params,
    CefRefPtr<CefMenuModel> model) {
  CEF_REQUIRE_UI_THREAD();

  // In an App Browser, remove standard browser navigation/source inspection menus.
  // Retain only essential editing and clipboard actions.
  int count = model->GetCount();
  for (int i = count - 1; i >= 0; --i) {
    int command_id = model->GetCommandIdAt(i);
    switch (command_id) {
      case MENU_ID_UNDO:
      case MENU_ID_REDO:
      case MENU_ID_CUT:
      case MENU_ID_COPY:
      case MENU_ID_PASTE:
      case MENU_ID_DELETE:
      case MENU_ID_SELECT_ALL:
        // Keep essential editing commands
        break;
      default:
        // Remove browser-specific chrome items (Back, Forward, Reload, View Source, etc.)
        model->RemoveAt(i);
        break;
    }
  }
}

void AppBrowserClient::CloseAllBrowsers(bool force_close) {
  if (!CefCurrentlyOn(TID_UI)) {
    CefPostTask(TID_UI, base::BindOnce(&AppBrowserClient::CloseAllBrowsers,
                                       this, force_close));
    return;
  }

  if (browser_list_.empty())
    return;

  for (auto& browser : browser_list_) {
    browser->GetHost()->CloseBrowser(force_close);
  }
}

}  // namespace app_browser

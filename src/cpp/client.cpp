#include "client.h"
#include "process_manager.h"

#include <sstream>
#include <string>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/cef_parser.h"
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

bool AppBrowserClient::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                      CefRefPtr<CefFrame> frame,
                                      CefRefPtr<CefRequest> request,
                                      bool user_gesture,
                                      bool is_redirect) {
  CEF_REQUIRE_UI_THREAD();

  std::string url = request->GetURL().ToString();
  const std::string action_prefix = "action://";
  if (url.rfind(action_prefix, 0) == 0) {
    std::string action_part = url.substr(action_prefix.length());
    size_t qpos = action_part.find('?');
    std::string command = (qpos == std::string::npos) ? action_part : action_part.substr(0, qpos);
    std::string query = (qpos == std::string::npos) ? "" : action_part.substr(qpos + 1);

    // Normalize command by trimming trailing slashes (e.g., "spawn/" -> "spawn")
    while (!command.empty() && command.back() == '/') {
      command.pop_back();
    }

    auto get_param = [&](const std::string& key) -> std::string {
      size_t pos = query.find(key + "=");
      if (pos == std::string::npos) return "";
      size_t start = pos + key.length() + 1;
      size_t end = query.find('&', start);
      std::string val = (end == std::string::npos) ? query.substr(start) : query.substr(start, end - start);
      return CefURIDecode(val, true, UU_NORMAL).ToString();
    };

    if (command == "spawn") {
      std::string target_url;
      size_t pos = query.find("url=");
      if (pos != std::string::npos) {
        size_t start = pos + 4;
        // Search for cache buster parameter &_t= if present
        size_t end = query.find("&_t=", start);
        std::string raw_val = (end == std::string::npos) ? query.substr(start) : query.substr(start, end - start);
        target_url = CefURIDecode(raw_val, true, UU_NORMAL).ToString();
      }
      if (!target_url.empty()) {
        ProcessManager::GetInstance()->SpawnChild(target_url);
      }
    } else if (command == "kill") {
      std::string pid_str = get_param("pid");
      if (!pid_str.empty()) {
        ProcessManager::GetInstance()->TerminateChild(std::atoi(pid_str.c_str()));
      }
    } else if (command == "focus") {
      std::string pid_str = get_param("pid");
      if (!pid_str.empty()) {
        ProcessManager::GetInstance()->FocusChild(std::atoi(pid_str.c_str()));
      }
    } else if (command == "kill-all") {
      ProcessManager::GetInstance()->TerminateAll();
    } else if (command == "open-search") {
      ProcessManager::GetInstance()->ShowSearchWindow();
    } else if (command == "ready") {
      ProcessManager::GetInstance()->SetManagerBrowser(browser);
      ProcessManager::GetInstance()->NotifyManagerUI();
    }

    return true; // Cancel navigation
  }

  return false;
}

void AppBrowserClient::OnAddressChange(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& url) {
  CEF_REQUIRE_UI_THREAD();

  if (!frame->IsMain())
    return;

  std::string url_str = url.ToString();
  // When navigating away from the local search bar to an external web page
  if (url_str.rfind("http://", 0) == 0 || url_str.rfind("https://", 0) == 0) {
    if (auto browser_view = CefBrowserView::GetForBrowser(browser)) {
      if (auto window = browser_view->GetWindow()) {
        CefSize current_size = window->GetSize();
        // If window is currently in the compact search bar size, expand to browsing size
        if (current_size.height < 300) {
          window->CenterWindow(CefSize(1280, 800));
        }
      }
    }
  }
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

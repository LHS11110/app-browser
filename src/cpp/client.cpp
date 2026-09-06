#include "client.h"
#include "app.h"
#include "process_manager.h"

#include <sstream>
#include <string>
#include <vector>

#include "include/base/cef_callback.h"
#include "include/cef_app.h"
#include "include/cef_image.h"
#include "include/cef_parser.h"
#include "include/views/cef_browser_view.h"
#include "include/views/cef_window.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/wrapper/cef_helpers.h"

namespace app_browser {

namespace {

AppBrowserClient* g_instance = nullptr;

int HexToVal(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

std::string UrlDecode(const std::string& in) {
  std::string out;
  out.reserve(in.length());
  for (size_t i = 0; i < in.length(); ++i) {
    if (in[i] == '%' && i + 2 < in.length()) {
      int h1 = HexToVal(in[i + 1]);
      int h2 = HexToVal(in[i + 2]);
      if (h1 != -1 && h2 != -1) {
        out += static_cast<char>((h1 << 4) | h2);
        i += 2;
        continue;
      }
    }
    out += in[i];
  }
  return out;
}

class FaviconDownloadCallback : public CefDownloadImageCallback {
 public:
  explicit FaviconDownloadCallback(CefRefPtr<CefBrowser> browser)
      : browser_(browser) {}

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    if (!image || image->IsEmpty()) return;

    if (auto browser_view = CefBrowserView::GetForBrowser(browser_)) {
      if (auto window = browser_view->GetWindow()) {
        window->SetWindowIcon(image);
        window->SetWindowAppIcon(image);
      }
    }

    int w = 0, h = 0;
    CefRefPtr<CefBinaryValue> png = image->GetAsPNG(1.0f, true, w, h);
    if (png && png->GetSize() > 0) {
      std::vector<uint8_t> buffer(png->GetSize());
      png->GetData(buffer.data(), buffer.size(), 0);
      SetAppDockIconFromData(buffer.data(), buffer.size());
    }
  }

 private:
  CefRefPtr<CefBrowser> browser_;
  IMPLEMENT_REFCOUNTING(FaviconDownloadCallback);
};

}  // namespace

AppBrowserClient::AppBrowserClient(const WindowConfig& config) : config_(config) {
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
      return UrlDecode(val);
    };

    if (command == "spawn") {
      std::string target_url;
      size_t pos = query.find("url=");
      if (pos != std::string::npos) {
        size_t start = pos + 4;
        // Search for cache buster parameter &_t= if present
        size_t end = query.find("&_t=", start);
        std::string raw_val = (end == std::string::npos) ? query.substr(start) : query.substr(start, end - start);
        target_url = UrlDecode(raw_val);
      }

      // Trim any whitespace
      while (!target_url.empty() && (target_url.front() == ' ' || target_url.front() == '\t')) {
        target_url.erase(0, 1);
      }
      while (!target_url.empty() && (target_url.back() == ' ' || target_url.back() == '\t' || target_url.back() == '\r' || target_url.back() == '\n')) {
        target_url.pop_back();
      }

      if (!target_url.empty()) {
        if (config_.is_search && config_.parent_pid > 0) {
          SendSpawnNotificationToParent(config_.parent_pid, target_url);
        } else {
          ProcessManager::GetInstance()->SpawnChild(target_url);
        }
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
      ProcessManager::GetInstance()->ClearSavedSession();
    } else if (command == "update-meta") {
      std::string pid_str = get_param("pid");
      std::string name = get_param("name");
      std::string group_id = get_param("groupId");
      if (!pid_str.empty()) {
        ProcessManager::GetInstance()->UpdateProcessMeta(std::atoi(pid_str.c_str()), name, group_id);
      }
    } else if (command == "open-search") {
      ProcessManager::GetInstance()->ShowSearchWindow();
    } else if (command == "open-bookmarks") {
      ProcessManager::GetInstance()->ShowBookmarksWindow();
    } else if (command == "close-bookmarks") {
      ProcessManager::GetInstance()->HideBookmarksWindow();
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
    if (config_.is_child) {
      SetAppDockIconForUrl(url_str);
    }
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

void AppBrowserClient::OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                                         const std::vector<CefString>& icon_urls) {
  CEF_REQUIRE_UI_THREAD();
  if (icon_urls.empty()) return;

  // Select the best candidate URL (prefer apple-touch-icon or large png)
  std::string best_url = icon_urls[0].ToString();
  for (const auto& url_cef : icon_urls) {
    std::string candidate = url_cef.ToString();
    if (candidate.find("apple-touch-icon") != std::string::npos ||
        candidate.find("192") != std::string::npos ||
        candidate.find("180") != std::string::npos ||
        candidate.find("128") != std::string::npos) {
      best_url = candidate;
      break;
    }
  }

  browser->GetHost()->DownloadImage(best_url, true, 256, false,
                                    new FaviconDownloadCallback(browser));
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

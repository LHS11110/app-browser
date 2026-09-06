#pragma once

#include <string>
#include <vector>
#include <mutex>
#include "include/cef_browser.h"
#include "include/views/cef_window.h"

namespace app_browser {

struct ChildProcessInfo {
  int pid = 0;
  std::string url;
  std::string title;
  std::string start_time;
  std::string name;
  std::string group_id = "default";
};

class ProcessManager {
 public:
  static ProcessManager* GetInstance();

  // Process Controls
  int SpawnChild(const std::string& url);
  bool TerminateChild(int pid);
  void TerminateAll();
  bool FocusChild(int pid);
  void SetChildVisibility(int pid, bool visible);
  void SetGroupVisibility(const std::string& group_id, bool visible);

  // Session Persistence & Restore
  void SaveSession();
  void RestoreSession();
  void ClearSavedSession();
  void UpdateProcessMeta(int pid, const std::string& name, const std::string& group_id);
  void UpdateProcessUrl(int pid, const std::string& url, const std::string& title);

  // Status & Synchronization
  void RefreshProcesses();
  std::vector<ChildProcessInfo> GetProcesses() const;
  std::string ToJson() const;

  // Manager UI Binding
  void SetManagerBrowser(CefRefPtr<CefBrowser> browser);
  void NotifyManagerUI();

  // Search Window & Process Management
  void SetSearchWindow(CefRefPtr<CefWindow> window);
  void OnSearchWindowClosed();
  void ToggleSearchWindow();
  void ShowSearchWindow();
  int SpawnSearchChild();
  void SetSearchUrl(const std::string& url);

  // Bookmarks Window Management
  void SetBookmarksWindow(CefRefPtr<CefWindow> window);
  void OnBookmarksWindowClosed();
  void ShowBookmarksWindow();
  void HideBookmarksWindow();

  // Window Clean Shutdown
  void CloseAllWindows();

  // IPC Synchronization
  void InitIpc();

 private:
  ProcessManager();
  ~ProcessManager();

  mutable std::mutex mutex_;
  std::vector<ChildProcessInfo> processes_;
  CefRefPtr<CefBrowser> manager_browser_;
  CefRefPtr<CefWindow> search_window_;
  CefRefPtr<CefWindow> bookmarks_window_;
  int search_child_pid_ = -1;
  std::string search_url_;
};

void SendSpawnNotificationToParent(int parent_pid, const std::string& target_url);
void SendUrlUpdateToParent(int parent_pid, int child_pid, const std::string& target_url, const std::string& title);
void SendVisibilityNotificationToChild(int child_pid, bool visible);
void RegisterChildVisibilityIpc(CefRefPtr<CefWindow> window);

}  // namespace app_browser

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
};

class ProcessManager {
 public:
  static ProcessManager* GetInstance();

  // Process Controls
  int SpawnChild(const std::string& url);
  bool TerminateChild(int pid);
  void TerminateAll();
  bool FocusChild(int pid);

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

  // IPC Synchronization
  void InitIpc();

 private:
  ProcessManager();
  ~ProcessManager();

  mutable std::mutex mutex_;
  std::vector<ChildProcessInfo> processes_;
  CefRefPtr<CefBrowser> manager_browser_;
  CefRefPtr<CefWindow> search_window_;
  int search_child_pid_ = -1;
  std::string search_url_;
};

void SendSpawnNotificationToParent(int parent_pid, const std::string& target_url);

}  // namespace app_browser

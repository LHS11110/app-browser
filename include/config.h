#pragma once

#include <string>
#include <cstdlib>

namespace app_browser {

struct WindowConfig {
  std::string title = "App Browser";
  std::string url = "";
  std::string manager_url = "";
  std::string search_url = "";
  int width = 0;
  int height = 0;
  int min_width = 300;
  int min_height = 50;
  bool is_child = false;
  bool is_translucent = false;
  float alpha = 1.0f;
};

inline WindowConfig ParseConfig(int argc, char* argv[]) {
  WindowConfig config;

  // 1. Environment variable check
  const char* env_url = std::getenv("APP_BROWSER_URL");
  if (env_url && std::string(env_url).length() > 0) {
    config.url = env_url;
  }

  // 2. Command-line argument parsing
  for (int i = 1; i < argc; ++i) {
    std::string arg = argv[i];
    const std::string url_prefix = "--url=";
    const std::string title_prefix = "--title=";
    const std::string width_prefix = "--width=";
    const std::string height_prefix = "--height=";

    if (arg == "--child") {
      config.is_child = true;
    } else if (arg.rfind(url_prefix, 0) == 0) {
      config.url = arg.substr(url_prefix.length());
    } else if (arg.rfind(title_prefix, 0) == 0) {
      config.title = arg.substr(title_prefix.length());
    } else if (arg.rfind(width_prefix, 0) == 0) {
      config.width = std::atoi(arg.substr(width_prefix.length()).c_str());
    } else if (arg.rfind(height_prefix, 0) == 0) {
      config.height = std::atoi(arg.substr(height_prefix.length()).c_str());
    }
  }

  // 3. Set default dimensions if not explicitly provided
  if (config.width <= 0 || config.height <= 0) {
    if (config.is_child || !config.url.empty()) {
      // Child or explicit URL: standard browser window
      config.width = 1280;
      config.height = 800;
      config.min_width = 400;
      config.min_height = 300;
    } else {
      // Parent search bar window
      config.width = 640;
      config.height = 64;
      config.min_width = 300;
      config.min_height = 50;
    }
  }

  return config;
}

}  // namespace app_browser

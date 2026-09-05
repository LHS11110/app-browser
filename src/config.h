#pragma once

#include <string>
#include <cstdlib>

namespace app_browser {

struct WindowConfig {
  std::string title = "App Browser";
  std::string url = "https://www.google.com";
  int width = 1280;
  int height = 800;
  int min_width = 400;
  int min_height = 300;
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

    if (arg.rfind(url_prefix, 0) == 0) {
      config.url = arg.substr(url_prefix.length());
    } else if (arg.rfind(title_prefix, 0) == 0) {
      config.title = arg.substr(title_prefix.length());
    } else if (arg.rfind(width_prefix, 0) == 0) {
      config.width = std::atoi(arg.substr(width_prefix.length()).c_str());
    } else if (arg.rfind(height_prefix, 0) == 0) {
      config.height = std::atoi(arg.substr(height_prefix.length()).c_str());
    }
  }

  return config;
}

}  // namespace app_browser

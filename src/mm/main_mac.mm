#import <Cocoa/Cocoa.h>

#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include "app.h"
#include "client.h"
#include "config.h"
#include "process_manager.h"

#if defined(CEF_USE_SANDBOX)
#include "include/cef_sandbox_mac.h"
#endif

// Forward declaration
@interface AppBrowserApplication : NSApplication <CefAppProtocol> {
 @private
  BOOL handlingSendEvent_;
}
@end

@interface AppBrowserAppDelegate : NSObject <NSApplicationDelegate>
- (void)tryToTerminateApplication:(NSApplication*)app;
- (void)setupApplicationMenu;
@end

@implementation AppBrowserApplication
- (BOOL)isHandlingSendEvent {
  return handlingSendEvent_;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
  handlingSendEvent_ = handlingSendEvent;
}

- (void)sendEvent:(NSEvent*)event {
  CefScopedSendingEvent sendingEventScoper;
  [super sendEvent:event];
}

- (void)terminate:(id)sender {
  AppBrowserAppDelegate* delegate =
      static_cast<AppBrowserAppDelegate*>([NSApp delegate]);
  [delegate tryToTerminateApplication:self];
}
@end

@implementation AppBrowserAppDelegate

- (void)setupApplicationMenu {
  NSMenu* mainMenu = [[NSMenu alloc] init];

  // 1. App menu
  NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:appMenuItem];
  NSMenu* appMenu = [[NSMenu alloc] init];
  [appMenuItem setSubmenu:appMenu];

  NSString* appName = [[NSProcessInfo processInfo] processName];
  [appMenu addItemWithTitle:[NSString stringWithFormat:@"About %@", appName]
                     action:@selector(orderFrontStandardAboutPanel:)
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:[NSString stringWithFormat:@"Hide %@", appName]
                     action:@selector(hide:)
              keyEquivalent:@"h"];
  NSMenuItem* hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                              action:@selector(hideOtherApplications:)
                                       keyEquivalent:@"h"];
  [hideOthers setKeyEquivalentModifierMask:(NSEventModifierFlagOption | NSEventModifierFlagCommand)];
  [appMenu addItemWithTitle:@"Show All"
                     action:@selector(unhideAllApplications:)
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:[NSString stringWithFormat:@"Quit %@", appName]
                     action:@selector(terminate:)
              keyEquivalent:@"q"];

  // 2. Edit menu (ensures standard keyboard shortcuts Cmd+C, Cmd+V, Cmd+A work in web views)
  NSMenuItem* editMenuItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:editMenuItem];
  NSMenu* editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenuItem setSubmenu:editMenu];

  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];

  // 3. Window menu
  NSMenuItem* windowMenuItem = [[NSMenuItem alloc] init];
  [mainMenu addItem:windowMenuItem];
  NSMenu* windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
  [windowMenuItem setSubmenu:windowMenu];
  [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
  [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];

  [NSApp setMainMenu:mainMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  [self setupApplicationMenu];
}

- (void)tryToTerminateApplication:(NSApplication*)app {
  app_browser::QuitAppCleanly();
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  [self tryToTerminateApplication:sender];
  return NSTerminateCancel;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)app {
  return YES;
}

@end

namespace app_browser {
void SetWindowTranslucent(CefWindowHandle handle, float alpha) {
  if (!handle) return;
  dispatch_async(dispatch_get_main_queue(), ^{
    NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(handle);
    if (!view) return;

    auto configureWindow = ^(NSWindow* window) {
      if (!window) return;
      [window setOpaque:NO];
      [window setBackgroundColor:[NSColor clearColor]];
      [window setAlphaValue:alpha];
      [window setHasShadow:YES];
      [window setTitlebarAppearsTransparent:YES];
      [view setWantsLayer:YES];
      view.layer.backgroundColor = [NSColor clearColor].CGColor;
      view.layer.opaque = NO;
    };

    NSWindow* window = [view window];
    if (window) {
      configureWindow(window);
    } else {
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        configureWindow([view window]);
      });
    }
  });
}

void ActivateApplication() {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp activateIgnoringOtherApps:YES];
  });
}
}  // namespace app_browser

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInMain()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);

  @autoreleasepool {
    // Initialize custom NSApplication for CEF
    [AppBrowserApplication sharedApplication];
    CHECK([NSApp isKindOfClass:[AppBrowserApplication class]]);

    // Ensure the application is registered as a regular GUI application with macOS WindowServer
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    AppBrowserAppDelegate* delegate = [[AppBrowserAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

    app_browser::WindowConfig config = app_browser::ParseConfig(argc, argv);

    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString* startHtmlPath = [resourcePath stringByAppendingPathComponent:@"web/search/index.html"];
    NSString* managerHtmlPath = [resourcePath stringByAppendingPathComponent:@"web/manager/index.html"];

    if ([[NSFileManager defaultManager] fileExistsAtPath:startHtmlPath]) {
      config.search_url = std::string("file://") + [startHtmlPath UTF8String];
    } else {
      config.search_url = "https://www.google.com";
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:managerHtmlPath]) {
      config.manager_url = std::string("file://") + [managerHtmlPath UTF8String];
    }

    if (config.url.empty()) {
      config.url = config.search_url;
    }

    CefSettings settings;
    settings.no_sandbox = true;

    // Explicitly configure browser_subprocess_path for helper processes
    NSString* helperPath = [[[NSBundle mainBundle] bundlePath]
        stringByAppendingPathComponent:@"Contents/Frameworks/AppBrowser Helper.app/Contents/MacOS/AppBrowser Helper"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:helperPath]) {
      CefString(&settings.browser_subprocess_path) = [helperPath UTF8String];
    }

    // Set cache directories in ~/Library/Application Support/AppBrowser
    NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* appDataDir = [appSupport stringByAppendingPathComponent:@"AppBrowser"];
    [[NSFileManager defaultManager] createDirectoryAtPath:appDataDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    if (config.is_child || config.is_search) {
      // Isolate cache path for each child process in separate sibling directory
      NSString* childCacheDir = [appDataDir stringByAppendingPathComponent:
          [NSString stringWithFormat:@"Child_%d", getpid()]];
      [[NSFileManager defaultManager] createDirectoryAtPath:childCacheDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
      CefString(&settings.root_cache_path) = [childCacheDir UTF8String];
      CefString(&settings.cache_path) = [childCacheDir UTF8String];
    } else {
      NSString* parentCacheDir = [appDataDir stringByAppendingPathComponent:@"Parent"];
      [[NSFileManager defaultManager] createDirectoryAtPath:parentCacheDir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
      CefString(&settings.root_cache_path) = [parentCacheDir UTF8String];
      CefString(&settings.cache_path) = [parentCacheDir UTF8String];
    }

    settings.log_severity = LOGSEVERITY_WARNING;

    CefRefPtr<app_browser::AppBrowserApp> app(new app_browser::AppBrowserApp(config));

    if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
      return CefGetExitCode();
    }

    // Run CEF event message loop
    CefRunMessageLoop();

    // Gracefully shut down CEF
    CefShutdown();

    [NSApp setDelegate:nil];
  }

  return 0;
}

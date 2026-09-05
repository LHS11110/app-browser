#import <Cocoa/Cocoa.h>

#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include "src/app.h"
#include "src/client.h"
#include "src/config.h"

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
  app_browser::AppBrowserClient* client = app_browser::AppBrowserClient::GetInstance();
  if (client && !client->IsClosing()) {
    client->CloseAllBrowsers(false);
  }
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
  [self tryToTerminateApplication:sender];
  return NSTerminateCancel;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)app {
  return YES;
}

@end

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

    app_browser::WindowConfig config = app_browser::ParseConfig(argc, argv);

    CefSettings settings;
#if !defined(CEF_USE_SANDBOX)
    settings.no_sandbox = true;
#endif

    // Set cache directories in ~/Library/Application Support/AppBrowser for session & cookie persistence
    NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* appDataDir = [appSupport stringByAppendingPathComponent:@"AppBrowser"];
    [[NSFileManager defaultManager] createDirectoryAtPath:appDataDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    CefString(&settings.root_cache_path) = [appDataDir UTF8String];
    CefString(&settings.cache_path) = [[appDataDir stringByAppendingPathComponent:@"Cache"] UTF8String];
    settings.log_severity = LOGSEVERITY_WARNING;

    CefRefPtr<app_browser::AppBrowserApp> app(new app_browser::AppBrowserApp(config));

    if (!CefInitialize(main_args, settings, app.get(), nullptr)) {
      return CefGetExitCode();
    }

    AppBrowserAppDelegate* delegate = [[AppBrowserAppDelegate alloc] init];
    [NSApp setDelegate:delegate];

    // Run CEF event message loop
    CefRunMessageLoop();

    // Gracefully shut down CEF
    CefShutdown();

    [NSApp setDelegate:nil];
  }

  return 0;
}

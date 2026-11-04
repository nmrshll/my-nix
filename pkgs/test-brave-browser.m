#import <AppKit/AppKit.h>

// A native browser behind the same waiting shell/Python layers as the real app.
@interface TestBrowser : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@end
@implementation TestBrowser
- (void)showBrowserWindow {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 300, 150)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        self.window.releasedWhenClosed = NO;
    }
    [self.window makeKeyAndOrderFront:nil];
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    if (NSProcessInfo.processInfo.environment[@"TEST_REOPEN"]) {
        [self showBrowserWindow];
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            NSDictionary *env = NSProcessInfo.processInfo.environment;
            if (self.window && [NSFileManager.defaultManager fileExistsAtPath:env[@"TEST_CLOSE"]]) {
                [self.window close];
                self.window = nil;
                [NSFileManager.defaultManager removeItemAtPath:env[@"TEST_CLOSE"] error:NULL];
                [@"closed" writeToFile:env[@"TEST_REOPEN"] atomically:YES
                    encoding:NSUTF8StringEncoding error:NULL];
            }
        }];
    }
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:NSProcessInfo.processInfo.environment[@"TEST_READY"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    (void)application;
    (void)visible;
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    if (env[@"TEST_REOPEN"]) {
        BOOL reused = self.window != nil;
        [self showBrowserWindow];
        NSUInteger visibleCount = 0;
        for (NSWindow *window in NSApp.windows) if (window.visible) visibleCount++;
        [[NSString stringWithFormat:@"%@:%lu", reused ? @"reused" : @"created",
            (unsigned long)visibleCount] writeToFile:env[@"TEST_REOPEN"]
            atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    return NO;
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application {
    (void)application;
    NSDictionary *env = NSProcessInfo.processInfo.environment;
    [@"quit" writeToFile:env[@"TEST_QUIT"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    return [NSFileManager.defaultManager fileExistsAtPath:env[@"TEST_CANCEL"]]
        ? NSTerminateCancel : NSTerminateNow;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--quit") == 0) {
            return [[NSRunningApplication runningApplicationWithProcessIdentifier:atoi(argv[2])]
                terminate] ? 0 : 1;
        }
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        TestBrowser *delegate = [[TestBrowser alloc] init];
        application.delegate = delegate;
        [application run];
        return 0;
    }
}

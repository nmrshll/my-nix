#import <AppKit/AppKit.h>

// A native browser behind the same waiting shell/Python layers as the real app.
@interface TestBrowser : NSObject <NSApplicationDelegate>
@end
@implementation TestBrowser
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [[NSString stringWithFormat:@"%d", getpid()] writeToFile:NSProcessInfo.processInfo.environment[@"TEST_READY"]
              atomically:YES encoding:NSUTF8StringEncoding error:NULL];
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

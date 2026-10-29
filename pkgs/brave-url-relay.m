#import <AppKit/AppKit.h>

// This is the bundle's actual executable. Keeping the settings/flags wrappers
// behind it lets LaunchServices find a running handler at CFBundleExecutable.
@interface BraveRelay : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *browser;
@property(nonatomic, strong) NSMutableSet<NSTask *> *requests;
@property(nonatomic, copy) NSString *launcher;
@end

@implementation BraveRelay
- (NSTask *)launch:(NSArray<NSString *> *)arguments {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:self.launcher];
    task.arguments = arguments;
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        fprintf(stderr, "Brave launcher: %s\n", error.localizedDescription.UTF8String);
        return nil;
    }
    return task;
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
    (void)application;
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (NSURL *url in urls) [arguments addObject:url.absoluteString];
    NSTask *request = [self launch:arguments];
    if (request) {
        [self.requests addObject:request];
        request.terminationHandler = ^(NSTask *finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.requests removeObject:finished];
            });
        };
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    (void)application;
    (void)visible;
    // A no-argument Chromium invocation raises the existing browser session.
    [self application:NSApp openURLs:@[]];
    return NO;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        BraveRelay *relay = [[BraveRelay alloc] init];
        relay.requests = [NSMutableSet set];
        relay.launcher = [[NSBundle mainBundle].executablePath stringByAppendingString:@"-launch-wrapped"];
        application.delegate = relay;
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (int i = 1; i < argc; i++) [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
        relay.browser = [relay launch:arguments];
        if (!relay.browser) return 127;
        // Keep the run loop alive to receive GURL events while Brave runs.
        relay.browser.terminationHandler = ^(NSTask *finished) {
            (void)finished;
            dispatch_async(dispatch_get_main_queue(), ^{
                [NSApp stop:nil];
                NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                    location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
                    context:nil subtype:0 data1:0 data2:0];
                [NSApp postEvent:wake atStart:NO];
            });
        };
        [application run];
        return relay.browser.terminationStatus;
    }
}

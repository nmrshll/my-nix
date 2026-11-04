#import <AppKit/AppKit.h>
#import <libproc.h>

// This is the bundle's actual executable. Keeping the settings/flags wrappers
// behind it lets LaunchServices find a running handler at CFBundleExecutable.
@interface BraveRelay : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSTask *browser;
@property(nonatomic, strong) NSMutableSet<NSTask *> *requests;
@property(nonatomic, copy) NSString *launcher;
@end

@implementation BraveRelay
- (BOOL)isBrowserProcess:(pid_t)pid {
    // The settings launcher waits for Chromium through one or more shell
    // wrappers. Target its native descendant, never the relay's bundle ID:
    // both processes belong to the same app bundle.
    while (pid > 1) {
        if (pid == self.browser.processIdentifier) return YES;
        struct proc_bsdinfo info;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return NO;
        if (info.pbi_ppid == (unsigned int)pid) return NO;
        pid = (pid_t)info.pbi_ppid;
    }
    return NO;
}

- (NSRunningApplication *)nativeBrowser {
    for (NSRunningApplication *candidate in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([candidate.bundleURL.URLByResolvingSymlinksInPath
                isEqual:NSBundle.mainBundle.bundleURL.URLByResolvingSymlinksInPath] &&
            [self isBrowserProcess:candidate.processIdentifier]) return candidate;
    }
    return nil;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application {
    (void)application;
    [[self nativeBrowser] terminate];
    // Keep forwarding events if Chromium cancels Quit (e.g. a download prompt).
    // Its normal exit ends the settings wrapper, whose handler stops our loop.
    return NSTerminateCancel;
}

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

- (void)reopenBrowserWithRetries:(NSUInteger)retries {
    NSRunningApplication *browser = [self nativeBrowser];
    if (!browser) {
        // A Dock click can arrive while the settings hook is still starting
        // Chromium. Wait for that child instead of launching another one.
        if (retries && self.browser.running) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{ [self reopenBrowserWithRetries:retries - 1]; });
        }
        return;
    }
    [browser activateWithOptions:NSApplicationActivateAllWindows];
    // Target Chromium's PID, not our shared bundle ID. Its native reopen
    // handler restores existing windows and creates one only when needed.
    NSAppleEventDescriptor *event = [NSAppleEventDescriptor
        appleEventWithEventClass:'aevt' eventID:'rapp'
        targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:browser.processIdentifier]
        returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
    NSError *error = nil;
    [event sendEventWithOptions:NSAppleEventSendNoReply timeout:1 error:&error];
    if (error) fprintf(stderr, "Brave reopen: %s\n", error.localizedDescription.UTF8String);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible {
    (void)application;
    (void)visible;
    // The relay has no windows; `visible` says nothing about Chromium's windows.
    // A fresh no-argument invocation can create a new window in that session.
    [self reopenBrowserWithRetries:50];
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

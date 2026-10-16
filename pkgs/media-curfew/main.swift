import AppKit

// The notice uses AppKit's standard alert layout, typography, colours and button.
// Dismissing it returns to other apps; enforcement runs independently of the UI.
final class BlockNotice: NSObject {
    private var alert: NSAlert?

    func show(until end: String) {
        if let alert = alert {
            alert.window.orderFrontRegardless()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Media players are blocked"
        alert.informativeText = "mpv and VLC are unavailable until \(end)."
        alert.alertStyle = .informational
        alert.showsSuppressionButton = false
        alert.showsHelp = false
        alert.icon = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Nighttime limit")
        alert.addButton(withTitle: "Back to other apps")
        alert.buttons[0].target = self
        alert.buttons[0].action = #selector(dismiss)
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        alert.window.center()
        self.alert = alert
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeKeyAndOrderFront(nil)
    }

    @objc func dismiss() {
        guard let alert = alert else { return }
        alert.window.orderOut(nil)
        self.alert = nil
        NSApp.hide(nil)
    }
}

final class CurfewAgent: NSObject, NSApplicationDelegate {
    private let curfew = Curfew()
    private let stopper = PlayerStopper()
    private let notice = BlockNotice()
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Enforce scheduled media limits without App Nap delaying checks")
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] _ in self?.check()
            })
        }
        // Recalculate local wall time on every tick, including after sleep, DST,
        // manual clock changes and time-zone changes. No cached overnight delay.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSLog("Media Curfew: active, 22:00–05:00 local time")
        check()
    }

    private func check() {
        guard curfew.isBlocked(at: Date()) else {
            stopper.reset()
            notice.dismiss()
            return
        }
        if stopper.stop(PlayerProcess.all()) {
            notice.show(until: curfew.endLabel)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = CurfewAgent()
app.delegate = delegate
app.run()

import AppKit
import Darwin

@main
struct CurfewTests {
    static func main() throws {
        if CommandLine.arguments.contains("--fixture") {
            signal(SIGTERM, CommandLine.arguments.contains("--ignore-term") ? SIG_IGN : SIG_DFL)
            FileHandle.standardOutput.write(Data("ready\n".utf8))
            while true { pause() }
        }

        let curfew = Curfew()
        // Exhaust every minute of the day, including both exact boundaries.
        for zone in ["Europe/London", "America/New_York", "Asia/Tokyo"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            for minute in 0..<1440 {
                let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16,
                                                               hour: minute / 60, minute: minute % 60))!
                precondition(curfew.isBlocked(at: date, calendar: calendar) == (minute >= 1320 || minute < 300))
            }
        }
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let iso = ISO8601DateFormatter()
        for (date, blocked) in [
            ("2026-03-29T00:59:59Z", true), ("2026-03-29T01:00:00Z", true),
            ("2026-03-29T03:59:59Z", true), ("2026-03-29T04:00:00Z", false),
            ("2026-10-25T00:59:59Z", true), ("2026-10-25T01:00:00Z", true),
            ("2026-10-25T04:59:59Z", true), ("2026-10-25T05:00:00Z", false)
        ] {
            precondition(curfew.isBlocked(at: iso.date(from: date)!, calendar: london) == blocked)
        }
        for name in ["mpv", ".mpv-wrapped", ".mpv-unwrapped-wrapped", "VLC", ".vlc-wrapped"] {
            precondition(Curfew.isPlayer(executable: "/nix/store/example/bin/\(name)"))
        }
        for name in ["mpv-helper", "vlc-helper", "vlc-cache-gen", "sh", "sleep", "media-curfew"] {
            precondition(!Curfew.isPlayer(executable: "/tmp/\(name)"))
        }
        precondition(Curfew.isPlayer(executable: "/tmp/renamed", bundleID: "io.mpv"))
        precondition(Curfew.isPlayer(executable: "/tmp/renamed", bundleID: "org.videolan.vlc"))
        precondition(PlayerProcess.inspect(getpid()) == nil)
        precondition(PlayerProcess.inspect(0) == nil)
        precondition(PlayerProcess.inspect(1) == nil)

        // Use isolated copies of this test binary as dummy players. Never signal
        // any real mpv/VLC process or change the system clock during tests.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let binary = dir.appendingPathComponent("mpv")
        try FileManager.default.copyItem(atPath: CommandLine.arguments[0], toPath: binary.path)
        for ignoresTerm in [false, true] {
            let child = Process()
            child.executableURL = binary
            child.arguments = ignoresTerm ? ["--fixture", "--ignore-term"] : ["--fixture"]
            let output = Pipe()
            child.standardOutput = output
            try child.run()
            defer { if child.isRunning { kill(child.processIdentifier, SIGKILL); child.waitUntilExit() } }
            precondition(String(data: output.fileHandleForReading.availableData, encoding: .utf8) == "ready\n")
            let target = PlayerProcess.inspect(child.processIdentifier)!
            precondition(target.isStillRunning)
            precondition(PlayerProcess.all().contains(target))
            let wrongIdentity = PlayerProcess(pid: target.pid, startedSeconds: target.startedSeconds + 1,
                                              startedMicroseconds: target.startedMicroseconds,
                                              executable: target.executable)
            precondition(!wrongIdentity.isStillRunning)
            let stopper = PlayerStopper()
            precondition(!stopper.stop([wrongIdentity], now: 0))
            precondition(stopper.stop([target], now: 0))
            if ignoresTerm {
                precondition(!stopper.stop([target], now: 1))
                precondition(target.isStillRunning)
                precondition(!stopper.stop([target], now: 2))
            }
            child.waitUntilExit()
            precondition(child.terminationReason == .uncaughtSignal)
            precondition(child.terminationStatus == (ignoresTerm ? SIGKILL : SIGTERM))
            precondition(!target.isStillRunning)
        }
        print("Passed: schedule boundaries, time zones, DST, player matching, process identity, graceful stop and escalation")
    }
}

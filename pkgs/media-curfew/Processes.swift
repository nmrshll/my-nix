import AppKit
import Darwin

struct PlayerProcess: Hashable {
    let pid: pid_t
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64
    let executable: String

    static func inspect(_ pid: pid_t, bundleID: String? = nil) -> PlayerProcess? {
        guard pid > 1, pid != getpid() else { return nil }
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info,
                           Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(cString: path)
        guard Curfew.isPlayer(executable: executable, bundleID: bundleID) else { return nil }
        return PlayerProcess(pid: pid, startedSeconds: info.pbi_start_tvsec,
                             startedMicroseconds: info.pbi_start_tvusec, executable: executable)
    }

    static func all() -> [PlayerProcess] {
        // libproc catches GUI and terminal/audio-only instances without spawning ps.
        let bytes = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 128)
        let read = proc_listpids(UInt32(PROC_UID_ONLY), getuid(), &pids,
                                Int32(pids.count * MemoryLayout<pid_t>.size))
        guard read > 0 else { return [] }
        let apps = Dictionary(NSWorkspace.shared.runningApplications.map {
            ($0.processIdentifier, $0.bundleIdentifier ?? "")
        }, uniquingKeysWith: { first, _ in first })
        return pids.prefix(Int(read) / MemoryLayout<pid_t>.size).compactMap {
            inspect($0, bundleID: apps[$0])
        }
    }

    var isStillRunning: Bool {
        // Recheck ownership, executable and process start time before every signal.
        Self.inspect(pid, bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier) == self
    }
}

final class PlayerStopper {
    private var pending: [PlayerProcess: TimeInterval] = [:]

    @discardableResult
    func stop(_ players: [PlayerProcess], now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        let live = Set(players)
        pending = pending.filter { live.contains($0.key) }
        var newlyBlocked = false
        for player in players where player.isStillRunning {
            if let deadline = pending[player] {
                if now >= deadline {
                    kill(player.pid, SIGKILL)
                }
            } else if kill(player.pid, SIGTERM) == 0 {
                // Give mpv a chance to save its watch-later position before escalation.
                pending[player] = now + 2
                newlyBlocked = true
                NSLog("Media Curfew: stopped %@ (pid %d)", player.executable, player.pid)
            }
        }
        return newlyBlocked
    }

    func reset() { pending.removeAll() }
}

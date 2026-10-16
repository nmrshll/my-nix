import Foundation

struct Curfew {
    let startHour: Int
    let endHour: Int

    init(startHour: Int = 22, endHour: Int = 5) {
        precondition((0...23).contains(startHour) && (0...23).contains(endHour))
        precondition(startHour != endHour)
        self.startHour = startHour
        self.endHour = endHour
    }

    func isBlocked(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return startHour > endHour
            ? hour >= startHour || hour < endHour
            : hour >= startHour && hour < endHour
    }

    var endLabel: String { String(format: "%02d:00", endHour) }

    static func isPlayer(executable: String, bundleID: String? = nil) -> Bool {
        if ["io.mpv", "org.videolan.vlc"].contains(bundleID ?? "") { return true }
        var name = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if name.hasPrefix(".") { name.removeFirst() }
        if name.hasSuffix("-wrapped") { name.removeLast("-wrapped".count) }
        return ["mpv", "mpv-unwrapped", "vlc"].contains(name)
    }
}

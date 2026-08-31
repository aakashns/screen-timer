import Foundation
import CoreGraphics

/// Tracks how long the display has been on today.
///
/// Two sources are combined and the larger one wins:
///  1. `pmset -g log`, which records "Display is turned on/off" events and so
///     covers time before this app was launched.
///  2. Live accumulation while the app runs, persisted per day in UserDefaults,
///     which covers the case where pmset's log has been rotated away.
final class ScreenTimeTracker {

    private let defaults = UserDefaults.standard
    private let storeKey = "dailyScreenSeconds"
    private let queue = DispatchQueue(label: "com.aakashns.screentimer.pmset", qos: .utility)

    /// On-time today accumulated up to `pmsetAsOf`, per pmset's log.
    private var pmsetSeconds: TimeInterval = 0
    private var pmsetAsOf = Date()
    private var pmsetAvailable = false
    private var refreshing = false

    /// On-time today accumulated by this process (plus previous runs today).
    private var trackedSeconds: TimeInterval = 0
    private var dayKey: String
    private var lastTick = Date()
    private var ticksSinceSave = 0

    var displayIsOn: Bool { CGDisplayIsAsleep(CGMainDisplayID()) == 0 }

    init() {
        dayKey = Self.key(for: Date())
        trackedSeconds = (defaults.dictionary(forKey: storeKey)?[dayKey] as? Double) ?? 0
        pmsetAsOf = Calendar.current.startOfDay(for: Date())
    }

    /// Seconds the screen has been on since midnight.
    var secondsToday: TimeInterval {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        var fromPmset: TimeInterval = 0
        if pmsetAvailable {
            let from = max(pmsetAsOf, startOfDay)
            fromPmset = pmsetSeconds + (displayIsOn ? max(0, now.timeIntervalSince(from)) : 0)
        }
        return max(fromPmset, trackedSeconds)
    }

    var formattedToday: String {
        let total = Int(secondsToday.rounded())
        return String(format: "%02d:%02d", total / 3600, (total % 3600) / 60)
    }

    // MARK: - Live accumulation

    /// Call roughly once a second.
    func tick() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        rolloverIfNeeded(now: now)

        // A large delta means we were suspended (system sleep, app frozen); the
        // screen was almost certainly off for most of it, so don't credit it.
        if displayIsOn, delta > 0, delta < 5 {
            trackedSeconds += delta
        }

        ticksSinceSave += 1
        if ticksSinceSave >= 20 { save() }
    }

    private func rolloverIfNeeded(now: Date) {
        let key = Self.key(for: now)
        guard key != dayKey else { return }
        save()
        dayKey = key
        trackedSeconds = 0
        pmsetSeconds = 0
        pmsetAsOf = Calendar.current.startOfDay(for: now)
        refresh()
    }

    func save() {
        ticksSinceSave = 0
        var store = defaults.dictionary(forKey: storeKey) as? [String: Double] ?? [:]
        store[dayKey] = trackedSeconds
        // Keep a short history so the file can't grow without bound.
        if store.count > 14 {
            for key in store.keys.sorted().dropLast(14) { store.removeValue(forKey: key) }
        }
        defaults.set(store, forKey: storeKey)
    }

    // MARK: - pmset

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        queue.async { [weak self] in
            let output = Self.runPmsetLog()
            let parsed = output.flatMap { Self.parse($0) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                guard let parsed else { return }
                self.pmsetSeconds = parsed.seconds
                self.pmsetAsOf = parsed.asOf
                self.pmsetAvailable = true
                // pmset knows about time before we were running; adopt it as a floor.
                self.trackedSeconds = max(self.trackedSeconds, self.secondsToday)
            }
        }
    }

    private static func runPmsetLog() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "log"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    /// Integrates today's display-on intervals from pmset's event log.
    ///
    /// Returns the total plus the instant that total is current as of: if the
    /// display is on at the end of the log, the caller keeps counting from the
    /// last event; otherwise the total is already complete up to now.
    private static func parse(_ log: String) -> (seconds: TimeInterval, asOf: Date)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        var events: [(date: Date, on: Bool)] = []
        for line in log.split(separator: "\n") {
            guard line.contains("Display is turned") else { continue }
            let text = String(line)
            guard text.count >= 25, let date = formatter.date(from: String(text.prefix(25))) else { continue }
            events.append((date, text.contains("Display is turned on")))
        }
        guard !events.isEmpty else { return nil }
        events.sort { $0.date < $1.date }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        var isOn = false
        for event in events where event.date <= startOfDay { isOn = event.on }

        var total: TimeInterval = 0
        var cursor = startOfDay
        for event in events where event.date > startOfDay && event.date <= now {
            if isOn { total += event.date.timeIntervalSince(cursor) }
            isOn = event.on
            cursor = event.date
        }
        return (total, isOn ? cursor : now)
    }

    private static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

import Foundation
import CoreGraphics

/// Tracks how long the display has been on today.
///
/// Two sources are combined and the larger one wins:
///  1. `pmset -g log`, which records display and power events and so covers
///     time before this app was launched.
///  2. Live accumulation while the app runs, persisted per day in UserDefaults,
///     which covers the case where pmset's log has been rotated away.
final class ScreenTimeTracker {

    private let defaults = UserDefaults.standard
    /// Deliberately not "dailyScreenSeconds". Totals under that key were
    /// inflated by a parser that read overnight downtime as screen time, and
    /// they were stored as a floor no corrected reading can lower. Reading
    /// under a new key drops them so today is derived afresh.
    private let storeKey = "dailyScreenSecondsV2"
    private let legacyStoreKey = "dailyScreenSeconds"
    private let resetKey = "screenSecondsResetAt"
    private let queue = DispatchQueue(label: "com.aakashns.screentimer.pmset", qos: .utility)

    /// On-time today accumulated up to `pmsetAsOf`, per pmset's log.
    private var pmsetSeconds: TimeInterval = 0
    private var pmsetAsOf = Date()
    /// Whether pmset had the display on at `pmsetAsOf`; only then may we keep
    /// counting forward from it.
    private var pmsetOn = false
    private var pmsetAvailable = false
    private var refreshing = false

    /// On-time today accumulated by this process (plus previous runs today).
    private var trackedSeconds: TimeInterval = 0
    private var dayKey: String
    private var lastTick = Date()
    private var ticksSinceSave = 0

    /// Set by a manual reset; time before this instant is not counted.
    private var resetAt: Date

    var displayIsOn: Bool { CGDisplayIsAsleep(CGMainDisplayID()) == 0 }

    init() {
        defaults.removeObject(forKey: legacyStoreKey)
        dayKey = Self.key(for: Date())
        trackedSeconds = (defaults.dictionary(forKey: storeKey)?[dayKey] as? Double) ?? 0
        let stamp = defaults.double(forKey: resetKey)
        resetAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : .distantPast
        pmsetAsOf = Calendar.current.startOfDay(for: Date())
    }

    /// The instant today's count starts from: midnight, or a later manual reset.
    private var countingSince: Date {
        max(Calendar.current.startOfDay(for: Date()), resetAt)
    }

    /// Seconds the screen has been on since `countingSince`.
    var secondsToday: TimeInterval {
        let now = Date()
        var fromPmset: TimeInterval = 0
        if pmsetAvailable {
            fromPmset = pmsetSeconds
            if pmsetOn, displayIsOn {
                let from = max(pmsetAsOf, countingSince)
                fromPmset += max(0, now.timeIntervalSince(from))
            }
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

    /// Drops everything counted so far and starts again from now.
    func reset() {
        resetAt = Date()
        defaults.set(resetAt.timeIntervalSince1970, forKey: resetKey)
        trackedSeconds = 0
        lastTick = resetAt
        clearPmset()
        save()
        refresh()
    }

    private func rolloverIfNeeded(now: Date) {
        let key = Self.key(for: now)
        guard key != dayKey else { return }
        save()
        dayKey = key
        trackedSeconds = 0
        clearPmset()
        refresh()
    }

    private func clearPmset() {
        pmsetSeconds = 0
        pmsetOn = false
        pmsetAvailable = false
        pmsetAsOf = countingSince
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
        let since = countingSince
        queue.async { [weak self] in
            let output = Self.runPmsetLog()
            let parsed = output.flatMap { Self.parse($0, since: since) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                // A reset or a day rollover while we were reading makes the
                // result answer the wrong question; drop it and wait for the
                // refresh those paths kick off.
                guard let parsed, since == self.countingSince else { return }
                self.pmsetSeconds = parsed.seconds
                self.pmsetAsOf = parsed.asOf
                self.pmsetOn = parsed.isOn
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

    /// What a pmset log line tells us about the display.
    enum LogEvent {
        case on
        case off
        /// powerd (re)started, so the machine was down for some unknown stretch
        /// before this line.
        case boot
    }

    /// Silence longer than this in the log means the machine was off or
    /// hibernating rather than merely idle.
    ///
    /// While the machine sleeps, powerd still wakes for maintenance and logs
    /// every 15-18 minutes, so routine gaps stay well under this. Real downtime
    /// runs to hours. 45 minutes sits in the empty band between the two.
    private static let downtimeGap: TimeInterval = 45 * 60

    /// Classifies a pmset log line, or nil if it says nothing about the display.
    ///
    /// "Display is turned off" is not logged reliably — a shutdown or a deep
    /// sleep can swallow it, leaving an "on" that never closes. The power
    /// domains below close it instead.
    static func classify(_ line: some StringProtocol) -> LogEvent? {
        // Skip the "yyyy-MM-dd HH:mm:ss Z " timestamp to reach the domain column.
        guard line.count > 26 else { return nil }
        let rest = line.dropFirst(26)
        if rest.hasPrefix("Notification") {
            if line.contains("Display is turned on") { return .on }
            if line.contains("Display is turned off") { return .off }
            return nil
        }
        // "Entering Sleep state ..." — the display is off for the duration.
        if rest.hasPrefix("Sleep ") { return .off }
        // A dark wake runs with the screen still off.
        if rest.hasPrefix("DarkWake") { return .off }
        if rest.hasPrefix("Start") { return .boot }
        // Plain "Wake" is deliberately ignored: a real wake logs its own
        // "Display is turned on", and "Wake Requests" lines are not wakes.
        return nil
    }

    private struct Entry {
        let date: Date
        let event: LogEvent
        /// Orders events sharing a timestamp: real events first, then any
        /// synthetic "the log goes quiet here" marker.
        let rank: Int
        /// Position in the log, so equal timestamps keep the order they happened.
        let order: Int
    }

    /// Reads the fixed "yyyy-MM-dd HH:mm:ss ±HHMM" prefix as epoch seconds.
    ///
    /// Gap detection has to timestamp every line in a log tens of thousands of
    /// lines long, and DateFormatter is far too slow for that.
    static func timestamp(_ line: some StringProtocol) -> TimeInterval? {
        var digits = [Int](repeating: 0, count: 25)
        var index = 0
        var sign = 0
        for byte in line.utf8 {
            if index == 25 { break }
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                digits[index] = Int(byte) - Int(UInt8(ascii: "0"))
            case UInt8(ascii: "-") where index == 20, UInt8(ascii: "+") where index == 20:
                sign = byte == UInt8(ascii: "-") ? -1 : 1
            // Any other byte must be the literal separator the format calls for.
            case UInt8(ascii: "-") where index == 4 || index == 7,
                 UInt8(ascii: " ") where index == 10 || index == 19,
                 UInt8(ascii: ":") where index == 13 || index == 16:
                break
            default:
                return nil
            }
            index += 1
        }
        guard index == 25, sign != 0 else { return nil }

        func number(_ range: Range<Int>) -> Int {
            range.reduce(0) { $0 * 10 + digits[$1] }
        }
        let year = number(0..<4), month = number(5..<7), day = number(8..<10)
        let hour = number(11..<13), minute = number(14..<16), second = number(17..<19)
        guard (1...12).contains(month), (1...31).contains(day),
              hour < 24, minute < 60, second < 61 else { return nil }

        // Days from the civil date to 1970-01-01, by Howard Hinnant's algorithm.
        let shifted = year - (month <= 2 ? 1 : 0)
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146097 + dayOfEra - 719468

        let offset = sign * (number(21..<23) * 3600 + number(23..<25) * 60)
        return TimeInterval(days * 86400 + hour * 3600 + minute * 60 + second - offset)
    }

    /// Integrates display-on intervals from pmset's event log since `since`.
    ///
    /// Returns the total, the instant that total is current as of, and whether
    /// the display was on then: if it was, the caller keeps counting from the
    /// last event; otherwise the total is already complete up to now.
    static func parse(_ log: String, since: Date) -> (seconds: TimeInterval, asOf: Date, isOn: Bool)? {
        var entries: [Entry] = []
        var order = 0
        var sawDisplayEvent = false
        var lastBeat: TimeInterval?

        for line in log.split(separator: "\n") {
            guard line.utf8.count > 26, let epoch = timestamp(line) else { continue }

            // Every log line is a heartbeat from a running powerd. A long
            // silence means the machine was gone, not that the display stayed
            // however we last saw it — this is what catches an overnight
            // shutdown that never logged its "Display is turned off".
            if let last = lastBeat, epoch - last > downtimeGap {
                entries.append(Entry(date: Date(timeIntervalSince1970: last),
                                     event: .off, rank: 1, order: order))
                order += 1
            }
            if epoch > lastBeat ?? -.greatestFiniteMagnitude { lastBeat = epoch }

            if let event = classify(line) {
                entries.append(Entry(date: Date(timeIntervalSince1970: epoch),
                                     event: event, rank: 0, order: order))
                order += 1
                if event != .boot { sawDisplayEvent = true }
            }
        }
        // Without a single display event the log tells us nothing usable; let
        // the live tracker answer instead.
        guard sawDisplayEvent else { return nil }
        entries.sort { ($0.date, $0.rank, $0.order) < ($1.date, $1.rank, $1.order) }

        let now = Date()

        var isOn = false
        for entry in entries where entry.date <= since {
            isOn = entry.event == .on
        }

        var total: TimeInterval = 0
        var cursor = since
        for entry in entries where entry.date > since && entry.date <= now {
            // A boot means the log skipped an unknown stretch of downtime, so
            // the span leading up to it is not screen time however it looks.
            if isOn, entry.event != .boot { total += entry.date.timeIntervalSince(cursor) }
            isOn = entry.event == .on
            cursor = entry.date
        }
        return (total, isOn ? cursor : now, isOn)
    }

    private static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

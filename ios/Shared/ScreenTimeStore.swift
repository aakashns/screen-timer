import Foundation

/// A confirmed screen-time total and the instant it was true.
struct ScreenTimeSnapshot {
    /// Seconds of screen time today that Screen Time itself has confirmed, by
    /// way of the last threshold event to fire.
    let confirmed: TimeInterval
    /// When that confirmation landed. The widget ticks on from here.
    let asOf: Date

    /// Range for a counting-up `Text(timerInterval:)`.
    ///
    /// WidgetKit will not re-render a widget every second — refreshes are
    /// budgeted at a few dozen a day — but `Text(timerInterval:)` is drawn and
    /// animated by the system, so it ticks with no refreshes at all. The trick
    /// is that it can only count from a fixed anchor, so the anchor is placed
    /// `confirmed` seconds *before* `asOf`: the timer then reads exactly
    /// `confirmed` at the moment the milestone landed and carries on from there.
    ///
    /// The upper bound freezes the tick one step later, which is when the next
    /// milestone should have arrived. Past that point the screen was evidently
    /// not on continuously, so ticking further would be inventing usage.
    var timerRange: ClosedRange<Date> {
        asOf.addingTimeInterval(-confirmed)...asOf.addingTimeInterval(Milestones.step)
    }

    /// What the tick reads right now, for the in-app display.
    ///
    /// Mirrors `timerRange` so the app and the widget never disagree.
    func estimate(now: Date = Date()) -> TimeInterval {
        confirmed + min(max(0, now.timeIntervalSince(asOf)), Milestones.step)
    }
}

/// Shared storage between the app, the monitor extension and the widget.
///
/// The *report* extension deliberately cannot participate: its sandbox blocks
/// app-group writes along with every other way out of its address space, which
/// is exactly why the milestone ladder exists.
struct ScreenTimeStore {

    static let appGroup = "group.com.aakashns.screentimer"
    static let shared = ScreenTimeStore()

    private let defaults: UserDefaults

    private let secondsKey = "confirmedSeconds"
    private let asOfKey = "confirmedAsOf"
    private let dayKey = "confirmedDay"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    /// Today's snapshot, or a zeroed one if nothing has been confirmed yet.
    ///
    /// The stored day is checked rather than trusted, so yesterday's milestone
    /// can never leak into today's total: the monitor zeroes it in
    /// `intervalDidStart`, but a widget can be asked to render before that
    /// callback arrives.
    func snapshot(now: Date = Date()) -> ScreenTimeSnapshot {
        guard defaults.string(forKey: dayKey) == Self.key(for: now),
              let asOf = defaults.object(forKey: asOfKey) as? Date else {
            return ScreenTimeSnapshot(confirmed: 0,
                                      asOf: Calendar.current.startOfDay(for: now))
        }
        return ScreenTimeSnapshot(confirmed: defaults.double(forKey: secondsKey), asOf: asOf)
    }

    /// Records a milestone. Never moves the total down, because thresholds are
    /// reported to have fired late, twice, and occasionally out of order.
    func record(seconds: TimeInterval, at date: Date = Date()) {
        guard seconds >= snapshot(now: date).confirmed else { return }
        defaults.set(seconds, forKey: secondsKey)
        defaults.set(date, forKey: asOfKey)
        defaults.set(Self.key(for: date), forKey: dayKey)
    }

    func reset(at date: Date = Date()) {
        defaults.set(0.0, forKey: secondsKey)
        defaults.set(Calendar.current.startOfDay(for: date), forKey: asOfKey)
        defaults.set(Self.key(for: date), forKey: dayKey)
    }

    static func formatted(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 3600, (total % 3600) / 60)
    }

    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

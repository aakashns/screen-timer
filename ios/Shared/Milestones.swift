import Foundation

/// The ladder of Screen Time thresholds that the monitor extension registers and
/// the widget interprets.
///
/// Screen Time totals cannot be read on demand: the only way real usage reaches
/// our own code is `DeviceActivityMonitor.eventDidReachThreshold`, which fires
/// when usage crosses a threshold we registered up front. So "how much screen
/// time today" is answered by a staircase of known crossings rather than a live
/// number, and everything else is interpolation.
enum Milestones {

    /// Gap between consecutive thresholds.
    ///
    /// This doubles as the widget's worst-case error. Between two milestones the
    /// widget ticks optimistically, as if the screen were on the whole time, and
    /// that tick is frozen after one step — so a long screen-off stretch can
    /// overstate the total by at most `step` before the display stops moving.
    static let step: TimeInterval = 15 * 60

    /// How many thresholds to register.
    ///
    /// `step * count` is the daily total past which no further correction
    /// arrives and the widget can only ever show the final milestone plus one
    /// step. DeviceActivity has an undocumented ceiling on events per activity,
    /// and exceeding it makes registration fail silently, so this is the first
    /// number to lower if `eventDidReachThreshold` never fires at all.
    static let count = 32   // 15 min x 32 = 8 h of coverage

    static func name(at index: Int) -> String { "milestone-\(index)" }

    /// Seconds of screen time that the event at `index` stands for.
    static func seconds(at index: Int) -> TimeInterval { step * Double(index + 1) }

    static func index(from name: String) -> Int? {
        guard name.hasPrefix("milestone-") else { return nil }
        return Int(name.dropFirst("milestone-".count))
    }
}

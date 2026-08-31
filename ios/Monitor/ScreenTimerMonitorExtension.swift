import DeviceActivity
import WidgetKit

/// Receives Screen Time threshold crossings and records them where the widget
/// can read them.
///
/// This is the only Screen Time extension point that is allowed to write to a
/// shared app group — the report extension's sandbox blocks it — so this class is
/// the entire bridge between real usage data and anything the user can see
/// outside the app.
final class ScreenTimerMonitorExtension: DeviceActivityMonitor {

    private let store = ScreenTimeStore.shared

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // A new daily interval means every threshold is counting from zero again,
        // so yesterday's total must not linger.
        store.reset()
        WidgetCenter.shared.reloadAllTimelines()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name,
                                         activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let index = Milestones.index(from: event.rawValue) else { return }
        store.record(seconds: Milestones.seconds(at: index))
        WidgetCenter.shared.reloadAllTimelines()
    }
}

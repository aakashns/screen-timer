import DeviceActivity
import FamilyControls
import Foundation

/// Sets up Screen Time monitoring: asks for authorization, then registers the
/// threshold ladder that feeds `ScreenTimeStore`.
@MainActor
final class ScreenTimeMonitor: ObservableObject {

    enum Authorization: Equatable {
        case unknown, approved, denied(String)
    }

    @Published private(set) var authorization: Authorization = .unknown

    /// One repeating daily activity. Thresholds are measured from the interval's
    /// start, so a midnight-to-midnight interval gives the daily reset for free.
    private let activity = DeviceActivityName("daily")
    private let center = DeviceActivityCenter()

    func start() async {
        do {
            // Already-granted authorization resolves immediately; this is safe
            // to call on every launch.
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = .approved
        } catch {
            authorization = .denied(error.localizedDescription)
            return
        }
        beginMonitoring()
    }

    private func beginMonitoring() {
        // 23:59 rather than 00:00, because an interval whose end equals its start
        // is rejected. The last minute of the day goes unmeasured as a result.
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true)

        // Empty application, category and web-domain sets mean "everything",
        // which is what makes this a total-screen-time measurement rather than a
        // per-app one — and is why no FamilyActivityPicker is needed.
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for index in 0..<Milestones.count {
            let seconds = Int(Milestones.seconds(at: index))
            events[DeviceActivityEvent.Name(Milestones.name(at: index))] =
                DeviceActivityEvent(applications: [],
                                    categories: [],
                                    webDomains: [],
                                    threshold: DateComponents(second: seconds))
        }

        // Restart rather than add, so changing the ladder in code takes effect
        // instead of colliding with a previously registered set.
        center.stopMonitoring([activity])
        do {
            try center.startMonitoring(activity, during: schedule, events: events)
        } catch {
            authorization = .denied("Could not start monitoring: \(error.localizedDescription)")
        }
    }
}

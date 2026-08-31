import DeviceActivity
import SwiftUI

@main
struct ScreenTimerReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalActivityScene { total in
            TotalActivityView(total: total)
        }
    }
}

/// Sums today's usage into a single string.
///
/// Everything here runs in a sandbox that blocks network access, app-group
/// writes, files, notifications, the pasteboard and iCloud key-value storage, so
/// `total` can be drawn and nothing else. Returning a preformatted string rather
/// than a number is a reminder of that: there is no caller to compute against.
struct TotalActivityScene: DeviceActivityReportScene {

    let context: DeviceActivityReport.Context = .totalActivity
    let content: (String) -> TotalActivityView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> String {
        var seconds: TimeInterval = 0
        for await each in data {
            for await segment in each.activitySegments {
                seconds += segment.totalActivityDuration
            }
        }
        return ScreenTimeStore.formatted(seconds)
    }
}

struct TotalActivityView: View {
    let total: String

    var body: some View {
        VStack(spacing: 6) {
            Text(total)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("Screen time today")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

import SwiftUI
import WidgetKit

@main
struct ScreenTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        ScreenTimerWidget()
    }
}

struct ScreenTimeEntry: TimelineEntry {
    let date: Date
    let snapshot: ScreenTimeSnapshot
}

struct ScreenTimeProvider: TimelineProvider {

    func placeholder(in context: Context) -> ScreenTimeEntry {
        ScreenTimeEntry(date: Date(),
                        snapshot: ScreenTimeSnapshot(confirmed: 0, asOf: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (ScreenTimeEntry) -> Void) {
        completion(ScreenTimeEntry(date: Date(), snapshot: ScreenTimeStore.shared.snapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScreenTimeEntry>) -> Void) {
        let now = Date()
        let snapshot = ScreenTimeStore.shared.snapshot(now: now)

        // The rendered view ticks by itself, so the timeline only needs an entry
        // wherever the *anchor* changes rather than one per visible second.
        var entries = [ScreenTimeEntry(date: now, snapshot: snapshot)]

        // Midnight has to zero the display even if the monitor's intervalDidStart
        // is late, which it often is.
        let calendar = Calendar.current
        if let midnight = calendar.date(byAdding: .day, value: 1,
                                        to: calendar.startOfDay(for: now)) {
            entries.append(ScreenTimeEntry(date: midnight,
                                           snapshot: ScreenTimeSnapshot(confirmed: 0,
                                                                        asOf: midnight)))
        }

        // Ask again once the current tick has frozen. Milestones also push a
        // reload the moment they land; this is the fallback for when they do not.
        let refresh = snapshot.asOf.addingTimeInterval(Milestones.step)
        completion(Timeline(entries: entries,
                            policy: .after(max(refresh, now.addingTimeInterval(60)))))
    }
}

struct ScreenTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScreenTimerWidget", provider: ScreenTimeProvider()) { entry in
            ScreenTimerWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Screen Timer")
        .description("How long your screen has been on today.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct ScreenTimerWidgetView: View {

    let entry: ScreenTimeEntry
    @Environment(\.widgetFamily) private var family

    /// The self-ticking readout.
    ///
    /// `Text(timerInterval:)` is animated by the system rather than by a widget
    /// refresh, which is the only way to get a live number into a widget at all —
    /// WidgetKit budgets refreshes at a few dozen a day and will not honour a
    /// per-second timeline.
    private var ticker: some View {
        Text(timerInterval: entry.snapshot.timerRange,
             pauseTime: entry.snapshot.timerRange.upperBound,
             countsDown: false,
             showsHours: true)
            .monospacedDigit()
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            // Inline gets one line and no custom styling, so the icon carries it.
            Label { ticker } icon: { Image(systemName: "iphone") }

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                ticker.font(.system(.caption, design: .rounded))
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("SCREEN ON")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                ticker.font(.system(.title2, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        default:
            VStack(spacing: 4) {
                Image(systemName: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ticker
                    .font(.system(size: family == .systemMedium ? 56 : 34,
                                  weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
    }
}

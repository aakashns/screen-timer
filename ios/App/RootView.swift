import DeviceActivity
import SwiftUI

struct RootView: View {

    @EnvironmentObject private var monitor: ScreenTimeMonitor
    @State private var showingSettings = false
    @State private var showingTruth = false
    @State private var snapshot = ScreenTimeStore.shared.snapshot()

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch monitor.authorization {
            case .unknown:
                ProgressView().tint(.white)
            case .denied(let message):
                DeniedView(message: message)
            case .approved:
                BigDigitsView(snapshot: snapshot)
            }

            VStack {
                Spacer()
                HStack(spacing: 28) {
                    Button { showingTruth = true } label: {
                        Label("Screen Time", systemImage: "chart.bar")
                    }
                    Button { showingSettings = true } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.bottom, 8)
        }
        .statusBarHidden()
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingTruth) { TruthSheet() }
        // A milestone can land while the app is backgrounded, so re-read on the
        // way in rather than trusting the value captured at init.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { snapshot = ScreenTimeStore.shared.snapshot() }
        }
    }
}

private struct DeniedView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.slash").font(.largeTitle)
            Text("Screen Time access is needed")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Grant it in Settings > Screen Time, then reopen this app.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(32)
    }
}

/// Today's total straight from Screen Time, for checking the widget against.
///
/// This is the only accurate reading in the app, and also the only place it can
/// legally appear: the number is rendered inside the report extension's own
/// process and never crosses back into ours.
private struct TruthSheet: View {
    /// Today, midnight to midnight, matching the monitor's daily interval.
    private var filter: DeviceActivityFilter {
        DeviceActivityFilter(
            segment: .daily(during: Calendar.current.dateInterval(of: .day, for: .now)
                ?? DateInterval(start: .now, duration: 86_400)),
            users: .all,
            devices: .init([.iPhone, .iPad]))
    }

    var body: some View {
        NavigationStack {
            DeviceActivityReport(.totalActivity, filter: filter)
                .navigationTitle("Screen Time")
        }
    }
}

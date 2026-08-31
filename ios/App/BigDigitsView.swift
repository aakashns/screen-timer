import Combine
import SwiftUI

/// The large ticking `HH:MM` readout, ported from the macOS overlay.
struct BigDigitsView: View {

    let snapshot: ScreenTimeSnapshot

    @AppStorage(AppearanceKey.corner) private var corner: DigitCorner = .center
    @AppStorage(AppearanceKey.size) private var size: DigitSize = .medium
    @AppStorage(AppearanceKey.transparency) private var transparency: DigitTransparency = .low

    /// Drives the in-app readout. The widget gets its tick free from the system,
    /// but a foreground view has to ask for one.
    @State private var now = Date()

    var body: some View {
        GeometryReader { geometry in
            let fontSize = min(geometry.size.width, geometry.size.height) * size.fontScale

            Text(ScreenTimeStore.formatted(snapshot.estimate(now: now)))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                // Equal advances for every digit, so the number does not jitter
                // sideways as the minutes change. Same reason the macOS build
                // measures against an all-zeros reference string.
                .monospacedDigit()
                .foregroundStyle(.white)
                .opacity(transparency.opacity)
                .shadow(color: .black.opacity(0.55), radius: fontSize * 0.06, y: fontSize * 0.015)
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: corner.alignment)
        }
        .padding(20)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

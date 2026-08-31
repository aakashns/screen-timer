import SwiftUI

struct SettingsView: View {

    @AppStorage(AppearanceKey.corner) private var corner: DigitCorner = .center
    @AppStorage(AppearanceKey.size) private var size: DigitSize = .medium
    @AppStorage(AppearanceKey.transparency) private var transparency: DigitTransparency = .low

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Position") {
                    Picker("Position", selection: $corner) {
                        ForEach(DigitCorner.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Size") {
                    Picker("Size", selection: $size) {
                        ForEach(DigitSize.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("Transparency") {
                    Picker("Transparency", selection: $transparency) {
                        ForEach(DigitTransparency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("Accuracy") {
                    Text("Screen Time confirms the total every \(Int(Milestones.step / 60)) minutes. Between confirmations the number ticks as though the screen stayed on, then stops until the next one lands.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

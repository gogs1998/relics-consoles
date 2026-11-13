import SwiftUI

/// Settings: haptics, game volume, the default screen filter, fast-forward speed and auto-save.
/// Changes apply at once, in the game too.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = AppSettings.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $settings.haptics) {
                        row("Haptics", detail: "A tap you can feel on each button press", symbol: "hand.tap.fill")
                    }
                    .tint(Theme.ember)
                    .accessibilityIdentifier("settings.haptics")
                    VStack(alignment: .leading, spacing: 8) {
                        row("Game volume", detail: nil, symbol: "speaker.wave.2.fill")
                        HStack(spacing: 12) {
                            Image(systemName: "speaker.fill").foregroundStyle(Theme.inkDim).accessibilityHidden(true)
                            Slider(value: $settings.volume, in: 0...1)
                                .tint(Theme.ember)
                                .accessibilityLabel("Game volume")
                                .accessibilityValue("\(Int((settings.volume * 100).rounded())) percent")
                                .accessibilityIdentifier("settings.volume")
                            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.inkDim).accessibilityHidden(true)
                        }
                    }
                } header: { header("Feel and sound") }

                Section {
                    ForEach(ScreenMode.allCases) { mode in
                        Button { settings.screenMode = mode } label: {
                            HStack {
                                row(mode.title, detail: detail(mode), symbol: mode.symbol)
                                Spacer()
                                if settings.screenMode == mode {
                                    Image(systemName: "checkmark").font(.rounded(.body, weight: .bold)).foregroundStyle(Theme.ember)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(settings.screenMode == mode ? .isSelected : [])
                        .accessibilityIdentifier("settings.screen.\(mode.rawValue)")
                    }
                } header: { header("Screen filter") } footer: {
                    Text("The pause menu can still pick a filter for one system. Choosing a default here resets those choices.")
                        .font(.rounded(.footnote, weight: .regular))
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Fast-forward speed", detail: nil, symbol: "forward.fill")
                        Picker("Fast-forward speed", selection: $settings.fastForwardSpeed) {
                            ForEach(AppSettings.fastForwardChoices, id: \.self) { Text("\($0)×").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.fastForward")
                    }
                    Toggle(isOn: $settings.autoSave) {
                        row("Auto-save", detail: "Saves your place when you close the Duo, leave the app or quit, and picks up there next time",
                            symbol: "clock.arrow.circlepath")
                    }
                    .tint(Theme.ember)
                    .accessibilityIdentifier("settings.autoSave")
                } header: { header("Play") } footer: {
                    Text("Games' own saves are always kept, whatever you choose here.")
                        .font(.rounded(.footnote, weight: .regular))
                }
            }
            .scrollContentBackground(.hidden)
            .background(BodySurface())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.rounded(.body, weight: .bold))
                        .tint(Theme.ember)
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.rounded(.caption, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(Theme.inkDim)
    }

    private func row(_ title: String, detail: String?, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.rounded(.body, weight: .semibold))
                .foregroundStyle(Theme.ember)
                .frame(minWidth: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.rounded(.body, weight: .semibold)).foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail).font(.rounded(.footnote, weight: .regular)).foregroundStyle(Theme.inkDim)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ mode: ScreenMode) -> String {
        switch mode {
        case .auto: "Pixel-perfect when it fills the screen, Sharp otherwise"
        case .sharp: "Crisp pixels at any size"
        case .integer: "Whole-number scaling, nearest pixels"
        case .scanlines: "Soft lines like a CRT television"
        case .lcd: "A fine pixel grid like a handheld screen"
        }
    }
}

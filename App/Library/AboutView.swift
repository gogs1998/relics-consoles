import SwiftUI

/// About: what the app is (and isn't), the non-affiliation line, and the licences.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Licence: Identifiable {
        let id: String
        let title: String
        let detail: String
        let file: String
    }

    private let licences = [
        Licence(id: "mgba", title: "mGBA", detail: "Game Boy Advance core · MPL-2.0 · an unmodified copy of commit 662dada; its source is at github.com/mgba-emu/mgba/tree/662dada",
                file: "Licence-mGBA-MPL-2.0"),
        Licence(id: "inih", title: "inih", detail: "Part of mGBA · BSD 3-Clause", file: "Licence-inih-BSD-3-Clause"),
        Licence(id: "ares", title: "ares", detail: "SNES and Mega Drive cores · ISC, with MAME-derived parts under BSD 3-Clause · commit 0b92893, github.com/ares-emulator/ares",
                file: "Licence-ares-ISC-and-bundled"),
        Licence(id: "qon", title: "qon", detail: "Part of ares · MIT", file: "Licence-qon-MIT"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Foldback plays games you own. It includes no games and no console system software, and never downloads any.")
                    Text("Foldback is not affiliated with, endorsed or sponsored by Nintendo or Sega. Console names are trademarks of their owners and are used only to say which game files the app can open.")
                        .foregroundStyle(.secondary)
                }
                Section("Our own work") {
                    Text("The NES and Game Boy / Game Boy Color cores, the app, its controller and art are original IQ Labs work.")
                }
                Section("Acknowledgements") {
                    ForEach(licences) { l in
                        NavigationLink {
                            ScrollView {
                                Text(text(for: l.file))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding()
                            }
                            .navigationTitle(l.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l.title).font(.rounded(.body, weight: .semibold))
                                Text(l.detail).font(.rounded(.caption)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Privacy") {
                    Text("No accounts, no ads, no analytics. Nothing leaves your device.")
                }
            }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func text(for file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "Licence text missing." }
        return s
    }
}

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
        Licence(id: "melonds", title: "melonDS", detail: "Nintendo DS core · GPL-3.0-or-later · an unmodified copy of commit 497aa6c; its source is at github.com/melonDS-emu/melonDS/tree/497aa6c",
                file: "Licence-melonDS-GPL-3.0"),
        Licence(id: "freebios", title: "FreeBIOS", detail: "Part of melonDS · the DS BIOS replacement by Gilead Kutnick (no Nintendo code) · BSD 2-Clause",
                file: "Licence-FreeBIOS-BSD-2-Clause"),
        Licence(id: "mupen64plus", title: "mupen64plus and rsp-hle",
                detail: "Nintendo 64 core and RSP · GPL-2.0-or-later · unmodified copies of mupen64plus-core commit daae68e and mupen64plus-rsp-hle commit 4cdc305; their source is at github.com/mupen64plus",
                file: "Licence-mupen64plus-GPL-2.0-or-later"),
        Licence(id: "mupen64plus-bundled", title: "MiniZip, MD5, xxHash, CIC-NUS-6105", detail: "Parts of mupen64plus · zlib, BSD 2-Clause",
                file: "Licence-mupen64plus-bundled"),
        Licence(id: "melonds-bundled", title: "xxHash, FatFs, tiny-AES-c, blip_buf", detail: "Parts of melonDS · BSD 2-Clause, FatFs, Unlicense, LGPL-2.1",
                file: "Licence-melonDS-bundled"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Relics: Games plays games you own. It includes no games and no console system software, and never downloads any.")
                    Text("Relics: Games is not affiliated with, endorsed or sponsored by Nintendo or Sega. Console names are trademarks of their owners and are used only to say which game files the app can open.")
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

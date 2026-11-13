import SwiftUI

/// About: what the app is (and isn't), the non-affiliation line, and the licences.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showSpeedTest = false

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
        Licence(id: "parallel-rdp", title: "paraLLEl-RDP, Granite and volk",
                detail: "Nintendo 64 graphics (RDP) on the GPU · MIT · unmodified copies of parallel-rdp-standalone commit 388d70f (github.com/Themaister/parallel-rdp-standalone) and the volk loader it bundles (github.com/zeux/volk)",
                file: "Licence-paraLLEl-RDP-MIT"),
        Licence(id: "moltenvk", title: "MoltenVK, SPIRV-Cross, cereal and Vulkan-Headers",
                detail: "Vulkan on Metal for the N64 graphics · Apache-2.0 (MoltenVK v1.4.2, SPIRV-Cross, Vulkan-Headers), BSD 3-Clause (cereal) · github.com/KhronosGroup/MoltenVK",
                file: "Licence-MoltenVK-Apache-2.0-and-bundled"),
        Licence(id: "cxd4", title: "cxd4 RSP interpreter",
                detail: "Nintendo 64 RSP for graphics tasks · CC0 1.0 (public domain dedication) by Iconoclast · an unmodified copy of mupen64plus-rsp-cxd4 commit b8e747b (github.com/mupen64plus/mupen64plus-rsp-cxd4)",
                file: "Licence-cxd4-CC0-1.0"),
        Licence(id: "gpl3", title: "GNU GPL 3.0", detail: "The licence of the app as a whole, of melonDS and of the GPL demos",
                file: "Licence-GPL-3.0"),
        Licence(id: "ccbysa", title: "CC BY-SA 4.0", detail: "The licence of µCity's and Alex vs Bus's graphics and music",
                file: "Licence-CC-BY-SA-4.0"),
        Licence(id: "melonds-bundled", title: "xxHash, FatFs, tiny-AES-c, blip_buf", detail: "Parts of melonDS · BSD 2-Clause, FatFs, Unlicense, LGPL-2.1",
                file: "Licence-melonDS-bundled"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Relics: Games plays games you own. It includes a few free homebrew demos, shared by their authors under free licences, and no Nintendo or Sega system software. It never downloads games.")
                    Text("Relics: Games is not affiliated with, endorsed or sponsored by Nintendo or Sega. Console names are trademarks of their owners and are used only to say which game files the app can open.")
                        .foregroundStyle(.secondary)
                }
                Section("Our own work") {
                    Text("The NES and Game Boy / Game Boy Color cores, the app, its controller and art are original IQ Labs work.")
                    Text("Relics: Games © 2026 IQ Labs. It is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License, version 3 or (at your option) any later version. It comes with NO WARRANTY. See GNU GPL 3.0 below.")
                        .foregroundStyle(.secondary)
                }
                Section("Free demos") {
                    licenceLink(Licence(id: "demos", title: "Demos on your shelf",
                                        detail: "µCity by Antonio Niño Díaz · Libbet and the Magic Floor, Thwaite and Concentration Room by Damian Yerrick · Alex vs Bus: The Race by M374LX · GPL-3.0-or-later, CC BY-SA 4.0, zlib · credits, licences and where to get the source",
                                        file: "Licence-demos-credits"))
                }
                Section("Acknowledgements") {
                    ForEach(licences) { l in licenceLink(l) }
                }
                Section("Privacy") {
                    Text("No accounts, no ads, no analytics. Nothing leaves your device.")
                }
                Section {
                    // Long-press opens the hidden N64 speed test (N64SpeedTestView).
                    Text(versionLine)
                        .font(.rounded(.footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 1) { showSpeedTest = true }
                        .accessibilityAction(named: "N64 speed test") { showSpeedTest = true }
                }
            }
            .navigationDestination(isPresented: $showSpeedTest) { N64SpeedTestView() }
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(version) (\(build))"
    }

    private func licenceLink(_ l: Licence) -> some View {
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

    private func text(for file: String) -> String {
        guard let url = Bundle.main.url(forResource: file, withExtension: "txt"),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return "Licence text missing." }
        return s
    }
}

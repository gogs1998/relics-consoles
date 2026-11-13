import N64Core
import SwiftUI
import UIKit

/// Hidden N64 speed test (About › long-press the version line). Runs our own bench ROM through the N64 renderer
/// (paraLLEl-RDP on MoltenVK + cxd4), synchronous then asynchronous, and shows fps with a CPU / RSP / RDP / GPU
/// breakdown and the thermal state, with a Share button for the report. Nothing else of N64 is reachable in
/// Release builds (N64_ENABLED is Debug-only). See docs/n64-rdp-spike.md.
struct N64SpeedTestView: View {
    @StateObject private var model = N64SpeedTestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Runs a built-in test scene (our own, not a game) as fast as it can, twice, and measures how fast this device could play Nintendo 64 games. It takes about two minutes; keep the app open and the screen on.")
                    .font(.rounded(.subheadline))
                    .foregroundStyle(.secondary)
                if let frame = model.frame {
                    Image(decorative: frame, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Test scene")
                }
                Text(model.status)
                    .font(.system(.footnote, design: .monospaced))
                    .accessibilityLabel("Status: \(model.status)")
                HStack(spacing: 16) {
                    Button(model.running ? "Running…" : (model.report.isEmpty ? "Start" : "Run again")) {
                        model.start()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.running)
                    .accessibilityHint("Runs the N64 speed test for about two minutes")
                    if !model.report.isEmpty && !model.running {
                        ShareLink(item: model.report) {
                            Label("Share report", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share report")
                    }
                }
                if !model.report.isEmpty {
                    Text(model.report)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .navigationTitle("N64 speed test")
        .onDisappear { model.leave() }
    }
}

@MainActor
final class N64SpeedTestModel: ObservableObject {
    @Published var frame: CGImage?
    @Published var status = "Ready."
    @Published var report = ""
    @Published var running = false

    func start() {
        guard !running else { return }
        running = true
        report = ""
        status = "Starting…"
        UIApplication.shared.isIdleTimerDisabled = true
        let header = Self.deviceLine()
        Thread.detachNewThread { [weak self] in
            let text = Self.runBoth(header: header) { status, pixels in
                Task { @MainActor in self?.show(status: status, pixels: pixels) }
            } partial: { text in
                Task { @MainActor in self?.report = text }
            }
            Task { @MainActor in self?.finish(text) }
        }
    }

    func leave() {
        if !running { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func finish(_ text: String) {
        report = text
        running = false
        status = "Done. Tap Share report to send it."
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func show(status: String, pixels: Data?) {
        self.status = status
        guard let pixels, let provider = CGDataProvider(data: pixels as CFData) else { return }
        frame = CGImage(width: 320, height: 240, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 320 * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                 | CGBitmapInfo.byteOrder32Little.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Runs on the bench thread: synchronous, then asynchronous RDP.
    nonisolated private static func runBoth(header: String,
                                            progress: @escaping @Sendable (String, Data?) -> Void,
                                            partial: @escaping @Sendable (String) -> Void) -> String {
        var text = header
        for synchronous in [true, false] {
            let before = thermal()
            let result = N64SpeedTest.run(synchronous: synchronous) { status, frame in
                progress(status, frame.map { Data(bytes: $0, count: 320 * 240 * 4) })
            }
            text += "\n" + result.report + "Thermal state: \(before) before, \(thermal()) after\n"
            partial(text)
            if !result.ok { break }
        }
        return text
    }

    nonisolated private static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private static func deviceLine() -> String {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Relics: Games \(version) (\(build)) N64 speed test · \(machine) · iOS \(UIDevice.current.systemVersion)\n"
    }
}

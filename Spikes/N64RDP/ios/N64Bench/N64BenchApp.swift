// N64 RDP spike: on-device benchmark (plain iPhone). Part of Relics: Games (GPLv3). Throwaway, see
// docs/n64-rdp-spike.md. Runs our own bench ROM through paraLLEl-RDP on MoltenVK + cxd4, synchronous then
// asynchronous RDP, and shows fps with the CPU / RSP / RDP / GPU breakdown.
import SwiftUI
import UIKit

@main
struct N64BenchApp: App {
    var body: some Scene {
        WindowGroup { BenchView() }
    }
}

final class BenchModel: ObservableObject {
    static let shared = BenchModel()
    @Published var frame: CGImage?
    @Published var status = "Starting…"
    @Published var report = ""
    @Published var running = false

    func start() {
        guard !running else { return }
        running = true
        report = ""
        UIApplication.shared.isIdleTimerDisabled = true
        let thread = Thread { BenchModel.runAll() }
        thread.stackSize = 16 << 20
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static func runAll() {
        guard let romURL = Bundle.main.url(forResource: "n64_rdpbench", withExtension: "z64"),
              let rom = try? Data(contentsOf: romURL),
              let ini = Bundle.main.url(forResource: "mupen64plus", withExtension: "ini") else {
            post(report: "Bench ROM or mupen64plus.ini missing from the bundle")
            return
        }
        let dataDir = ini.deletingLastPathComponent().path
        var text = "\(UIDevice.current.model), iOS \(UIDevice.current.systemVersion), \(machine())\n"
        for sync in [true, false] {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            var buf = [CChar](repeating: 0, count: 16384)
            let thermalBefore = thermal()
            let ok = rom.withUnsafeBytes { raw in
                n64bench_run(raw.bindMemory(to: UInt8.self).baseAddress, rom.count, work.path, dataDir, sync,
                             { line, fb, _ in BenchModel.progress(line, fb) }, nil, &buf, buf.count)
            }
            try? FileManager.default.removeItem(at: work)
            text += "\n" + String(cString: buf)
            text += "Thermal state: \(thermalBefore) before, \(thermal()) after\n"
            print(String(cString: buf))
            post(report: text)
            if !ok { break }
        }
        DispatchQueue.main.async {
            BenchModel.shared.running = false
            BenchModel.shared.status = "Done"
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private static func progress(_ line: UnsafePointer<CChar>?, _ fb: UnsafePointer<UInt32>?) {
        let status = line.map { String(cString: $0) } ?? ""
        var image: CGImage?
        if let fb {
            let data = Data(bytes: fb, count: 320 * 240 * 4)
            if let provider = CGDataProvider(data: data as CFData) {
                image = CGImage(width: 320, height: 240, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 320 * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                         | CGBitmapInfo.byteOrder32Little.rawValue),
                                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
            }
        }
        DispatchQueue.main.async {
            BenchModel.shared.status = status
            if let image { BenchModel.shared.frame = image }
        }
    }

    private static func post(report: String) {
        DispatchQueue.main.async { BenchModel.shared.report = report }
    }

    private static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func machine() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }
}

struct BenchView: View {
    @ObservedObject private var model = BenchModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let frame = model.frame {
                    Image(decorative: frame, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(4 / 3, contentMode: .fit)
                        .accessibilityLabel("Current benchmark frame")
                }
                Text(model.status)
                    .font(.system(.footnote, design: .monospaced))
                Text(model.report)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Button(model.running ? "Running…" : "Run again") { model.start() }
                        .disabled(model.running)
                    if !model.report.isEmpty {
                        ShareLink("Share report", item: model.report)
                    }
                }
            }
            .padding()
        }
        .onAppear { model.start() }
    }
}

import CoreGraphics
import CoreKit
import Foundation
@testable import GBCore
import ImageIO
@testable import NESCore
import Testing

/// Third-party accuracy suites (downloaded to TestSuites/, gitignored; approved by Gordon 11 Nov 2026).
/// Runs only when ACCURACY_DIR points at TestSuites. Writes a markdown report to ACCURACY_OUT.
///
///     ACCURACY_DIR=$PWD/../../TestSuites ACCURACY_OUT=/tmp/acc.md swift test -c release --filter Accuracy
@Suite(.serialized) struct AccuracyTests {
    static let dir = ProcessInfo.processInfo.environment["ACCURACY_DIR"].map { URL(fileURLWithPath: $0) }
    static let out = ProcessInfo.processInfo.environment["ACCURACY_OUT"]
    static let only = ProcessInfo.processInfo.environment["ACCURACY_ONLY"]

    struct Row { var suite: String; var test: String; var result: String; var pass: Bool? }

    static func files(_ sub: String, ext: Set<String>) -> [URL] {
        guard let base = dir?.appendingPathComponent(sub),
              let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var list: [URL] = []
        for case let u as URL in e where ext.contains(u.pathExtension.lowercased()) { list.append(u) }
        return list.sorted { $0.path < $1.path }
    }

    static func rel(_ u: URL, _ sub: String) -> String {
        u.path.replacingOccurrences(of: dir!.appendingPathComponent(sub).path + "/", with: "")
    }

    // MARK: NES

    /// blargg's $6000 protocol: $6001-3 = DE B0 61, $6000 = $80 running, $81 needs reset, else result code.
    static func runBlargg(_ url: URL, maxFrames: Int = 3600) -> (String, Bool?) {
        guard let data = try? Data(contentsOf: url) else { return ("unreadable", nil) }
        let nes: NESSystem
        do { nes = try NESSystem(rom: data, battery: nil) } catch {
            return ("not run: \((error as? LocalizedError)?.errorDescription ?? "\(error)")", nil)
        }
        var started = false
        var resetAt = -1
        for f in 0..<maxFrames {
            nes.runFrame(input: [])
            let sig = nes.debugPeek(0x6001) == 0xDE && nes.debugPeek(0x6002) == 0xB0 && nes.debugPeek(0x6003) == 0x61
            if sig { started = true }
            guard started else { if f > 600 { break } else { continue } }
            let status = nes.debugPeek(0x6000)
            if status == 0x81 {
                if resetAt < 0 { resetAt = f + 8 }
                if f == resetAt { nes.reset(); resetAt = -1 }
                continue
            }
            if status < 0x80 {
                var text = ""
                var a: UInt16 = 0x6004
                while a < 0x7000 {
                    let c = nes.debugPeek(a)
                    if c == 0 { break }
                    text.append(Character(UnicodeScalar(c)))
                    a += 1
                }
                let summary = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " / ")
                return (status == 0 ? "PASS" : "FAIL \(status): \(summary.prefix(140))", status == 0)
            }
        }
        return (started ? "timed out" : "no $6000 result (screen-only test)", nil)
    }

    static func runNestest() -> (String, Bool?) {
        guard let url = files("nes-test-roms/other", ext: ["nes"]).first(where: { $0.lastPathComponent == "nestest.nes" }),
              let data = try? Data(contentsOf: url), let nes = try? NESSystem(rom: data, battery: nil) else {
            return ("missing", nil)
        }
        nes.pc = 0xC000
        for _ in 0..<9000 { nes.stepInstruction() }
        let official = nes.debugPeek(0x02), unofficial = nes.debugPeek(0x03)
        let ok = official == 0 && unofficial == 0
        return (ok ? "PASS (official and unofficial)" :
                    String(format: "FAIL: official $%02X, unofficial $%02X", official, unofficial), ok)
    }

    /// AccuracyCoin: press Start on the menu (runs every test), then read each test's result byte.
    static func runAccuracyCoin() -> [Row] {
        guard let base = dir?.appendingPathComponent("AccuracyCoin"),
              let data = try? Data(contentsOf: base.appendingPathComponent("AccuracyCoin.nes")),
              let asm = try? String(contentsOf: base.appendingPathComponent("AccuracyCoin.asm"), encoding: .utf8),
              let nes = try? NESSystem(rom: data, battery: nil) else { return [Row(suite: "AccuracyCoin", test: "-", result: "missing", pass: nil)] }
        // symbol = $addr
        var symbols: [String: UInt16] = [:]
        var tests: [(String, String)] = []
        var page = ""
        for raw in asm.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("Suite_") && t.hasSuffix(":") { page = String(t.dropFirst(6).dropLast()) }
            if let eq = t.firstIndex(of: "="), t.hasPrefix("result_") {
                let name = t[..<eq].trimmingCharacters(in: .whitespaces)
                let val = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if val.hasPrefix("$"), let v = UInt16(val.dropFirst(), radix: 16) { symbols[name] = v }
            }
            if t.hasPrefix("table \""), let q2 = t.dropFirst(7).firstIndex(of: "\"") {
                let name = String(t[t.index(t.startIndex, offsetBy: 7)..<q2])
                let parts = t[t.index(after: q2)...].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2 { tests.append(("\(page): \(name)", parts[1])) }
            }
        }
        for _ in 0..<90 { nes.runFrame(input: []) }
        for _ in 0..<6 { nes.runFrame(input: [.start]) }
        for _ in 0..<9000 { nes.runFrame(input: []) }
        var rows: [Row] = []
        for (name, sym) in tests {
            guard let addr = symbols[sym] else { continue }
            let v = nes.debugPeek(addr)
            if addr < 0x0400 { continue }   // "draw" tests on page 3 aren't pass/fail
            let pass = (v & 1) == 1
            rows.append(Row(suite: "AccuracyCoin", test: name,
                            result: v == 0xFF ? "skipped" : (pass ? "PASS" : "FAIL code \(v >> 2)"), pass: v == 0xFF ? nil : pass))
        }
        if let outDir = ProcessInfo.processInfo.environment["DUMP_DIR"] {
            writePNG(nes.framebuffer, width: 256, height: 240, to: "\(outDir)/accuracycoin.png")
        }
        return rows
    }

    // MARK: Game Boy

    enum GBVerdict { case serialText, mooneye }

    static func runGB(_ url: URL, verdict: GBVerdict, maxFrames: Int = 3600) -> (String, Bool?) {
        guard let data = try? Data(contentsOf: url) else { return ("unreadable", nil) }
        let gb: GBSystem
        do { gb = try GBSystem(rom: data, battery: nil) } catch {
            return ("not run: \((error as? LocalizedError)?.errorDescription ?? "\(error)")", nil)
        }
        for _ in 0..<maxFrames {
            gb.runFrame(input: [])
            let log = gb.serialLog
            switch verdict {
            case .mooneye:
                if log.count >= 6 {
                    let tail = Array(log.suffix(6))
                    if tail == [3, 5, 8, 13, 21, 34] { return ("PASS", true) }
                    if tail.allSatisfy({ $0 == 0x42 }) { return ("FAIL", false) }
                }
            case .serialText:
                let text = String(decoding: log, as: UTF8.self)
                if text.contains("Passed") { return ("PASS", true) }
                if text.contains("Failed") {
                    let s = text.replacingOccurrences(of: "\n", with: " / ")
                    return ("FAIL: \(s.suffix(140))", false)
                }
            }
        }
        let text = String(decoding: gb.serialLog.filter { $0 >= 32 && $0 < 127 }, as: UTF8.self)
        return ("timed out\(text.isEmpty ? "" : ": " + String(text.suffix(100)))", nil)
    }

    /// acid2: run, then compare with the reference picture through a colour bijection
    /// (our palettes differ from the reference's, the structure must not).
    static func runAcid(_ rom: URL, reference: URL) -> (String, Bool?) {
        guard let data = try? Data(contentsOf: rom), let gb = try? GBSystem(rom: data, battery: nil),
              let src = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return ("missing", nil) }
        for _ in 0..<120 { gb.runFrame(input: []) }
        let w = 160, h = 144
        var ref = [UInt32](repeating: 0, count: w * h)
        ref.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let ours = Array(gb.framebuffer)
        var fwd: [UInt32: UInt32] = [:], back: [UInt32: UInt32] = [:]
        var bad = 0
        for i in 0..<(w * h) {
            let r = ref[i] | 0xFF000000, o = ours[i] | 0xFF000000
            if let m = fwd[r], m != o { bad += 1; continue }
            if let m = back[o], m != r { bad += 1; continue }
            fwd[r] = o; back[o] = r
        }
        if let outDir = ProcessInfo.processInfo.environment["DUMP_DIR"] {
            gb.framebuffer.withMemoryRebound(to: UInt32.self) { writePNG($0, width: w, height: h, to: "\(outDir)/\(rom.deletingPathExtension().lastPathComponent).png") }
        }
        return (bad == 0 ? "PASS" : "FAIL: \(bad) pixels differ", bad == 0)
    }

    // MARK: the run

    @Test func runSuites() throws {
        guard Self.dir != nil else { return }
        var rows: [Row] = []
        func want(_ s: String) -> Bool { Self.only == nil || s.contains(Self.only!) }

        if want("nestest") { let r = Self.runNestest(); rows.append(Row(suite: "nestest", test: "nestest.nes (automation)", result: r.0, pass: r.1)) }

        if want("nes") {
            for u in Self.files("nes-test-roms", ext: ["nes"]) {
                let r = Self.runBlargg(u)
                rows.append(Row(suite: "nes-test-roms", test: Self.rel(u, "nes-test-roms"), result: r.0, pass: r.1))
            }
        }
        if want("AccuracyCoin") { rows += Self.runAccuracyCoin() }

        if want("gb") {
            let blargg = Self.files("gb-collection/blargg", ext: ["gb", "gbc"])
            for u in blargg {
                let r = Self.runGB(u, verdict: .serialText, maxFrames: 4000)
                rows.append(Row(suite: "blargg (GB)", test: Self.rel(u, "gb-collection/blargg"), result: r.0, pass: r.1))
            }
            for u in Self.files("gb-collection/mooneye-test-suite", ext: ["gb"]) {
                let name = u.lastPathComponent
                // Hardware-model-specific tests for models we don't emulate are skipped.
                let other = ["-mgb", "-sgb", "-sgb2", "-S.gb", "-A.gb", "-dmg0", "-cgb", "-C.gb", "-agb", "-ags", "-G.gb"]
                if other.contains(where: { name.contains($0) }) && !name.contains("dmgABC") { continue }
                if u.path.contains("/manual-only/") || u.path.contains("/utils/") { continue }
                let r = Self.runGB(u, verdict: .mooneye, maxFrames: 1200)
                rows.append(Row(suite: "mooneye", test: Self.rel(u, "gb-collection/mooneye-test-suite"), result: r.0, pass: r.1))
            }
            for (rom, ref) in [("dmg-acid2/dmg-acid2.gb", "dmg-acid2/dmg-acid2-dmg.png"),
                               ("cgb-acid2/cgb-acid2.gbc", "cgb-acid2/cgb-acid2.png")] {
                guard let base = Self.dir?.appendingPathComponent("gb-collection") else { continue }
                let r = Self.runAcid(base.appendingPathComponent(rom), reference: base.appendingPathComponent(ref))
                rows.append(Row(suite: "acid2", test: rom, result: r.0, pass: r.1))
            }
        }

        // Report
        var md = ""
        var bySuite: [String: (Int, Int, Int)] = [:]
        for r in rows {
            var t = bySuite[r.suite] ?? (0, 0, 0)
            switch r.pass { case true?: t.0 += 1; case false?: t.1 += 1; case nil: t.2 += 1 }
            bySuite[r.suite] = t
        }
        md += "| Suite | Pass | Fail | Not automated / not run |\n|---|---|---|---|\n"
        for (s, t) in bySuite.sorted(by: { $0.key < $1.key }) { md += "| \(s) | \(t.0) | \(t.1) | \(t.2) |\n" }
        md += "\n"
        for suite in Array(Set(rows.map(\.suite))).sorted() {
            md += "### \(suite)\n\n| Test | Result |\n|---|---|\n"
            for r in rows where r.suite == suite {
                md += "| \(r.test.replacingOccurrences(of: "|", with: "/")) | \(r.result.replacingOccurrences(of: "|", with: "/")) |\n"
            }
            md += "\n"
        }
        if let out = Self.out { try md.write(toFile: out, atomically: true, encoding: .utf8) }
        print(md.prefix(1500))
    }
}

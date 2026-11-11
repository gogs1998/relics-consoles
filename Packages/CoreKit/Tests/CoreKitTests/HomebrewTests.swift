import CoreKit
import Foundation
@testable import GBCore
import Testing

/// Approved homebrew (TestSuites/homebrew, gitignored). Runs only when ACCURACY_DIR is set.
@Test func homebrewLibbet() throws {
    guard let dir = ProcessInfo.processInfo.environment["ACCURACY_DIR"] else { return }
    let url = URL(fileURLWithPath: dir).appendingPathComponent("homebrew/libbet.gb")
    guard let data = try? Data(contentsOf: url) else { return }
    let gb = try GBSystem(rom: data, battery: nil)
    var colours = Set<UInt32>()
    var peak: Float = 0
    for f in 0..<1500 {
        let input: InputState = (f % 120 < 10) ? [.start] : ((f % 120 < 30) ? [.a] : (f > 600 ? [.right] : []))
        gb.runFrame(input: input)
        for s in gb.debugPendingAudio { peak = max(peak, abs(s)) }
        gb.discardAudio()
        if f % 100 == 0 { colours.formUnion(gb.framebuffer) }
        if let out = ProcessInfo.processInfo.environment["DUMP_DIR"], [200, 700, 1400].contains(f) {
            writePNG(gb.framebuffer, width: 160, height: 144, to: "\(out)/libbet-\(f).png")
        }
    }
    print("libbet: \(colours.count) colours, audio peak \(peak)")
    #expect(colours.count >= 3)
    #expect(peak > 0.01)
}

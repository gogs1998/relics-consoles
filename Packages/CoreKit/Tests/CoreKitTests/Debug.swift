import CoreGraphics
import CoreKit
import Foundation
import ImageIO
@testable import NESCore
import Testing
import UniformTypeIdentifiers

func writePNG(_ fb: UnsafeBufferPointer<UInt32>, width: Int, height: Int, to path: String) {
    var px = Array(fb)
    let ctx = px.withUnsafeMutableBytes { raw in
        CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    }
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Dumps frames to $DUMP_DIR when set (manual visual check).
@Test func dumpFrames() throws {
    guard let dir = ProcessInfo.processInfo.environment["DUMP_DIR"] else { return }
    for name in ["demo", "cpu_selftest"] {
        let nes = try NESSystem(rom: try testROM("\(name).nes"), battery: nil)
        for f in 0..<150 { nes.runFrame(input: f > 60 && f < 100 ? [.right] : (f == 110 ? [.a] : [])) }
        writePNG(nes.framebuffer, width: 256, height: 240, to: "\(dir)/\(name).png")
    }
}

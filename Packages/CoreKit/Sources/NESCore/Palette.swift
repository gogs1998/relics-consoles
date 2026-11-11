import Foundation

/// Generates the 64-colour master palette (and its eight emphasis variants) from a simple
/// model of the composite signal: each colour is a square wave between two voltage levels,
/// decoded as YIQ. Our own derivation; no third-party palette file is used.
enum NESPalette {
    static func fill(_ out: UnsafeMutablePointer<UInt32>) {
        // Signal levels per luma row, normalised so black = 0 and white = 1.
        let low: [Double] = [-0.117, 0.000, 0.308, 0.715]
        let high: [Double] = [0.397, 0.681, 1.000, 1.000]
        for emphasis in 0..<8 {
            for luma in 0..<4 {
                for hue in 0..<16 {
                    var y: Double
                    var sat: Double
                    switch hue {
                    case 0: y = high[luma]; sat = 0
                    case 13: y = low[luma]; sat = 0
                    case 14, 15: y = 0; sat = 0
                    default:
                        y = (low[luma] + high[luma]) / 2
                        sat = (high[luma] - low[luma]) / 2
                    }
                    let angle = (165.0 - 30.0 * Double(hue - 1)) * Double.pi / 180
                    let i = sat * cos(angle) * 1.1
                    let q = sat * sin(angle) * 1.1
                    var r = y + 0.956 * i + 0.621 * q
                    var g = y - 0.272 * i - 0.647 * q
                    var b = y - 1.106 * i + 1.703 * q
                    if hue < 14 && emphasis != 0 {
                        // Emphasis darkens the channels that are *not* emphasised.
                        let dim = 0.79
                        if emphasis & 1 != 0 { g *= dim; b *= dim }
                        if emphasis & 2 != 0 { r *= dim; b *= dim }
                        if emphasis & 4 != 0 { r *= dim; g *= dim }
                    }
                    func channel(_ v: Double) -> UInt32 {
                        let c = max(0, min(1, v))
                        return UInt32((pow(c, 1 / 1.1) * 255).rounded())
                    }
                    let argb = 0xFF00_0000 | (channel(r) << 16) | (channel(g) << 8) | channel(b)
                    out[emphasis * 64 + luma * 16 + hue] = argb
                }
            }
        }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
// Placeholder app icon: graphite body, a fold seam, a screen above and an ember cap below. Our own design.
let s = 1024
let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
let cs = CGColorSpaceCreateDeviceRGB()
func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
let grad = CGGradient(colorsSpace: cs, colors: [col(0.17, 0.18, 0.21), col(0.07, 0.075, 0.09)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])
// screen (top half; CG origin bottom-left)
let screen = CGRect(x: 170, y: 590, width: 684, height: 300)
ctx.setFillColor(col(0.03, 0.035, 0.04)); ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 46, cornerHeight: 46, transform: nil)); ctx.fillPath()
// a little horizon inside the screen
ctx.setFillColor(col(0.88, 0.64, 0.23)); ctx.fillEllipse(in: CGRect(x: 560, y: 700, width: 110, height: 110))
ctx.setFillColor(col(0.36, 0.48, 0.60)); ctx.fill(CGRect(x: 200, y: 625, width: 624, height: 50))
// seam
ctx.setFillColor(col(0, 0, 0, 0.75)); ctx.fill(CGRect(x: 0, y: 500, width: 1024, height: 36))
// d-pad
ctx.setFillColor(col(0.22, 0.23, 0.26))
ctx.addPath(CGPath(roundedRect: CGRect(x: 230, y: 200, width: 80, height: 230), cornerWidth: 18, cornerHeight: 18, transform: nil))
ctx.addPath(CGPath(roundedRect: CGRect(x: 155, y: 275, width: 230, height: 80), cornerWidth: 18, cornerHeight: 18, transform: nil))
ctx.fillPath()
// ember and sand caps
let ember = CGGradient(colorsSpace: cs, colors: [col(1.0, 0.5, 0.3), col(0.8, 0.25, 0.11)] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.addEllipse(in: CGRect(x: 690, y: 300, width: 150, height: 150)); ctx.clip()
ctx.drawRadialGradient(ember, startCenter: CGPoint(x: 740, y: 410), startRadius: 5, endCenter: CGPoint(x: 765, y: 375), endRadius: 95, options: []); ctx.restoreGState()
let sand = CGGradient(colorsSpace: cs, colors: [col(0.95, 0.9, 0.78), col(0.73, 0.65, 0.5)] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.addEllipse(in: CGRect(x: 520, y: 200, width: 150, height: 150)); ctx.clip()
ctx.drawRadialGradient(sand, startCenter: CGPoint(x: 570, y: 310), startRadius: 5, endCenter: CGPoint(x: 595, y: 275), endRadius: 95, options: []); ctx.restoreGState()
let img = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)

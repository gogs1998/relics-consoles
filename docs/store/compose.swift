// Store screenshot composer for Relics: Consoles (after the Relics compose scripts in DuoStudio, rewritten here).
// Usage: swift docs/store/compose.swift <captures-dir> <out-dir> <inner|outer|iphone69|ipad13>
// Reads <captures-dir>/<file>.png (real simulator captures, untouched) and writes <out-dir>/<file>.png at the exact
// App Store size: Duo inner 2007x2853, Duo outer 1398x2034, iPhone 6.9" 1320x2868, iPad 13" 2064x2752. Colours: our Graphite and Ember.
import AppKit

let args = CommandLine.arguments
let src = args[1], out = args[2], set = args[3]
struct S { let file, title, sub: String; let accent: Int }
func c(_ h: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let sets: [String: (w: Int, h: Int, shots: [S])] = [
    "inner": (2007, 2853, [
        S(file: "1-table-thwaite", title: "Fold it.\nNow it's a handheld.", sub: "Game on the upright screen, controller flat under your thumbs", accent: 0xFF6B3D),
        S(file: "2-table-editor", title: "Build your\nown controller", sub: "Drag, resize or hide any button, for every game and pose", accent: 0x5C7A99),
        S(file: "3-table-alexvsbus", title: "Quick saves\nalong the hinge", sub: "Three picture slots, rewind and fast-forward", accent: 0xE0A33B),
        S(file: "4-book-ucity", title: "Open it like a book", sub: "The game on one page, the controls across both", accent: 0x4D5C7A),
        S(file: "5-flat-libbet", title: "Flat, it's\na classic handheld", sub: "Every console has its own layout for every pose", accent: 0x8C80B3),
        S(file: "6-shelf", title: "Your games,\non your shelf", sub: "NES to N64: add the games you own from Files", accent: 0xE86E59),
    ]),
    "outer": (1398, 2034, [
        S(file: "1-outer-shelf", title: "Your games,\non your shelf", sub: "Add the games you own from Files", accent: 0xE86E59),
        S(file: "2-outer-sleep", title: "Close it to\npause and save", sub: "Open it to carry on where you were", accent: 0x8C80B3),
        S(file: "3-outer-settings", title: "Make it yours", sub: "Screen styles, volume, fast-forward speed", accent: 0xFF6B3D),
    ]),
    "ipad13": (2064, 2752, [
        S(file: "1-thwaite", title: "Play the retro\ngames you own", sub: "NES to N64: seven consoles, one shelf", accent: 0xFF6B3D),
        S(file: "2-editor", title: "Make the\ncontroller yours", sub: "Move, resize, fade or hide any button", accent: 0x5C7A99),
        S(file: "3-alexvsbus", title: "A big screen\nfor small pixels", sub: "Sharp pixels, scanlines or a handheld LCD look", accent: 0xE0A33B),
        S(file: "4-shelf", title: "Your games,\non your shelf", sub: "Add the games you own from Files", accent: 0xE86E59),
    ]),
    "iphone69": (1320, 2868, [
        S(file: "1-thwaite", title: "Play the retro\ngames you own", sub: "NES to N64: seven consoles, one shelf", accent: 0xFF6B3D),
        S(file: "2-editor", title: "Make the\ncontroller yours", sub: "Move, resize, fade or hide any button", accent: 0x5C7A99),
        S(file: "3-alexvsbus", title: "Save anywhere,\nrewind anytime", sub: "Picture save states, rewind and fast-forward", accent: 0xE0A33B),
        S(file: "4-landscape", title: "Turn it sideways", sub: "Controls beside the picture", accent: 0x4D5C7A),
        S(file: "5-shelf", title: "Your games,\non your shelf", sub: "Add the games you own from Files", accent: 0xE86E59),
    ]),
]
guard let spec = sets[set] else { fatalError("set must be inner, outer, iphone69 or ipad13") }
let W = spec.w, H = spec.h
let k = CGFloat(W) / 2007   // scale type and margins from the inner design
func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size * k, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size * k) ?? base }
    return base
}
let titleFont = font(136, .heavy), subFont = font(60, .medium)
var written: [String] = []
for s in spec.shots {
    let path = "\(src)/\(s.file).png"
    guard let loaded = NSImage(contentsOfFile: path), var cg = loaded.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("skip \(s.file): no capture"); continue
    }
    // A landscape capture is turned a quarter (the phone held sideways) so it fills the portrait frame.
    // Duo inner accepts landscape (2853x2007): book-pose captures stay sideways on a landscape canvas (1.0.1).
    let landscape = set == "inner" && cg.width > cg.height
    let CW = landscape ? H : W, CH = landscape ? W : H
    if cg.width > cg.height && !landscape {
        let r = CGContext(data: nil, width: cg.height, height: cg.width, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        r.translateBy(x: CGFloat(cg.height), y: 0)
        r.rotate(by: .pi / 2)
        r.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        cg = r.makeImage()!
    }
    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: CW, pixelsHigh: CH, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: CW, height: CH)
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let full = NSRect(x: 0, y: 0, width: CW, height: CH)
    NSGradient(colors: [c(0x25282E), c(0x1C1E23), c(0x111215)])!.draw(in: full, angle: -90)
    // A soft ember glow behind the device.
    let glow = NSGradient(colors: [c(s.accent, 0.38), c(s.accent, 0)])!
    glow.draw(in: NSRect(x: -CGFloat(CW) * 0.25, y: -CGFloat(CH) * 0.15, width: CGFloat(CW) * 1.5, height: CGFloat(CH) * 0.95),
              relativeCenterPosition: NSPoint(x: 0, y: -0.2))
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineSpacing = 4 * k
    let ink = c(0xEDE8DE)
    (s.title as NSString).draw(in: NSRect(x: 80 * k, y: CGFloat(CH) - 470 * k, width: CGFloat(CW) - 160 * k, height: 380 * k),
                               withAttributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: para])
    (s.sub as NSString).draw(in: NSRect(x: 100 * k, y: CGFloat(CH) - 600 * k, width: CGFloat(CW) - 200 * k, height: 150 * k),
                             withAttributes: [.font: subFont, .foregroundColor: ink.withAlphaComponent(0.72), .paragraphStyle: para])
    // The real capture, untouched, in a device outline running off the bottom.
    let aspect = CGFloat(cg.width) / CGFloat(cg.height)
    var shotH = CGFloat(CH) - 660 * k, shotW = shotH * aspect
    if shotW > CGFloat(CW) - 140 * k { shotW = CGFloat(CW) - 140 * k; shotH = shotW / aspect }
    let rect = NSRect(x: (CGFloat(CW) - shotW) / 2, y: 0, width: shotW, height: shotH)
    let body = rect.insetBy(dx: -24 * k, dy: -24 * k)
    let shadow = NSShadow(); shadow.shadowBlurRadius = 70 * k; shadow.shadowColor = NSColor(white: 0, alpha: 0.6)
    shadow.shadowOffset = NSSize(width: 0, height: -16 * k)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); c(0x08090A).setFill()
    NSBezierPath(roundedRect: body, xRadius: 96 * k, yRadius: 96 * k).fill(); NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: 74 * k, yRadius: 74 * k).addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    img.draw(in: rect); NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.current?.flushGraphics()
    // App Store: RGB, no alpha.
    let ctx = CGContext(data: nil, width: CW, height: CH, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: CW, height: CH))
    let flat = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! flat.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(s.file).png"))
    written.append(s.file)
}
print("wrote \(written.count): \(written.joined(separator: ", "))")

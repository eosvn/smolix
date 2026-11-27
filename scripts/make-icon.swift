// Renders the Smolix app icon and packs it into an .icns.
// Usage: swift scripts/make-icon.swift App/AppIcon.icns
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "App/AppIcon.icns"
let canvas: CGFloat = 1024

func renderMaster() -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824pt body centered on a 1024 canvas.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 0.20, green: 0.78, blue: 0.80, alpha: 1),
        NSColor(srgbRed: 0.27, green: 0.42, blue: 0.95, alpha: 1),
    ])!.draw(in: shape, angle: -70)

    func drawSymbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, center: NSPoint) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(alpha)]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let size = image.size
        image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height))
    }

    drawSymbol("computermouse.fill", pointSize: 360, weight: .regular, alpha: 1, center: NSPoint(x: 512, y: 500))
    drawSymbol("chevron.compact.up", pointSize: 150, weight: .semibold, alpha: 0.75, center: NSPoint(x: 512, y: 812))
    drawSymbol("chevron.compact.down", pointSize: 150, weight: .semibold, alpha: 0.75, center: NSPoint(x: 512, y: 200))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Smolix-\(UUID().uuidString)")
let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: tmp) }

let master = tmp.appendingPathComponent("master.png")
try renderMaster().representation(using: .png, properties: [:])!.write(to: master)

func run(_ tool: String, _ args: [String]) throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw NSError(domain: tool, code: Int(p.terminationStatus)) }
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try run("/usr/bin/sips", ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output])
print("Wrote \(output)")

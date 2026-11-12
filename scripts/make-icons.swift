import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let set = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
func render(_ size: Int, template: Bool = false) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
    if template { ctx.scaleBy(x: 1.45, y: 1.45); ctx.translateBy(x: -160, y: -180) }
    func rounded(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
    if !template {
        let tile = rounded(NSRect(x: 64, y: 64, width: 896, height: 896), 204)
        NSGradient(colors: [NSColor(srgbRed: 0.28, green: 0.35, blue: 0.91, alpha: 1), NSColor(srgbRed: 0.08, green: 0.12, blue: 0.32, alpha: 1)])!.draw(in: tile, angle: -65)
        NSColor.white.withAlphaComponent(0.14).setStroke(); tile.lineWidth = 3; tile.stroke()
    }
    let ink = template ? NSColor.black : NSColor.white
    let screen = rounded(NSRect(x: 208, y: 338, width: 608, height: 404), 57)
    if !template {
        NSColor(srgbRed: 0.13, green: 0.20, blue: 0.48, alpha: 1).setFill(); screen.fill()
        ctx.saveGState(); screen.addClip()
        NSGradient(colors: [NSColor(srgbRed: 0.30, green: 0.47, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.10, green: 0.16, blue: 0.38, alpha: 1)])!.draw(in: screen, angle: -50)
        ctx.restoreGState()
    }
    ink.setStroke(); screen.lineWidth = 37; screen.stroke()
    let stand = NSBezierPath(); stand.move(to: NSPoint(x: 512,y: 330)); stand.line(to: NSPoint(x: 512,y: 242)); stand.move(to: NSPoint(x: 392,y: 234)); stand.line(to: NSPoint(x: 632,y: 234)); stand.lineWidth = 37; stand.lineCapStyle = .round; stand.stroke()
    // Focus brackets remain legible at Finder and menu-bar sizes.
    let focus = NSBezierPath()
    focus.move(to: NSPoint(x: 428,y: 630)); focus.line(to: NSPoint(x: 384,y: 630)); focus.line(to: NSPoint(x: 384,y: 586))
    focus.move(to: NSPoint(x: 596,y: 450)); focus.line(to: NSPoint(x: 640,y: 450)); focus.line(to: NSPoint(x: 640,y: 494))
    focus.lineWidth = 27; focus.lineCapStyle = .round; focus.lineJoinStyle = .round
    (template ? ink : NSColor(srgbRed: 0.40, green: 0.96, blue: 0.90, alpha: 1)).setStroke(); focus.stroke()
    (template ? ink : NSColor(srgbRed: 0.54, green: 1, blue: 0.92, alpha: 1)).setFill()
    NSBezierPath(ovalIn: NSRect(x: 479,y: 507,width: 66,height: 66)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for n in [16,32,128,256,512] {
    try render(n).write(to: set.appendingPathComponent("icon_\(n)x\(n).png"))
    try render(n*2).write(to: set.appendingPathComponent("icon_\(n)x\(n)@2x.png"))
}
try render(256).write(to: root.appendingPathComponent("BrandIcon.png"))
try render(1024).write(to: root.appendingPathComponent("AppIcon-preview.png"))
try render(44, template: true).write(to: root.appendingPathComponent("MenuIcon.png"))

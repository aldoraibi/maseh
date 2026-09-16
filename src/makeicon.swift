import AppKit

func iconImage(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = size * 0.055
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)

    let colors = [NSColor(srgbRed: 0.05, green: 0.44, blue: 0.86, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.03, green: 0.26, blue: 0.62, alpha: 1).cgColor] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    ctx.restoreGState()

    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.5, weight: .medium)
    if let sym = NSImage(systemSymbolName: "doc.text.viewfinder", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceOver)
        sym.draw(at: .zero, from: .zero, operation: .destinationIn, fraction: 1)
        tinted.unlockFocus()
        let w = sym.size.width, h = sym.size.height
        tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
    }
    img.unlockFocus()
    return img
}

let dir = CommandLine.arguments[1]
for s in [16, 32, 64, 128, 256, 512, 1024] {
    let im = iconImage(CGFloat(s))
    guard let tiff = im.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = s == 1024 ? "icon_512x512@2x.png" : "icon_\(s)x\(s).png"
    try! png.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    if s >= 32 && s <= 512 {
        let im2 = iconImage(CGFloat(s * 2))
        if let t2 = im2.tiffRepresentation, let r2 = NSBitmapImageRep(data: t2),
           let p2 = r2.representation(using: .png, properties: [:]) {
            try! p2.write(to: URL(fileURLWithPath: "\(dir)/icon_\(s)x\(s)@2x.png"))
        }
    }
}
print("icons done")

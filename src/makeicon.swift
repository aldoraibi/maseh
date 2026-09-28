import AppKit

// أيقونة التطبيق — نفس رمز شريط القوائم «شعاع متحرك» على بلاطة «منتصف الليل» (بنفس مقاسات وتدرّج أيقونة ميزان).
// التصميم على لوح 1024، والرمز مرسوم في مساحة 18×18 (المركز 0,0) مثل أيقونة الشريط تماماً.

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func iconImage(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let k = size / 1024                                   // مقياس اللوح

    // البلاطة: 824 بزاوية 185 (شبكة أيقونات macOS)
    let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k)
    // ظل خفيف تحت البلاطة
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: hex(0x000000, 0.35).cgColor)
    hex(0x19222F).setFill(); path.fill()
    ctx.restoreGState()
    // تدرّج منتصف الليل: رمادي مزرقّ في الأعلى إلى كحلي داكن في الأسفل
    let stops: [(CGFloat, UInt32)] = [(0, 0x606B7D), (0.24, 0x475467), (0.61, 0x273344), (0.85, 0x1D2837), (1, 0x19222F)]
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: stops.map { hex($0.1).cgColor } as CFArray,
                          locations: stops.map { $0.0 })!
    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()
    // حافة زجاجية رفيعة
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5 * k, dy: 1.5 * k), xRadius: 184 * k, yRadius: 184 * k)
    rim.lineWidth = max(1, 3 * k)
    hex(0xFFFFFF, 0.14).setStroke(); rim.stroke()

    // الرمز
    let s = 38 * k                                        // وحدة واحدة من مساحة 18×18
    let c = CGPoint(x: size / 2, y: size / 2)
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x * s, y: c.y + y * s) }
    let ink = hex(0xE4EEFF)
    func stroke(_ p: NSBezierPath, _ w: CGFloat, _ col: NSColor, glow: Bool = false) {
        p.lineWidth = w * s; p.lineCapStyle = .round; p.lineJoinStyle = .round
        ctx.saveGState()
        if glow { ctx.setShadow(offset: .zero, blur: 26 * k, color: hex(0x6EA8FF, 0.85).cgColor) }
        col.setStroke(); p.stroke()
        ctx.restoreGState()
    }
    // زوايا الإطار
    let kk: CGFloat = 7, l: CGFloat = 2.6, r: CGFloat = 1.6
    for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
        let p = NSBezierPath()
        p.move(to: P(sx * kk, sy * (kk - l)))
        p.line(to: P(sx * kk, sy * (kk - r)))
        p.curve(to: P(sx * (kk - r), sy * kk), controlPoint1: P(sx * kk, sy * kk), controlPoint2: P(sx * kk, sy * kk))
        p.line(to: P(sx * (kk - l), sy * kk))
        stroke(p, 0.66, ink)
    }
    // الشعاع المتوهّج وأثراه
    func seg(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ a: CGFloat, glow: Bool = false) {
        let p = NSBezierPath(); p.move(to: P(-x, y)); p.line(to: P(x, y)); stroke(p, w, ink.withAlphaComponent(a), glow: glow)
    }
    seg(2.6, -3.4, 0.52, 0.22)
    seg(3.6, -1.6, 0.62, 0.48)
    seg(4.6, 0.6, 0.78, 1.0, glow: true)

    img.unlockFocus()
    return img
}

let dir = CommandLine.arguments[1]
func write(_ px: Int, _ name: String) {
    let im = iconImage(CGFloat(px))
    guard let tiff = im.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try! png.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
}
for s in [16, 32, 128, 256, 512] {
    write(s, "icon_\(s)x\(s).png")
    write(s * 2, "icon_\(s)x\(s)@2x.png")
}
print("icons done")

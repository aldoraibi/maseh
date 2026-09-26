import SwiftUI

/// توقيع «YAHYA ALDORAIBI» — حروف مرسومة يدوياً بوزن الشعرة (من عائلة «الميزان»، بلا قطع).
/// ارتفاع الحرف 100 وحدة في التصميم. النسخة المرجعية لكل الأدوات: ~/ClaudeFonts/brand/
struct NameMark: Shape {
    static let spacing: CGFloat = 30, word: CGFloat = 110

    /// كل حرف: عرضه، ومساراته بإحداثيات التصميم (y للأسفل، الارتفاع 100).
    private static func glyph(_ c: Character) -> (CGFloat, (inout Path) -> Void) {
        func p(_ pts: [(CGFloat, CGFloat)]) -> (inout Path) -> Void {
            { path in path.move(to: CGPoint(x: pts[0].0, y: pts[0].1)); for q in pts.dropFirst() { path.addLine(to: CGPoint(x: q.0, y: q.1)) } }
        }
        switch c {
        case "Y": return (96, { path in p([(0, 0), (48, 50)])(&path); p([(96, 0), (48, 50), (48, 100)])(&path) })
        case "A": return (88, { path in p([(0, 100), (44, 0), (88, 100)])(&path); p([(18, 64), (70, 64)])(&path) })
        case "H": return (78, { path in p([(0, 0), (0, 100)])(&path); p([(78, 0), (78, 100)])(&path); p([(0, 50), (78, 50)])(&path) })
        case "D": return (78, { path in
            p([(0, 0), (0, 100)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 30, y: 0))
            path.addCurve(to: CGPoint(x: 30, y: 100), control1: CGPoint(x: 92, y: 0), control2: CGPoint(x: 92, y: 100))
            path.addLine(to: CGPoint(x: 0, y: 100)) })
        case "L": return (62, { path in p([(0, 0), (0, 100), (62, 100)])(&path) })
        case "O": return (100, { path in path.addEllipse(in: CGRect(x: 0, y: 0, width: 100, height: 100)) })
        case "R": return (74, { path in
            p([(0, 100), (0, 0)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 40, y: 0))
            path.addCurve(to: CGPoint(x: 40, y: 54), control1: CGPoint(x: 78, y: 0), control2: CGPoint(x: 78, y: 54))
            path.addLine(to: CGPoint(x: 0, y: 54))
            p([(36, 54), (74, 100)])(&path) })
        case "I": return (0, { path in p([(0, 0), (0, 100)])(&path) })
        case "B": return (70, { path in
            p([(0, 0), (0, 100)])(&path)
            path.move(to: CGPoint(x: 0, y: 0)); path.addLine(to: CGPoint(x: 36, y: 0))
            path.addCurve(to: CGPoint(x: 36, y: 48), control1: CGPoint(x: 68, y: 0), control2: CGPoint(x: 68, y: 48))
            path.addLine(to: CGPoint(x: 0, y: 48))
            path.move(to: CGPoint(x: 0, y: 48)); path.addLine(to: CGPoint(x: 40, y: 48))
            path.addCurve(to: CGPoint(x: 40, y: 100), control1: CGPoint(x: 76, y: 48), control2: CGPoint(x: 76, y: 100))
            path.addLine(to: CGPoint(x: 0, y: 100)) })
        default: return (0, { _ in })
        }
    }

    /// العرض الكلي بوحدات التصميم.
    static var designWidth: CGFloat {
        var x: CGFloat = 0
        for w in "YAHYA ALDORAIBI".split(separator: " ", omittingEmptySubsequences: false) {
            if x > 0 { x += word - spacing }
            for c in w { x += glyph(c).0 + spacing }
        }
        return x - spacing
    }

    func path(in rect: CGRect) -> Path {
        var unit = Path(); var x: CGFloat = 0
        for c in "YAHYA ALDORAIBI" {
            if c == " " { x += Self.word - Self.spacing; continue }
            let (w, draw) = Self.glyph(c)
            var g = Path(); draw(&g)
            unit.addPath(g, transform: CGAffineTransform(translationX: x, y: 0))
            x += w + Self.spacing
        }
        let s = rect.height / 100
        return unit.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: rect.minX / s, y: rect.minY / s))
    }
}

/// الاسم بخط الشعرة — حروف كاملة بلا قطع.
struct NameMarkView: View {
    var height: CGFloat = 9
    var color: Color
    var body: some View {
        let lw = max(0.8, height * 0.075)   // الشعرة: لا تقل عن 0.8 نقطة لتبقى مرئية
        NameMark()
            .stroke(color, style: StrokeStyle(lineWidth: lw, lineCap: .butt, lineJoin: .miter))
            .frame(width: NameMark.designWidth * height / 100, height: height)
            .padding(.vertical, lw / 2)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel("YAHYA ALDORAIBI")
    }
}

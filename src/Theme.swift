import SwiftUI
import AppKit

// هوية «منتصف الليل» — المرجع: ~/ClaudeFonts/brand/README.md
// خطوط ثمانية، ثيم داكن أحادي، زجاج، زوايا، أيقونات ببلاطات، وتوقيع في الأسفل.

let arSerif = "thmanyah serif display"

extension Color {
    init(hex: String, alpha: Double = 1) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        self = Color(.sRGB,
                     red: Double((v >> 16) & 0xFF) / 255,
                     green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255,
                     opacity: alpha)
    }
}

enum Mid {
    static let deep     = Color(hex: "0E131C")
    static let panel    = Color(hex: "1E2430")
    static let text     = Color(hex: "EEF2F8")
    static let secondary = Color(hex: "E2E9F5", alpha: 0.60)
    static let faint    = Color(hex: "E2E9F5", alpha: 0.34)
    static let divider  = Color(hex: "BECDE6", alpha: 0.12)
    static let accent   = Color(hex: "DCE4F0")
    static let warning  = Color(hex: "FFB4A8")
    static let hover    = Color.white.opacity(0.06)
    static let tileBorder = Color.white.opacity(0.22)

    // تدرّج درجات الأقسام — من الفاتح للداكن
    static let degrees = [
        Color(hex: "DCE4F0"), Color(hex: "B7C2D4"), Color(hex: "9AA7BB"),
        Color(hex: "7C889E"), Color(hex: "64718A"),
    ]
    static func degree(_ i: Int) -> Color { degrees[max(0, min(degrees.count - 1, i))] }
}

// MARK: - اللغة والاتجاه (نفس نظام ميزان: العربية افتراضياً، وتُحفظ بالمفتاح "lang")

enum Lang: String, CaseIterable {
    case ar, en
    static var current: Lang { Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "ar") ?? .ar }
    var isRTL: Bool { self == .ar }
    var layout: LayoutDirection { isRTL ? .rightToLeft : .leftToRight }
    var nativeName: String { self == .ar ? "العربية" : "English" }
}

/// نص بلغتين حسب لغة الواجهة الحالية.
func tr(_ ar: String, _ en: String) -> String { Lang.current == .ar ? ar : en }

// MARK: - Liquid Glass — منقول حرفياً من ميزان

extension View {
    /// لوح زجاجي واحد يغطي الواجهة. الشفافية (0–1) من الإعدادات:
    /// كلما زادت قلّت الصبغة الحبرية #1E2430، ويبقى التمويه دائماً ليبقى النص مقروءاً.
    @ViewBuilder
    func glassSheet(transparency: Double = 0.8, radius: CGFloat = 18) -> some View {
        let t = min(max(transparency, 0), 1)
        let tint = Color(hex: "1E2430", alpha: 0.25 + 0.6 * (1 - t))
        if #available(macOS 26, *) {
            self.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint))
        }
    }

    /// كبسولة/مستطيل زجاجي تفاعلي للأزرار (يلمع ويتمدّد عند الضغط على macOS 26).
    @ViewBuilder
    func glassButton(tint: Color? = nil, radius: CGFloat = 10) -> some View {
        if #available(macOS 26, *) {
            let g: Glass = tint.map { .regular.tint($0) } ?? .regular
            self.glassEffect(g.interactive(), in: .rect(cornerRadius: radius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(tint ?? .clear))
        }
    }
}

/// هوية منتصف الليل + زجاج ميزان. `sheet: false` للمنبثقات التي يرسم النظام زجاجها بنفسه.
struct MidnightStyle: ViewModifier {
    @ObservedObject var m = Model.shared
    var radius: CGFloat
    var sheet: Bool
    var window: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        let styled = content
            .foregroundStyle(Mid.text)
            .tint(Mid.accent)
            .environment(\.colorScheme, .dark)
        if !sheet {
            styled
        } else if window {
            // النوافذ: الزجاج يمتد خلف شريط العنوان (مثل إعدادات ميزان)
            styled.background { Color.clear.glassSheet(transparency: m.glass, radius: radius).ignoresSafeArea() }
        } else {
            styled.glassSheet(transparency: m.glass, radius: radius)
        }
    }
}

extension View {
    /// ثيم منتصف الليل الزجاجي — اللوح (20)، النوافذ (24)، المنبثقات (بلا لوح إضافي).
    func midnight(radius: CGFloat = 20, sheet: Bool = true, window: Bool = false) -> some View {
        modifier(MidnightStyle(radius: radius, sheet: sheet, window: window))
    }
}

// خلفية مصمتة (للتصيير خارج الشاشة فقط — لا تمويه هناك)
struct MidnightBackground: View {
    @ObservedObject var m = Model.shared
    var body: some View {
        let tint = 0.25 + 0.6 * (1 - m.glass)
        ZStack {
            Mid.deep
            Mid.panel.opacity(tint)
            RadialGradient(colors: [Color(hex: "2E3A50", alpha: 0.55), .clear],
                           center: .topTrailing, startRadius: 4, endRadius: 420)
            RadialGradient(colors: [Color(hex: "3E4A5E", alpha: 0.35), .clear],
                           center: .bottomLeading, startRadius: 4, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

// بلاطة أيقونة مربّعة مستديرة بتدرّج درجة القسم + حد أبيض
struct IconTile: View {
    var symbol: String
    var degree: Int = 0
    var size: CGFloat = 30
    var body: some View {
        let c = Mid.degree(degree)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [c, c.opacity(0.55)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Mid.tileBorder, lineWidth: 1))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(Mid.deep)
            )
    }
}

// التوقيع في منتصف الأسفل — «مطوّر بواسطة» + YAHYA ALDORAIBI باللون الخافت
struct SignatureFooter: View {
    @AppStorage("lang") private var lang = "ar"
    var body: some View {
        VStack(spacing: 4) {
            Text(tr("مطوّر بواسطة", "Developed by"))
                .font(.custom(arFont, size: 10))
                .foregroundStyle(Mid.faint)
            NameMarkView(height: 9, color: Mid.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// الزر الأساسي: زجاج مصبوغ باللون المميّز ونص داكن (مثل زر ميزان الأساسي)
struct PrimaryFill: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Mid.panel)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .glassButton(tint: Mid.accent)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// الزر الثانوي: زجاج صافٍ تفاعلي
struct GlassCapsule: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Mid.text)
            .padding(.vertical, 7).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .glassButton()
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(enabled ? 1 : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - أيقونة شريط القوائم «شعاع متحرك» (بأسلوب ميزان: خطوط رفيعة بأطراف مستديرة، 18×18)
enum MenuBarIcon {
    static func image(alert: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let ink: NSColor = alert ? NSColor(srgbRed: 1.0, green: 0.706, blue: 0.659, alpha: 1) : .black
            let c = CGPoint(x: 9, y: 9)
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: c.x + x, y: c.y + y) }
            func stroke(_ p: NSBezierPath, _ w: CGFloat, _ col: NSColor) {
                p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; col.setStroke(); p.stroke()
            }
            // زوايا الإطار
            let k: CGFloat = 7, l: CGFloat = 2.6, r: CGFloat = 1.6
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] as [(CGFloat, CGFloat)] {
                let p = NSBezierPath()
                p.move(to: P(sx * k, sy * (k - l)))
                p.line(to: P(sx * k, sy * (k - r)))
                p.curve(to: P(sx * (k - r), sy * k), controlPoint1: P(sx * k, sy * k), controlPoint2: P(sx * k, sy * k))
                p.line(to: P(sx * (k - l), sy * k))
                stroke(p, 1.4, ink)
            }
            // الشعاع وأثراه
            func seg(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ a: CGFloat) {
                let p = NSBezierPath(); p.move(to: P(-x, y)); p.line(to: P(x, y)); stroke(p, w, ink.withAlphaComponent(a))
            }
            seg(4.6, 0.6, 1.5, 1.0)
            seg(3.6, -1.6, 1.1, 0.45)
            seg(2.6, -3.4, 0.9, 0.2)
            return true
        }
        img.isTemplate = !alert
        img.accessibilityDescription = tr("الماسح", "Maseh")
        return img
    }
}

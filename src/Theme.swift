import SwiftUI

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

// خلفية النافذة: عمق مع توهّجين مموّهين
struct MidnightBackground: View {
    var body: some View {
        ZStack {
            Mid.deep
            RadialGradient(colors: [Color(hex: "2E3A50", alpha: 0.90), .clear],
                           center: .topTrailing, startRadius: 4, endRadius: 420)
            RadialGradient(colors: [Color(hex: "3E4A5E", alpha: 0.55), .clear],
                           center: .bottomLeading, startRadius: 4, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// ثيم منتصف الليل لأي نافذة/لوح
    func midnight() -> some View {
        self.background(MidnightBackground())
            .foregroundStyle(Mid.text)
            .tint(Mid.accent)
            .environment(\.colorScheme, .dark)
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
    var body: some View {
        VStack(spacing: 4) {
            Text("مطوّر بواسطة")
                .font(.custom(arFont, size: 10))
                .foregroundStyle(Mid.faint)
            NameMarkView(height: 9, color: Mid.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// الزر الأساسي: فاتح بنص داكن
struct PrimaryFill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Mid.deep)
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Mid.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

// الزر الثانوي: كبسولة زجاجية
struct GlassCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Mid.text)
            .padding(.vertical, 7).padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Mid.divider, lineWidth: 1))
    }
}

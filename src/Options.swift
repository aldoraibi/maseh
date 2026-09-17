import SwiftUI
import AppKit

struct PPDChoice: Identifiable {
    let id: String
    let name: String
}

struct PPDOption: Identifiable {
    let id: String
    let name: String
    let def: String
    let choices: [PPDChoice]
}

// الخيارات التي تهم المستخدم فعلاً من بين عشرات الخيارات الداخلية
let wantedKeys: [String] = [
    "PageSize", "MediaType", "CNIJMediaType", "InputSlot", "CNIJMediaSupply",
    "ColorModel", "CNIJGrayScale", "OutputMode",
    "CNIJPrintQuality", "cupsPrintQuality", "PrintQuality", "Quality",
    "Resolution", "CNIJPZVividPosiProcess", "Duplex",
]

let arabicKeyNames: [String: String] = [
    "PageSize": "مقاس الورق",
    "MediaType": "نوع الورق",
    "CNIJMediaType": "نوع الورق",
    "InputSlot": "مصدر الورق",
    "CNIJMediaSupply": "مصدر الورق",
    "ColorModel": "نظام الألوان",
    "CNIJGrayScale": "أبيض وأسود",
    "CNIJGrayScaleCheckBox": "أبيض وأسود",
    "OutputMode": "وضع الإخراج",
    "CNIJPrintQuality": "جودة الطباعة",
    "cupsPrintQuality": "جودة الطباعة",
    "PrintQuality": "جودة الطباعة",
    "Quality": "جودة الطباعة",
    "Resolution": "الدقة",
    "CNIJPZVividPosiProcess": "ألوان زاهية للصور",
    "CNIJMarginType": "الهوامش",
    "Duplex": "الطباعة على الوجهين",
]

let arabicChoiceNames: [String: String] = [
    "Plain Paper": "ورق عادي",
    "Photo Paper Plus Glossy II": "ورق صور لامع بلس II",
    "Photo Paper Pro Luster": "ورق صور احترافي لاستر",
    "Photo Paper Plus Semi-gloss": "ورق صور نصف لامع",
    "Glossy Photo Paper": "ورق صور لامع",
    "Matte Photo Paper": "ورق صور مطفي",
    "Envelope": "ظرف",
    "High Resolution Paper": "ورق عالي الدقة",
    "Other Photo Paper": "ورق صور آخر",
    "Super Fine": "فائقة الجودة",
    "Fine": "عالية",
    "Normal(Fine)": "قياسية (عالية)",
    "Normal": "قياسية",
    "Draft": "مسودة",
    "Off": "إيقاف",
    "On": "تشغيل",
    "None": "بلا",
    "Yes": "نعم",
    "No": "لا",
    "Gray": "رمادي",
    "Grayscale": "تدرّج رمادي",
    "Color": "ألوان",
    "OFF": "إيقاف",
    "ON": "تشغيل",
]

func parsePPD(queue: String) -> [PPDOption] {
    let path = "/etc/cups/ppd/\(queue).ppd"
    guard let raw = try? String(contentsOfFile: path, encoding: .isoLatin1) else { return [] }

    var options: [PPDOption] = []
    var key = ""
    var label = ""
    var choices: [PPDChoice] = []
    var defaults: [String: String] = [:]

    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
        let l = String(line)

        if l.hasPrefix("*Default") {
            let body = l.dropFirst(8)
            if let c = body.firstIndex(of: ":") {
                let k = String(body[body.startIndex..<c])
                let v = body[body.index(after: c)...].trimmingCharacters(in: .whitespaces)
                defaults[k] = v
            }
            continue
        }

        if l.hasPrefix("*OpenUI *") {
            let body = l.dropFirst(9)
            guard let colon = body.firstIndex(of: ":") else { continue }
            let head = String(body[body.startIndex..<colon])
            let parts = head.split(separator: "/", maxSplits: 1).map(String.init)
            key = parts.first ?? ""
            label = parts.count > 1 ? parts[1] : key
            choices = []
            continue
        }

        if l.hasPrefix("*CloseUI:") {
            if !key.isEmpty, wantedKeys.contains(key), choices.count > 1 {
                options.append(PPDOption(id: key,
                                         name: arabicKeyNames[key] ?? label,
                                         def: defaults[key] ?? choices[0].id,
                                         choices: choices))
            }
            key = ""; choices = []
            continue
        }

        if !key.isEmpty, l.hasPrefix("*\(key) ") {
            let body = l.dropFirst(key.count + 2)
            guard let colon = body.firstIndex(of: ":") else { continue }
            let head = String(body[body.startIndex..<colon])
            let parts = head.split(separator: "/", maxSplits: 1).map(String.init)
            let cid = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            let cname = parts.count > 1 ? parts[1] : cid
            guard !cid.isEmpty else { continue }
            var pretty = arabicChoiceNames[cname] ?? cname
            pretty = pretty.replacingOccurrences(of: " borderless", with: " بلا حدود")
            pretty = pretty.replacingOccurrences(of: "US Letter", with: "Letter")
            choices.append(PPDChoice(id: cid, name: pretty))
        }
    }

    return options
}

/// احتياطي للطابعات التي لا تملك ملف PPD (مثل طابعات IPP الحديثة)
func parseLpoptions(queue: String) -> [PPDOption] {
    let out = PrintQueue.shell("/usr/bin/lpoptions", ["-p", queue, "-l"])
    var options: [PPDOption] = []
    for raw in out.split(separator: "\n") {
        let line = String(raw)
        guard let colon = line.firstIndex(of: ":") else { continue }
        let head = String(line[line.startIndex..<colon])
        let parts = head.split(separator: "/", maxSplits: 1).map(String.init)
        let key = parts.first ?? ""
        guard wantedKeys.contains(key) else { continue }
        let label = parts.count > 1 ? parts[1] : key
        var def = ""
        var choices: [PPDChoice] = []
        for t in line[line.index(after: colon)...].split(separator: " ") {
            var v = String(t)
            if v.hasPrefix("*") { v.removeFirst(); def = v }
            guard !v.isEmpty else { continue }
            choices.append(PPDChoice(id: v, name: arabicChoiceNames[v] ?? v))
        }
        if choices.count > 1 {
            options.append(PPDOption(id: key,
                                     name: arabicKeyNames[key] ?? label,
                                     def: def.isEmpty ? choices[0].id : def,
                                     choices: choices))
        }
    }
    return options
}

@MainActor
final class PrintOptions: ObservableObject {
    static let shared = PrintOptions()

    @Published var options: [PPDOption] = []
    @Published var values: [String: String] = [:]
    @Published var loadedFor = ""

    func load(force: Bool = false) {
        let q = Model.shared.queue
        guard !q.isEmpty, force || q != loadedFor else { return }
        loadedFor = q
        var found = parsePPD(queue: q)
        if found.isEmpty { found = parseLpoptions(queue: q) }
        options = found
        var v: [String: String] = [:]
        for o in options {
            let stored = UserDefaults.standard.string(forKey: "opt.\(q).\(o.id)")
            v[o.id] = stored ?? o.def
        }
        values = v
    }

    func set(_ key: String, _ value: String) {
        values[key] = value
        UserDefaults.standard.set(value, forKey: "opt.\(Model.shared.queue).\(key)")
    }

    func reset() {
        let q = Model.shared.queue
        for o in options {
            UserDefaults.standard.removeObject(forKey: "opt.\(q).\(o.id)")
            values[o.id] = o.def
        }
    }

    /// وسائط -o التي تُمرَّر لأمر الطباعة
    func lpArgs() -> [String] {
        var args: [String] = []
        for o in options {
            guard let v = values[o.id], v != o.def, !v.isEmpty else { continue }
            args.append("-o")
            args.append("\(o.id)=\(v)")
        }
        return args
    }
}

struct OptionsView: View {
    @ObservedObject var po = PrintOptions.shared
    @ObservedObject var m = Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("خيارات الطباعة")
                    .font(.custom(arFont, size: 14).weight(.bold))
                Spacer()
                Picker("", selection: $m.queue) {
                    ForEach(m.queues, id: \.self) { q in Text(q).tag(q) }
                }
                .labelsHidden().frame(width: 190)
                .onChange(of: m.queue) { _, _ in po.load(force: true) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if po.options.isEmpty {
                Text("لا توجد خيارات متاحة لهذه الطابعة")
                    .font(.custom(arFont, size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(28)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        ForEach(po.options) { o in
                            HStack {
                                Text(o.name)
                                    .font(.custom(arFont, size: 12))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { po.values[o.id] ?? o.def },
                                    set: { po.set(o.id, $0) }
                                )) {
                                    ForEach(o.choices) { c in
                                        Text(c.name).tag(c.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 235)
                            }
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                Button(action: po.reset) {
                    Text("إعادة للافتراضي").font(.custom(arFont, size: 12))
                }
                Spacer()
                Text("تُطبَّق على كل مهام الطباعة من التطبيق")
                    .font(.custom(arFont, size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .frame(minWidth: 520, minHeight: 420)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { m.loadQueues(); po.load() }
    }
}

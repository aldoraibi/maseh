import SwiftUI
import AppKit
import Vision
import Network
import CoreText
import UniformTypeIdentifiers
import UserNotifications

// ───────────────────────── الطراز ─────────────────────────

struct ScanPage: Identifiable {
    let id = UUID()
    var cg: CGImage
    var rotation: Int = 0
    var display: NSImage {
        let r = rotatedCG(cg, degrees: rotation)
        return NSImage(cgImage: r, size: NSSize(width: r.width, height: r.height))
    }
}

func rotatedCG(_ img: CGImage, degrees: Int) -> CGImage {
    let d = ((degrees % 360) + 360) % 360
    if d == 0 { return img }
    let w = img.width, h = img.height
    let swap = (d == 90 || d == 270)
    let nw = swap ? h : w, nh = swap ? w : h
    guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return img }
    ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
    ctx.rotate(by: CGFloat(d) * .pi / 180)
    ctx.draw(img, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))
    return ctx.makeImage() ?? img
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var pages: [ScanPage] = []
    @Published var busy = false
    @Published var status = ""
    @Published var progress = false

    @Published var printerIP: String = "" {
        didSet { UserDefaults.standard.set(printerIP, forKey: "printerIP") }
    }
    @Published var dpi: Int = 300 {
        didSet { UserDefaults.standard.set(dpi, forKey: "dpi") }
    }
    @Published var colorMode: String = "color" {
        didSet { UserDefaults.standard.set(colorMode, forKey: "colorMode") }
    }
    @Published var ocr: Bool = true {
        didSet { UserDefaults.standard.set(ocr, forKey: "ocr") }
    }
    @Published var lastDir: String = "" {
        didSet { UserDefaults.standard.set(lastDir, forKey: "lastDir") }
    }
    @Published var queue: String = "" {
        didSet { UserDefaults.standard.set(queue, forKey: "queue") }
    }
    @Published var copies: Int = 1 {
        didSet { UserDefaults.standard.set(copies, forKey: "copies") }
    }
    @Published var photoPaper: String = "A4" {
        didSet { UserDefaults.standard.set(photoPaper, forKey: "photoPaper") }
    }
    @Published var photoFill: Bool = false {
        didSet { UserDefaults.standard.set(photoFill, forKey: "photoFill") }
    }
    @Published var layout: String = "one" {
        didSet { UserDefaults.standard.set(layout, forKey: "layout") }
    }
    @Published var queues: [String] = []
    @Published var discovering = false

    private init() {
        let d = UserDefaults.standard
        if let v = d.string(forKey: "printerIP") { printerIP = v }
        if d.object(forKey: "dpi") != nil { dpi = d.integer(forKey: "dpi") }
        if let v = d.string(forKey: "colorMode") { colorMode = v }
        if d.object(forKey: "ocr") != nil { ocr = d.bool(forKey: "ocr") }
        if let v = d.string(forKey: "lastDir") { lastDir = v }
        if let v = d.string(forKey: "queue") { queue = v }
        if d.object(forKey: "copies") != nil { copies = max(1, d.integer(forKey: "copies")) }
        if let v = d.string(forKey: "photoPaper") { photoPaper = v }
        if d.object(forKey: "photoFill") != nil { photoFill = d.bool(forKey: "photoFill") }
        if let v = d.string(forKey: "layout") { layout = v }
    }

    func loadQueues() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lpstat")
        p.arguments = ["-e"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        let found = out.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        queues = found
        if queue.isEmpty || !found.contains(queue) {
            queue = found.first(where: { $0.lowercased().contains("canon") }) ?? found.first ?? ""
        }
        PrintOptions.shared.load()
    }

    // ─────────────── اكتشاف الطابعات على الشبكة ───────────────

    struct FoundPrinter { let name: String; let uuid: String; let uri: String }

    /// خريطة كل طابور طباعة إلى معرّف جهازه (uuid) من إعدادات النظام.
    /// سطر lpstat -v: «جهاز لـ QUEUE: dnssd://…uuid=XXXX». نفصل عند أول «:».
    nonisolated static func queueUUIDs() -> [(queue: String, uuid: String)] {
        let out = PrintQueue.shell("/usr/bin/lpstat", ["-v"])
        var result: [(String, String)] = []
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let left = String(line[line.startIndex..<colon])
            let right = String(line[line.index(after: colon)...])
            guard let q = left.split(separator: " ").last.map(String.init) else { continue }
            // استخراج uuid=… من رابط الجهاز
            guard let r = right.range(of: "uuid=", options: .caseInsensitive) else { continue }
            let tail = right[r.upperBound...]
            let uuid = String(tail.prefix { $0.isHexDigit || $0 == "-" })
            guard !uuid.isEmpty else { continue }
            result.append((q, uuid))
        }
        return result
    }

    /// تشغيل أمر مع مهلة قصوى (شبكة الاكتشاف قد تتأخر).
    nonisolated static func shellTimeout(_ path: String, _ args: [String], seconds: Double) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            if p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// يبحث عن الطابعات المتصلة فعلاً عبر Bonjour، ويختار الطابور المطابق تلقائياً.
    func discoverPrinters(auto: Bool = false) {
        guard !discovering else { return }
        discovering = true
        if !auto { status = "جاري البحث عن الطابعات…" }
        let currentQueue = queue
        Task.detached(priority: .userInitiated) {
            let raw = Model.shellTimeout(
                "/usr/bin/ippfind",
                ["_ipps._tcp", "_ipp._tcp",
                 "--exec", "echo", "{service_name}\t{txt_uuid}\t{}", ";"],
                seconds: 6)

            var online: [FoundPrinter] = []
            for line in raw.split(separator: "\n") {
                let f = String(line).components(separatedBy: "\t")
                guard f.count >= 3 else { continue }
                let uuid = f[1].trimmingCharacters(in: .whitespaces).lowercased()
                guard !uuid.isEmpty else { continue }
                online.append(FoundPrinter(name: f[0], uuid: uuid, uri: f[2]))
            }
            let onlineUUIDs = Set(online.map { $0.uuid })
            let map = Model.queueUUIDs()
            let matching = map.filter { onlineUUIDs.contains($0.uuid.lowercased()) }

            // فضّل الطابور الحالي إن كان متصلاً، ثم كانون، ثم أي متصل
            var chosen: String? = matching.first(where: { $0.queue == currentQueue })?.queue
            if chosen == nil {
                chosen = matching.first(where: { $0.queue.lowercased().contains("canon") })?.queue
                    ?? matching.first?.queue
            }

            await MainActor.run {
                self.discovering = false
                self.loadQueues()
                if let c = chosen {
                    if self.queue != c {
                        self.queue = c
                        PrintOptions.shared.load(force: true)
                    }
                    self.status = "الطابعة المتصلة: \(c)"
                } else if !online.isEmpty {
                    self.status = "عُثر على طابعة غير مُضافة في النظام — أضِفها من «طابعات وماسحات»"
                } else if !auto {
                    self.status = "لم يُعثر على طابعة متصلة على هذه الشبكة"
                }
            }
        }
    }

    func printFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "اختر ملفات أو صوراً للطباعة"
        panel.prompt = "طباعة"
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.pdf, .image]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls

        let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let images = urls.filter { $0.pathExtension.lowercased() != "pdf" }
        for u in pdfs { send(u, cleanup: false) }
        if !images.isEmpty { printPhotoURLs(images, deleteSources: false) }
    }

    /// طباعة ملفات أُفلتت على اللوحة (سحب وإفلات).
    /// PDF يُرسل مباشرة، الصور تمرّ عبر قوالب الصور، والبقية تُرسل كما هي.
    static let imageExts: Set<String> =
        ["png","jpg","jpeg","heic","heif","tiff","tif","gif","bmp","webp"]

    func printDropped(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let pdfs   = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let images = urls.filter { Model.imageExts.contains($0.pathExtension.lowercased()) }
        let others = urls.filter {
            let e = $0.pathExtension.lowercased()
            return e != "pdf" && !Model.imageExts.contains(e)
        }
        for u in pdfs   { send(u, cleanup: false) }
        for u in others { send(u, cleanup: false) }
        if !images.isEmpty { printPhotoURLs(images, deleteSources: false) }
        let n = urls.count
        status = n == 1 ? "جاري طباعة الملف المُفلت…" : "جاري طباعة \(n) ملفات…"
    }

    func printPhotoURLs(_ urls: [URL], deleteSources: Bool = false) {
        guard !urls.isEmpty else { return }
        busy = true; progress = true
        status = "جاري تجهيز الصور…"
        let paper = photoPaper, fill = photoFill, lay = layout
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos_\(UUID().uuidString).pdf")
        Task.detached(priority: .userInitiated) {
            let ok = buildPhotoPDF(urls: urls, paper: paper, fill: fill, layout: lay, to: tmp)
            if deleteSources {
                let tmpDir = FileManager.default.temporaryDirectory.standardizedFileURL.path
                for u in urls where u.standardizedFileURL.path.hasPrefix(tmpDir) {
                    try? FileManager.default.removeItem(at: u)
                }
            }
            await MainActor.run {
                self.busy = false; self.progress = false
                if ok {
                    self.send(tmp, cleanup: true)
                } else {
                    try? FileManager.default.removeItem(at: tmp)
                    self.status = "تعذّر تجهيز الصور"
                }
            }
        }
    }

    func printScanned() {
        guard !pages.isEmpty, !busy else { return }
        busy = true; progress = true
        status = "جاري التجهيز للطباعة…"
        let snapshot = pages.map { rotatedCG($0.cg, degrees: $0.rotation) }
        let density = CGFloat(dpi)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("print_\(UUID().uuidString).pdf")
        Task.detached(priority: .userInitiated) {
            let ok = await buildPDF(images: snapshot, dpi: density, ocr: false, to: tmp)
            await MainActor.run {
                self.busy = false; self.progress = false
                if ok {
                    self.send(tmp, cleanup: true)
                } else {
                    try? FileManager.default.removeItem(at: tmp)
                    self.status = "تعذّر التجهيز"
                }
            }
        }
    }

    func send(_ url: URL, cleanup: Bool) {
        guard !queue.isEmpty else {
            if cleanup { try? FileManager.default.removeItem(at: url) }
            status = "لم تُحدَّد طابعة"
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/lp")
        var args = ["-d", queue, "-n", String(copies)]
        args.append(contentsOf: PrintOptions.shared.lpArgs())
        args.append(url.path)
        p.arguments = args
        let outPipe = Pipe()
        p.standardOutput = outPipe; p.standardError = FileHandle.nullDevice
        p.environment = ["LANG": "C", "LC_ALL": "C", "PATH": "/usr/bin:/bin"]
        do { try p.run() } catch {
            if cleanup { try? FileManager.default.removeItem(at: url) }
            status = "تعذّر إرسال الطباعة"
            return
        }
        let reply = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        // مخرجات lp مترجمة، لذا نبحث عن الرمز الذي يبدأ باسم الطابور
        let tokens = reply.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        if let jid = tokens.first(where: { $0.hasPrefix(queue + "-") }) {
            PrintQueue.shared.note(id: String(jid),
                                   title: url.deletingPathExtension().lastPathComponent)
        }
        PrintQueue.shared.start()
        status = p.terminationStatus == 0
            ? "أُرسلت للطباعة ✓"
            : "فشل الإرسال للطابعة"
        if cleanup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }


    private var pixmaURL: URL? {
        Bundle.main.url(forResource: "pixma", withExtension: nil)
    }

    private var browser: NWBrowser?

    /// يفتح طلب إذن «الشبكة المحلية» باسم التطبيق نفسه.
    /// بدونه يفشل الاتصال بالطابعة بصمت لأن macOS يحجب الشبكة المحلية افتراضياً.
    func primeLocalNetwork() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let b = NWBrowser(for: .bonjour(type: "_ipp._tcp", domain: nil), using: params)
        b.stateUpdateHandler = { _ in }
        b.browseResultsChangedHandler = { _, _ in }
        b.start(queue: .main)
        browser = b
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.browser?.cancel()
            self?.browser = nil
        }

        // اتصال مباشر بالطابعة يضمن ظهور الطلب ويثبّت هوية التطبيق كعميل شبكة
        if !printerIP.isEmpty, let u = URL(string: "http://\(printerIP)/") {
            var r = URLRequest(url: u)
            r.timeoutInterval = 4
            URLSession.shared.dataTask(with: r) { _, _, _ in }.resume()
        }
    }

    func scan() {
        guard !busy else { return }
        guard let exe = pixmaURL else { status = "لم يُعثر على محرك المسح"; return }
        busy = true; progress = true; status = "جاري المسح…"
        let ip = printerIP, res = String(dpi), mode = colorMode

        Task.detached(priority: .userInitiated) {
            var made: CGImage? = nil
            var failure: String? = nil
            // بعض الطابعات تُرجع مسحة سوداء تماماً إذا لم يسخن مصباح الماسح بعد،
            // أو عند تصادم جلستَي مسح. نرفض المسحة السوداء ونعيد المحاولة مرة واحدة.
            for attempt in 0..<2 {
                let r = Model.scanOnce(exe: exe, ip: ip, res: res, mode: mode)
                if let img = r.image {
                    if Model.isBlank(img) {
                        if attempt == 0 {
                            await MainActor.run { self.status = "المسحة سوداء… إعادة المحاولة" }
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            continue
                        }
                        failure = "خرجت الصفحة سوداء — تأكد من وجود ورقة على الزجاج وإغلاق الغطاء، ثم أعد المسح"
                    } else {
                        made = img
                    }
                } else {
                    failure = r.error
                }
                break
            }

            await MainActor.run {
                self.busy = false; self.progress = false
                if let img = made {
                    self.pages.append(ScanPage(cg: img))
                    self.status = "تمت إضافة صفحة \(self.pages.count)"
                } else {
                    self.status = failure ?? "فشل غير معروف"
                }
            }
        }
    }

    /// مسحة واحدة عبر محرك pixma؛ تُرجع الصورة أو رسالة خطأ.
    nonisolated static func scanOnce(exe: URL, ip: String, res: String, mode: String) -> (image: CGImage?, error: String?) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan_\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let p = Process()
        p.executableURL = exe
        var a = ["scan", tmp.path, "--resolution", res, "--color", mode]
        if !ip.isEmpty { a.append(contentsOf: ["--device", ip]) }
        p.arguments = a
        let errPipe = Pipe()
        p.standardError = errPipe
        p.standardOutput = FileHandle.nullDevice
        do {
            try p.run()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let text = String(data: errData, encoding: .utf8) ?? ""
                let last = text.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last(where: { !$0.isEmpty }) ?? ""
                let l = last.lowercased()
                if l.contains("no canon") || l.contains("not found") {
                    return (nil, "لم يُعثر على الطابعة على هذه الشبكة")
                } else if l.contains("permission") || l.contains("not permitted") {
                    return (nil, "الشبكة المحلية محجوبة — فعّلها من إعدادات النظام")
                } else if l.contains("no route") || l.contains("timed out") || l.contains("refused") {
                    return (nil, "الطابعة لا تستجيب — تأكد أنها متصلة بنفس الشبكة")
                } else if last.isEmpty {
                    return (nil, "تعذّر الاتصال بالماسح")
                }
                return (nil, String(last.prefix(70)))
            }
        } catch {
            return (nil, "تعذّر تشغيل محرك المسح")
        }
        guard let src = CGImageSourceCreateWithURL(tmp as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0,
                        [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            return (nil, "تعذّرت قراءة الصورة الممسوحة")
        }
        return (img, nil)
    }

    /// هل الصورة سوداء فعلياً (مسحة فاشلة)؟ عيّنة من السطوع.
    nonisolated static func isBlank(_ img: CGImage) -> Bool {
        let w = img.width, h = img.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return false }
        let px = data.assumingMemoryBound(to: UInt8.self)
        var sum = 0, n = 0
        let sx = max(1, w / 40), sy = max(1, h / 40)
        for y in stride(from: 0, to: h, by: sy) {
            for x in stride(from: 0, to: w, by: sx) {
                let i = y * ctx.bytesPerRow + x * 4
                sum += (Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2])) / 3; n += 1
            }
        }
        return n > 0 && (sum / n) < 8   // متوسط السطوع < 8 من 255 = سوداء
    }

    func rotate(_ id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].rotation = (pages[i].rotation + 90) % 360
    }

    func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
        status = pages.isEmpty ? "" : "\(pages.count) صفحة"
    }

    func clear() { pages.removeAll(); status = "" }

    func save() {
        guard !pages.isEmpty, !busy else { return }
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "حفظ المستند الممسوح"
        panel.nameFieldLabel = "الاسم:"
        panel.prompt = "حفظ"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultName()
        panel.canCreateDirectories = true
        if !lastDir.isEmpty { panel.directoryURL = URL(fileURLWithPath: lastDir) }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        lastDir = url.deletingLastPathComponent().path

        busy = true; progress = true
        status = ocr ? "جاري استخراج النص والحفظ…" : "جاري الحفظ…"
        let snapshot = pages.map { rotatedCG($0.cg, degrees: $0.rotation) }
        let wantOCR = ocr, density = CGFloat(dpi)

        Task.detached(priority: .userInitiated) {
            let ok = await buildPDF(images: snapshot, dpi: density, ocr: wantOCR, to: url)
            await MainActor.run {
                self.busy = false; self.progress = false
                if ok {
                    self.status = "تم الحفظ ✓"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    self.pages.removeAll()
                } else {
                    self.status = "تعذّر إنشاء الملف"
                }
            }
        }
    }

    private func defaultName() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return "مسح \(f.string(from: Date()))"
    }
}

// ───────────────────────── PDF + OCR ─────────────────────────

func buildPDF(images: [CGImage], dpi: CGFloat, ocr: Bool, to url: URL) async -> Bool {
    var boxes: [[(String, CGRect)]] = []
    if ocr {
        for img in images { boxes.append(await recognize(img)) }
    }

    var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return false }

    for (i, img) in images.enumerated() {
        let w = CGFloat(img.width) / dpi * 72.0
        let h = CGFloat(img.height) / dpi * 72.0
        var box = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.beginPage(mediaBox: &box)
        ctx.draw(img, in: box)

        if ocr, i < boxes.count {
            ctx.saveGState()
            ctx.setTextDrawingMode(.invisible)
            for (text, bb) in boxes[i] where !text.isEmpty {
                let r = CGRect(x: bb.minX * w, y: bb.minY * h, width: bb.width * w, height: bb.height * h)
                guard r.height > 1 else { continue }
                let font = CTFontCreateWithName("Geeza Pro" as CFString, r.height * 0.82, nil)
                let attr = NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.clear,
                ])
                let line = CTLineCreateWithAttributedString(attr)
                ctx.textMatrix = .identity
                ctx.textPosition = CGPoint(x: r.minX, y: r.minY + r.height * 0.15)
                CTLineDraw(line, ctx)
            }
            ctx.restoreGState()
        }
        ctx.endPage()
    }
    ctx.closePDF()
    return FileManager.default.fileExists(atPath: url.path)
}

func paperSize(_ name: String) -> CGSize {
    switch name {
    case "10x15": return CGSize(width: 283.46, height: 425.20)
    case "13x18": return CGSize(width: 368.50, height: 510.24)
    default: return CGSize(width: 595.28, height: 841.89)
    }
}

func loadOriented(_ u: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(u as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    var deg = 0
    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
       let o = props[kCGImagePropertyOrientation] as? Int {
        switch o {
        case 3: deg = 180
        case 6: deg = 270
        case 8: deg = 90
        default: deg = 0
        }
    }
    return deg == 0 ? img : rotatedCG(img, degrees: deg)
}

func layoutGrid(_ name: String) -> (cols: Int, rows: Int, cell: CGSize?) {
    switch name {
    case "two": return (1, 2, nil)
    case "four": return (2, 2, nil)
    case "six": return (2, 3, nil)
    case "nine": return (3, 3, nil)
    case "id46": return (0, 0, CGSize(width: 113.39, height: 170.08))
    case "id35": return (0, 0, CGSize(width: 99.21, height: 127.56))
    default: return (1, 1, nil)
    }
}

func drawInto(_ ctx: CGContext, _ img: CGImage, _ area: CGRect, fill: Bool) {
    let iw = CGFloat(img.width), ih = CGFloat(img.height)
    guard iw > 0, ih > 0 else { return }
    let scale = fill ? max(area.width / iw, area.height / ih)
                     : min(area.width / iw, area.height / ih)
    let w = iw * scale, h = ih * scale
    ctx.saveGState()
    ctx.clip(to: area)
    ctx.draw(img, in: CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h))
    ctx.restoreGState()
}

func buildPhotoPDF(urls: [URL], paper: String, fill: Bool, layout: String, to url: URL) -> Bool {
    let base = paperSize(paper)
    var mediaBox = CGRect(origin: .zero, size: base)
    guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return false }

    var images: [CGImage] = []
    for u in urls { if let i = loadOriented(u) { images.append(i) } }
    guard !images.isEmpty else { ctx.closePDF(); return false }

    let grid = layoutGrid(layout)
    let margin: CGFloat = 20
    let gutter: CGFloat = 8

    // ── صورة واحدة في الصفحة: التوجيه تلقائي ──
    if layout == "one" {
        for img in images {
            let size = CGFloat(img.width) > CGFloat(img.height)
                ? CGSize(width: base.height, height: base.width) : base
            var box = CGRect(origin: .zero, size: size)
            ctx.beginPage(mediaBox: &box)
            let m: CGFloat = fill ? 0 : 18
            drawInto(ctx, img, box.insetBy(dx: m, dy: m), fill: fill)
            ctx.endPage()
        }
        ctx.closePDF()
        return FileManager.default.fileExists(atPath: url.path)
    }

    // ── ورقة صور شخصية بمقاس ثابت ──
    if let cell = grid.cell {
        let cols = max(1, Int((base.width - margin * 2 + gutter) / (cell.width + gutter)))
        let rows = max(1, Int((base.height - margin * 2 + gutter) / (cell.height + gutter)))
        let perPage = cols * rows
        let source = images.count == 1
            ? Array(repeating: images[0], count: perPage)
            : images
        var i = 0
        while i < source.count {
            var box = CGRect(origin: .zero, size: base)
            ctx.beginPage(mediaBox: &box)
            let gw = CGFloat(cols) * cell.width + CGFloat(cols - 1) * gutter
            let gh = CGFloat(rows) * cell.height + CGFloat(rows - 1) * gutter
            let ox = (base.width - gw) / 2
            let oy = (base.height - gh) / 2
            ctx.setStrokeColor(CGColor(gray: 0.78, alpha: 1))
            ctx.setLineWidth(0.4)
            for r in 0..<rows {
                for c in 0..<cols {
                    guard i < source.count else { break }
                    let x = ox + CGFloat(c) * (cell.width + gutter)
                    let y = base.height - oy - CGFloat(r + 1) * cell.height - CGFloat(r) * gutter
                    let area = CGRect(x: x, y: y, width: cell.width, height: cell.height)
                    drawInto(ctx, source[i], area, fill: true)
                    ctx.stroke(area)
                    i += 1
                }
            }
            ctx.endPage()
        }
        ctx.closePDF()
        return FileManager.default.fileExists(atPath: url.path)
    }

    // ── تقسيم الصفحة إلى شبكة ──
    let cols = grid.cols, rows = grid.rows
    let perPage = cols * rows
    let cw = (base.width - margin * 2 - CGFloat(cols - 1) * gutter) / CGFloat(cols)
    let ch = (base.height - margin * 2 - CGFloat(rows - 1) * gutter) / CGFloat(rows)
    var i = 0
    while i < images.count {
        var box = CGRect(origin: .zero, size: base)
        ctx.beginPage(mediaBox: &box)
        for r in 0..<rows {
            for c in 0..<cols {
                guard i < images.count else { break }
                let x = margin + CGFloat(c) * (cw + gutter)
                let y = base.height - margin - CGFloat(r + 1) * ch - CGFloat(r) * gutter
                drawInto(ctx, images[i], CGRect(x: x, y: y, width: cw, height: ch), fill: fill)
                i += 1
            }
        }
        ctx.endPage()
        if perPage == 0 { break }
    }
    ctx.closePDF()
    return FileManager.default.fileExists(atPath: url.path)
}

func recognize(_ img: CGImage) async -> [(String, CGRect)] {
    await withCheckedContinuation { cont in
        DispatchQueue.global(qos: .userInitiated).async {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["ar-SA", "en-US"]
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: img, options: [:])
            var found: [(String, CGRect)] = []
            if (try? handler.perform([req])) != nil {
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                found = obs.compactMap { o in
                    guard let c = o.topCandidates(1).first else { return nil }
                    return (c.string, o.boundingBox)
                }
            }
            cont.resume(returning: found)
        }
    }
}

// ───────────────────────── الواجهة ─────────────────────────

let arFont = "thmanyah sans"

struct Panel: View {
    @ObservedObject var m = Model.shared
    @State private var showSettings = false
    @State private var dropTargeted = false
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var q = PrintQueue.shared

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let u = url, u.isFileURL { urls.append(u) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { Model.shared.printDropped(urls) }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if !q.jobs.isEmpty {
                QueueBlock()
                Divider()
            }
            if m.pages.isEmpty { empty } else { strip }
            Divider()
            footer
        }
        .frame(width: 420)
        .midnight()
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if dropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 28, weight: .medium))
                        Text("أفلت الملفات هنا للطباعة")
                            .font(.custom(arFont, size: 13).weight(.medium))
                    }
                    .foregroundStyle(.tint)
                }
                .padding(6)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            m.loadQueues()
            m.primeLocalNetwork()
            m.discoverPrinters(auto: true)
            q.start()
        }
        .onDisappear { q.stop() }
        .environment(\.layoutDirection, .rightToLeft)
    }

    private var header: some View {
        HStack(spacing: 11) {
            IconTile(symbol: "scanner.fill", degree: 0, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("الماسح")
                    .font(.custom(arSerif, size: 16).weight(.medium))
                    .foregroundStyle(Mid.text)
                Text(m.status.isEmpty ? "Canon G3010" : m.status)
                    .font(.custom(arFont, size: 11))
                    .foregroundStyle(m.status.contains("⚠️") ? Mid.warning : Mid.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if m.progress { ProgressView().controlSize(.small) }
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Mid.secondary)
            .popover(isPresented: $showSettings, arrowEdge: .bottom) { settings }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Mid.faint)
            Text("ضع الورقة في الماسح واضغط «مسح صفحة»")
                .font(.custom(arFont, size: 12))
                .foregroundStyle(Mid.secondary)
                .multilineTextAlignment(.center)
            Text("أو اسحب ملفاً أو صورة وأفلته هنا لطباعته")
                .font(.custom(arFont, size: 11))
                .foregroundStyle(Mid.faint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var strip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(m.pages.enumerated()), id: \.element.id) { idx, page in
                    thumb(page, number: idx + 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 164)
    }

    private func thumb(_ page: ScanPage, number: Int) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: page.display)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 118)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                Button { m.remove(page.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.custom(arFont, size: 11))
                    .foregroundStyle(.secondary)
                Button { m.rotate(page.id) } label: {
                    Image(systemName: "rotate.right").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: m.scan) {
                HStack(spacing: 7) {
                    Image(systemName: "plus.viewfinder")
                    Text(m.pages.isEmpty ? "مسح صفحة" : "مسح صفحة أخرى")
                        .font(.custom(arFont, size: 13).weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(PrimaryFill())
            .disabled(m.busy)

            HStack(spacing: 10) {
                Button(action: m.save) {
                    Text("حفظ PDF…")
                        .font(.custom(arFont, size: 13).weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                }
                .buttonStyle(GlassCapsule())
                .disabled(m.pages.isEmpty || m.busy)

                Button(action: m.clear) {
                    Text("تفريغ")
                        .font(.custom(arFont, size: 13))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 4)
                }
                .buttonStyle(GlassCapsule())
                .disabled(m.pages.isEmpty || m.busy)
            }

            HStack(spacing: 10) {
                Button(action: m.printScanned) {
                    HStack(spacing: 5) {
                        Image(systemName: "printer")
                        Text("طباعة الممسوح")
                            .font(.custom(arFont, size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(GlassCapsule())
                .disabled(m.pages.isEmpty || m.busy)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openPhotos()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle")
                        Text("طباعة صور…")
                            .font(.custom(arFont, size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(GlassCapsule())
                .disabled(m.busy)
            }

            HStack(spacing: 10) {
                Button(action: m.printFile) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.badge.arrow.up")
                        Text("طباعة ملف…")
                            .font(.custom(arFont, size: 13))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(GlassCapsule())
                .disabled(m.busy)
            }

            Toggle(isOn: $m.ocr) {
                Text("PDF قابل للبحث (استخراج النص العربي)")
                    .font(.custom(arFont, size: 11))
            }
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Button { NSApp.terminate(nil) } label: {
                Text("إنهاء")
                    .font(.custom(arFont, size: 11))
                    .foregroundStyle(Mid.faint)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            SignatureFooter()
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    private func openPhotos() {
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("photos") == true }) {
            w.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: "photos")
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("الإعدادات").font(.custom(arFont, size: 13).weight(.bold))
            HStack {
                Text("عنوان الطابعة").font(.custom(arFont, size: 12))
                Spacer()
                TextField("", text: $m.printerIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .environment(\.layoutDirection, .leftToRight)
            }
            HStack {
                Text("الطابعة").font(.custom(arFont, size: 12))
                Spacer()
                Picker("", selection: $m.queue) {
                    ForEach(m.queues, id: \.self) { q in Text(q).tag(q) }
                }
                .labelsHidden().frame(width: 165)
                .onChange(of: m.queue) { _, _ in PrintOptions.shared.load(force: true) }
            }
            Button { m.discoverPrinters() } label: {
                HStack(spacing: 5) {
                    if m.discovering {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    Text(m.discovering ? "جاري البحث…" : "بحث عن الطابعات المتصلة")
                        .font(.custom(arFont, size: 12))
                }
            }
            .disabled(m.discovering)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Text("عدد النسخ").font(.custom(arFont, size: 12))
                Spacer()
                Stepper(value: $m.copies, in: 1...20) {
                    Text("\(m.copies)").font(.custom(arFont, size: 12))
                }
                .frame(width: 100)
            }
            Divider()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                showSettings = false
                openWindow(id: "options")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("خيارات الطابعة (الألوان ونوع الورق)")
                        .font(.custom(arFont, size: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            HStack {
                Text("مقاس ورق الصور").font(.custom(arFont, size: 12))
                Spacer()
                Picker("", selection: $m.photoPaper) {
                    Text("A4").tag("A4")
                    Text("١٠×١٥ سم").tag("10x15")
                    Text("١٣×١٨ سم").tag("13x18")
                }
                .labelsHidden().frame(width: 120)
            }
            HStack {
                Text("تقسيم الصفحة").font(.custom(arFont, size: 12))
                Spacer()
                Picker("", selection: $m.layout) {
                    Text("صورة واحدة").tag("one")
                    Text("صورتان").tag("two")
                    Text("٤ صور").tag("four")
                    Text("٦ صور").tag("six")
                    Text("٩ صور").tag("nine")
                    Divider()
                    Text("شخصية ٤×٦ سم").tag("id46")
                    Text("شخصية ٣٥×٤٥ مم").tag("id35")
                }
                .labelsHidden().frame(width: 140)
            }
            Toggle(isOn: $m.photoFill) {
                Text("ملء الصفحة بالكامل (بلا هوامش)")
                    .font(.custom(arFont, size: 11))
            }
            .toggleStyle(.checkbox)
            HStack {
                Text("الدقة").font(.custom(arFont, size: 12))
                Spacer()
                Picker("", selection: $m.dpi) {
                    Text("150").tag(150)
                    Text("300").tag(300)
                    Text("600").tag(600)
                }
                .labelsHidden().frame(width: 100)
            }
            HStack {
                Text("الألوان").font(.custom(arFont, size: 12))
                Spacer()
                Picker("", selection: $m.colorMode) {
                    Text("ملوّن").tag("color")
                    Text("رمادي").tag("grayscale")
                }
                .labelsHidden().frame(width: 100)
            }
        }
        .padding(16)
        .frame(width: 300)
        .midnight()
        .environment(\.layoutDirection, .rightToLeft)
    }
}

#if !TESTBUILD
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Model.shared.loadQueues()
        Model.shared.primeLocalNetwork()
        Model.shared.discoverPrinters(auto: true)
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

struct MenuLabel: View {
    @ObservedObject var q = PrintQueue.shared
    var body: some View {
        Image(systemName: q.paused ? "exclamationmark.triangle.fill" : "scanner")
    }
}

@main
struct ScannerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        MenuBarExtra {
            Panel()
        } label: {
            MenuLabel()
        }
        .menuBarExtraStyle(.window)

        Window("طباعة صور", id: "photos") {
            PhotoGrid()
        }
        .defaultSize(width: 720, height: 520)

        Window("خيارات الطباعة", id: "options") {
            OptionsView()
        }
        .defaultSize(width: 560, height: 470)
    }
}
#endif

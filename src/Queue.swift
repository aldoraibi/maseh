import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class PrintQueue: ObservableObject {
    static let shared = PrintQueue()

    struct Job: Identifiable {
        let id: String
        let title: String
        let rank: String
        let size: String
    }

    struct PState { var stopped = false; var paperOut = false; var attention = false }

    @Published var jobs: [Job] = []
    @Published var state = ""
    @Published var paused = false          // الطباعة متوقفة (ورق/خطأ)
    @Published var attention = ""          // سبب التوقف بالعربية
    private var titles: [String: String] = [:]
    private var timer: Timer?
    private var hadJobs = false
    private var idleTicks = 0
    private var notifiedStall = false
    private var resumeThrottle = 0

    func note(id: String, title: String) {
        titles[id] = title
        hadJobs = true
        poll()
    }

    func start() {
        guard timer == nil else { poll(); return }
        idleTicks = 0
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in self.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        return out
    }

    // مخرجات أوامر CUPS مترجمة حسب لغة النظام، لذلك نعتمد على رقم المهمة
    // بصيغة (اسم_الطابور-رقم) وهو غير مترجم في أي لغة.
    private var polling = false

    func poll() {
        let q = Model.shared.queue
        guard !q.isEmpty else { jobs = []; state = ""; return }
        guard !polling else { return }
        polling = true
        let known = titles
        Task.detached(priority: .utility) {
            let out = PrintQueue.shell("/usr/bin/lpstat", ["-W", "not-completed", "-o", q])
            let active = PrintQueue.shell("/usr/bin/lpstat", ["-p", q])
            let list = PrintQueue.parse(queue: q, out: out, active: active, titles: known)
            let ps = list.isEmpty ? PState() : PrintQueue.readPrinterState(q)
            await MainActor.run { self.apply(list, ps) }
        }
    }

    /// حالة الطابعة بمفاتيح IPP الإنجليزية الثابتة (مستقلة عن لغة النظام).
    nonisolated static func readPrinterState(_ queue: String) -> PState {
        let test = stateTestFile()
        guard !test.isEmpty else { return PState() }
        let uri = "ipp://localhost/printers/\(queue)"
        let out = Model.shellTimeout("/usr/bin/ipptool", ["-t", uri, test], seconds: 4)
        var s = PState()
        for raw in out.split(separator: "\n") {
            let line = String(raw)
            let low = line.lowercased()
            if low.contains("printer-state (enum)") {
                s.stopped = low.contains("stopped")
            } else if low.contains("printer-state-reasons") {
                let rl = low
                if rl.contains("media-empty") || rl.contains("media-needed") { s.paperOut = true }
                if rl.contains("-error") || rl.contains("jam") || rl.contains("cover-open")
                    || rl.contains("door-open") || rl.contains("marker-supply-empty") { s.attention = true }
            }
        }
        if s.stopped { s.attention = true }
        return s
    }

    /// ملف اختبار ipptool يُكتب مرة واحدة ويُعاد استخدامه.
    nonisolated static func stateTestFile() -> String {
        let path = NSTemporaryDirectory() + "maseh_state.test"
        if !FileManager.default.fileExists(atPath: path) {
            let body = """
            {
              OPERATION Get-Printer-Attributes
              GROUP operation-attributes-tag
              ATTR charset attributes-charset utf-8
              ATTR naturalLanguage attributes-natural-language en
              ATTR uri printer-uri $uri
              ATTR keyword requested-attributes printer-state,printer-state-reasons
              STATUS successful-ok
              DISPLAY printer-state
              DISPLAY printer-state-reasons
            }
            """
            try? body.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return FileManager.default.fileExists(atPath: path) ? path : ""
    }

    /// يعيد تمكين الطابور ويحرّر المهام المعلّقة — يستأنف الطباعة دون زر الطابعة.
    nonisolated static func resumeQueue(_ queue: String) {
        _ = shell("/usr/sbin/cupsenable", [queue])
        let held = shell("/usr/bin/lpstat", ["-W", "not-completed", "-o", queue])
        for raw in held.split(separator: "\n") {
            guard let id = raw.split(separator: " ").first, id.hasPrefix(queue + "-") else { continue }
            _ = shell("/usr/bin/lp", ["-i", String(id), "-H", "resume"])
        }
    }

    /// استئناف يدوي من زر التطبيق.
    func resume() {
        let q = Model.shared.queue
        guard !q.isEmpty else { return }
        Model.shared.status = "جاري استئناف الطباعة…"
        resumeThrottle = 0
        Task.detached(priority: .userInitiated) {
            PrintQueue.resumeQueue(q)
            await MainActor.run { self.poll() }
        }
    }

    private func notifyStall(_ paperOut: Bool) {
        let content = UNMutableNotificationContent()
        content.title = paperOut ? "انتهى الورق" : "الطباعة متوقفة"
        content.body = paperOut
            ? "ضع ورقاً في الطابعة وستُكمل الطباعة تلقائياً"
            : "تحقّق من الطابعة لاستئناف الطباعة"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "maseh.stall.\(UUID().uuidString)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    nonisolated static func parse(queue q: String, out: String, active: String,
                                  titles: [String: String]) -> [Job] {
        var list: [Job] = []
        for raw in out.split(separator: "\n") {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let first = line.split(separator: " ").first else { continue }
            let id = String(first)
            guard id.hasPrefix(q + "-") else { continue }
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var kb = ""
            if f.count >= 3, let b = Int(f[2]), b > 0 {
                kb = b >= 1_048_576 ? "\(b / 1_048_576) م.ب" : "\(max(1, b / 1024)) ك.ب"
            }
            list.append(Job(id: id,
                            title: titles[id] ?? id,
                            rank: active.contains(id) ? "قيد الطباعة" : "في الانتظار",
                            size: kb))
        }
        return list
    }

    private func apply(_ list: [Job], _ ps: PState) {
        polling = false
        jobs = list

        if list.isEmpty {
            paused = false; attention = ""; notifiedStall = false; resumeThrottle = 0
            state = "لا توجد مهام"
            if hadJobs {
                hadJobs = false
                Model.shared.status = "تمت الطباعة ✓"
            }
            idleTicks += 1
            if idleTicks > 8 { stop() }
            return
        }

        hadJobs = true
        idleTicks = 0

        if ps.paperOut || ps.attention {
            paused = true
            attention = ps.paperOut ? "انتهى الورق" : "الطباعة متوقفة"
            state = ps.paperOut ? "انتهى الورق" : "الطباعة متوقفة"
            Model.shared.status = ps.paperOut
                ? "⚠️ انتهى الورق — ضع ورقاً وستُكمل تلقائياً"
                : "⚠️ الطباعة متوقفة — تحقّق من الطابعة"

            if !notifiedStall {
                notifiedStall = true
                notifyStall(ps.paperOut)
            }

            // محاولة استئناف تلقائي كل ~8 ثوانٍ: بمجرد توفّر الورق تُكمل الطباعة
            resumeThrottle += 1
            if resumeThrottle >= 4 {
                resumeThrottle = 0
                let q = Model.shared.queue
                Task.detached(priority: .utility) { PrintQueue.resumeQueue(q) }
            }
        } else {
            paused = false; attention = ""; notifiedStall = false; resumeThrottle = 0
            state = list.contains { $0.rank == "قيد الطباعة" } ? "تطبع الآن" : "في الانتظار"
        }
    }

    func cancel(_ id: String) {
        _ = PrintQueue.shell("/usr/bin/cancel", [id])
        poll()
    }

    func cancelAll() {
        let q = Model.shared.queue
        guard !q.isEmpty else { return }
        _ = PrintQueue.shell("/usr/bin/cancel", ["-a", q])
        poll()
    }
}

struct QueueBlock: View {
    @ObservedObject var q = PrintQueue.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if q.paused {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(q.attention.isEmpty ? "الطباعة متوقفة" : q.attention)
                            .font(.custom(arFont, size: 11).weight(.bold))
                        Text("ضع ورقاً وستُكمل تلقائياً، أو اضغط «متابعة»")
                            .font(.custom(arFont, size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: q.resume) {
                        Text("متابعة").font(.custom(arFont, size: 11).weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 6) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(q.paused ? Color.orange : Color.accentColor)
                Text("طابور الطباعة — \(q.state)")
                    .font(.custom(arFont, size: 11).weight(.medium))
                Spacer()
                if q.jobs.count > 1 {
                    Button(action: q.cancelAll) {
                        Text("إلغاء الكل").font(.custom(arFont, size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            ForEach(q.jobs) { job in
                HStack(spacing: 7) {
                    if job.rank == "قيد الطباعة" {
                        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 12)
                    } else {
                        Circle().fill(Color.orange).frame(width: 6, height: 6).frame(width: 12)
                    }
                    Text(job.title)
                        .font(.custom(arFont, size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.rank)
                        .font(.custom(arFont, size: 10))
                        .foregroundStyle(.secondary)
                    if !job.size.isEmpty {
                        Text(job.size)
                            .font(.custom(arFont, size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button { q.cancel(job.id) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04))
    }
}

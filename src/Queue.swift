import SwiftUI
import AppKit

@MainActor
final class PrintQueue: ObservableObject {
    static let shared = PrintQueue()

    struct Job: Identifiable {
        let id: String
        let title: String
        let rank: String
        let size: String
    }

    @Published var jobs: [Job] = []
    @Published var state = ""
    private var titles: [String: String] = [:]
    private var timer: Timer?
    private var hadJobs = false
    private var idleTicks = 0

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
            await MainActor.run { self.apply(list) }
        }
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

    private func apply(_ list: [Job]) {
        polling = false
        jobs = list

        if list.isEmpty {
            state = "لا توجد مهام"
            if hadJobs {
                hadJobs = false
                Model.shared.status = "تمت الطباعة ✓"
            }
            idleTicks += 1
            if idleTicks > 8 { stop() }
        } else {
            hadJobs = true
            idleTicks = 0
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
            HStack(spacing: 6) {
                Image(systemName: "printer.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.tint)
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

import SwiftUI
import Photos
import AppKit

@MainActor
final class PhotoLib: ObservableObject {
    static let shared = PhotoLib()

    @Published var assets: [PHAsset] = []
    @Published var selected: Set<String> = []
    @Published var note = "جاري فتح مكتبة الصور…"
    @Published var working = false

    func load() {
        guard assets.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { st in
            DispatchQueue.main.async {
                guard st == .authorized || st == .limited else {
                    self.note = "لم يُسمح بالوصول إلى الصور — فعّلها من إعدادات النظام ← الخصوصية ← الصور"
                    return
                }
                let o = PHFetchOptions()
                o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
                o.fetchLimit = 400
                let res = PHAsset.fetchAssets(with: o)
                var a: [PHAsset] = []
                res.enumerateObjects { obj, _, _ in a.append(obj) }
                self.assets = a
                self.note = a.isEmpty ? "لا توجد صور في المكتبة" : ""
            }
        }
    }

    func toggle(_ a: PHAsset) {
        if selected.contains(a.localIdentifier) { selected.remove(a.localIdentifier) }
        else { selected.insert(a.localIdentifier) }
    }

    func printSelected() {
        let chosen = assets.filter { selected.contains($0.localIdentifier) }
        guard !chosen.isEmpty else { return }
        working = true
        note = "جاري تحضير \(chosen.count) صورة…"

        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.version = .current
        opts.deliveryMode = .highQualityFormat

        var urls: [URL] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for a in chosen {
            group.enter()
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: opts) { data, uti, _, _ in
                defer { group.leave() }
                guard let data else { return }
                var ext = "jpg"
                if let uti, uti.contains("png") { ext = "png" }
                else if let uti, uti.contains("heic") { ext = "heic" }
                let u = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lib_\(UUID().uuidString).\(ext)")
                if (try? data.write(to: u)) != nil {
                    lock.lock(); urls.append(u); lock.unlock()
                }
            }
        }

        group.notify(queue: .main) {
            self.working = false
            guard !urls.isEmpty else { self.note = "تعذّر تحضير الصور"; return }
            self.note = ""
            self.selected.removeAll()
            Model.shared.printPhotoURLs(urls, deleteSources: true)
            NSApp.keyWindow?.close()
        }
    }
}

struct PhotoGrid: View {
    @ObservedObject var lib = PhotoLib.shared
    @ObservedObject var m = Model.shared
    @ObservedObject var q = PrintQueue.shared
    @Environment(\.openWindow) private var openWindow

    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            if !lib.note.isEmpty {
                Text(lib.note)
                    .font(.custom(arFont, size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(22)
            }

            ScrollView {
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(lib.assets, id: \.localIdentifier) { a in
                        Cell(asset: a, on: lib.selected.contains(a.localIdentifier))
                            .onTapGesture { lib.toggle(a) }
                    }
                }
                .padding(12)
            }

            Divider()

            HStack(spacing: 10) {
                Text(lib.selected.isEmpty ? "اختر صوراً للطباعة" : "\(lib.selected.count) صورة محددة")
                    .font(.custom(arFont, size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $m.layout) {
                    Text("صورة في صفحة").tag("one")
                    Text("صورتان").tag("two")
                    Text("٤ صور").tag("four")
                    Text("٦ صور").tag("six")
                    Text("٩ صور").tag("nine")
                    Divider()
                    Text("شخصية ٤×٦ سم").tag("id46")
                    Text("شخصية ٣٥×٤٥ مم").tag("id35")
                }
                .labelsHidden().frame(width: 130)

                Picker("", selection: $m.photoPaper) {
                    Text("A4").tag("A4")
                    Text("١٠×١٥ سم").tag("10x15")
                    Text("١٣×١٨ سم").tag("13x18")
                }
                .labelsHidden().frame(width: 110)

                Toggle(isOn: $m.photoFill) {
                    Text("ملء الصفحة").font(.custom(arFont, size: 11))
                }
                .toggleStyle(.checkbox)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "options")
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("خيارات الطابعة")

                Button(action: lib.printSelected) {
                    HStack(spacing: 5) {
                        Image(systemName: "printer")
                        Text("طباعة").font(.custom(arFont, size: 13).weight(.medium))
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .disabled(lib.selected.isEmpty || lib.working || m.busy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 640, minHeight: 460)
        .environment(\.layoutDirection, .rightToLeft)
        .safeAreaInset(edge: .top) {
            if !q.jobs.isEmpty { QueueBlock() }
        }
        .onAppear { lib.load(); m.loadQueues(); q.start() }
        .onDisappear { q.stop() }
    }
}

private struct Cell: View {
    let asset: PHAsset
    let on: Bool
    @State private var img: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 104, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(on ? Color.accentColor : Color.clear, lineWidth: 3)
            )

            if on {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(5)
            }
        }
        .contentShape(Rectangle())
        .task { fetch() }
    }

    private func fetch() {
        let o = PHImageRequestOptions()
        o.isNetworkAccessAllowed = true
        o.deliveryMode = .opportunistic
        o.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 240, height: 240),
            contentMode: .aspectFill,
            options: o
        ) { image, _ in
            if let image { self.img = image }
        }
    }
}

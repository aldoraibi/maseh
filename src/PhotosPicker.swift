import SwiftUI
import Photos
import AppKit

@MainActor
final class PhotoLib: ObservableObject {
    static let shared = PhotoLib()

    @Published var assets: [PHAsset] = []
    @Published var selected: Set<String> = []
    @Published var note = tr("جاري فتح مكتبة الصور…", "Opening the Photos library…")
    @Published var working = false

    func load() {
        guard assets.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { st in
            DispatchQueue.main.async {
                guard st == .authorized || st == .limited else {
                    self.note = tr("لم يُسمح بالوصول إلى الصور — فعّلها من إعدادات النظام ← الخصوصية ← الصور", "No access to Photos — enable it in System Settings → Privacy → Photos")
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
                self.note = a.isEmpty ? tr("لا توجد صور في المكتبة", "No photos in the library") : ""
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
        note = tr("جاري تحضير \(chosen.count) صورة…", "Preparing \(chosen.count) photos…")

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
            guard !urls.isEmpty else { self.note = tr("تعذّر تحضير الصور", "Couldn't prepare the photos"); return }
            self.note = ""
            self.selected.removeAll()
            Model.shared.printPhotoURLs(urls, deleteSources: true)
            NSApp.keyWindow?.close()
        }
    }
}

struct PhotoGrid: View {
    @ObservedObject var lib = PhotoLib.shared
    @AppStorage("lang") private var lang = "ar"
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
                Text(lib.selected.isEmpty ? tr("اختر صوراً للطباعة", "Choose photos to print") : tr("\(lib.selected.count) صورة محددة", "\(lib.selected.count) selected"))
                    .font(.custom(arFont, size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("", selection: $m.layout) {
                    Text(tr("صورة في صفحة", "One per page")).tag("one")
                    Text(tr("صورتان", "2 photos")).tag("two")
                    Text(tr("٤ صور", "4 photos")).tag("four")
                    Text(tr("٦ صور", "6 photos")).tag("six")
                    Text(tr("٩ صور", "9 photos")).tag("nine")
                    Divider()
                    Text(tr("شخصية ٤×٦ سم", "ID 4×6 cm")).tag("id46")
                    Text(tr("شخصية ٣٥×٤٥ مم", "ID 35×45 mm")).tag("id35")
                }
                .labelsHidden().frame(width: 130)

                Picker("", selection: $m.photoPaper) {
                    Text("A4").tag("A4")
                    Text(tr("١٠×١٥ سم", "10×15 cm")).tag("10x15")
                    Text(tr("١٣×١٨ سم", "13×18 cm")).tag("13x18")
                }
                .labelsHidden().frame(width: 110)

                Toggle(isOn: $m.photoFill) {
                    Text(tr("ملء الصفحة", "Fill page")).font(.custom(arFont, size: 11))
                }
                .toggleStyle(.checkbox)

                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    gShowOptions?()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help(tr("خيارات الطابعة", "Printer options"))

                Button(action: lib.printSelected) {
                    HStack(spacing: 5) {
                        Image(systemName: "printer")
                        Text(tr("طباعة", "Print")).font(.custom(arFont, size: 13).weight(.medium))
                    }
                    .foregroundStyle(Mid.panel)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .glassButton(tint: Mid.accent, radius: 16)
                }
                .buttonStyle(.plain)
                .disabled(lib.selected.isEmpty || lib.working || m.busy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 640, minHeight: 460)
        .midnight(radius: 24, window: true)
        .safeAreaInset(edge: .bottom) { SignatureFooter().padding(.bottom, 8) }
        .environment(\.layoutDirection, Lang.current.layout)
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

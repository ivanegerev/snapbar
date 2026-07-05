import SwiftUI
import AppKit
import AVFoundation
import ImageIO

/// The capture history browser: a searchable grid of everything in the save
/// folder — screenshots, recordings, GIF exports — with the full action set.
struct HistoryItem: Identifiable {
    let url: URL
    let date: Date
    let isMovie: Bool
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

final class HistoryModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", images = "Shots", clips = "Clips"
        var id: String { rawValue }
    }

    @Published var items: [HistoryItem] = []
    @Published var query = ""
    @Published var filter: Filter = .all

    private static let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"]
    private static let movieExts: Set<String> = ["mov", "mp4"]

    func refresh() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Prefs.saveDirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var out: [HistoryItem] = []
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let isMovie = Self.movieExts.contains(ext)
            guard isMovie || Self.imageExts.contains(ext) else { continue }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            out.append(HistoryItem(url: url, date: date, isMovie: isMovie))
        }
        out.sort { $0.date > $1.date }
        items = Array(out.prefix(400))
    }

    var visible: [HistoryItem] {
        items.filter { item in
            switch filter {
            case .all: break
            case .images: if item.isMovie { return false }
            case .clips: if !item.isMovie { return false }
            }
            return query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
        }
    }
}

/// Async thumbnail loading with a shared cache (images, PDFs, and movie posters).
final class ThumbLoader {
    static let shared = ThumbLoader()
    private let cache = NSCache<NSURL, NSImage>()

    func thumbnail(for url: URL, isMovie: Bool) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let image: NSImage? = await Task.detached(priority: .utility) {
            if isMovie {
                let generator = AVAssetImageGenerator(asset: AVAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 480, height: 480)
                guard let cg = try? generator.copyCGImage(
                    at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil
                ) else { return nil }
                return NSImage(cgImage: cg, size: .zero)
            }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return NSImage(contentsOf: url)
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 480,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return NSImage(cgImage: cg, size: .zero)
            }
            return NSImage(contentsOf: url)
        }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

// MARK: - Views

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    @EnvironmentObject var services: AppServices

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.visible.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 172), spacing: 14)], spacing: 14) {
                        ForEach(model.visible) { item in
                            HistoryCell(item: item)
                                .environmentObject(services)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AppServices.capturesChanged)) { _ in
            model.refresh()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search captures", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Picker("", selection: $model.filter) {
                ForEach(HistoryModel.Filter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            Spacer()
            Text("\(model.visible.count) FRAMES")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            Button {
                NSWorkspace.shared.open(Prefs.saveDirURL)
            } label: {
                Image(systemName: "folder")
            }
            .help("Open captures folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.on.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "No captures yet — press ⌃⇧4 to shoot your first frame." : "Nothing matches “\(model.query)”.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryCell: View {
    let item: HistoryItem
    @EnvironmentObject var services: AppServices
    @State private var thumb: NSImage?

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.05)
                    Image(systemName: item.isMovie ? "film" : "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1))
            .overlay(alignment: .bottomTrailing) {
                if item.isMovie {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .padding(5)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }

            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(Self.dateFmt.string(from: item.date))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .task(id: item.url) {
            thumb = await ThumbLoader.shared.thumbnail(for: item.url, isMovie: item.isMovie)
        }
        .onTapGesture(count: 2) { services.open(item.url) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { services.open(item.url) }
            if item.isMovie {
                Button("Edit Clip…") { services.editClip(item.url) }
            } else {
                Button("Annotate…") { services.annotate(item.url) }
                Button("Pin to Screen") { services.pin(item.url) }
            }
            Button("Copy") { services.copyImage(item.url) }
            Button("Copy Path") { services.copyPath(item.url) }
            Button("Reveal in Finder") { services.reveal(item.url) }
            Divider()
            Button("Move to Trash", role: .destructive) { services.trash(item.url) }
        }
        .help(item.name)
    }
}

// MARK: - Window controller

final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?
    private let model = HistoryModel()

    func show() {
        if window == nil {
            let view = HistoryView(model: model).environmentObject(AppServices.shared)
            let hosting = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Capture History"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 780, height: 540))
            win.isReleasedWhenClosed = false
            win.center()
            window = win
        }
        model.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

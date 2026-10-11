import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum PhotoExport: String, CaseIterable, Identifiable {
    case jpeg = "JPEG", heic = "HEIC"
    var id: String { rawValue }
    var suffix: String { self == .jpeg ? "jpg" : "heic" }
    var type: String { self == .jpeg ? UTType.jpeg.identifier : UTType.heic.identifier }
}

struct SourceFrame: Identifiable {
    let url: URL
    let number: Int
    let group: Int
    var id: URL { url }
}

struct SavedProject: Identifiable {
    let directory: URL
    let date: Date
    let settings: StackSettings?
    let frames: [SourceFrame]
    let versions: [URL]
    var id: URL { directory }
    var cover: URL? { versions.first ?? frames.first?.url }
    var canRestack: Bool { settings != nil && settings?.mode != .burst && !frames.isEmpty }
}

enum ProjectFiles {
    static func root() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Stacks", isDirectory: true)
    }

    static func list(at root: URL? = nil) throws -> [SavedProject] {
        let directory = try root ?? self.root()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .compactMap { url -> SavedProject? in
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
                return try load(url)
            }.sorted { $0.date > $1.date }
    }

    static func load(_ directory: URL) throws -> SavedProject {
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey], options: [.skipsHiddenFiles])
            .filter {
                let values = try $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                return values.isRegularFile == true && values.isSymbolicLink != true
            }
        let settings = (try? Data(contentsOf: directory.appendingPathComponent("settings.json")))
            .flatMap { try? JSONDecoder().decode(StackSettings.self, from: $0) }
        let repeats = max(1, settings?.repeats ?? 1)
        let pictures = urls.filter { ["jpg", "jpeg", "heic", "heif", "png"].contains($0.pathExtension.lowercased()) }
        let frames = pictures.compactMap { url -> SourceFrame? in
            let pieces = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            guard pieces.count >= 2, pieces[0] == "frame", let number = Int(pieces[1]), number > 0 else { return nil }
            return SourceFrame(url: url, number: number, group: (number - 1) / repeats)
        }.sorted { $0.number < $1.number }
        let versions = pictures.filter { !$0.lastPathComponent.hasPrefix("frame-") }.sorted {
            if $0 == $1 { return false }
            if $0.lastPathComponent == "MacroStack.jpg" { return true }
            if $1.lastPathComponent == "MacroStack.jpg" { return false }
            return $0.lastPathComponent < $1.lastPathComponent
        }
        let date = try directory.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
        return SavedProject(directory: directory, date: date, settings: settings, frames: frames, versions: versions)
    }

    static func groups(_ frames: [SourceFrame], including selection: Set<URL>) -> [[SourceFrame]] {
        let chosen = frames.filter { selection.contains($0.url) }.sorted { $0.number < $1.number }
        var groups: [[SourceFrame]] = []
        for frame in chosen {
            if groups.last?.last?.group == frame.group { groups[groups.count - 1].append(frame) }
            else { groups.append([frame]) }
        }
        return groups
    }

    static func preview(_ url: URL, maximumDimension: Int = 4096) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension
              ] as CFDictionary) else { throw MacroError.message("Could not read this photo.") }
        return image
    }

    static func write(_ image: CGImage, to url: URL, format: PhotoExport = .jpeg) throws {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.type as CFString, 1, nil) else {
            throw MacroError.message("\(format.rawValue) export is unavailable on this device. Try JPEG.")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.98] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MacroError.message("Photo export failed. Check available storage or try JPEG.") }
        try (data as Data).write(to: url, options: .atomic)
    }

    static func detailImage(_ image: CIImage, amount: Float) -> CIImage {
        let strength = min(1, max(0, amount))
        guard strength > 0 else { return image }
        return image.clampedToExtent().applyingFilter("CIUnsharpMask", parameters: [
            kCIInputRadiusKey: 1.2, kCIInputIntensityKey: strength * 0.75
        ]).cropped(to: image.extent)
    }

    static func createVersion(from source: URL, in directory: URL, amount: Float, format: PhotoExport) throws -> URL {
        guard source.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]) else {
            throw MacroError.message("The source photo could not be opened.")
        }
        let edited = detailImage(image, amount: amount)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(edited, from: edited.extent, format: .RGBA8,
                                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else {
            throw MacroError.message("Could not render this version.")
        }
        let label = amount > 0 ? "Detail" : "Export"
        let url = directory.appendingPathComponent("\(label)-\(UUID().uuidString).\(format.suffix)")
        try write(cg, to: url, format: format)
        let recipe: [String: Any] = ["source": source.lastPathComponent, "amount": amount, "filter": "unsharp-mask", "format": format.rawValue]
        try JSONSerialization.data(withJSONObject: recipe, options: [.prettyPrinted, .sortedKeys])
            .write(to: url.appendingPathExtension("json"), options: .atomic)
        return url
    }

    static func title(_ url: URL) -> String {
        switch url.lastPathComponent {
        case "MacroStack.jpg": return "Original result"
        case "Best-single.jpg": return "Best single"
        default:
            let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-")
            let label = parts.first.map(String.init) ?? "Version"
            return label + " · " + (parts.dropFirst().first.map(String.init) ?? "") + " · " + url.pathExtension.uppercased()
        }
    }
}

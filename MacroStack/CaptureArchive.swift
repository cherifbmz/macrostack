import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Only immutable paths cross queues. Original camera bytes are never recompressed.
final class CaptureArchive: @unchecked Sendable {
    let directory: URL
    let outputURL: URL
    let referenceURL: URL

    init(settings: StackSettings) throws {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        directory = documents.appendingPathComponent("Stacks/\(UUID().uuidString)", isDirectory: true)
        outputURL = directory.appendingPathComponent("MacroStack.jpg")
        referenceURL = directory.appendingPathComponent("Best-single.jpg")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        try Data("Capture in progress. Source files remain available if capture is interrupted.".utf8)
            .write(to: directory.appendingPathComponent("status.txt"), options: .atomic)
    }

    func saveOriginal(_ data: Data, index: Int, focus: Float) throws {
        let source = CGImageSourceCreateWithData(data as CFData, nil)
        let type = source.flatMap { CGImageSourceGetType($0) } as String?
        let ext = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "image"
        let name = String(format: "frame-%03d-focus-%.4f.%@", index, focus, ext)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    func complete(image: CGImage, reference: CGImage, frames: Int, rejected: Int, fallbacks: Int) throws {
        for (cgImage, url) in [(image, outputURL), (reference, referenceURL)] {
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw MacroError.message("Could not create the output file.")
            }
            CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.98] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MacroError.message("Could not save the image. Check available storage.") }
        }
        let summary = "Completed: \(frames) photos; \(rejected) excluded from averaging for softness; \(fallbacks) translation-only alignments.\nBest-single is selected by an overall edge-detail score and aligned/cropped to match the stack.\n"
        try Data(summary.utf8).write(to: directory.appendingPathComponent("status.txt"), options: .atomic)
    }
}

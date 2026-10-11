import SwiftUI

@MainActor
final class ProjectModel: ObservableObject {
    @Published var project: SavedProject
    @Published var selectedVersion: URL?
    @Published var included: Set<URL>
    @Published var fullResolution = true
    @Published var alignFrames = true
    @Published var protectMotion = true
    @Published var detailAmount: Float = 0.35
    @Published var exportFormat: PhotoExport = .jpeg
    @Published var isProcessing = false
    @Published var progress = 0.0
    @Published var status = ""
    @Published var errorMessage: String?
    private var operation: Task<Void, Never>?

    init(project: SavedProject) {
        self.project = project
        selectedVersion = project.versions.first
        included = Set(project.frames.map(\.url))
        fullResolution = project.settings?.fullResolution ?? true
    }

    func cancel() { operation?.cancel() }

    func restack() {
        guard !isProcessing, project.canRestack, let settings = project.settings else { return }
        let groups = ProjectFiles.groups(project.frames, including: included)
        guard !groups.isEmpty else { errorMessage = "Include at least one source frame."; return }
        let directory = project.directory
        let dimension = fullResolution ? 4096 : 2048
        let alignment = alignFrames
        let protection = protectMotion
        isProcessing = true; progress = 0
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task {
            let worker = StackWorker()
            defer { isProcessing = false; operation = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                try await worker.begin(maximumDimension: dimension, subjectRegion: settings.subjectRegion,
                                       registerImages: alignment, protectMotion: protection)
                let total = groups.reduce(0) { $0 + $1.count }
                var processed = 0
                for group in groups {
                    for frame in group {
                        try Task.checkCancellation()
                        status = "Processing source photo \(frame.number)…"
                        _ = try await worker.add(file: frame.url)
                        processed += 1; progress = Double(processed) / Double(total)
                    }
                    try await worker.finishGroup()
                }
                let (stack, reference, rejected, fallbacks, _) = try await worker.finish()
                try Task.checkCancellation()
                status = "Saving a new version…"
                let names = groups.flatMap { $0.map { $0.url.lastPathComponent } }
                let output = try await Task.detached(priority: .userInitiated) {
                    let id = UUID().uuidString
                    let output = directory.appendingPathComponent("Restack-\(id).jpg")
                    try ProjectFiles.write(stack, to: output)
                    try ProjectFiles.write(reference, to: directory.appendingPathComponent("Reference-\(id).jpg"))
                    let recipe: [String: Any] = ["frames": names, "alignFrames": alignment, "protectMotion": protection,
                        "maximumDimension": dimension, "rejectedFrames": rejected, "translationFallbacks": fallbacks]
                    try JSONSerialization.data(withJSONObject: recipe, options: [.prettyPrinted, .sortedKeys])
                        .write(to: output.appendingPathExtension("json"), options: .atomic)
                    return output
                }.value
                try Task.checkCancellation()
                try await reload(select: output)
                status = "New stack saved. \(rejected) soft repeats excluded; \(fallbacks) simpler alignments."
            } catch is CancellationError { status = "Processing cancelled."; await worker.discard() }
            catch { errorMessage = error.localizedDescription; await worker.discard() }
        }
    }

    func makeVersion() {
        guard !isProcessing, let source = selectedVersion else { return }
        let directory = project.directory
        let amount = detailAmount
        let format = exportFormat
        isProcessing = true; progress = 0
        status = "Rendering a separate version…"
        UIApplication.shared.isIdleTimerDisabled = true
        operation = Task {
            defer { isProcessing = false; operation = nil; UIApplication.shared.isIdleTimerDisabled = false }
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try ProjectFiles.createVersion(from: source, in: directory, amount: amount, format: format)
                }.value
                try Task.checkCancellation()
                try await reload(select: output)
                status = "New \(format.rawValue) version saved. Your source is unchanged."
            } catch is CancellationError { status = "Stopped viewing the operation. Any completed version remains in Projects." }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func reload(select url: URL) async throws {
        let directory = project.directory
        let updated = try await Task.detached(priority: .utility) { try ProjectFiles.load(directory) }.value
        try Task.checkCancellation()
        project = updated
        selectedVersion = url
    }
}

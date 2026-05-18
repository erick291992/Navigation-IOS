import SwiftUI
import PhotosUI
import Observation

@MainActor
@Observable
public class CropFlowViewModel {
    // MARK: - Configuration & Callbacks
    private let pickerManager: MediaPickerManager
    private let historyManager: MediaHistoryManager
    private let configuration: MediaPickerConfiguration
    private var onCompletion: ([MediaItem]) -> Void
    private var onCancel: () -> Void
    
    // MARK: - Public State
    public var items: [MediaItem] = []
    public var croppedResults: [Int: UIImage] = [:]
    public var flowState: FlowState = .idle
    
    public enum FlowState: Equatable {
        case idle
        case processing
        case camera
        case cropping(index: Int, total: Int)
        case finished
    }
    
    public init(
        configuration: MediaPickerConfiguration,
        initialItems: [MediaItem] = [],
        pickerManager: MediaPickerManager = .shared,
        historyManager: MediaHistoryManager = .shared,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.pickerManager = pickerManager
        self.historyManager = historyManager
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        self.items = initialItems

        if !initialItems.isEmpty {
            self.moveToNextUncropped()
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Fire-and-forget Task storage (see CODING_GUIDELINES.md §3)
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    // MARK: - Actions
    
    public func handleCapture(_ image: UIImage) {
        flowState = .processing
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let mediaItem = try await self.pickerManager.process(image)
                await MainActor.run {
                    self.items = [mediaItem]
                    self.moveToNextUncropped()
                }
            } catch {
                await MainActor.run {
                    self.flowState = .idle
                }
            }
        }
        tasks.append(task)
    }
    
    /// Stores the cropped image in `croppedResults` (UIImage only — JPEG
    /// encoding is deferred to `finalize` so the per-crop tap stays snappy
    /// and we don't encode any image we ultimately discard if the user
    /// goes back). Earlier shape took a fully-built MediaItem and encoded
    /// JPEG inline in the view's `onDone` closure — that blocked main per
    /// crop and double-encoded (once on tap, once in finalize).
    public func finishCrop(image: UIImage, index: Int) {
        croppedResults[index] = image
        moveToNextUncropped()
    }
    
    public func jumpTo(index: Int) {
        guard index < items.count else { return }
        flowState = .cropping(index: index, total: items.count)
    }
    
    public func requestCamera() {
        flowState = .camera
    }
    
    public func cancelCrop() {
        flowState = .idle
    }
    
    public func dismiss() {
        items = []
        croppedResults = [:]
        flowState = .idle
        onCancel()
    }
    
    // MARK: - Private Logic
    
    private func moveToNextUncropped() {
        for i in 0..<items.count {
            if croppedResults[i] == nil {
                flowState = .cropping(index: i, total: items.count)
                return
            }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.finalize()
        }
        tasks.append(task)
    }

    private func finalize() async {
        // Snapshot on main (safe to read @MainActor state) — we'll send the
        // pairs into a detached Task for the heavy encode work below.
        let pairs: [(MediaItem, UIImage)] = items.enumerated().compactMap { index, originalItem in
            guard let croppedImage = croppedResults[index] else { return nil }
            return (originalItem, croppedImage)
        }

        // Encode every JPEG off main on a worker thread. For N cropped
        // images this would otherwise block main for ~N × ~200 ms while the
        // user waits for the picker to finish. Task.detached runs on the
        // cooperative pool with no actor inheritance.
        let finalItems: [MediaItem] = await Task.detached(priority: .userInitiated) {
            pairs.map { originalItem, croppedImage in
                MediaItem(
                    data: croppedImage.jpegData(compressionQuality: 0.8) ?? originalItem.data,
                    thumbnail: croppedImage,
                    contentType: originalItem.contentType,
                    originalURL: originalItem.originalURL
                )
            }
        }.value

        // Back on main here (Task body completed, we're awaiting from a
        // @MainActor method).
        historyManager.addToHistory(finalItems)
        onCompletion(finalItems)
        items = []
        croppedResults = [:]
        flowState = .finished
    }
}

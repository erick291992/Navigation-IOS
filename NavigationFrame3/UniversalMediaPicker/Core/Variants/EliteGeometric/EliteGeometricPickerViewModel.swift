import SwiftUI
import PhotosUI
import Photos
import Observation

@MainActor
@Observable
public final class EliteGeometricPickerViewModel {
    // MARK: - Configuration & Callbacks
    public let configuration: MediaPickerConfiguration
    private let onCompletion: ([MediaItem]) -> Void
    private let onCancel: () -> Void
    
    // MARK: - Services (constructor-default DI; production omits, tests inject)
    private let cameraService: CameraService
    private let photoKitService: PhotoKitService
    private let historyManager: MediaHistoryManager
    private let pickerManager: MediaPickerManager
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    
    // MARK: - Internal State
    public var selection: [PhotosPickerItem] = []
    public var selectedAssets: [PHAsset] = []
    public var isShowingSystemPicker = false
    public var selectedMode: CreatorMode = .library
    public var isRecording = false
    public var previewAsset: PHAsset?
    public var previewHistoryItem: MediaItem?
    /// Incremented when the user tries to add beyond `selectionLimit`.
    /// View binds `.sensoryFeedback(.error, trigger: rejectionCount)` so
    /// the haptic stays in the view layer.
    public var rejectionCount: Int = 0
    public var zoomFactor: CGFloat { cameraService.zoomFactor }
    public var availableZoomFactors: [CGFloat] { cameraService.availableZoomFactors }
    
    // Flow Management
    public var currentStage: FlowStage = .select
    public var processedItems: [MediaItem] = []
    
    public enum CreatorMode: String, CaseIterable {
        case library = "LIBRARY"
        case reuse = "REUSE"
        case photo = "PHOTO"
        case video = "VIDEO"
    }

    public enum FlowStage: Equatable {
        case select
        case crop
    }
    
    public init(
        configuration: MediaPickerConfiguration,
        cameraService: CameraService = .shared,
        photoKitService: PhotoKitService = .shared,
        historyManager: MediaHistoryManager = .shared,
        pickerManager: MediaPickerManager = .shared,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.cameraService = cameraService
        self.photoKitService = photoKitService
        self.historyManager = historyManager
        self.pickerManager = pickerManager
        self.onCompletion = onCompletion
        self.onCancel = onCancel
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Computed State
    public var recentAssets: [PHAsset] { photoKitService.recentAssets }
    public var history: [MediaItem] { historyManager.history }
    public var authStatus: PHAuthorizationStatus { photoKitService.authStatus }
    
    public var canProceed: Bool {
        if selectedMode == .library { return previewAsset != nil || !selectedAssets.isEmpty }
        if selectedMode == .reuse { return previewHistoryItem != nil }
        return false
    }
    
    // MARK: - Actions
    
    public func setup() {
        let fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.photoKitService.fetchRecentAssets()
            // Read recentAssets AFTER the fetch completes (pre-existing race).
            if self.previewAsset == nil, let first = self.recentAssets.first {
                self.previewAsset = first
            }
        }
        let warmTask = Task { [weak self] in
            guard let self else { return }
            await self.cameraService.startWarming()
        }
        tasks.append(contentsOf: [fetchTask, warmTask])
    }

    public func updateAuth() {
        photoKitService.updateAuthStatus()
        if photoKitService.authStatus == .authorized || photoKitService.authStatus == .limited {
            let task = Task { [weak self] in
                guard let self else { return }
                await self.photoKitService.fetchRecentAssets()
            }
            tasks.append(task)
        }
    }
    
    public func selectMode(_ mode: CreatorMode) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedMode = mode
        }
    }
    
    public func toggleAsset(_ asset: PHAsset) {
        if configuration.selectionLimit > 1 {
            if let index = selectedAssets.firstIndex(of: asset) {
                selectedAssets.remove(at: index)
                if previewAsset == asset {
                    previewAsset = selectedAssets.last
                }
            } else {
                if selectedAssets.count < configuration.selectionLimit {
                    selectedAssets.append(asset)
                    previewAsset = asset
                } else {
                    rejectionCount += 1
                }
            }
        } else {
            previewAsset = asset
        }
    }
    
    public func setPreviewHistoryItem(_ item: MediaItem?) {
        self.previewHistoryItem = item
    }
    
    public func toggleSystemPicker() {
        isShowingSystemPicker.toggle()
    }
    
    public func flipCamera() {
        cameraService.flipCamera()
    }
    
    public func setZoom(_ factor: CGFloat) {
        cameraService.setZoom(factor)
    }
    
    public func onCancelAction() {
        onCancel()
    }
    
    public func handleNext() {
        if selectedMode == .reuse, let item = previewHistoryItem {
            // Bridge directly to crop stage
            self.processedItems = [item]
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.currentStage = .crop
            }
        } else if selectedMode == .library {
            let assetsToProcess = selectedAssets.isEmpty ? (previewAsset.map { [$0] } ?? []) : Array(selectedAssets)
            let task = Task {
                if let processed = try? await pickerManager.process(assetsToProcess) {
                    await MainActor.run {
                        self.processedItems = processed
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.currentStage = .crop
                        }
                    }
                }
            }
            tasks.append(task)
        }
    }
    
    public func finalizeFlow(items: [MediaItem]) {
        onCompletion(items)
    }
    
    public func cancelCrop() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStage = .select
            processedItems = []
        }
    }
    
    public func onShutterTap() {
        if selectedMode == .photo {
            capturePhoto()
        } else if selectedMode == .video {
            // Video placeholder
        }
    }
    
    public func capturePhoto() {
        cameraService.capture { [weak self] image in
            guard let self = self, let image = image else { return }
            let task = Task {
                if let processed = try? await self.pickerManager.process(image) {
                    await MainActor.run {
                        self.processedItems = [processed]
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            self.currentStage = .crop
                        }
                    }
                }
            }
            self.tasks.append(task)
        }
    }
    
    public func handleSystemPickerSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let task = Task {
            if let results = try? await pickerManager.process(items) {
                await MainActor.run {
                    onCompletion(results)
                }
            }
        }
        tasks.append(task)
    }
    
    public func openLimitedPicker() {
        photoKitService.openLimitedPicker()
    }

    // MARK: - Previewer image (called by EliteGeometricPickerView per previewer)

    /// Synchronous thumbnail peek — parent feeds the result to
    /// `LibraryPreviewer.initialImage` for first-frame paint.
    public func thumbnail(for asset: PHAsset?) -> UIImage? {
        guard let asset else { return nil }
        return photoKitService.cachedThumbnail(for: asset)
    }

    /// Async high-res fetch at the previewer size. Parent passes a closure
    /// wrapping this as `LibraryPreviewer.loadAsync`; the previewer awaits
    /// it in `.task(id:)` for auto-cancel on asset change.
    public func requestThumbnail(for asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            photoKitService.loadThumbnail(for: asset, size: PhotoKitService.previewerTargetSize) { image in
                continuation.resume(returning: image)
            }
        }
    }
}

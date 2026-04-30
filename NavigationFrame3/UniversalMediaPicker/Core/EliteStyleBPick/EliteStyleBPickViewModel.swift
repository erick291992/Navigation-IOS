import SwiftUI
import PhotosUI
import Photos
import Observation

@MainActor
@Observable
public class EliteStyleBPickViewModel {
    // MARK: - Configuration & Callbacks
    private let configuration: MediaPickerConfiguration
    private let onCompletion: ([MediaItem]) -> Void
    private let onCancel: () -> Void
    
    // MARK: - Services
    @ObservationIgnored private let cameraService = CameraService.shared
    @ObservationIgnored private let photoKit = PhotoKitService.shared
    @ObservationIgnored private let historyManager = MediaHistoryManager.shared
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    
    // MARK: - Public State
    public var selection: [PhotosPickerItem] = []
    public var selectedAssets: [PHAsset] = []
    public var isShowingSystemPicker = false
    public var selectedMode: CreatorMode = .library
    public var isRecording = false
    public var previewAsset: PHAsset?
    public var previewHistoryItem: MediaItem?
    
    public enum CreatorMode: String, CaseIterable {
        case library = "LIBRARY"
        case reuse = "REUSE"
        case photo = "PHOTO"
        case video = "VIDEO"
    }
    
    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
    }
    
    // MARK: - Computed State
    public var recentAssets: [PHAsset] { photoKit.recentAssets }
    public var history: [MediaItem] { historyManager.history }
    public var authStatus: PHAuthorizationStatus { photoKit.authStatus }
    public var isCameraSourceReady: Bool { cameraService.isSourceReady }
    
    public var canProceed: Bool {
        if selectedMode == .library { return previewAsset != nil || !selectedAssets.isEmpty }
        if selectedMode == .reuse { return previewHistoryItem != nil }
        return false
    }
    
    // MARK: - Actions
    
    public func setup() {
        photoKit.fetchRecentAssets()
        cameraService.setup()
    }
    
    public func updateAuth() {
        photoKit.updateAuthStatus()
        if photoKit.authStatus == .authorized || photoKit.authStatus == .limited {
            photoKit.fetchRecentAssets()
        }
    }
    
    public func setMode(_ mode: CreatorMode) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMode = mode
        }
    }
    
    public func selectAsset(_ asset: PHAsset) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation {
            if configuration.selectionLimit > 1 {
                if let index = selectedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                    selectedAssets.remove(at: index)
                    if previewAsset?.localIdentifier == asset.localIdentifier {
                        previewAsset = selectedAssets.last
                    }
                } else {
                    if selectedAssets.count < configuration.selectionLimit {
                        selectedAssets.append(asset)
                        previewAsset = asset
                    } else {
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            } else {
                previewAsset = asset
            }
        }
    }
    
    public func selectHistoryItem(_ item: MediaItem) {
        withAnimation {
            previewHistoryItem = item
        }
    }
    
    public func handleNext() {
        if selectedMode == .reuse, let item = previewHistoryItem {
            onCompletion([item])
        } else if selectedMode == .library {
            let assetsToProcess = selectedAssets.isEmpty ? (previewAsset.map { [$0] } ?? []) : Array(selectedAssets)
            
            let task = Task {
                if let processed = try? await MediaPickerEngine.shared.process(assetsToProcess) {
                    await MainActor.run {
                        onCompletion(processed)
                    }
                }
            }
            tasks.append(task)
        }
    }
    
    public func capturePhoto() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        cameraService.capture { [weak self] image in
            guard let self = self, let image = image else { return }
            
            let task = Task {
                if let processed = try? await MediaPickerEngine.shared.process(image) {
                    await MainActor.run {
                        self.onCompletion([processed])
                    }
                }
            }
            self.tasks.append(task)
        }
    }
    
    public func flipCamera() {
        cameraService.flipCamera()
    }
    
    public func cancel() {
        onCancel()
    }
    
    public func handleSystemPickerSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let task = Task {
            if let results = try? await MediaPickerManager.shared.process(items) {
                await MainActor.run {
                    onCompletion(results)
                }
            }
        }
        tasks.append(task)
    }
    
    deinit {
        // Cancel all inflight tasks
        // Since VM is MainActor, this is safe if we don't block
    }
}

import SwiftUI
import PhotosUI
import Photos
import Observation

@MainActor
@Observable
public class EliteGeometricPickerViewModel {
    // MARK: - Configuration & Callbacks
    public let configuration: MediaPickerConfiguration
    private let onCompletion: ([MediaItem]) -> Void
    private let onCancel: () -> Void
    
    // MARK: - Services
    public let cameraService = CameraService.shared
    public let photoKit = PhotoKitService.shared
    private let historyManager = MediaHistoryManager.shared
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    
    // MARK: - Internal State
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
    
    public var canProceed: Bool {
        if selectedMode == .library { return previewAsset != nil || !selectedAssets.isEmpty }
        if selectedMode == .reuse { return previewHistoryItem != nil }
        return false
    }
    
    // MARK: - Actions
    
    public func setup() {
        photoKit.fetchRecentAssets()
        cameraService.setup()
        
        if previewAsset == nil, let first = recentAssets.first {
            previewAsset = first
        }
    }
    
    public func updateAuth() {
        photoKit.updateAuthStatus()
        if photoKit.authStatus == .authorized || photoKit.authStatus == .limited {
            photoKit.fetchRecentAssets()
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
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
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
    
    public func onCancelAction() {
        onCancel()
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
    
    public func onShutterTab() {
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
                if let processed = try? await MediaPickerManager.shared.process(image) {
                    await MainActor.run {
                        self.onCompletion([processed])
                    }
                }
            }
            self.tasks.append(task)
        }
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
}

import SwiftUI
import PhotosUI
import Photos
import Observation

@MainActor
@Observable
public class UnifiedCreatorViewModel {
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
    public var isShowingSystemPicker = false
    public var selectedMode: CreatorMode = .library
    public var isRecording = false
    public var previewAsset: PHAsset?
    public var previewHistoryItem: MediaItem?
    
    public enum CreatorMode {
        case library, reuse, photo
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
    public var recentAssets: [PHAsset] { 
        let assets = photoKit.recentAssets 
        return assets
    }
    
    public var history: [MediaItem] { historyManager.history }
    public var authStatus: PHAuthorizationStatus { photoKit.authStatus }
    
    // MARK: - Actions
    
    public func setup() {
        photoKit.fetchRecentAssets()
        cameraService.setup()
        
        // Proactive update: if we have assets but no preview, set it now
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
    
    public func setPreviewAsset(_ asset: PHAsset?) {
        self.previewAsset = asset
    }
    
    public func setPreviewHistoryItem(_ item: MediaItem?) {
        self.previewHistoryItem = item
    }
    
    public func toggleSystemPicker() {
        photoKit.openSystemPicker(selectionLimit: configuration.selectionLimit) { [weak self] assets in
            self?.handleAssets(assets)
        }
    }
    
    public func openLimitedPicker() {
        photoKit.openLimitedPicker()
    }
    
    public func flipCamera() {
        cameraService.flipCamera()
    }
    
    public func onCancelAction() {
        onCancel()
    }
    
    public func onShutterTab() {
        switch selectedMode {
        case .photo:
            capturePhoto()
        case .library:
            if let asset = previewAsset ?? recentAssets.first {
                handleAsset(asset)
            }
        case .reuse:
            if let item = previewHistoryItem ?? history.first {
                onCompletion([item])
            }
        }
    }
    
    public func capturePhoto() {
        cameraService.capture { [weak self] image in
            guard let self = self, let image = image else { return }
            let task = Task {
                if let item = try? await MediaPickerManager.shared.process(image) {
                    await MainActor.run {
                        self.onCompletion([item])
                    }
                }
            }
            self.tasks.append(task)
        }
    }
    
    public func handleAsset(_ asset: PHAsset) {
        handleAssets([asset])
    }
    
    public func handleAssets(_ assets: [PHAsset]) {
        let task = Task {
            if let processedItems = try? await MediaPickerEngine.shared.process(assets), !processedItems.isEmpty {
                await MainActor.run {
                    self.onCompletion(processedItems)
                }
            }
        }
        tasks.append(task)
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
    
    public func galleryShortcutAction() {
        switch authStatus {
        case .authorized:
            photoKit.openSystemPicker(selectionLimit: configuration.selectionLimit) { [weak self] assets in
                self?.handleAssets(assets)
            }
        case .limited:
            openLimitedPicker()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }
    
    public func modeTitle(_ mode: CreatorMode) -> String {
        switch mode {
        case .library: return "LIBRARY"
        case .reuse: return "REUSE"
        case .photo: return "PHOTO"
        }
    }
}

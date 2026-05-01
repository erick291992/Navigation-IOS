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
    private let pickerManager = MediaPickerManager.shared
    private let pickerEngine = MediaPickerEngine.shared
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    
    // MARK: - Internal State
    public let gridViewModel: AssetGridViewModel
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
        self.gridViewModel = AssetGridViewModel(selectionLimit: configuration.selectionLimit)
        
        // Principal Move: Perform full setup (camera warm-up + photo fetch) 
        // immediately during init to eliminate "first-frame" lag.
        self.setup()
    }
    
    // MARK: - Computed State
    public var recentAssets: [PHAsset] { 
        photoKit.recentAssets 
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
        // 1. Update state INSTANTLY for UI logic (Title, Buttons, etc.)
        selectedMode = mode
        
        // 2. Swap data source (No animation for data)
        if mode == .reuse {
            gridViewModel.trigger(.loadHistory(history))
        } else {
            gridViewModel.trigger(.loadInitialData)
        }
    }
    
    public func setPreviewGridAsset(_ asset: GridAsset) {
        if let phAsset = asset.phAsset {
            self.previewAsset = phAsset
            self.previewHistoryItem = nil
        } else if let mediaItem = asset.mediaItem {
            self.previewHistoryItem = mediaItem
            self.previewAsset = nil
        }
    }
    
    public func toggleSystemPicker() {
        photoKit.openSystemPicker(selectionLimit: configuration.selectionLimit) { [weak self] assets in
            self?.handleGridAssets(assets.map { .phAsset($0) })
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
        let selected = gridViewModel.state.selectedAssets
        if !selected.isEmpty {
            handleGridAssets(selected)
            return
        }
        
        // Fallback to preview item
        switch selectedMode {
        case .photo:
            capturePhoto()
        case .library:
            if let asset = previewAsset {
                handleGridAssets([.phAsset(asset)])
            }
        case .reuse:
            if let item = previewHistoryItem {
                handleGridAssets([.mediaItem(item)])
            }
        }
    }
    
    public func capturePhoto() {
        cameraService.capture { [weak self] image in
            guard let self = self, let image = image else { return }
            let task = Task {
                if let item = try? await self.pickerManager.process(image) {
                    await MainActor.run {
                        self.onCompletion([item])
                    }
                }
            }
            self.tasks.append(task)
        }
    }
    
    public func handleGridAssets(_ assets: [GridAsset]) {
        let task = Task {
            var finalItems: [MediaItem] = []
            
            // Separate phAssets from already processed mediaItems
            let phAssets = assets.compactMap { $0.phAsset }
            let existingItems = assets.compactMap { $0.mediaItem }
            
            // Process phAssets if any
            if !phAssets.isEmpty, let processed = try? await self.pickerEngine.process(phAssets) {
                finalItems.append(contentsOf: processed)
            }
            
            // Add existing items
            finalItems.append(contentsOf: existingItems)
            
            if !finalItems.isEmpty {
                await MainActor.run {
                    self.onCompletion(finalItems)
                }
            }
        }
        tasks.append(task)
    }
    
    public func handleSystemPickerSelection(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let task = Task {
            if let results = try? await self.pickerManager.process(items) {
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
                self?.handleGridAssets(assets.map { .phAsset($0) })
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

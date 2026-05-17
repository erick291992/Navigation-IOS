import Foundation
import Photos
import PhotosUI
import Observation

/// `@MainActor @Observable` coordinator for the universal media picker.
///
/// Holds all **picker-specific cross-cutting state** (`selectedMode`,
/// `previewAsset`, `previewHistoryItem`, `currentAlbum`, `selectedAssets`).
/// Owns the picker's lifecycle callbacks (`onCompletion`, `onCancel`) and
/// orchestrates the flow between the camera service, the photo service, the
/// history manager, the picker engine, and the picker manager.
///
/// Subviews (Camera/Library/History viewfinders, the asset grid, the
/// shutter/mode bar) are self-contained. They receive cross-cutting state
/// from this coordinator either as `let` parameters or `@Binding`, and they
/// fire callbacks UP for events. This coordinator routes the events to its
/// services.
///
/// **Selection sync**: `AssetGridView` mirrors its `state.selectedAssets` up
/// to this VM via the `onSelectionChange` callback. This mirror drives
/// `selectionCount` (NEXT button count) and `handleNextTapped` /
/// `handleShutter` (selection processing). No direct reference to
/// `AssetGridViewModel` is held here — the grid VM lives privately inside
/// `AssetGridView`'s `@State`.
@MainActor
@Observable
public final class PickerViewModel {
    // MARK: - Configuration & callbacks (immutable)

    public let configuration: MediaPickerConfiguration
    private let onCompletion: ([MediaItem]) -> Void
    private let onCancel: () -> Void

    // MARK: - Services (private — VMs forward, views never see)

    private let cameraService = CameraService.shared
    private let photoKit = PhotoKitService.shared
    private let historyManager = MediaHistoryManager.shared
    private let pickerEngine = MediaPickerEngine.shared
    private let pickerManager = MediaPickerManager.shared

    // MARK: - Cross-cutting picker state (the truth source for parameters down)

    public var selectedMode: PickerMode = .library
    public var previewAsset: PHAsset?
    public var previewHistoryItem: MediaItem?

    /// Currently displayed album — single source of truth, passed to
    /// `AssetGridView` and `AlbumDropdownMenu` via `@Binding`.
    public var currentAlbum: PhotoLibraryService.AlbumInfo?

    /// Mirror of `AssetGridView`'s selection, updated via the
    /// `onSelectionChange` callback. Drives NEXT-button count and
    /// shutter/NEXT-tapped processing.
    public var selectedAssets: [GridAsset] = []

    // MARK: - Init

    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
    }

    // MARK: - Computed proxies (read by PickerView via the strict View → VM rule)

    public var authStatus: PHAuthorizationStatus { photoKit.authStatus }
    public var recentAssets: [PHAsset] { photoKit.recentAssets }
    public var history: [MediaItem] { historyManager.history }
    public var albums: [PhotoLibraryService.AlbumInfo] { photoKit.albums }

    public var availableZoomFactors: [CGFloat] { cameraService.availableZoomFactors }
    public var zoomFactor: CGFloat { cameraService.zoomFactor }

    public var selectionCount: Int { selectedAssets.count }

    // MARK: - Intent: album bootstrap (initial-album setup for the picker flow)

    /// Picker-flow initial-album bootstrap. Loads the album list via the
    /// PhotoKit facade and seeds `currentAlbum` to the first one if not
    /// already set. `AssetGridView`'s `.onChange(of: currentAlbum)` then
    /// triggers the first asset load.
    public func loadInitialAlbumIfNeeded() async {
        await photoKit.loadAlbumsIfNeeded()
        if currentAlbum == nil, let first = photoKit.albums.first {
            currentAlbum = first
        }
    }

    // MARK: - Intent: selection sync (callback from AssetGridView)

    /// Called from `AssetGridView.onSelectionChange` whenever the grid VM's
    /// selection array changes. Keeps our mirror in sync so `selectionCount`
    /// and the shutter/NEXT handlers see the same selection the user just
    /// made.
    public func updateSelection(_ assets: [GridAsset]) {
        selectedAssets = assets
    }

    // MARK: - Intent: preview / mode

    /// Called from `AssetGridView.onAssetTap` with the tapped grid asset.
    /// Updates `previewAsset` (library mode) or `previewHistoryItem` (reuse
    /// mode) so the top viewfinder reflects the user's most recent tap.
    public func handleGridAssetTap(_ asset: GridAsset) {
        if let phAsset = asset.phAsset {
            previewAsset = phAsset
            previewHistoryItem = nil
        } else if let item = asset.mediaItem {
            previewHistoryItem = item
            previewAsset = nil
        }
    }

    /// Called from the mode bar. The grid VM listens for `selectedMode`
    /// changes via its own `.onChange` and swaps its data source
    /// accordingly — we just publish the new mode here.
    public func selectMode(_ mode: PickerMode) {
        selectedMode = mode
    }

    public func setPreview(_ asset: PHAsset) {
        previewAsset = asset
        previewHistoryItem = nil
    }

    // MARK: - Intent: shutter / NEXT / cancel

    /// Fires when the shutter is tapped. Mode-aware:
    /// - photo mode: capture via camera.
    /// - library/reuse mode + selection: submit selection.
    /// - library/reuse mode + no selection: submit the preview item.
    public func handleShutter() {
        if !selectedAssets.isEmpty {
            handleGridAssets(selectedAssets)
            return
        }

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

    /// Fires when the NEXT button is tapped. Processes the user's current
    /// selection (mirrored from `AssetGridView`).
    public func handleNextTapped() {
        handleGridAssets(selectedAssets)
    }

    public func handleCancel() {
        onCancel()
    }

    // MARK: - Intent: camera

    public func flipCamera() {
        cameraService.flipCamera()
    }

    public func setZoom(_ factor: CGFloat) {
        cameraService.setZoom(factor)
    }

    private func capturePhoto() {
        cameraService.capture { [weak self] image in
            guard let self, let image else { return }
            Task {
                guard let item = try? await self.pickerManager.process(image) else { return }
                await MainActor.run {
                    self.onCompletion([item])
                }
            }
        }
    }

    // MARK: - Intent: gallery shortcut + system picker

    /// Mode-aware gallery shortcut behavior (auth-based routing).
    public func handleGalleryShortcut() {
        switch authStatus {
        case .authorized:
            openSystemPicker()
        case .limited:
            photoKit.openLimitedPicker()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            break
        }
    }

    /// Opens `PHPickerViewController` via PhotoKitService and routes results
    /// back through the grid-assets handler.
    public func openSystemPicker() {
        photoKit.openSystemPicker(selectionLimit: configuration.selectionLimit) { [weak self] assets in
            self?.handleGridAssets(assets.map { .phAsset($0) })
        }
    }

    // MARK: - Intent: lifecycle

    /// Called from `PickerView`'s `scenePhase` observer when the app becomes
    /// active again. Refreshes auth status and (if newly authorized) recents.
    public func refreshAuthIfNeeded() {
        photoKit.updateAuthStatus()
        if photoKit.authStatus == .authorized || photoKit.authStatus == .limited {
            Task { await photoKit.fetchRecentAssets() }
        }
    }

    /// Triggered from the onboarding "GET STARTED" button. Requests auth +
    /// warms camera so the user lands in a populated picker on grant.
    public func requestPermissions() {
        Task { await photoKit.fetchRecentAssets() }
        Task { await cameraService.startWarming() }
    }

    // MARK: - Processing pipeline

    public func handleGridAssets(_ assets: [GridAsset]) {
        Task {
            var finalItems: [MediaItem] = []

            let phAssets = assets.compactMap { $0.phAsset }
            let existingItems = assets.compactMap { $0.mediaItem }

            if !phAssets.isEmpty,
               let processed = try? await self.pickerEngine.process(phAssets) {
                finalItems.append(contentsOf: processed)
            }

            finalItems.append(contentsOf: existingItems)

            if !finalItems.isEmpty {
                await MainActor.run {
                    self.onCompletion(finalItems)
                }
            }
        }
    }
}

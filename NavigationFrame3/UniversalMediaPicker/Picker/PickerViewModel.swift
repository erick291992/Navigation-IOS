import Foundation
import Photos
import PhotosUI
import Observation

/// `@MainActor @Observable` coordinator for the universal media picker.
///
/// Holds all **picker-specific cross-cutting state** (`selectedMode`,
/// `previewAsset`, `previewHistoryItem`, `currentAlbum`). Owns the picker's
/// lifecycle callbacks (`onCompletion`, `onCancel`) and orchestrates the
/// flow between the camera service, the photo service, the grid VM cache,
/// the history manager, the picker engine, and the picker manager.
///
/// Subviews (Camera/Library/History viewfinders, the asset grid, the
/// shutter/mode bar) are self-contained. They receive cross-cutting state
/// from this coordinator either as `let` parameters (for read-only values)
/// or `@Binding` (for two-way values like `currentAlbum`); they fire
/// callbacks UP for events; this coordinator routes the events to its
/// services.
///
/// The shared-cache `AssetGridViewModel` is held privately as an
/// implementation detail. `PickerView` never sees it — its presence is the
/// load-bearing flicker fix from `ASSETGRID_FLICKER_POSTMORTEM.md` §4.
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

    /// Shared grid VM (process-cached). Private — PickerView reads its own
    /// computed proxies (`selectionCount`, etc.) and never sees this directly.
    private let gridViewModel: AssetGridViewModel

    // MARK: - Cross-cutting picker state (the truth source for parameters down)

    public var selectedMode: PickerMode = .library
    public var previewAsset: PHAsset?
    public var previewHistoryItem: MediaItem?

    /// Currently displayed album — single source of truth, passed to
    /// `AssetGridView` and `AlbumDropdownMenu` via `@Binding`.
    public var currentAlbum: PhotoLibraryService.AlbumInfo?

    // MARK: - Init

    public init(
        configuration: MediaPickerConfiguration,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onCompletion = onCompletion
        self.onCancel = onCancel
        // Resolve the process-cached grid VM (survives upstream identity churn).
        self.gridViewModel = AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
    }

    // MARK: - Computed proxies (read by PickerView via the strict View → VM rule)

    public var authStatus: PHAuthorizationStatus { photoKit.authStatus }
    public var recentAssets: [PHAsset] { photoKit.recentAssets }
    public var history: [MediaItem] { historyManager.history }
    public var albums: [PhotoLibraryService.AlbumInfo] { photoKit.albums }

    public var availableZoomFactors: [CGFloat] { cameraService.availableZoomFactors }
    public var zoomFactor: CGFloat { cameraService.zoomFactor }

    /// Count read from the shared grid VM via internal cache reference. View
    /// reads this proxy; the VM-to-VM access stays an implementation detail.
    public var selectionCount: Int { gridViewModel.state.selectedAssets.count }

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

    /// Called from the mode bar.
    public func selectMode(_ mode: PickerMode) {
        selectedMode = mode
        if mode == .reuse {
            gridViewModel.trigger(.loadHistory(history))
        } else if let album = currentAlbum {
            // Re-load the current album's assets (switching back from .reuse
            // cleared them). `.selectAlbum` is internal to the grid VM —
            // PickerViewModel uses it via its private gridViewModel reference.
            gridViewModel.trigger(.selectAlbum(album))
        }
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
        let selected = gridViewModel.state.selectedAssets
        if !selected.isEmpty {
            handleGridAssets(selected)
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

    /// Fires when the NEXT button is tapped. Processes the grid's current
    /// selection (read from the internal grid VM reference).
    public func handleNextTapped() {
        handleGridAssets(gridViewModel.state.selectedAssets)
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

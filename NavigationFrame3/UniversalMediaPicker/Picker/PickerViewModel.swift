import Foundation
import SwiftUI
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
    //
    // Constructor-default DI: production callers omit these params and get
    // the `.shared` singletons; tests inject mocks via `init(...,
    // photoKit: mockPhotoKit, ...)` without touching the type. No call-site
    // changes needed when the rule is unified across the picker.

    private let cameraService: CameraService
    private let photoKit: PhotoKitService
    private let historyManager: MediaHistoryManager
    private let pickerManager: MediaPickerManager

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
        cameraService: CameraService = .shared,
        photoKit: PhotoKitService = .shared,
        historyManager: MediaHistoryManager = .shared,
        pickerManager: MediaPickerManager = .shared,
        onCompletion: @escaping ([MediaItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.cameraService = cameraService
        self.photoKit = photoKit
        self.historyManager = historyManager
        self.pickerManager = pickerManager
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

    // MARK: - Intent: gallery thumbnail (shutter-bar shortcut)

    /// Resolved bitmap for the 48x48 gallery shortcut on the shutter bar.
    /// Eager-loaded into observable state so the leaf views
    /// (`ShutterAndModeBarView` → `GalleryShortcutButton`) stay pure: they
    /// just take a `UIImage?` and render it. No `.task`, no closures
    /// threading through the chain — wrong shape for an always-visible
    /// singleton thumbnail (see `AssetThumbnailCell` for the lazy/many case).
    public var galleryThumbImage: UIImage?

    /// 140pt matches the previous `AssetThumbnailView` default (size 70 ×
    /// 2x retina). `ThumbnailCache`'s largest-wins policy means a hit from
    /// the grid's 400x400 prewarm is returned and SwiftUI downscales
    /// visually — perceptually identical, one fewer disk fetch.
    private let galleryThumbSize = CGSize(width: 140, height: 140)

    /// Loads (or refreshes) the gallery-shortcut thumbnail from
    /// `recentAssets.first`. Sync peek first; falls through to an async
    /// fetch on miss. Clears the image when there's no recent asset.
    /// PickerView triggers this from its `.task` and `.onChange(of:
    /// recentAssets)` — same lifecycle hook the previewAsset bootstrap uses.
    public func loadGalleryThumbIfNeeded() async {
        guard let asset = recentAssets.first else {
            galleryThumbImage = nil
            return
        }
        if let cached = photoKit.cachedThumbnail(for: asset) {
            galleryThumbImage = cached
            return
        }
        galleryThumbImage = await withCheckedContinuation { continuation in
            photoKit.loadThumbnail(for: asset, size: galleryThumbSize) { image in
                continuation.resume(returning: image)
            }
        }
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

    // MARK: - Intent: gallery shortcut (non-authorized paths only)

    /// Auth-based routing for the gallery shortcut tap when the user is
    /// NOT authorized. The authorized path is handled inside
    /// `GalleryShortcutButton` by `PhotosPicker` directly — no callback
    /// reaches here for that case.
    public func handleGalleryShortcut() {
        switch authStatus {
        case .limited:
            photoKit.openLimitedPicker()
        case .denied, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        default:
            // .authorized goes through PhotosPicker; .notDetermined is
            // handled by the onboarding flow, not this button.
            break
        }
    }

    /// Called from `PickerView`'s `.onChange(of: systemPickerSelection)`
    /// when `PhotosPicker` writes a new selection. Routes the picked
    /// items through `pickerManager.process(_:)` and hands the
    /// resulting `MediaItem` array to the completion callback.
    ///
    /// This replaces the old delegate-callback path: `PhotosPicker` is a
    /// SwiftUI-native binding, so we no longer need a shared mutable
    /// delegate, a topVC traversal, or imperative `present()` — Apple's
    /// own picker handles its lifecycle and just writes back via the
    /// binding when the user picks.
    public func processPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        if let mediaItems = try? await pickerManager.process(items) {
            onCompletion(mediaItems)
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
               let processed = try? await self.pickerManager.process(phAssets) {
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

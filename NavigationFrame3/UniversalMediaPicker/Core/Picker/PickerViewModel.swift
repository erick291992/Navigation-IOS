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
    // photoKitService: mockPhotoKitService, ...)` without touching the type. No call-site
    // changes needed when the rule is unified across the picker.

    private let cameraService: CameraService
    private let photoKitService: PhotoKitService
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

        // Eager-init from the prewarmed singleton cache. When the modifier's
        // prewarm has already completed (the common case), PhotoKitService
        // holds albums + prewarmedFirstAlbumAssets + the warm thumbnail
        // bitmaps. Reading them at init time means our first body evaluation
        // sees the warm content — no async wait, no "popping in." When
        // prewarm hasn't completed (cold race), these reads return nil/empty
        // and the grid's loadAssets path (via onFirstAssetChanged →
        // handleFirstAlbumAssetChanged) fills them later.
        //
        // Both `previewAsset` AND `galleryThumbImage` are seeded from the
        // ALBUM's first asset — they share a single source of truth (the
        // currently-active album), not separate library-wide vs album-scoped
        // queries. The shortcut's thumbnail follows the album visually
        // (matches what the user is currently looking at) while its TAP
        // behavior is unchanged (opens Apple's PhotosPicker for full-library
        // browsing). See MEDIA_PICKER_GUIDELINES.md "The three PhotoKit
        // queries (side by side)" for the rationale.
        if let firstAlbumAsset = photoKitService.prewarmedFirstAlbumAssets.first {
            self.previewAsset = firstAlbumAsset
            // Warm path: bitmap already in ThumbnailCache → use it.
            // Cold path: cache empty (prewarm cancelled before its gallery
            // thumb step ran, or that step was dropped entirely) → spawn
            // an async load so the shortcut doesn't stay on the spinner.
            // Without this fallback, the @onChange in PickerView never
            // fires (init already set previewAsset to the same value the
            // grid will publish), so `handleFirstAlbumAssetChanged`'s
            // own fallback path never runs.
            if let cached = photoKitService.cachedThumbnail(for: firstAlbumAsset) {
                self.galleryThumbImage = cached
            } else {
                let task = Task { [weak self] in
                    guard let self else { return }
                    let image = await withCheckedContinuation { (cont: CheckedContinuation<UIImage?, Never>) in
                        self.photoKitService.loadThumbnail(for: firstAlbumAsset, size: self.galleryThumbSize) { img in
                            cont.resume(returning: img)
                        }
                    }
                    self.galleryThumbImage = image
                }
                tasks.append(task)
            }
        }
        if let firstAlbum = photoKitService.albums.first {
            self.currentAlbum = firstAlbum
        }
    }

    deinit {
        tasks.forEach { $0.cancel() }
    }

    // MARK: - Fire-and-forget Task storage
    //
    // Sync intent methods (`processPicked`, `refreshGalleryThumb`,
    // `handleGridAssets`, etc.) spawn internal Tasks. We retain the handles
    // here and cancel them on deinit so a mid-flight dismiss doesn't leak
    // self-references or orphan in-flight work. See CODING_GUIDELINES.md §3
    // "Fire-and-forget Task pattern."

    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    // MARK: - Computed proxies (read by PickerView via the strict View → VM rule)

    public var authStatus: PHAuthorizationStatus { photoKitService.authStatus }
    public var history: [MediaItem] { historyManager.history }
    public var albums: [PhotoLibraryService.AlbumInfo] { photoKitService.albums }

    public var availableZoomFactors: [CGFloat] { cameraService.availableZoomFactors }
    public var zoomFactor: CGFloat { cameraService.zoomFactor }

    public var selectionCount: Int { selectedAssets.count }

    // MARK: - Intent: mount-time bootstrap

    /// Single entry point called from `PickerView.task` on mount. Owns the
    /// orchestration of the picker's initial async setup so the view stays
    /// dumb (a view never decides what runs in parallel vs serially — that
    /// belongs to the VM).
    ///
    /// Used to also call `loadGalleryThumbIfNeeded()` to refresh the
    /// shortcut from a separate library-wide recents fetch. After the
    /// unification, the gallery thumb is eager-set in `init` from
    /// `prewarmedFirstAlbumAssets.first` (same source as the previewer)
    /// and follows the album via `handleFirstAlbumAssetChanged(_:)`. The
    /// cold-race fallback inside `handleFirstAlbumAssetChanged` covers the
    /// case where init read empty values.
    public func bootstrap() async {
        await loadInitialAlbumIfNeeded()
    }

    // MARK: - Intent: album bootstrap (initial-album setup for the picker flow)

    /// Picker-flow initial-album bootstrap. Loads the album list via the
    /// PhotoKit facade and seeds `currentAlbum` to the first one if not
    /// already set. `AssetGridView`'s `.onChange(of: currentAlbum)` then
    /// triggers the first asset load.
    public func loadInitialAlbumIfNeeded() async {
        await photoKitService.loadAlbumsIfNeeded()
        if currentAlbum == nil, let first = photoKitService.albums.first {
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

    /// Called from `PickerView.onFirstAssetChanged` when the grid's first
    /// asset changes (album swap, or initial population on cold-race).
    /// Updates BOTH the previewer's asset AND the gallery-shortcut thumbnail
    /// so they stay in sync — both follow the active album. The shortcut's
    /// tap behavior (opens Apple's PhotosPicker) is unchanged; only its
    /// thumbnail image visually mirrors the album the user is browsing.
    ///
    /// Warm path: `cachedThumbnail` hits and `galleryThumbImage` is set
    /// synchronously on this turn of the run loop. Cold-race fallback:
    /// cache miss → spawn a tracked Task that async-fetches at the gallery
    /// thumb size.
    public func handleFirstAlbumAssetChanged(_ asset: PHAsset) {
        previewAsset = asset
        previewHistoryItem = nil
        if let cached = photoKitService.cachedThumbnail(for: asset) {
            galleryThumbImage = cached
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                self.photoKitService.loadThumbnail(for: asset, size: self.galleryThumbSize) { image in
                    continuation.resume(returning: image)
                }
            }
            self.galleryThumbImage = image
        }
        tasks.append(task)
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
            let task = Task { [weak self] in
                guard let self else { return }
                guard let item = try? await self.pickerManager.process(image) else { return }
                await MainActor.run {
                    self.onCompletion([item])
                }
            }
            self.tasks.append(task)
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
            photoKitService.openLimitedPicker()
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
    /// when `PhotosPicker` writes a new selection. Routes the picked items
    /// through `pickerManager.process(_:)` and hands the resulting
    /// `MediaItem` array to the completion callback.
    ///
    /// Sync signature with internal tracked Task — view's `.onChange` body
    /// stays a single line, processing survives the view's lifecycle until
    /// either it completes or the VM deinits.
    public func processPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            if let mediaItems = try? await self.pickerManager.process(items) {
                self.onCompletion(mediaItems)
            }
        }
        tasks.append(task)
    }

    // MARK: - Intent: lifecycle

    /// Called from `PickerView`'s `scenePhase` observer when the app becomes
    /// active again. Refreshes auth status and (if newly authorized) recents.
    public func refreshAuthIfNeeded() {
        photoKitService.updateAuthStatus()
        if photoKitService.authStatus == .authorized || photoKitService.authStatus == .limited {
            let task = Task { [weak self] in
                guard let self else { return }
                await self.photoKitService.fetchRecentAssets()
            }
            tasks.append(task)
        }
    }

    /// Triggered from the onboarding "GET STARTED" button. Requests auth +
    /// warms camera so the user lands in a populated picker on grant.
    public func requestPermissions() {
        let fetchTask = Task { [weak self] in
            guard let self else { return }
            await self.photoKitService.fetchRecentAssets()
        }
        let warmTask = Task { [weak self] in
            guard let self else { return }
            await self.cameraService.startWarming()
        }
        tasks.append(contentsOf: [fetchTask, warmTask])
    }

    // MARK: - Processing pipeline

    public func handleGridAssets(_ assets: [GridAsset]) {
        let task = Task { [weak self] in
            guard let self else { return }
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
        tasks.append(task)
    }
}

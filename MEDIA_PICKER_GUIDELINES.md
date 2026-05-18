# Universal Media Picker

A self-contained, drop-in SwiftUI media picker module. Drag the `UniversalMediaPicker/` folder into any iOS 17+ project and it works.

## Quick start

```swift
struct MyView: View {
    @State private var isPresented = false

    var body: some View {
        Button("Select Media") { isPresented = true }
            .mediaPicker(
                isPresented: $isPresented,
                configuration: .init(selectionLimit: 5, crop: .square),
                onCompletion: { items in print("Picked \(items.count)") },
                onCancel: { }
            )
    }
}
```

That's the entire public API. Everything else is internal.

## Where this document lives

This file (`MEDIA_PICKER_GUIDELINES.md`) and its sibling [DATA_FLOW_PATTERNS.md](DATA_FLOW_PATTERNS.md) live at the **project root** alongside [CODING_GUIDELINES.md](CODING_GUIDELINES.md), not inside the picker module. The picker module is dependency-free and drag-droppable; the docs that describe it live one level up so they can reference the broader project guidelines without a circular dependency.

When dropping the picker into another project, copy these three docs alongside the `UniversalMediaPicker/` folder (or merge their contents into that project's existing docs).

## Folder structure

```
ProjectRoot/
├── CODING_GUIDELINES.md               ← broad project conventions
├── MEDIA_PICKER_GUIDELINES.md         ← you are here (picker overview + integration)
├── DATA_FLOW_PATTERNS.md              ← view ↔ VM ↔ service conventions
│
└── NavigationFrame3/
    └── UniversalMediaPicker/          ← the self-contained module
        │
        ├── API/                       ← public surface
        │   └── MediaPickerModifier.swift  ← the .mediaPicker(...) entry
        │
        ├── Core/                      ← all picker UI (views + view models)
        │   ├── Picker/                ← root picker view + flow container
        │   ├── Viewfinder/            ← top-half viewfinder system
        │   │   ├── Camera/            ← live camera mode
        │   │   ├── Library/           ← photo library mode
        │   │   └── History/           ← reuse-history mode
        │   ├── AssetGrid/             ← bottom-half asset grid
        │   ├── Crop/                  ← post-selection crop flow
        │   ├── Controls/              ← shared view leaves (buttons, dropdowns, etc.)
        │   └── Variants/              ← alternative picker UIs
        │       └── EliteGeometric/
        │
        ├── Services/                  ← stateful infrastructure (one type per file)
        │   ├── PhotoKitService.swift          ← PhotoKit facade + thumbnail caching
        │   ├── PhotoLibraryService.swift      ← albums + limited-access UIKit bridge
        │   ├── CameraService.swift            ← AVCaptureSession lifecycle
        │   ├── CameraDeviceService.swift      ← per-device discovery + capabilities
        │   ├── MediaPickerManager.swift       ← PHAsset/PhotosPickerItem → MediaItem processor
        │   └── MediaHistoryManager.swift      ← reuse-history persistence
        │
        ├── Models/                    ← public value types (one per file)
        │   ├── MediaItem.swift                ← the output type returned to consumers
        │   ├── GridAsset.swift                ← polymorphic PHAsset|MediaItem wrapper
        │   ├── MediaCrop.swift                ← crop modes (square, 4:5, freeform, …)
        │   ├── MediaPickerState.swift         ← internal flow state
        │   ├── MediaPickerConfiguration.swift ← entry-point config
        │   ├── MediaPickerStyle.swift         ← visual theming
        │   └── PickerMode.swift               ← camera | library | history
        │
        └── Examples/                  ← reference integrations (delete in prod)
            ├── MediaPickerDemoView.swift
            ├── AdvancedPickerExampleView.swift / -ViewModel.swift
            └── CustomPickerExampleView.swift / -ViewModel.swift
```

The picker module has six top-level entries (`API/`, `Core/`, `Services/`, `Models/`, `Examples/`). Singular folder names denote concepts (`API/`, `Core/`); plural names denote catalogs of peers (`Services/`, `Models/`, `Examples/`, `Controls/`, `Variants/`).

## Architectural conventions

This module follows strict View → ViewModel → Service lane discipline. Read [DATA_FLOW_PATTERNS.md](DATA_FLOW_PATTERNS.md) for the full set of conventions (when to use `@Binding` vs callbacks, why view models are `@MainActor` but services are not, the closure-based leaf cell pattern, etc.). For broad project-wide patterns that apply beyond the picker, see [CODING_GUIDELINES.md](CODING_GUIDELINES.md).

Two documented infrastructure exceptions exist where views call services directly:
- `API/MediaPickerModifier.swift` (warms services before any VM exists)
- `Core/Controls/CameraPreviewView.swift` (`UIViewRepresentable` bridge for the live AV preview layer)

Both are commented at the file head explaining why.

## What feeds each UI element

The picker screen has four distinct UI regions. After the unification work (2026-05-18), the previewer + gallery shortcut + grid all derive their visual content from **a single album-scoped data source**. The dropdown's album list is separate (it lists albums, not assets), and there's one tiny library-wide boolean query left for the library-viewfinder's empty-state check.

```
┌─────────────────────────────────────────┐
│                                         │
│   [BIG PREVIEW IMAGE]                   │  ← #1 Previewer (top half)
│                                         │     fed by: PickerViewModel.previewAsset
│                                         │     initial value: prewarmedFirstAlbumAssets.first
│                                         │     on album switch: follows album's first
│                                         │     on grid tap: follows the tapped asset
├─────────────────────────────────────────┤
│  Recents ▾                    NEXT      │  ← #2 Album dropdown
│                                         │     fed by: photoKitService.albums
├─────────────────────────────────────────┤
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                    │
│  │  │ │  │ │  │ │  │                    │  ← #3 Asset grid
│  └──┘ └──┘ └──┘ └──┘                    │     fed by: assetGridState.assets
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                    │     mounts from: prewarmedFirstAlbumAssets
│  │  │ │  │ │  │ │  │                    │     pagination grows the list
│  └──┘ └──┘ └──┘ └──┘                    │
├─────────────────────────────────────────┤
│ [🖼]      ( ⚪ )         [⟲]            │  ← #4 Shutter row
│  ↑                                      │     [🖼] = gallery-shortcut button
│  prewarmedFirstAlbumAssets.first        │     fed by: PickerViewModel.galleryThumbImage
│  (same as previewer's source)           │     visually follows the album like the previewer
└─────────────────────────────────────────┘
```

### Data flow: one fetch feeds three UI elements

The previewer (#1), gallery shortcut (#4), and grid (#3) all derive from a single PhotoKit fetch during cold-open prewarm: the album's first page (`prewarmedFirstAlbumAssets`, currently 20 PHAssets at `gridInitialPageSize`).

```
                     ┌──────────────────────────────┐
                     │  Album-scoped fetch          │
                     │  fetchAssets(in: firstAlbum, │
                     │              limit: 20)      │
                     │  → prewarmedFirstAlbumAssets │
                     └──────────────────────────────┘
                                  │
                                  ↓ feeds all of:
              ┌───────────────────┼───────────────────┐
              │                   │                   │
              ↓                   ↓                   ↓
        Previewer            Gallery thumb         Grid cells
        (firstPage.first)    (firstPage.first)     (firstPage.prefix(20))
        @ 1000pt cache       same asset            @ 400pt cache
                             140pt cache hit       (cell 0 inherits the
                             via largest-wins      1000pt entry — same key)
```

**Album switch propagates to all three together.** `AssetGridView.onChange(of: assetGridState.assets.first?.id)` fires when the album swap completes; it calls `PickerViewModel.handleFirstAlbumAssetChanged(_:)`, which updates BOTH `previewAsset` AND `galleryThumbImage` in lock-step. The shortcut's TAP behavior (opens Apple's `PhotosPicker` for library-wide browsing) is unchanged — only its thumbnail visually mirrors the album.

### The remaining library-wide fetch (and why it's still there)

`PhotoKitService` still issues one library-wide query during prewarm: `fetchRecentAssets(limit: 1)`. It does NOT feed any visible photo. Its sole purpose is to populate `recentAssets` with at least one item so `LibraryViewfinderViewModel.hasRecents` can answer "does the user have ANY photos in their library?" — used to choose between the "loading," "empty," and "ready" view states in the library viewfinder.

Cost: ~100ms cold start. Future cleanup (see `project_picker_deferred_media_type_filter.md` and related memos) would eliminate this fetch entirely by deriving `hasRecents` from `prewarmedFirstAlbumAssets` instead. Until then, the limit:1 fetch is the architectural compromise — main picker is fully unified for visible content, with a tiny boolean signal still routing through `recentAssets`.

The `EliteGeometricPickerViewModel` variant explicitly passes `limit: 30` to `fetchRecentAssets` because it uses `recentAssets` as its grid data source (different architecture from the main picker — Elite Geometric doesn't have an album dropdown).

### The three PhotoKit queries (side by side, after unification)

Three distinct PhotoKit fetches happen, but only ONE of them feeds visible photo content:

```
QUERY 1 — recents (LibraryVM signal)  QUERY 2 — grid page 1 (UNIFIED)     QUERY 3 — grid pagination (lazy)
──────────────────────────────         ─────────────────────────────       ────────────────────────────────
PHAsset.fetchAssets(                   PHAsset.fetchAssets(                PHAsset.fetchAssets(
    with: .image,                          in: currentAlbum,                   in: currentAlbum,
    options: {                             options: {                          options: {
      sortDesc: creationDate↓                sortDesc: creationDate↓             sortDesc: creationDate↓
      fetchLimit: 1                          fetchLimit: 20                      (NO fetchLimit — unbounded)
    }                                      }                                   }
)                                      )                                   )

Scope: library-wide                    Scope: one album                    Scope: one album
Filter: images only                    Filter: all media (img + video)     Filter: all media
Size: 1 PHAsset                        Size: 20 PHAssets                   Size: full result (lazy)
Used by: LibraryViewfinder's           Used by: previewer, gallery         Used by: grid pagination
  hasRecents bool check ONLY             shortcut, AND grid cells 0-19       (materializes 20..80,
  (no visible image)                     (single source of truth for          80..140, etc.)
                                         visible content)

Cost: ~100ms cold start                Cost: ~10ms (top-K fast path)       Cost: ~75ms unbounded sort
  (first PhotoKit op)                                                        on 33k-photo library
```

**Pagination is index-range materialization, not offset arithmetic.** `fetchAssetsResult` returns a lazy `PHFetchResult<PHAsset>` over the whole album; `materialize(from: result, range: 20..<80)` extracts page 2. Page 1's first 20 (from query 2) are guaranteed to equal the first 20 of query 3's result because both share `sortDescriptors = [creationDate↓]`. No risk of cell 19 appearing twice across page boundaries.

### Cell 0 + previewer + shortcut share a cache entry — by design

Grid cell 0, the previewer, and the gallery shortcut all visually display the SAME PHAsset (the active album's first asset). They all read from `ThumbnailCache.shared`, keyed by `"<localIdentifier>|<modDate>"`. The cache entry is populated by `prewarmVisibleContent`:

```
T-2.5s   prewarmVisibleContent step 2:
           loadThumbnail(for: firstAlbumAsset, size: 1000×1000)
         → ThumbnailCache["<firstAlbumAsset.id>|<modDate>"] = UIImage @ 1000×1000

T-2.3s   prewarmVisibleContent step 3:
           loadThumbnail(for: firstAlbumAsset, size: 140×140)
         → cache write skipped (largest-wins: existing 1000pt is bigger;
            the request still hits PhotoKit's internal cache pool)

T-2.3s   prewarmVisibleContent step 4 — prewarms first 20 grid cells:
           Each cell's loadThumbnail at 400pt:
             - Cell 0: cache HIT on the 1000pt entry → no fetch needed
             - Cells 1-19: cache miss → PhotoKit warm-pool fetch at 400pt
                           → cache written at 400pt for each

T=0      Sheet opens. Cells 0-19 + previewer + shortcut paint from cache:
         - Previewer reads cache for firstAlbumAsset → 1000pt entry hit
         - Shortcut reads cache for firstAlbumAsset → same 1000pt entry hit
         - Cell 0 reads cache for firstAlbumAsset → same 1000pt entry hit
         - Cells 1-19 read their own 400pt entries (also hits)
```

This three-way cache-key collision used to be incidental — pre-unification, the previewer prewarmed using `recentAssets.first` (library-wide), which happened to share an identifier with `gridCells[0]` only when the user's most recent thing was an image. After unification, the previewer + shortcut + grid all derive from `prewarmedFirstAlbumAssets.first` by design. The collision is intentional, not coincidental.

**Design invariant for future contributors:** previewer + shortcut + grid cell 0 share one ThumbnailCache entry. Don't change what prewarm step 2 caches (size or asset) without preserving this. If the previewer's asset diverges from the grid's first asset, you've broken the unification — the shortcut would show a different photo than cell 0, which contradicts the iOS-native "consistency between what you see and what you tap" expectation.

## Requirements

- iOS 17+ (`.sensoryFeedback`, `@Observable`, `PhotosPicker`)
- Info.plist entries:
  - `NSPhotoLibraryUsageDescription`
  - `NSCameraUsageDescription`
  - `NSMicrophoneUsageDescription` (if recording video)

## Style customization

```swift
let style = MediaPickerStyle(
    accentColor: .pink,
    doneButtonStyle: .capsule,
    gridStyle: .init(columnCount: 3, spacing: 2)
)
let config = MediaPickerConfiguration(style: style)
```

## Headless / custom UI

To build a fully custom picker UI on top of the same engine, see `Examples/AdvancedPickerExampleView.swift`. The key seam is `MediaPickerManager.shared.process(...)` — pass it raw `PHAsset`s or `PhotosPickerItem`s, get `MediaItem`s back.

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

The picker screen has four distinct UI regions, and they're fed by **different data sources**. Two of them happen to look identical on the default Recents view, which causes confusion — this section makes the wiring explicit.

```
┌─────────────────────────────────────────┐
│                                         │
│   [BIG PREVIEW IMAGE]                   │  ← #1 Previewer (top half)
│                                         │     fed by: PickerViewModel.previewAsset
│                                         │     initial value: recentAssets.first
│                                         │     after grid loads: follows the grid
│                                         │     after grid tap: follows the tap
├─────────────────────────────────────────┤
│  Recents ▾                    NEXT      │  ← #2 Album dropdown
│                                         │     fed by: photoKitService.albums
├─────────────────────────────────────────┤
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                    │
│  │  │ │  │ │  │ │  │                    │  ← #3 Asset grid
│  └──┘ └──┘ └──┘ └──┘                    │     fed by: assetGridState.assets
│  ┌──┐ ┌──┐ ┌──┐ ┌──┐                    │     fetched fresh per album switch
│  │  │ │  │ │  │ │  │                    │     does NOT read recentAssets
│  └──┘ └──┘ └──┘ └──┘                    │
├─────────────────────────────────────────┤
│ [🖼]      ( ⚪ )         [⟲]            │  ← #4 Shutter row
│  ↑                                      │     [🖼] = gallery-shortcut button
│  recentAssets.first                     │     fed by: recentAssets.first (always)
└─────────────────────────────────────────┘
```

### The two PhotoKit fetches: `recentAssets` vs `assetGridState.assets`

These look like the same query in different places. They aren't.

| | `photoKitService.recentAssets` | `assetGridState.assets` |
|---|---|---|
| **Scope** | Library-wide (no album) | Album-scoped (`PHAssetCollection`) |
| **Filter** | Images only (`.image`) | All media (images + videos) |
| **Size** | ~30 items (capped via `fetchLimit`) | 60 + paginated growth |
| **Owner** | `PhotoKitService` (shared) | `AssetGridViewModel` (per-mount) |
| **Lifecycle** | Prewarmed once; refreshed on library-change observer | Reloaded fresh on every album switch |
| **Feeds** | #1 previewer first paint, #4 gallery shortcut | #3 grid cells |

On the **default Recents view** the two sets overlap because the Recents smart album (`smartAlbumUserLibrary`) is "all images + videos sorted by creation date." Same direction (newest first), so the first ~30 items match. **Switch to any other album** (Screenshots, Favorites, Videos) and they diverge: the grid reloads to that album's contents, `recentAssets` keeps the library-wide newest 30.

### Why two queries instead of one

Three reasons we don't collapse `recentAssets` into the grid's fetch:

1. **First-paint timing.** The previewer needs *something to show NOW* when the sheet opens. The grid is mounting in parallel and won't have data for ~150-400ms (the album-scoped fetch). `recentAssets` is pre-loaded during the modifier's `prewarm()` BEFORE the sheet opens, so the previewer paints from `recentAssets.first` on the first frame.

2. **The gallery-shortcut button has different semantics.** Per iOS convention (matches Apple's Camera app), the gallery shortcut always shows "the most recent photo in your library" — independent of which album the user is browsing in the grid. Switch to Screenshots → grid changes, gallery shortcut stays on library-wide newest. That requires a library-wide list, which is exactly what `recentAssets` is.

3. **Limited Access compatibility.** When the user is in Limited Access mode, the library-wide query and any album-scoped query return different (possibly disjoint) sets. The previewer + gallery shortcut need to respect the limited-set independent of album scoping.

### How #1 (the previewer) transitions from `recentAssets` to the grid

The previewer doesn't read `recentAssets` directly — it reads `PickerViewModel.previewAsset`. The value of `previewAsset` evolves through three states:

1. **At VM init**: eager-set to `recentAssets.first` (sync read from the prewarmed singleton).
2. **After the grid loads** for any album: `AssetGridView` fires `onFirstAssetChanged(...)`, which calls `viewModel.setPreview(...)` with the grid's first asset. The previewer follows the active album from this point.
3. **After a grid tap**: `onAssetTap` fires `viewModel.handleGridAssetTap(...)` which sets `previewAsset` to the tapped item.

So `recentAssets` is **scaffolding for the cold-open window** for the previewer. Once the grid has data, the previewer is grid-driven for the rest of the session.

`LibraryViewfinderViewModel.displayAsset(preferring:)` is a one-line defensive helper:

```swift
public func displayAsset(preferring preview: PHAsset?) -> PHAsset? {
    preview ?? photoKitService.recentAssets.first
}
```

It just falls back to `recentAssets.first` if the parent somehow didn't pass a `previewAsset`. In practice the parent always does (init eager-sets it), so the fallback is a safety net rather than a primary path.

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

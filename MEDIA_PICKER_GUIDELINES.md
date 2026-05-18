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

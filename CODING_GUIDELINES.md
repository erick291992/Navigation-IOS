# Coding Guidelines

A reference for how this codebase is structured and why. Pasteable into other projects so AI assistants follow the same patterns by default.

The conventions here were established during the `UniversalMediaPicker` rebuild and verified to compile + run on iOS 17+. They are written as **rules with rationale** — follow the rule, and when an edge case arises, the rationale tells you whether it applies.

---

## 1. Folder structure

### Top-level shape

Each self-contained feature module follows this five-folder shape:

```
ProjectRoot/
├── CODING_GUIDELINES.md         ← broad project conventions (this file)
├── DATA_FLOW_PATTERNS.md        ← per-feature data-flow conventions
├── FEATURE_GUIDELINES.md        ← feature-specific overview + integration guide
│
└── FeatureModule/               ← drop-droppable, dependency-free
    ├── API/                     ← public surface (the few files consumers call)
    ├── Core/                    ← all internal UI (views + view models)
    ├── Services/                ← stateful infrastructure
    ├── Models/                  ← public value types
    └── Examples/                ← reference integrations (delete in prod)
```

This is the "drag-and-drop module" pattern: a consumer can drop the folder into any project and have a working feature with no scattered dependencies elsewhere. The guideline docs live at the **project root**, not inside the feature folder, so they can reference each other freely without creating circular dependencies between module and docs. When dropping the feature into another project, copy the relevant `*_GUIDELINES.md` docs alongside.

### Singular vs plural folder names

**Plural** = the folder's value *is the collection*. "Browse a bag of N peers, pick one."
**Singular** = the folder's value *is the concept*. "This is the thing, here are its parts."

Test: ask **"what is one item from this folder?"**

| Folder | One item is… | Verdict |
|---|---|---|
| `Models/` | "a model" | Plural ✓ |
| `Services/` | "a service" | Plural ✓ |
| `Controls/` | "a control" | Plural ✓ |
| `Examples/` | "an example" | Plural ✓ |
| `Variants/` | "a variant" | Plural ✓ |
| `Core/` | (no "a core" — it IS the core) | Singular ✓ |
| `API/` | (no "an API file" — it IS the surface) | Singular ✓ |
| `Picker/` | (no "a picker" — it IS the picker's parts) | Singular ✓ |

**Plural folders are catalogs. Singular folders are concepts.**

Don't dump everything into type-based plural folders (`Views/`, `ViewModels/`, `Models/`). That fragments features across four folders. Feature folders are singular (`Picker/`, `Crop/`); only horizontal infrastructure stays plural.

### One public type per file

`Models/` and the public types in `API/` follow **one type per file**. The filename equals the type name. This is the Apple idiom (compare Foundation, SwiftUI source layout). It makes the type discoverable, makes diffs minimal, and gives an obvious place for related extensions.

Internal helpers (small structs used only inside one file) stay with their parent.

### Filenames are domain-action; folders are features

- File: `AssetGridViewModel.swift`, `ShutterButton.swift`, `CameraPreviewView.swift`
- Folder: `AssetGrid/`, `Crop/`, `Viewfinder/Camera/`

Not the other way around. You navigate to the feature, then the file describes the role within it.

---

## 2. Separation of concerns — the View → ViewModel → Service rule

### The rule

```
View    → reads from / sends intent to → ViewModel
ViewModel → calls / observes →            Service
Service → wraps Apple framework / state
```

**Views never call services directly. Services never know about views.** ViewModels are the only thing allowed to bridge the two.

### Why

- **Testability.** A VM with `MediaPickerManager` as a constructor parameter can be tested with a mock. A view that calls `MediaPickerManager.shared` inline cannot.
- **Reusability.** A view that takes `UIImage?` works in any context. A view that takes `PHAsset` and resolves it via PhotoKit only works where PhotoKit is present.
- **Concurrency safety.** VMs are `@MainActor`; services are typically nonisolated. The hop is the actor boundary. Views skipping the VM blur this boundary and break Swift 6 strict checking.

### Documented exceptions

Two and only two places skip the rule. Both have a header comment explaining why:

1. **`API/MediaPickerModifier.swift`** — the public ViewModifier fires `service.prewarm()` in `.onAppear` / `.task` before any VM exists. The whole purpose of the modifier is to warm services at host-view appearance.
2. **`Core/Controls/CameraPreviewView.swift`** — UIKit `UIViewRepresentable` for the live AV preview layer. Needs synchronous access to the `AVCaptureSession` reference; the VM hop has no async/await moment in `makeUIView`.

If you find yourself wanting to add a third exception, **don't**. Add a method to the VM instead, or pass the value down as a parameter.

### Pattern selection (View ↔ ViewModel ↔ View)

Three patterns coexist, each correct in its niche. Choose with the decision tree:

| Use | Pattern | When |
|---|---|---|
| `let value: T` + `let onAction: () -> Void` | **Callback up** (Pattern 1) | Default. Use for leaf views (cells, buttons, presentational shells). |
| `@Binding var value: T` | **Bidirectional binding** (Pattern 2) | Only when Apple's API requires it (`PhotosPicker`, `TextField`) OR when a value is truly bidirectional and updates from both sides. |
| `@Bindable var vm: SomeVM` | **Direct VM access** (Pattern 3) | When a view needs to read many fields of a VM AND the view is owned by that VM's owner. Use sparingly. |

`Picker/Viewfinder/AssetGrid` use Pattern 1 by default; `LibraryViewfinder` uses Pattern 2 (`pickerSelection: Binding<[PhotosPickerItem]>`) where `PhotosPicker` demands it. `EliteGeometricPickerView` uses Pattern 3 internally.

**Never mix patterns within a single child.** A view that takes `@Binding var foo` AND `let onFooChanged: (Foo) -> Void` is doing the same job twice and will get out of sync.

---

## 3. Concurrency strategy

### `@MainActor` placement

Three valid placements, each with a specific job:

| Where | Effect | When to use |
|---|---|---|
| `@MainActor class Foo {…}` | Every method, init, and property runs on main | **View models.** They're SwiftUI's consumers — all reads/writes should be main-isolated by default. |
| `@MainActor public static let shared = Foo()` | Only the shared accessor is main | **Services with main-thread invariants** (UIKit ownership, AV session). Rare. |
| `@MainActor func foo() {…}` (per-method) | This method, plus its sync writes to observable state | **Services that do mixed work.** Class is nonisolated; UI-touching methods opt in. |

### The nonisolated-class pattern (services)

Default shape for a service:

```swift
@Observable
public final class FooService: NSObject {
    public static let shared = FooService()      // nonisolated
    public var someObservableState: T = ...

    // Nonisolated async — the body runs on the cooperative pool per SE-0338.
    public func fetchSomething() async {
        let result = await heavyWork()             // off main
        await MainActor.run {                       // hop back to write
            setSomeObservableState(result)
        }
    }

    @MainActor                                      // sync writers are main
    private func setSomeObservableState(_ v: T) {
        guard someObservableState != v else { return }
        someObservableState = v
    }
}
```

**Why not `@MainActor` on the whole class?** Because `await service.fetchSomething()` from a `@MainActor` VM would hop to main, run the body on main, await heavy work on main (which then hops to cooperative pool anyway), and hop back. The class-level annotation creates main-thread pressure for no benefit. Nonisolated async functions are explicit about *where work runs* (off main) and *where writes happen* (main, via `MainActor.run`).

**Why not `actor`?** Three reasons:
1. `@Observable` requires class semantics; macros don't work on actors.
2. Many service methods touch UIKit (`UIApplication.shared`, `AVCaptureSession`), which is `@MainActor`. An actor would just force everything through `await` for no isolation benefit.
3. The shared instance pattern (`static let shared`) is the dominant access mode; we don't have a re-entrancy problem to solve.

Use `actor` only when you have **mutable state that genuinely needs serialization across threads** AND no UIKit involvement.

### Off-main CPU work

For genuinely heavy CPU (JPEG encoding, image processing, video frame extraction), use `Task.detached(priority: .userInitiated)` inside a VM method:

```swift
let finalItems = await Task.detached(priority: .userInitiated) {
    pairs.map { ... heavy encoding ... }
}.value
// We're back on main here.
```

`Task.detached` does not inherit the caller's actor — the closure runs on the cooperative pool with no main-thread contamination.

Don't put a `@MainActor` annotation on a class whose methods do heavy CPU. The annotation lies about where the work runs and SwiftUI will stutter.

### Equality-guarded setters

Every `@Observable` setter cascades to all observers, even when the value didn't change. For frequently-written state, guard:

```swift
@MainActor
private func setAuthStatus(_ value: PHAuthorizationStatus) {
    guard authStatus != value else { return }
    authStatus = value
}
```

This is not premature optimization — without it, a `PHPhotoLibraryChangeObserver` firing during a normal photo-library change can cascade ten re-evaluations of the entire grid. The original picker flicker bug was caused by missing equality guards.

### `@ObservationIgnored`

Mark non-observable internals (caches, configuration, request options) with `@ObservationIgnored`:

```swift
@ObservationIgnored private let cachingManager = PHCachingImageManager()
```

This keeps the `@Observable` macro from generating change-tracking shims for fields no view should observe. Cleaner generated code, fewer phantom re-renders.

---

## 4. Dependency injection — constructor-default

Every view model takes its services as constructor parameters with `.shared` defaults:

```swift
public init(
    configuration: Config,
    photoKit: PhotoKitService = .shared,
    cameraService: CameraService = .shared,
    historyManager: MediaHistoryManager = .shared,
    onCompletion: @escaping ([MediaItem]) -> Void,
    onCancel: @escaping () -> Void
) { ... }
```

**Production callers** omit the service params — they get `.shared`. Zero call-site noise.

**Tests** pass mocks: `PickerViewModel(configuration: …, photoKit: MockPhotoKit(), …)`.

This is non-negotiable for any VM. Never call `Service.shared.method()` inline inside a VM body — always go through the stored property.

---

## 5. Pure presentational leaves

Cells, previewers, and any view that renders a piece of media follow this shape:

```swift
struct AssetThumbnailCell: View {
    let source: AssetSource                                  // identity
    let initialImage: UIImage?                                // sync paint
    let loadAsync: (() async -> UIImage?)?                    // async upgrade
    let selectionIndex: Int?                                  // adornment
    let onTap: () -> Void                                     // intent up

    @State private var asyncLoaded: UIImage?
    private var displayImage: UIImage? { asyncLoaded ?? initialImage }

    var body: some View {
        ZStack { ... }
        .task(id: source.id) {
            guard displayImage == nil, let loadAsync else { return }
            asyncLoaded = await loadAsync()
        }
    }
}
```

### Why two image inputs

- `initialImage` is the **synchronous cache peek** the parent does before instantiating the cell. The cell paints something on its first frame; no spinner blink.
- `loadAsync` is the **async upgrade loader** the parent provides. Runs in `.task(id:)` so SwiftUI auto-cancels it on cell recycle / disappear. Only runs when `initialImage` is nil (cells) OR always (previewers, which need to upgrade to a larger size).

### Why `@State` for the loaded image

A cell-local `@State` means a finished load re-renders only this cell. If the loaded image lived in the VM's observable state, every cell would re-render on every load completion. Per-cell granularity preserved.

### Leaf views take primitives, not framework types

A view that takes `UIImage` or `String` works in any project. A view that takes `PHAsset` only works where PhotoKit is imported. The parent VM resolves framework types into primitives before passing down. This is what makes the picker's leaf views reusable verbatim in other apps.

---

## 6. View switching — single-sheet flow container

For multi-stage flows (select → crop, onboarding → main, etc.), use a single ZStack container with a flow-state enum:

```swift
struct FlowContainer: View {
    @State private var stage: Stage = .stageA
    @State private var carriedData: T = ...

    enum Stage { case stageA, stageB }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Base layer — always alive (preserves scroll/selection state)
            StageAView(onAdvance: { data in
                carriedData = data
                withAnimation { stage = .stageB }
            })
            .accessibilityHidden(stage == .stageB)

            // Overlay — created/destroyed on stage transitions
            if stage == .stageB {
                StageBView(data: carriedData, onGoBack: {
                    withAnimation {
                        stage = .stageA
                        carriedData = ...      // reset
                    }
                })
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
    }
}
```

### Why one ZStack instead of nested sheets

Nested SwiftUI sheets flicker (the "double sheet" bug). They also tear down state on dismiss. A single sheet hosting a ZStack with `.transition` gives you crisp animation and lets you keep the base layer's state alive across overlay open/close. The picker uses this for `select` ↔ `crop`.

### Why the base layer stays alive

`PickerView` builds `AssetGridView` which holds scroll position and selection state. Tearing it down when entering `crop` would lose all of that on `goBack`. The `accessibilityHidden` modifier keeps VoiceOver coherent without unmounting the view tree.

---

## 7. Haptic feedback — `.sensoryFeedback` only

Always use `.sensoryFeedback(_:trigger:)`. Never use `UIImpactFeedbackGenerator` directly.

### Reasons

- `.sensoryFeedback` lets SwiftUI manage Core Haptics prepare/fire lifecycle. `UIImpactFeedbackGenerator` requires a manual `prepare()` ~400-1000ms before the haptic to avoid first-tap stalls; SwiftUI does this for you.
- It's declarative: you describe the trigger value, not the imperative fire.
- It composes with `.disabled` and the rest of SwiftUI's modifier system.

### Trigger patterns

**Tap-counter trigger** (haptic fires on every tap):
```swift
@State private var tapTrigger = 0

Button { tapTrigger += 1; ... } label: { ... }
    .sensoryFeedback(.impact(weight: .light), trigger: tapTrigger)
```

**State-change trigger** (haptic fires only when state actually changes):
```swift
.sensoryFeedback(.selection, trigger: viewModel.selectedAssets)
```

The second form uses Apple's `Equatable` diff — taps that don't change the selection (e.g., a tap blocked by selection-limit) don't fire. This is the right form for grid selection.

**Error/rejection trigger** (haptic fires on rejection):
```swift
@State private var rejectionCount: Int = 0
// In VM: rejectionCount += 1 when user attempts an invalid action

.sensoryFeedback(.error, trigger: viewModel.rejectionCount)
```

### Don't sprinkle `.sensoryFeedback` on every Button

Reserve haptics for moments where the user genuinely benefits from physical confirmation: selection changes, mode switches, capture, rejection. Putting haptics on every tap is iOS-novice noise.

---

## 8. Eager value-passing for singletons

For an always-visible singleton view (the gallery-shortcut thumbnail in the shutter bar, a status icon in a nav bar), **the VM eagerly loads the value into observable state** and leaf views just read it:

```swift
// In the parent VM:
public var galleryThumbImage: UIImage?

public func loadGalleryThumbIfNeeded() async {
    guard let asset = recentAssets.first else { galleryThumbImage = nil; return }
    if let cached = photoKit.cachedThumbnail(for: asset) {
        galleryThumbImage = cached; return
    }
    galleryThumbImage = await ... // async fetch
}
```

```swift
// In the leaf view:
GalleryShortcutButton(thumbnail: vm.galleryThumbImage)
```

This is different from cells/previewers (which use `initialImage` + `loadAsync` because there are *N of them* and the parent can't pre-resolve all). For a single always-visible image, eager loading into VM state keeps the leaf view pure (just takes `UIImage?`) and avoids closure-threading through the parent chain.

**Rule of thumb:** N instances → closure-based lazy pattern. Single instance → eager value-passing.

---

## 9. Process-wide caches

For values that benefit from cross-screen reuse (image thumbnails, parsed JSON, decoded media), use a process-wide cache exposed as a type-level singleton:

```swift
public enum ThumbnailCache {
    public static let shared: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 500
        return c
    }()

    public static func key(for asset: PHAsset) -> NSString {
        let mod = asset.modificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(asset.localIdentifier)|\(mod)" as NSString
    }
}
```

### Notes

- **`NSCache`, not `Dictionary`.** `NSCache` evicts under memory pressure automatically; a `Dictionary` will OOM you.
- **Include `modificationDate` in the cache key.** Otherwise an in-place edit in Photos.app (same identifier, new pixels) serves stale data.
- **Single source of truth for keys.** Expose a `key(for:)` static function and call it from every read AND every write. If reads and writes drift, the cache silently misses.
- **Largest-wins policy for images.** Cache one entry per logical asset at the largest size ever fetched; downscale visually via `.scaledToFill()`. Keying by size too means a small late-arriving thumbnail overwrites a large early one and the previewer goes blurry.

---

## 10. Prewarming Apple framework caches

When a framework offers a prefetcher (PhotoKit's `PHCachingImageManager`, Combine's `prefetch`, etc.), use it AND reuse the request shape between warm and read so the warm pool actually hits:

```swift
// Single source of truth for the request options
@ObservationIgnored private let thumbnailRequestOptions: PHImageRequestOptions = {
    let opts = PHImageRequestOptions()
    opts.isSynchronous = false
    opts.deliveryMode = .highQualityFormat
    return opts
}()

// Warm
cachingManager.startCachingImages(
    for: assets, targetSize: size, contentMode: .aspectFill, options: thumbnailRequestOptions
)

// Read (must match warm shape exactly)
cachingManager.requestImage(
    for: asset, targetSize: size, contentMode: .aspectFill, options: thumbnailRequestOptions
) { ... }
```

If the warm and the read use different `options`, different `contentMode`, or different `targetSize`, PhotoKit treats them as different requests and the warm pool is wasted. Single source of truth prevents drift.

---

## 11. Comment style

### Default to writing no comments

Well-named identifiers already say what the code does. Add a comment only when the **why is non-obvious**: a hidden constraint, an Apple-API quirk, a subtle invariant, a workaround for a specific bug.

### When to comment

- **Why a non-obvious choice was made.** "Using `.onAppear` not `.task` here because the camera warm-up needs the 16-32ms head-start."
- **A specific bug being worked around.** "Defensive: PhotoKit's Limited Access set is briefly empty during popup dismiss — don't clobber a populated list."
- **An Apple-API subtlety.** "`UIImage.size` is in points; multiply by `scale` for true pixels."
- **An exception to a documented rule.** The "Infrastructure Exception" header in `MediaPickerModifier.swift` and `CameraPreviewView.swift`.

### When NOT to comment

- ❌ Describing what the code does. `// Increment counter` next to `counter += 1`.
- ❌ Referencing the current task, ticket, or PR. ("Added for #1234." This belongs in the commit message.)
- ❌ Listing callers. ("Used by FooView and BarView." These drift.)
- ❌ Restating type signatures in prose.

### File-header comments

Reserve for files that introduce a non-obvious pattern. A typical file needs no header. The header on `PickerViewModel.swift` is justified because it documents the selection-mirror pattern; the header on `ShutterButton.swift` would not be.

### MARK organization

Use `// MARK: - Section` for any file with multiple logical sections (init, public API, intent handlers, private helpers). Helps Xcode's symbol jump-bar.

---

## 12. Quick-reference: when adding a new X

| Adding a… | Ask | Default answer |
|---|---|---|
| View leaf (button, cell, icon) | Does it need framework types to do its job? | No → take primitives. Yes → wrap the framework call in a VM method. |
| View model | What services does it need? | Constructor-inject all with `.shared` defaults. `@MainActor @Observable final class`. |
| Service | Does it do mixed I/O + UI work? | Yes → nonisolated class with selective `@MainActor` on writers. UIKit-only → `@MainActor` on the shared accessor. |
| Public type | Where does it live? | `Models/`, one type per file. |
| Internal helper struct | Where does it live? | Same file as the view/VM that uses it. |
| Flow stage (multi-step UX) | Sheet, NavigationStack, or single-ZStack? | Single ZStack with flow-state enum. |
| Haptic | Tap-counter or state-change? | State-change if you have an `Equatable` value that gates it; tap-counter for fire-on-tap. |
| Cache | Cross-screen reuse? | `NSCache`-backed `enum` namespace with `key(for:)`. Include modification timestamps in the key. |
| New folder | Plural or singular? | Plural if "bag of N peers." Singular if "the X." |

---

## 13. Anti-patterns to refuse

- ❌ `Service.shared.method()` inside a view body.
- ❌ `Service.shared.method()` inside a VM body when the service is in a stored property.
- ❌ `@MainActor` on a whole class that does heavy CPU work.
- ❌ `UIImpactFeedbackGenerator` directly (use `.sensoryFeedback`).
- ❌ Nested SwiftUI sheets for multi-stage flows.
- ❌ View props typed as framework types when primitives would do.
- ❌ Cache keys that omit modification timestamps for editable resources.
- ❌ Plural folder names for features (`Pickers/`, `Onboardings/`).
- ❌ Multi-type files for public types (`Models.swift`, `Components.swift` grab-bags).
- ❌ `// Added for ticket #X` or `// Used by Y` comments.
- ❌ Doc comments that restate the type signature.

---

## How to use this in a new project

1. Drop this file at the project root.
2. Drop your `FeatureModule/` next to it with the `API/Core/Services/Models/Examples/` shape.
3. Tell your AI assistant: "Follow `CODING_GUIDELINES.md`."
4. When a new pattern emerges that's worth keeping, add a section here with the *why*. Don't let one-off conventions proliferate without documentation.

The goal is a codebase where any contributor (human or AI) can predict where a file lives, what shape its types take, and where its concurrency boundaries are — without reading every existing file first.

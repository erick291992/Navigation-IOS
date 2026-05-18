# Data Flow Patterns — Universal Media Picker

This document captures the parent ↔ child data-flow patterns we considered, which the picker module **actually uses today**, where they appear in the code, and the recommendation for new work.

## The four candidate patterns

These came out of a design discussion on 2026-05-17. Each is a legitimate SwiftUI pattern for crossing a view boundary.

### Pattern 1 — `let` down + callback up

Parent owns the value; child can read it; child fires events upward. Parent decides what to do.

```swift
struct Parent: View {
    @State private var color: Color = .red

    var body: some View {
        Child(
            color: color,                         // ↓ value snapshot
            onColorChange: { color = $0 }         // ↑ event closure
        )
    }
}

struct Child: View {
    let color: Color
    let onColorChange: (Color) -> Void
}
```

### Pattern 2 — `@Binding` (two-way sync)

Parent and child share a single writable reference. Either side can write; both observe the same memory. Apple's primitives (`TextField`, `Toggle`, `Picker`, `PhotosPicker`) require this.

```swift
struct Parent: View {
    @State private var color: Color = .red

    var body: some View {
        Child(color: $color)
            .onChange(of: color) { _, new in /* parent reacts */ }
    }
}

struct Child: View {
    @Binding var color: Color
}
```

### Pattern 3 — `@Bindable` (entire `@Observable` passed down)

Parent owns an `@Observable` model; child receives it as `@Bindable` and can read/write any of its properties as bindings.

```swift
@Observable
class SharedModel { var color: Color = .red }

struct Parent: View {
    @State private var model = SharedModel()
    var body: some View { Child(model: model) }
}

struct Child: View {
    @Bindable var model: SharedModel
    var body: some View {
        ColorPicker("Pick", selection: $model.color)
    }
}
```

### Pattern H (hybrid) — `@Binding` down + internal VM mirror + sync

Child receives a binding but ALSO owns its own `@Observable` VM that mirrors the value. Constructor seeds initial value; two `.onChange` blocks keep parent ↔ VM in sync. Button actions stay pure (`vm.brighten()`) while the VM stays SwiftUI-free.

```swift
struct Child: View {
    @Binding var color: Color
    @State private var vm: ChildVM

    init(color: Binding<Color>) {
        self._color = color
        self._vm = State(initialValue: ChildVM(initialColor: color.wrappedValue))
    }

    var body: some View {
        Button("Brighten") { vm.brighten() }        // pure intent
            .onChange(of: color)    { _, n in vm.setBase(n) }   // sync DOWN
            .onChange(of: vm.color) { _, n in color = n }       // sync UP
    }
}
```

## What this codebase uses today

| Pattern | Used? | Where |
|---|---|---|
| **Pattern 1** (let + callback) | **Primary — most of the codebase** | `onAssetTap`, `onSelectionChange`, `onShutter`, `onFlipCamera`, `onSelectMode`, `onGalleryShortcut`, `onLimitedTap`, `onAuthorizedEmptyStateFallback`, `onCompletion`, `onCancel`, every leaf-view event |
| **Pattern 2** (`@Binding`) | **Used narrowly** | Only where Apple's API requires it or where a value is truly bidirectional:<br>• `currentAlbum: Binding<PhotoLibraryService.AlbumInfo?>` — `AssetGridView`/`AlbumDropdownMenu` share with `PickerViewModel`<br>• `pickerSelection: Binding<[PhotosPickerItem]>` — required by `PhotosPicker` in `GalleryShortcutButton` and `LibraryViewfinderView` |
| **Pattern 3** (`@Bindable`) | **Not used** | No view receives another view's VM as a parameter. Every container view owns its own VM via `@State`. |
| **Pattern H** (hybrid) | **Not used** | No view in the codebase keeps a `@State` VM that mirrors a `@Binding` via two `.onChange` syncs. |

## How the code is structured

Five layers, each with a fixed responsibility:

### 1. Leaf views — pure presentation

Take primitive inputs (UIImage?, String?, enum), optional callbacks. Zero service / cache references. May have local `@State` for view-private UI state (loaded image, animation state).

Examples: `AssetThumbnailCell`, `GalleryShortcutButton`, `LibraryPreviewer`, `EmptyStateView`, `ExitButton`, `ShutterButton`, `ZoomDialView`.

### 2. Mid views — compose leaves, pass props through

Receive parent's data + closures, forward them to leaves. May add UI-state conditionals (auth-state branching, mode switching).

Examples: `ShutterAndModeBarView`, `ViewfinderArea`.

### 3. Container views — own a VM, expose events

Instantiate their own VM via `@State`. Expose events to parent via callbacks. Wire VM intents to leaf-view actions.

Examples: `AssetGridView` (owns `AssetGridViewModel`), `PickerView` (owns `PickerViewModel`), `LibraryViewfinderView` (owns `LibraryViewfinderViewModel`), `CameraViewfinderView` (owns `CameraViewfinderViewModel`).

### 4. ViewModels — state + intent methods

`@MainActor @Observable` classes. Hold observable state (read by view). Expose intent methods (called by view). Services injected via constructor with `= .shared` defaults. **No `Binding<T>` inside VMs.**

Standard shape:

```swift
@MainActor @Observable
public final class SomeViewModel {
    private let service: SomeService

    public init(service: SomeService = .shared) {
        self.service = service
    }

    public var someState: SomeType
    public func someIntent() { /* uses service, updates state */ }
}
```

Examples: `PickerViewModel`, `AssetGridViewModel`, `LibraryViewfinderViewModel`, `CameraViewfinderViewModel`, `EliteGeometricPickerViewModel`, `CropFlowViewModel`, `CustomPickerExampleViewModel`, `AdvancedPickerExampleViewModel`.

### 5. Services — singletons, system-resource brokers

`.shared` singletons with `private init()`. Hold cross-service references as stored properties. Called only by VMs (one documented exception: `MediaPickerModifier` for prewarm).

Examples: `PhotoKitService`, `CameraService`, `PhotoLibraryService`, `CameraDeviceService`, `MediaPickerManager`, `MediaPickerEngine` (slated for deletion), `MediaHistoryManager`.

## Cross-VM coordination

**No VM holds a reference to another VM.** Cross-cutting state flows through the View layer using SwiftUI's data flow primitives:

- Parent VM → child VM: via View's `@Binding` (parent VM's property → child VM's intent, triggered by `.onChange`)
- Child VM → parent VM: via View's callback (`.onChange(of: childVM.state)` → callback up)

Concrete: `AssetGridView` has `@Binding var currentAlbum` and `.onChange(of: currentAlbum)` that calls `viewModel.trigger(.selectAlbum(...))`. Selection changes bubble up via `onSelectionChange(viewModel.state.selectedAssets)` in the opposite `.onChange`.

## Decision rule for new code

When adding a value that crosses a view boundary:

1. **Discrete event** (tap, completion, error)? → **Pattern 1** (callback)
2. **SwiftUI API requirement** (`TextField`, `Toggle`, `Picker`, `PhotosPicker`)? → **Pattern 2** (`@Binding`)
3. **Source of truth lives in child's VM**, parent only observes? → **Pattern 1** (bubble up via `.onChange(of: childVM.X)`)
4. **Source of truth in parent VM** + multiple downstream views read+write? → **Pattern 2** (`@Binding`)
5. **Source of truth in parent VM** + downstream is read-only? → **let snapshot down**
6. **Parent and child genuinely share one model**? → **Pattern 3** (`@Bindable`) — currently no examples, use sparingly
7. **Need testable child VM + Apple API requires Binding on the parent**? → **Pattern H** (hybrid) — currently no examples, last resort

## Recommendations going forward

### Are we mixing patterns constantly?

**No — and that perception is the point of this doc.** The picker mixes patterns *by purpose*, not randomly:

- 90%+ of parent ↔ child relationships use **Pattern 1** (callbacks)
- ~5% use **Pattern 2** (`@Binding`) and only when Apple's API requires it or when a value is genuinely shared (`currentAlbum`)
- The other two patterns are absent

That's principled, not chaotic. The mix only looks chaotic until you know the decision rule above.

### What to do going forward

1. **Default to Pattern 1.** Most new view boundaries should be `let` down + callback up. It scales, it's explicit, it doesn't blur ownership.

2. **Use Pattern 2 only when:**
   - Apple's API demands it (`PhotosPicker(selection:)`, `Picker(selection:)`, `TextField(text:)`), OR
   - A value is genuinely two-way and multiple views legitimately read+write it (e.g., `currentAlbum`)

3. **Avoid Pattern 3 unless a real need appears.** Passing a VM down via `@Bindable` couples the child to the parent's model. The "self-contained subview owns its own VM" pattern this codebase uses is harder to break later.

4. **Avoid Pattern H (hybrid) unless both conditions are true:**
   - You need a child VM for testability/isolation reasons, AND
   - The parent has a structural reason to expose a Binding (Apple API requirement)

   In practice, callbacks (Pattern 1) cover the same ground with less ceremony for most cases.

5. **Keep VMs SwiftUI-free in their bodies.** They can `import SwiftUI` if a parameter type requires it (like `PhotosPickerItem` needing the cross-import overlay), but no `View`, `Binding<T>`, `EnvironmentValues`, or `ViewModifier` should appear inside VM code. Intent methods take and return primitives.

6. **Keep `@State VM` per container view.** Don't introduce shared VMs between parent and child — it tempts violations of the "no VM holds a reference to another VM" rule.

7. **Document any new pattern adoption.** If a future feature needs Pattern 3 or H, add a section to this doc with the file + the reason. Don't let one-off patterns proliferate without documentation.

8. **No async orchestration in view bodies.** A view's `.task` / `.onAppear` body must be a single VM method call. Decisions about *how* the work runs (sequential, parallel via `async let`, with retries, with backoff) belong in the VM. If you find yourself reaching for `async let` or two sequential `await`s inside a view, add a `bootstrap()`-style method on the VM and put the orchestration there. See [CODING_GUIDELINES.md](CODING_GUIDELINES.md) §2 "View body discipline" for the rationale and `.task` vs `.onAppear` decision matrix.

### Known inconsistencies to clean up

_All previously-tracked inconsistencies in this section have been resolved as of 2026-05-17 (`EmptyStateView` refactored to `@ViewBuilder`, `MediaPickerEngine` deleted, `AdvancedPickerExampleView` migrated to its VM). Add new items here as they arise._

### Bottom line

The current codebase IS following a real architectural rule. It's just not written down anywhere before this doc. Future contributors should read this file before adding a new view boundary. PR reviews should check that new code matches the decision rule above.

Don't refactor the existing code to "one pattern" — that's a unification trap. The mix is correct.

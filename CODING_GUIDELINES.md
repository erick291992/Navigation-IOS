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

### Identifier naming — be descriptive at the call site

**Avoid generic names** like `state`, `data`, `info`, `manager`, `helper`, `model`, `service` (when not the full type name), or single-word abbreviations of multi-word types. Generic names read fine *inside* the type that owns them but become ambiguous at call sites elsewhere.

**Rule of thumb:** the name should be self-describing when read at any call site, without needing to look up the type.

❌ **Bad** — generic, ambiguous at call site:
```swift
// Inside AssetGridViewModel:
public var state = AssetGridState()       // ← "state" of what?

// At call site (in AssetGridView.swift):
viewModel.state.assets          // ambiguous — could be view's @State, SwiftUI state, …
viewModel.state.selectedAssets
viewModel.state.isLoading
```

```swift
// Inside PickerViewModel:
private let photoKit: PhotoKitService    // ← reads like Apple's framework

// At call site:
photoKit.loadAlbumsIfNeeded()    // is this Apple's PhotoKit or our service?
```

✅ **Good** — descriptive, self-explaining everywhere:
```swift
// Inside AssetGridViewModel:
public var assetGridState = AssetGridState()    // ← name matches the type

// At call site:
viewModel.assetGridState.assets         // obviously the grid's own state struct
viewModel.assetGridState.selectedAssets
viewModel.assetGridState.isLoading
```

```swift
// Inside PickerViewModel:
private let photoKitService: PhotoKitService    // ← matches the type name

// At call site:
photoKitService.loadAlbumsIfNeeded()    // clearly our facade, not Apple's framework
```

**Common offenders to watch for:**

| Generic | Better |
|---|---|
| `state` (when it's a struct of state) | `assetGridState`, `pickerState`, `flowState` |
| `data` | `userData`, `responseData`, `mediaItemData` |
| `info` | `albumInfo`, `errorInfo`, `deviceInfo` |
| `manager` (when it's a Service) | The full type name — `mediaPickerManager` or `historyManager` |
| `service` (when calling site needs disambiguation) | Domain-prefixed — `photoKitService`, `cameraService` |
| `photoKit`, `mediaPicker`, `camera` (when the actual type is named `…Service` or `…Manager`) | Match the type — `photoKitService`, `mediaPickerManager`, `cameraService` |
| Single-letter or abbreviated VMs (`vm`, `gm`) at call sites | Full name — `viewModel`, `gridModel` |

**Why this matters more than it seems:** code is read at the call site, not at the declaration. A property named `state` reads fine on the line where it's declared (you can see the type next to it). On line 200 of another file, `viewModel.state.assets` is a small puzzle every time someone reads it. Descriptive names eliminate the puzzle without costing anything.

**Exception — local variables in tight scope:** inside a 5-line function, `let state = ...` is fine because the type is visible right above. The rule is about properties/parameters that get accessed from elsewhere.

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

### View body discipline — no orchestration in views

A view's `.task` / `.onAppear` body must be **a single call to a VM method**. The view's job is "tell the VM to do its thing." Any decision about *how* the work runs — sequential vs parallel, with retries, with timeouts, with backoff — belongs in the VM.

❌ **Wrong** (orchestration in the view):
```swift
.task {
    async let albumBootstrap: Void = viewModel.loadAlbums()
    async let galleryThumb: Void = viewModel.loadGalleryThumb()
    _ = await (albumBootstrap, galleryThumb)
}
```

✅ **Right** (VM owns the orchestration):
```swift
// View
.task { await viewModel.bootstrap() }

// VM
public func bootstrap() async {
    async let albumBootstrap: Void = loadAlbums()
    async let galleryThumb: Void = loadGalleryThumb()
    _ = await (albumBootstrap, galleryThumb)
}
```

The wrong version locks the parallelization shape into the view. If you later want to add a third step, add retry, or serialize one of them under some condition, you have to edit the view — which means the view now contains orchestration logic. Move it to the VM up front.

**The rule extends to `.onAppear { Task { … } }` blocks too.** The body of that inner `Task` closure should also be a single VM method call, not a sequence of orchestrated awaits.

This is a specific application of the broader View → ViewModel → Service rule, but worth stating separately because `async let` is seductive and easy to inline at the call site when you first reach for parallelization.

### `.task` vs `.onAppear` — which lifecycle hook

Both fire when the view appears, with deliberate differences. Choose based on what you need:

| | `.onAppear { … }` | `.task { await … }` |
|---|---|---|
| Closure type | Sync | Async |
| Timing | Immediately on appearance | ~16-32ms later (scheduling overhead) |
| Auto-cancellation on disappear | ❌ | ✅ (task implicitly cancelled) |
| Async work | Must wrap in `Task { … }` manually; that Task is NOT auto-cancelled | Native; auto-cancels |
| Re-runs on reappear | ✅ | ✅ (cancels previous if still running) |

**Default to `.task`.** It's the modern path: async-native, cancels cleanly, ties to the view's lifecycle.

**Use `.onAppear` when:**
- The kickoff is latency-critical and you need the ~16-32ms head start (e.g., camera cold-start).
- The work should keep running even if the view briefly disappears (e.g., warming a long-lived shared service).
- You're doing pure sync setup (no `await` involved at all).

**Concrete example** — `MediaPickerModifier.swift` uses both deliberately:

```swift
.onAppear {
    Task { await CameraService.shared.startWarming() }   // every ms matters
}
.task {
    await PhotoKitService.shared.prewarm()                // cancellable if user navigates away
}
```

Both choices are documented in that file's header comment.

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

### What `@MainActor` does NOT mean

A common misread: "`@MainActor` makes this function slow because it runs on the main thread."

That's not what `@MainActor` does. The annotation says **"only one thread can execute this at a time, and that thread is main."** Whether it's slow depends on **what's inside** the function, not the annotation. A `@MainActor` function that just dispatches to async APIs (PhotoKit, AVFoundation, URLSession, etc.) is essentially free — those APIs don't block; they queue work and return immediately. A `@MainActor` function that JPEG-encodes a 4K image **is** slow because it does heavy CPU on main.

**Two things to check when you see `@MainActor`:**
1. *What does the function actually do?* Dispatching to async work = cheap. Crunching CPU = expensive.
2. *Is the caller already on `@MainActor`?* If yes (e.g., a VM calling a service method), there's no thread hop — calling it costs nothing. If no, there's one hop, which is also cheap (~microseconds) unless you're calling it in a tight loop.

The "sole-writer" pattern uses `@MainActor` on the writer method (not the whole class) as the cheapest way to prevent data races on a shared mutable variable. Alternatives — actors, locks, serial queues — all have higher overhead. `@MainActor` on a fast writer beats them.

### Async ≠ off-main — actor inheritance rules

A common confusion: "`async` function" does NOT mean "runs off main." Where the body actually runs is determined by **actor inheritance**, not by the `async` keyword. These five rules govern everything:

1. **A `@MainActor async` function's body runs on main.** Awaiting it from main suspends, runs the body on main, returns. The `async` just means "may suspend."

2. **A nonisolated `async` function's body runs on the cooperative pool.** When awaited from any actor context (including `@MainActor`), Swift hops off main, runs the body on the pool, and resumes on the caller's actor. **This is SE-0338 — it's automatic.** Most off-main work in this codebase happens through this rule, not through `Task.detached`.

3. **`Task { … }` inherits the actor of the enclosing context.** Inside a `@MainActor` method, `Task { … }` is `@MainActor`. Its body runs on main.

4. **`Task.detached { … }` does NOT inherit.** It always starts on the cooperative pool. Use it to escape a `@MainActor` enclosing context when you genuinely need off-main work AND can't go through a nonisolated async function.

5. **`async let` child tasks inherit the parent's actor.** Inside a `@MainActor` method, `async let a = methodA()` creates a child task that is `@MainActor` (if `methodA` is also `@MainActor`). Both children run on main, interleaving at await points. **This is not true thread-level parallelism** — see the parallelism decision framework below.

**Concrete examples in this codebase:**

```swift
// PhotoKitService is NOT @MainActor at the class level.
// loadAlbumsIfNeeded is nonisolated async.
public func loadAlbumsIfNeeded() async { … }

// In a @MainActor VM, this is automatically off-main per rule 2:
await photoKitService.loadAlbumsIfNeeded()

// In a @MainActor VM, this Task runs on MAIN (rule 3):
Task { await someAsyncWork() }

// In a @MainActor VM, this Task runs on the COOPERATIVE POOL (rule 4):
Task.detached { await someAsyncWork() }

// In a @MainActor bootstrap, both children inherit @MainActor (rule 5):
async let a: Void = loadInitialAlbumIfNeeded()   // @MainActor
async let b: Void = loadGalleryThumbIfNeeded()   // @MainActor
_ = await (a, b)                                  // both interleave on main
```

**Practical implication:** you almost never need `Task.detached` in this codebase, because services are already nonisolated and their async methods auto-hop off main via SE-0338. Reach for `Task.detached` only for **CPU-bound work inside a `@MainActor` VM** (encoding, parsing) — that's why `CropFlowViewModel.finalize` uses it.

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

### The fire-and-forget Task pattern (sync method, async work inside)

For action methods called from sync call sites (button taps, gesture handlers, `.onChange` blocks), use this pattern instead of making the method `async`:

```swift
@MainActor
@Observable
final class SomeViewModel {
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    deinit {
        tasks.forEach { $0.cancel() }   // cancel in-flight work on dismiss
    }

    func handleSomeAction() {                          // sync signature
        let task = Task { [weak self] in               // inherits @MainActor
            guard let self else { return }
            do {
                try await self.repository.doWork()     // hops off-main per SE-0338
            } catch {
                logger.error("Failed: \(error.localizedDescription)")
            }
        }
        tasks.append(task)
    }
}
```

**Why this shape:**

- **Sync signature.** Caller writes `vm.handleSomeAction()` — no `await`, no `Task` wrapping. Button code stays clean: `Button("Action") { vm.handleSomeAction() }`.
- **Internal `Task { }`.** Spawns the async work. Inherits `@MainActor` (rule 3 above), but the await on a nonisolated repository method hops off-main automatically.
- **`tasks` array + deinit cancellation.** If the view dismisses while work is in flight, the task gets cancelled. Prevents zombie work and `self`-retention leaks.
- **Error handled inline.** Fire-and-forget means no caller to surface errors to. Log + recover.

**When to use:**
- User actions: tap, swipe, drag-release.
- `.onChange` reactions where the caller is sync.
- Background work the view doesn't need to wait for.

**When NOT to use:**
- Bootstrap / mount work where the view's `.task` needs to await completion → use `async func bootstrap()` instead; the view's `.task { await viewModel.bootstrap() }` provides the lifecycle binding naturally.
- Coordinated multi-step flows where you need ordering or completion signals → use sequential `async` methods.

**Reference implementations:**
- `HomeFeedViewModel.givePostEnergy` (meetsta-ios) — canonical with task-array + deinit cancellation.
- `CameraService.flipCamera` — minimal version (single Task, no array, because the operation is short-lived and the service lives for the app's lifetime).

### When parallelism helps — and when it doesn't (the decision framework)

Before reaching for `async let`, `Task.detached`, or `withTaskGroup`, run through this checklist. Parallelism is not free just because the syntax is clean.

**Step 1 — Identify the work type.**

| Work type | Parallelism payoff |
|---|---|
| **CPU-bound** (encoding, parsing, image transform) | High. Cores actually run in parallel. Use `Task.detached`. |
| **I/O through a shared framework** (PhotoKit, AVFoundation, URLSession) | Low to zero. The framework serializes through its own internal queues; Swift parallelism just queues things faster on its end. |
| **I/O across different frameworks / endpoints** (one network call + one disk read) | High. The systems run independently. |

**Step 2 — Identify the downstream serialization.**

PhotoKit serves image requests through `PHCachingImageManager`'s internal queue. URLSession serializes per-host. AVFoundation has its capture-session queue. **You don't get parallelism your downstream doesn't support.** Even if you fire 10 parallel Swift tasks, the framework underneath may process them sequentially.

How to check: skim the Apple docs for the methods you're calling. Phrases like "serial queue," "background queue," or *no* threading mention at all (which usually means "we handle it") all imply serialization.

**Step 3 — Identify the main-thread side-effect cost.**

Every parallel task that writes `@Observable` state will fire its writes near-simultaneously. Each write triggers SwiftUI to re-evaluate every view that reads the property. Two parallel tasks bunching their writes = two cascade bursts back-to-back, all on main.

If this happens during a sensitive window (sheet animation, initial layout), SwiftUI's scheduler defers other main-thread work — and other things (sibling view tasks, layout, animation frames) appear slow.

Sequential execution spreads the writes out in time, giving SwiftUI gaps between cascades. Total work is identical; distribution is better.

**Step 4 — Compute net benefit.**

```
net = (sequential_wall_time − parallel_wall_time)        // the win
    − (cascade_pileup_cost + scheduling_pressure_cost)    // the side effects
```

- If downstream is serial and the work is small → win is near zero, cost is real → **sequential is better.**
- If downstream is parallel and the work is large → win exceeds the side-effect cost → **parallel is better.**

**Worked examples from this codebase:**

| Site | Decision | Why |
|---|---|---|
| `CropFlowViewModel.finalize` (N JPEG encodes) | **`Task.detached`** | CPU-bound, cores parallelize, no downstream serialization. |
| `MediaPickerManager.process(items:)` (N items) | **Sequential `for` loop** with nonisolated async | Each item processes off-main; PhotoKit serializes anyway; loop is simple and main-thread-friendly. |
| `PickerViewModel.bootstrap()` (album bootstrap + gallery thumb) | **Sequential `await`s** | PhotoKit serializes both requests internally; parallel cascade pile-up during sheet animation made the visible content (grid, previewer) appear ~250ms slower than sequential. Measured. See `project_picker_perf_state.md` in memory. |
| `CameraService.flipCamera` | **Fire-and-forget `Task`** | Single button-triggered action, no coordination, caller is sync. |

**The quick gut-check question:**

> "If I weren't using `async let` here, what's the bottleneck?"

If the answer is "the downstream framework's queue," parallelism won't help — use sequential. If the answer is "CPU on main," use `Task.detached`. If the answer is "two independent slow things," `async let` is the right tool.

### Don't fire orphan Tasks

A `Task { … }` block with no stored handle is "fire-and-forget" in the worst sense — it survives the view dismissing, retains `self` until completion, and leaks if the work is slow. If you need fire-and-forget on a `@MainActor` VM, use the task-array pattern above. The only exception is short-lived Tasks on long-lived singletons (e.g., `CameraService.flipCamera`) where leak risk is bounded.

### Coalesce concurrent calls to the same service fetch

When a service method (`PhotoKitService.fetchRecentAssets`, a URL-session refresh, a database reload — any "go get / refresh state X") has **multiple distinct triggers** that can fire close in time, two callers can race and issue the same work twice. Symptoms: redundant network requests, redundant disk/decode work, redundant pressure on a shared queue-backed framework (PhotoKit, AVFoundation, etc.).

The fix is **in-flight Task coalescing**: store a handle to the running Task; the second-and-later caller awaits the existing Task instead of starting a new one.

**Canonical example in this codebase: `PhotoKitService.fetchRecentAssets`.** Called from six distinct triggers (modifier prewarm, scenePhase active, onboarding GET STARTED, Limited-picker dismiss, PhotoKit change observer, library viewfinder mount). Two pairs of triggers can fire near-simultaneously (Limited-picker dismiss + change observer; foreground + change observer). The coalescer makes the second caller a no-op duplicate.

```swift
@ObservationIgnored private var inFlightRecentsFetch: Task<Void, Never>?

public func fetchRecentAssets(limit: Int = 30) async {
    // Check + create atomically on MainActor so two nonisolated callers
    // racing on the cooperative pool don't both pass the nil check.
    let task: Task<Void, Never> = await MainActor.run {
        if let existing = inFlightRecentsFetch {
            return existing
        }
        let newTask = Task { [weak self] in
            guard let self else { return }
            await self.performRecentAssetsFetch(limit: limit)
            // Spawned Task clears its own handle on completion.
            await MainActor.run { self.inFlightRecentsFetch = nil }
        }
        inFlightRecentsFetch = newTask
        return newTask
    }
    await task.value
}

private func performRecentAssetsFetch(limit: Int) async { /* the actual work */ }
```

**Why it's structured this way:**

1. **`MainActor.run` for the check-or-create.** The service is nonisolated, so two callers can enter on different threads. Wrapping the read + write in a single `MainActor.run` block makes them atomic — only one Task ever gets created.
2. **The spawned Task clears its own handle.** Cleaner than having every caller participate in cleanup. After the handle is nil, a subsequent legitimately-new call gets a fresh Task.
3. **Both callers `await task.value`.** Same result for both. The duplicate caller pays zero PhotoKit cost — just an extra `await` resume.

**When this pattern applies:**
- Service methods invoked from multiple reactive triggers (scenePhase, system observers, user actions).
- Especially when the underlying work hits a shared serial queue (PhotoKit, AVFoundation, URLSession) where duplicates compete with visible-content requests for queue time.
- Less critical for pure in-memory work (the equality guard on the writer already suppresses cascades there).

**Trade-off — first caller's parameters win.** If callers pass different arguments (`limit: 30` vs `limit: 5`), the second caller gets whatever the in-flight Task was configured with. Usually fine because most call sites use defaults; if not, the in-flight handle should be keyed by argument.

**Don't conflate with the equality guard.** The guard in `updateAssets` prevents the duplicate `@Observable` cascade (UI re-eval). The coalescer prevents the duplicate WORK (PhotoKit fetch). Both are needed: the guard for the case where two legitimate fetches return the same data; the coalescer for the case where two near-simultaneous triggers fire the same fetch.

### Bounded fast-path + background unbounded (the "hybrid fetch" pattern)

When you have an operation that has both a **fast bounded variant** and a **slow unbounded variant** of the same work — and the caller wants the bounded result on the critical path but eventually needs the unbounded result for downstream operations — split into two phases:

1. **PHASE 1 (critical path):** await the bounded variant. User waits for this.
2. **PHASE 2 (background):** spawn a fire-and-forget `Task` that does the unbounded variant. Store the result in observable state for downstream use. User does NOT wait.

If downstream operations need the full result and might run before PHASE 2 completes, **`await` the stored Task** in those operations — not `nil`-check the result and no-op.

**The canonical example in this codebase: `AssetGridViewModel.loadAssets`.**

```swift
private func loadAssets(for album) async {
    // PHASE 1 — bounded fetch, fast (top-K path), on critical path
    let firstPage = await photoKitService.fetchAssets(in: album, limit: 60)
    state.assets = firstPage.map { .phAsset($0) }
    state.isLoading = false                                  // ← user sees grid here

    // PHASE 2 — unbounded fetch, slow (full sort), off critical path
    let task = Task { [weak self] in
        guard let self else { return }
        let fullResult = await self.photoKitService.fetchAssetsResult(in: album)
        self.fetchResult = fullResult                        // ← used by pagination
    }
    self.pendingFullFetch = task
    tasks.append(task)
}

// Downstream operation that needs PHASE 2's result:
private func loadNextPageCore() async {
    // If the user scrolled past page 1 before PHASE 2 finished, await it.
    if fetchResult == nil, let pending = pendingFullFetch {
        await pending.value
    }
    guard let result = fetchResult else { return }
    // ... use result for pagination
}
```

**When this pattern applies:**

- PhotoKit / AVFoundation / URLSession calls where there's a `fetchLimit` (or equivalent) fast path AND an unbounded version
- Any API where "give me the first N" is implemented differently from "give me everything"
- Generally: any operation where the bounded variant is dramatically cheaper than the unbounded

**Why this matters:** PhotoKit's `PHAsset.fetchAssets(in:options:)` is a real-world example of this asymmetry. With `fetchLimit: 60`, PhotoKit uses a top-K algorithm — finds the 60 most-recent items without sorting the rest. Without `fetchLimit`, it does a full `creationDate`-descending sort over the entire library (which can be 50k+ entries). On a 33k-library, measured: bounded ≈ 150-400ms, unbounded ≈ 41-1126ms (and the unbounded variant *also* hogs PhotoKit's queue, delaying other PhotoKit requests like the library previewer image fetch).

**What this is NOT:** this is not the same as "just paginate." Pagination is *how you consume* the result; the hybrid is *how you fetch* it. You can have pagination without the hybrid (just do one unbounded fetch upfront) — but you'll pay the unbounded cost on the critical path.

**Anti-pattern to avoid:** doing the unbounded fetch on the critical path "because it's lazy." A `PHFetchResult` is lazy about *materializing* `PHAsset` objects, but it's NOT lazy about *the sort*. The sort happens upfront over the entire matching set. Treating "lazy result" as "lazy fetch" was the mistake the first pagination iteration made; see `project_picker_perf_state.md` for the measurement.

### Refinement: lazy PHASE 2 (defer-until-user-intent)

**PHASE 2 doesn't have to fire eagerly in the background.** When the same operation that drives PHASE 2 is on a **shared queue-backed framework** (PhotoKit, AVFoundation, URLSession), eager-firing PHASE 2 right after PHASE 1 can starve other visible content competing for that same queue — even though PHASE 2 is "in the background."

The refinement: **defer PHASE 2 until the user actually demonstrates intent for its results.** For the picker's pagination case, that's "user scrolls past cell 50" (the sentinel). The Task that does the unbounded fetch is spawned inside `loadNextPageCore` on first call, not at the end of `loadAssets`:

```swift
// loadAssets — PHASE 1 only, no PHASE 2 spawn
private func loadAssets(for album) async {
    let firstPage = await photoKitService.fetchAssets(in: album, limit: 60)
    state.assets = firstPage.map { .phAsset($0) }
    state.isLoading = false
    // No PHASE 2 here — deferred to first sentinel hit.
}

// loadNextPageCore — lazy spawn of PHASE 2
private func loadNextPageCore() async {
    if fetchResult == nil {
        if pendingFullFetch == nil {
            let task = Task { [weak self] in
                guard let self else { return }
                let fullResult = await self.photoKitService.fetchAssetsResult(in: album)
                self.fetchResult = fullResult
            }
            pendingFullFetch = task
            tasks.append(task)
        }
        if let pending = pendingFullFetch {
            await pending.value
        }
    }
    // ... materialize next page ...
}
```

**When to use eager PHASE 2 vs lazy PHASE 2:**

| | Eager PHASE 2 (fires in `loadAssets`) | Lazy PHASE 2 (fires in `loadNextPage`) |
|---|---|---|
| PHASE 2 work is on a CPU pool, no queue contention | ✅ Better — pre-warm pays off | Either works |
| PHASE 2 competes with visible content on a shared framework queue | ❌ Risk of starving visible content | ✅ Better — visible content gets the queue free |
| User likely to scroll past page 1 quickly | Either works | Either works |
| User often picks first-page result and dismisses | Eager wastes work | ✅ Better — never pays the cost |

For our picker (PhotoKit serial queue + library previewer + gallery thumb competing for it), **lazy was the right choice** — measured the eager version delaying the previewer by 100-300ms.

### Producer-consumer for warm state (prewarm + eager-init)

**Pattern: an `@Observable` service "produces" warm state during host-view appearance; downstream VMs "consume" that state synchronously at their own `init` time.** This is how the picker's `~250ms first paint` is achieved.

**Producer side** — service exposes prewarmed state as observable properties, populated by a prewarm method called early:

```swift
@Observable
public final class PhotoKitService: NSObject {
    public var recentAssets: [PHAsset] = []
    public var albums: [PhotoLibraryService.AlbumInfo] = []
    public var prewarmedFirstAlbumAssets: [PHAsset] = []   // ← cached for consumer

    public func prewarm() async {
        await fetchRecentAssets()      // fills recentAssets
        await loadAlbumsIfNeeded()      // fills albums
        await prewarmVisibleContent()   // fills prewarmedFirstAlbumAssets + ThumbnailCache
    }
}

// Called from the public modifier at the host-view appearance:
.task {
    await PhotoKitService.shared.prewarm()
}
```

**Consumer side** — VMs read those properties synchronously at `init` to set their own state. No async wait, no body-eval-then-onAppear cycle:

```swift
@MainActor @Observable
public final class PickerViewModel {
    public var previewAsset: PHAsset?
    public var galleryThumbImage: UIImage?
    public var currentAlbum: PhotoLibraryService.AlbumInfo?

    public init(..., photoKitService: PhotoKitService = .shared, ...) {
        // ... existing assignments ...
        // Eager-init from warm singleton state. Reads return nil if prewarm
        // hasn't completed (cold race) — async fallback path handles that case.
        if let firstRecent = photoKitService.recentAssets.first {
            self.previewAsset = firstRecent
            self.galleryThumbImage = photoKitService.cachedThumbnail(for: firstRecent)
        }
        if let firstAlbum = photoKitService.albums.first {
            self.currentAlbum = firstAlbum
        }
    }
}
```

**Why this beats `.onAppear`:**

If you set initial state in `.onAppear { vm.fillFromCache() }`, the view's FIRST body evaluation sees empty state → renders placeholder → onAppear fires → state updates → view re-evaluates → renders populated state. Two renders, visible flicker.

Init-based eager-fill: view's first evaluation sees populated state → renders correctly on the first frame. One render, no flicker.

**Watch out for internal-state invariants:**

If the normal data path also sets internal bookkeeping properties (e.g., `lastLoadedAlbum`, `lastFetchedAt`), the eager-init path must set them too. Otherwise async paths that depend on that bookkeeping break silently. In the picker, eager-init had to set `AssetGridViewModel.lastLoadedAlbum` because pagination's `loadNextPageCore` reads it — without that line, pagination silently broke for the initial album.

**The "cold race" fallback:**

When the user opens the picker before prewarm completes, the eager-init reads return nil/empty. The existing async path (bootstrap → loadAssets → etc.) still runs and fills the state normally. Eager-init is a **fast path for the warm case**, not a replacement for the async path.

**Anti-pattern to avoid:** having the VM async-fetch data that's already sitting on the injected service. If the service has it and the VM needs it, read it synchronously in init. Don't duplicate the async fetch.

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
    photoKitService: PhotoKitService = .shared,
    cameraService: CameraService = .shared,
    historyManager: MediaHistoryManager = .shared,
    onCompletion: @escaping ([MediaItem]) -> Void,
    onCancel: @escaping () -> Void
) { ... }
```

**Production callers** omit the service params — they get `.shared`. Zero call-site noise.

**Tests** pass mocks: `PickerViewModel(configuration: …, photoKitService: MockPhotoKitService(), …)`.

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
    if let cached = photoKitService.cachedThumbnail(for: asset) {
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

### Beware queue contention — don't starve the visible content

When prewarming or prefetching on a shared async resource (PhotoKit, AVFoundation, URLSession, any framework with internal queues), ask first: **who else queues into this resource, and would my prefetch delay them?**

Concrete failure mode (from a real attempt in this codebase): we tried priming `ThumbnailCache` for 16 grid cells during `setCachedAssets` to make first-paint synchronous. Code-analysis-wise it looked free — "dead time during SwiftUI layout, let's use it." But the 16 grid-thumb requests queued into PhotoKit **ahead of** the more visually prominent library previewer (1000×1000) and gallery shortcut (140×140) requests. Grid cells appeared instantly; the big visible images appeared later. Net perceived perf was worse because the user looks at the big images first.

**Rule:** before adding a "prewarm" or "predispatch" on a shared queue-backed framework, identify what else competes for that queue and whether the more visible/critical consumers can tolerate being delayed. If they can't:
- Issue the visible/critical requests FIRST, then the prefetch.
- Or skip the prefetch entirely.
- Or use a framework feature that lets you set request priority (e.g., `URLRequest`'s `networkServiceType`, `Task(priority:)`).

"Free work in dead time" is a real pattern, but only when no one else needs that dead time. On a shared queue, dead time isn't dead — it's just unused by you.

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
| `.task` body in a view | More than one line? More than one `await`? | Wrong — move to a VM method, view calls `await viewModel.someMethod()` once. |
| `.onAppear` vs `.task` | Need auto-cancellation on dismiss? | `.task`. Need the absolute earliest moment, work survives disappear? `.onAppear { Task { … } }`. |
| Action method called from a button / gesture | Caller is sync; no completion to await | Sync method + internal `Task { … }` + `tasks` array + deinit cancel. See §3 "Fire-and-forget Task pattern." |
| `async let` to parallelize two methods | Is the downstream framework serial? Does parallel cause Observable cascade bursts? | If yes to either → sequential `await`s. Parallel `@MainActor` `async let` is rarely net-positive. See §3 "When parallelism helps." |
| Heavy CPU work inside a VM | Will it block main if not detached? | Wrap in `Task.detached(priority: .userInitiated) { … }.value`. Never put `@MainActor` on a class whose methods do heavy CPU. |
| Fetch with a bounded-fast / unbounded-slow API split (PhotoKit, URLSession, etc.) | Does the caller need the bounded for first paint AND the unbounded for downstream? | Use the hybrid fast-path + background unbounded pattern. Critical-path consumer awaits bounded; downstream consumers await the stored background Task. |
| Bounded fast-path returns but PHASE 2 unbounded fetch competes with visible content | Does PHASE 2 hit a shared serial queue (PhotoKit, AVFoundation)? | Lazy PHASE 2 — defer the spawn to first user-intent trigger (sentinel, button) instead of eager-background after PHASE 1. |
| Initial VM state derivable from injected service properties | Is the data already on a singleton at VM construction time? | Eager-init in VM `init` — read the singleton synchronously and assign. Don't async-fetch what's already there. |
| Service method invoked from N reactive triggers | Can two triggers fire close in time? | Coalesce — store an in-flight `Task<Void, Never>?`; the second caller `await`s it. See §3 "Coalesce concurrent calls to the same service fetch." |
| Type whose `==` should mean "same content" but uses `id = UUID()` for `Identifiable` | Need content equality? | Implement `==` + `hash(into:)` explicitly over the content fields. `Identifiable.id` (instance identity) and `Equatable.==` (content identity) are allowed to diverge. |
| Public type | Where does it live? | `Models/`, one type per file. |
| Internal helper struct | Where does it live? | Same file as the view/VM that uses it. |
| Flow stage (multi-step UX) | Sheet, NavigationStack, or single-ZStack? | Single ZStack with flow-state enum. |
| Haptic | Tap-counter or state-change? | State-change if you have an `Equatable` value that gates it; tap-counter for fire-on-tap. |
| Cache | Cross-screen reuse? | `NSCache`-backed `enum` namespace with `key(for:)`. Include modification timestamps in the key. |
| Prewarm / prefetch | What else queues into the same framework? | If anything more visible competes, prioritize the visible one first or skip the prewarm. |
| New folder | Plural or singular? | Plural if "bag of N peers." Singular if "the X." |

---

## 13. Anti-patterns to refuse

- ❌ `Service.shared.method()` inside a view body.
- ❌ `Service.shared.method()` inside a VM body when the service is in a stored property.
- ❌ `@MainActor` on a whole class that does heavy CPU work.
- ❌ `async let` / multiple sequential `await`s inside a view's `.task` or `.onAppear { Task { … } }` body. Move the orchestration to a VM method.
- ❌ A `.task` body that does more than call a single VM method (with the exception of bracketing perf-log calls).
- ❌ `async let` on `@MainActor` methods without first checking the downstream framework's serialization. Parallel-by-default on a `@MainActor` class is rarely net-positive; see §3.
- ❌ Fire-and-forget `Task { … }` from a VM without storing the task in a `tasks` array. Leaks `self` and orphans work if the view dismisses mid-flight.
- ❌ Reaching for `Task.detached` when SE-0338 already covers the case (the called function is nonisolated async). Just `await` it.
- ❌ `UIImpactFeedbackGenerator` directly (use `.sensoryFeedback`).
- ❌ Nested SwiftUI sheets for multi-stage flows.
- ❌ View props typed as framework types when primitives would do.
- ❌ Cache keys that omit modification timestamps for editable resources.
- ❌ Naive prefetch on a shared queue-backed framework without first checking whether more-visible content competes for the same queue.
- ❌ Treating a "lazy" result type as a "lazy" fetch. `PHFetchResult` is lazy about materializing items but NOT about sorting them. Same trap exists for any API that says "lazy" in the name — read the docs for what's actually deferred.
- ❌ Doing an unbounded fetch on the critical path when a bounded fast-path exists. See §3 "Bounded fast-path + background unbounded."
- ❌ Async-fetching data inside a VM method when the same data is already sitting on the injected service. Read it synchronously in `init`. See §3 "Producer-consumer for warm state."
- ❌ Setting initial state in `.onAppear` instead of `init`. `.onAppear` runs AFTER the first render → flicker. `init` runs BEFORE the first render → no flicker.
- ❌ Generic property names like `state`, `data`, `info`, `manager` for properties that get read at remote call sites. Prefix with domain so `viewModel.state.assets` becomes `viewModel.assetGridState.assets`. See §1 "Identifier naming."
- ❌ Stored-property name that doesn't match the type when the type has a meaningful suffix. `let photoKit: PhotoKitService` reads like Apple's framework at call sites. Match the type — `let photoKitService: PhotoKitService`.
- ❌ Plural folder names for features (`Pickers/`, `Onboardings/`).
- ❌ Multi-type files for public types (`Models.swift`, `Components.swift` grab-bags).
- ❌ `// Added for ticket #X` or `// Used by Y` comments.
- ❌ Doc comments that restate the type signature.
- ❌ Leaving dead surface — unused enum cases, observable state fields with no producer, methods with no callers, parameters the body ignores. These accumulate when a UX is designed but never shipped, or when a refactor moves the consumer without pruning the supply. **Delete on sight.** A future contributor reading `case toggleMultiSelect` will assume the feature exists and try to use it. If the surface comes back, re-add it deliberately with a real producer.
- ❌ Service-to-service references that hard-code `.shared` inline (e.g., `private let foo = FooService.shared`). Use constructor-default DI even for services — same shape as VMs (`init(foo: FooService = .shared)`). Production callers don't notice; the parameter shape is ready for protocol-based test injection later.
- ❌ Multiple distinct triggers calling the same service refresh with no coalescer. Two near-simultaneous triggers will issue the same fetch twice and double the pressure on shared queue-backed frameworks (PhotoKit, AVFoundation, URLSession). See §3 "Coalesce concurrent calls to the same service fetch."
- ❌ `Identifiable` via `id = UUID()` per-instance AND relying on the synthesized `Equatable` for content equality. Two instances built from identical data compare unequal because their UUIDs differ. If you need content equality, implement `==` + `hash(into:)` explicitly over the content fields (and document the divergence between `Identifiable.id` and `Equatable.==`).
- ❌ ASCII section banners (long `━━━` rules + box-art around declarations). Use `// MARK:` — Xcode's jump bar surfaces them, and they don't visually fight the code below.
- ❌ Theatrical emoji prefixing what-comments (`// 🛡️ Sovereign Layer: Always on Top` next to `.zIndex(100)`). If a comment is decorative rather than load-bearing, delete it. If it carries a real WHY, write that WHY without emoji.

---

## How to use this in a new project

1. Drop this file at the project root.
2. Drop your `FeatureModule/` next to it with the `API/Core/Services/Models/Examples/` shape.
3. Tell your AI assistant: "Follow `CODING_GUIDELINES.md`."
4. When a new pattern emerges that's worth keeping, add a section here with the *why*. Don't let one-off conventions proliferate without documentation.

The goal is a codebase where any contributor (human or AI) can predict where a file lives, what shape its types take, and where its concurrency boundaries are — without reading every existing file first.

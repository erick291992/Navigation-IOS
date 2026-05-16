# Universal Media Picker — Perf Push (Handoff & Re-Architecture Notes)

> **Status:** Intermediate perf fixes shipped. Re-architecture pending.
>
> This doc captures everything we tried, what worked, what didn't, and what should be done next. It's written for the engineer (or AI) who will inherit the picker module and do the proper re-architecture. Read it before opening any files.

---

## TL;DR

We took tap-to-grid latency from ~3.3 seconds down to ~150ms-ish on warm taps (~800ms on cold) through a series of localized fixes. The picker is now production-acceptable but the underlying architecture still has compromises that should be addressed in a clean rewrite.

**The biggest learning of the whole push:** every "smart" architectural attempt to defer / lazy-mount the picker's view tree was a workaround for one root cause — **`UnifiedCreatorView` is monolithic.** It bundles the static shell (header, mode buttons, shutter), the heavy UIKit-bridged camera viewfinder, and the asset grid into one mount unit. That coupling is what makes every perf trade-off a zero-sum game between "button feels snappy" and "shell visible immediately." Re-architecture should split it.

---

## 1. The bug we started with

User taps "Media" in `PostCreateView` → ~3.3-second freeze before the photo grid appears. On real devices, even slower (4-6s with realistic photo libraries). Heavy `PHAsset.fetchAssets` blocking the main thread + `AVCaptureSession.startRunning` blocking SwiftUI's mount of `CameraPreviewView`.

---

## 2. What we shipped (current state of `main` after the perf push)

7 files in `UniversalMediaPicker/` have functional changes. Diff is intentionally minimal — no diagnostic log noise. Build is clean.

### 2.1 `PhotoKitService.swift` — async refactor (Fix A)

`fetchRecentAssets` is now `async`. The heavy `PHAsset.fetchAssets` call moved to a `nonisolated private static func performFetch(limit:) async -> [PHAsset]`. Per SE-0338, calling a nonisolated async function via `await` from a `@MainActor` context hops execution to the cooperative thread pool — `PHAsset.fetchAssets` runs on a background thread, main thread stays free. State mutation (`updateAssets(_:)`) happens back on MainActor when the await returns.

Also: the `.notDetermined` permission-request branch now uses `withCheckedContinuation` to bridge `PHPhotoLibrary.requestAuthorization`'s callback into structured async.

Removed: the unused `private var fetchResult: PHFetchResult<PHAsset>?` property.

### 2.2 `UnifiedCreatorViewModel.swift` — async-aware caller updates

`setup()` now spawns a `Task` for the async `photoKit.fetchRecentAssets()`. The Task inherits MainActor, but the await on the nonisolated `performFetch` inside `fetchRecentAssets` hops to the cooperative pool. Main thread stays free. Preview-asset assignment moved inside the Task so it runs *after* the fetch completes (was a subtle bug — assigning from `recentAssets.first` before the fetch returned).

`updateAuth()` wraps its `fetchRecentAssets()` call in a `Task` for the same reason.

### 2.3 `MediaPickerModifier.swift` — pre-warm pipeline

Added two pre-warm hooks attached to the host view (the consumer of `.mediaPicker(...)`). All pre-warm is **inside the picker module** — consumers' public API stays `.mediaPicker(isPresented:configuration:onCompletion:)`. They don't know about `CameraService` or `PhotoKitService`.

- **`.onAppear { CameraService.shared.setup() }`** — fires the moment the host view appears. `CameraService.setup()` is idempotent (early-returns if already configured), so safe to call repeatedly. We use `.onAppear` rather than `.task` because `.onAppear` fires ~16-32ms sooner — every millisecond of head-start matters for the AVCaptureSession cold start.
- **`.task { … await PhotoKitService.shared.fetchRecentAssets(); … AssetGridViewModel.shared(…).trigger(.loadInitialData) }`** — async block that pre-fetches both observable state stores the picker reads from (PhotoKit's `recentAssets` for the viewfinder/gallery-shortcut, and `AssetGridViewModel.state.assets` for the actual grid). **Auth-status guarded** — we don't trigger the iOS permission prompt eagerly here; first-time users hit the prompt at tap time (the expected UX moment).
- **`.sheet(onDismiss:)`** — calls `prepareForNewSession()` on the cached `AssetGridViewModel` to clear per-session selection state (since the cache outlives a single picker session).

### 2.4 `AssetGridView.swift` — skeleton placeholder

When `vm.state.assets.isEmpty`, render 40 lightweight gray placeholder cells (`skeletonGrid`) instead of an empty `ScrollView`. Matches the real grid's column count and spacing so when assets arrive the layout doesn't shift — cells just appear in place. Modern iOS pattern (Photos, Files, Mail).

### 2.5 `UnifiedCreatorView.swift` — lazy camera mount + per-section loading

- **`@State private var isCameraMounted = false`** + `.task { try? await Task.sleep(for: .milliseconds(32)); isCameraMounted = true }`. `CameraPreviewView()` is wrapped in `if isCameraMounted` so the ~50ms UIKit/AVFoundation bridging cost is deferred ~32ms. Lets the rest of the picker's view tree mount first.
- **Per-section loading spinners** (drive by existing observable state, no new state introduced):
  - Camera viewfinder: `ProgressView` when `selectedMode == .photo && cameraService.isSourceReady && (!isCameraMounted || !cameraService.isSessionRunning)`. Disappears when both the lazy mount completes AND the AVCaptureSession produces frames.
  - Library viewfinder: `ProgressView` when authorized but `recentAssets.isEmpty`. Disappears when PhotoKit propagates.
  - Gallery shortcut (bottom-left 48×48): `ProgressView` inside the rounded square when authorized but `recentAssets.first == nil`. Disappears when first asset arrives.

### 2.6 `AssetGridViewModel.swift` — already had the shared-cache fix from the prior flicker work

No new functional changes in this push beyond the perf-log stripping. The `@MainActor static var cache: [Int: AssetGridViewModel]` + `shared(selectionLimit:)` + `prepareForNewSession()` were added during the AssetGrid flicker postmortem (see `ASSETGRID_FLICKER_POSTMORTEM.md`).

### 2.7 `EliteGeometricPickerViewModel.swift` — required compile-fix for async refactor

Two trivial `Task { await photoKit.fetchRecentAssets() }` wrappers because the underlying function became async. This view model is unused in the active app (demo-only) — kept compiling.

---

## 3. Things we tried that didn't survive

Several intermediate architectures were attempted and reverted. Documenting them because if you re-investigate, you'll re-derive these — knowing the dead ends will save you time.

### 3.1 Big center spinner during gated mount — REVERTED

We added an `isContentReady` `@State` gate to `MediaPickerFlowContainer` so the sheet content closure returned cheaply (`Color.black` + a centered `ProgressView`), and `UnifiedCreatorView` mounted ~32ms later via `.task`. **This was the fastest version we ever measured** in terms of perceived sheet-pop time — the sheet truly popped up instantly because its content was a single `Color.black`. But the giant centered spinner felt wrong UX-wise (user pointed out it hides everything including the static shell), so we removed it.

> **Important measurement from this iteration:** with the `MediaPickerFlowContainer`-level gate, the sheet appeared at TAP+13ms and grid at TAP+822ms. After moving the gate inward to `UnifiedCreatorView` (current architecture), grid appears at TAP+136ms but sheet *content closure* eval has more synchronous work, so the button feels slightly stuck. We traded "fast sheet pop" for "shell-visible-immediately." **For the rebuild, find a way to keep both** — see §5.

### 3.2 `DispatchQueue.main.async` to defer the binding-set — REVERTED

Tried wrapping `viewModel.isUniversalPickerPresented = true` in `DispatchQueue.main.async`. Didn't help: the next runloop tick is just microseconds later, not enough time for the button animation to render before the heavy synchronous work begins. Also: user correctly objected to `DispatchQueue` as non-modern.

### 3.3 `Task { @MainActor in try? await Task.sleep(for: .milliseconds(100)); … }` defer — REVERTED

Modern equivalent of the above. Did push the heavy work ~100ms later, but the button still felt stuck because the heavy work block is ~100ms long itself — moving it didn't make it shorter. Also added 100ms to absolute tap-to-grid time. User reverted.

### 3.4 Big centered fade-in spinner — REVERTED

Combined the `isContentReady` gate with a `ProgressView` + `.transition(.opacity)` fade-in for `UnifiedCreatorView`. Worked but the user (correctly) preferred per-section spinners over one big spinner.

### 3.5 No gate at all — REVERTED

Removed the `isContentReady` gate entirely. `UnifiedCreatorView` mounted synchronously inside the sheet content closure. **Slowest version measured (1.2s tap-to-grid).** SwiftUI synchronously constructs the entire `UnifiedCreatorView` tree before the sheet can begin animating. We reverted.

---

## 4. Current measured latency

Test conditions: iOS Simulator, library with 200 photos, camera + photo library pre-warmed via PostCreateView.onAppear path.

| Milestone | Δ from TAP | Note |
|---|---|---|
| Sheet content closure begins | ~3ms | Sheet animation can start almost immediately |
| `MediaPickerFlowContainer.body` evaluates | ~30ms | Lightweight ZStack + UnifiedCreatorView |
| `UnifiedCreatorViewModel.init` returns | ~32ms | Pre-warm makes setup() return instantly |
| `AssetGridView.onAppear` (grid mounted, populated from cache) | ~136ms | Shell visible, grid has 200 assets ready |
| Camera lazy-mount gate flips | ~150ms (32ms after view appears) | CameraPreviewView mounts, real preview replaces spinner |
| Subsequent picker open (warm caches) | ~50-100ms | Significantly faster |

**Button-press feel:** "still a little stuck" per user — 136ms of synchronous mount work after TAP blocks the button's press-up animation. Borderline acceptable; some devices/sessions feel it more than others. Not fully solved by current architecture.

---

## 5. What still needs to happen — the re-architecture

The whole push showed that the picker module's perceived-perf ceiling is bounded by **`UnifiedCreatorView` being monolithic**. Every fix has been a workaround for that. The clean fix is to split it.

### 5.1 The target architecture

```
PhotoLibraryService (actor) — pure data, all PhotoKit calls
   ↑ awaited by ↑
PhotoKitService (@MainActor @Observable facade) — exposes recentAssets/authStatus, hosts UIKit calls
   ↑ read by ↑
UnifiedCreatorViewModel (@MainActor @Observable)

CameraDevice (actor) — pure data, all AVFoundation calls
   ↑ awaited by ↑
CameraService (@MainActor @Observable facade) — exposes session/isSessionRunning, hosts UIKit calls
   ↑ read by ↑
UnifiedCreatorViewModel
```

The two-layer pattern (`actor` for data, `@MainActor` `@Observable` for facade) was discussed extensively during this push. It encodes thread-safety in the type system, eliminates the `nonisolated` escape hatches we currently rely on, and makes the heavy work naturally off-main-thread without ceremony.

### 5.2 The view-tree split

Break `UnifiedCreatorView` into independent subviews that each own their own `@State` and lifecycle:

```
PickerShellView                    ← always mounts instantly (header, mode bar, shutter)
  ├ ViewfinderArea                 ← own @State, own .task, own loading state
  │   ├ CameraViewfinder           ← lazy-mounts CameraPreviewView internally
  │   ├ LibraryViewfinder
  │   └ HistoryViewfinder
  └ BottomPanel
      ├ StripHeader (Recents / NEXT)
      ├ AssetGridView              ← already self-contained with skeleton
      └ ShutterAndModeBar
```

When each subview owns its mount lifecycle, SwiftUI can:
- Mount the shell instantly (cheap)
- Mount each subview as its `.task` decides
- Eliminate the 104ms synchronous "mount the entire UnifiedCreatorView tree" block that's currently causing the button-stuck feel

### 5.3 The `State(initialValue:)` eager-eval trap — design out of the architecture

The eager evaluation of `State(initialValue: UnifiedCreatorViewModel(...))` was the root cause of multiple issues (double-init, repeated `setup()` calls, wasted PhotoKit fetches). The flicker postmortem worked around it with the `AssetGridViewModel.shared(...)` cache. The right fix in the rebuild is to **not call `self.setup()` from `init`** — instead, `viewModel.setup()` should run from a `.task` on the View, so it runs exactly once per view mount regardless of how many throwaway VMs SwiftUI constructs.

### 5.4 The "best of both worlds" — keep the fast sheet pop AND show shell immediately

The current architecture forces a trade-off because `MediaPickerFlowContainer`'s sheet content closure has to synchronously construct `UnifiedCreatorView` (which is heavy). If `UnifiedCreatorView` were split into `PickerShellView` (lightweight) + lazy subviews, the sheet content closure would return fast AND the shell would be visible. No gate needed.

This is the architecture the user kept gravitating toward but the monolithic `UnifiedCreatorView` made impossible without significant refactor.

### 5.5 Other things to clean up in the rebuild

- **`PostCreateView.swift:147`** — `configuration: .init(selectionLimit: 1, crop: .landscape, style: .tealSleek)` constructs a fresh `MediaPickerConfiguration` value on every `PostCreateView` body re-eval. Hoist to `@State` so the modifier sees stable parameters. Minor but principled.
- **`SheetNavigationContainer.swift`** — the original AnyView-wrapping pattern was fixed in the flicker postmortem (`.ifLet { … }` chain). This is fine, but worth verifying in the rebuild that no new patterns of opaque wrapping creep in.
- **`CameraService.setup()`** has an unguarded `self.isSourceReady = (status == .authorized)` write. Idempotent equality guard would prevent unnecessary @Observable cascades on second call. Trivial fix when you're already in the file.
- **`UnifiedCreatorViewModel.init` calls `self.setup()`** — move this to `.task` on the view (see §5.3). Won't change perf (already fast post-Fix A) but eliminates the wasted work.

---

## 6. Cross-project sync state

The Meetsta picker module should be `cp`'d to `NavigationFrame3` after this push to keep them in sync. Files to copy:

```
Meetsta/UniversalMediaPicker/Core/AssetGrid/AssetGridView.swift
Meetsta/UniversalMediaPicker/Core/AssetGrid/AssetGridViewModel.swift
Meetsta/UniversalMediaPicker/Core/UnifiedCreator/UnifiedCreatorView.swift
Meetsta/UniversalMediaPicker/Core/UnifiedCreator/UnifiedCreatorViewModel.swift
Meetsta/UniversalMediaPicker/Core/EliteGeometricPicker/EliteGeometricPickerViewModel.swift
Meetsta/UniversalMediaPicker/Entry/MediaPickerModifier.swift
Meetsta/UniversalMediaPicker/Services/PhotoKitService.swift
```

The picker module is intentionally kept identical between the two projects. Past sync was via straight `cp` and that pattern continues here.

---

## 7. Notes for the next engineer (the re-architecture)

### Where to start
1. Read `ASSETGRID_FLICKER_POSTMORTEM.md` first — it covers the prior flicker investigation and explains the AnyView/SheetNavigationContainer issue you'd otherwise re-discover.
2. Then read this doc.
3. Build the new architecture in a separate branch — don't try to in-place-refactor from the current state. The current state is good enough to keep shipping while the rebuild proceeds.

### What to keep from the current code
- The two-layer **shared/cached `AssetGridViewModel`** pattern (`shared(selectionLimit:)`). This is a real win and the cache survives SwiftUI's identity churn perfectly.
- The **`prepareForNewSession()`** hygiene method. Per-session reset on sheet dismiss is the correct contract.
- The **skeleton-cells** UX pattern in `AssetGridView`. Don't lose this.
- The **per-section loading** indicators in `UnifiedCreatorView` (camera spinner, library spinner, gallery-shortcut spinner). Move them to the new subviews.
- The **`MediaPickerModifier` pre-warm** (camera + photos + grid VM). This is a real perf win.

### What to throw away
- The `isCameraMounted` lazy gate inside `UnifiedCreatorView`. Workaround for the monolith — the split-view architecture eliminates the need.
- The `nonisolated private static func performFetch(limit:) async` pattern in `PhotoKitService`. Replace with proper `actor PhotoLibraryService` whose methods are naturally off-MainActor.
- Both `setup()` calls from `init` (in `UnifiedCreatorViewModel` AND `EliteGeometricPickerViewModel`). Move to `.task`.

### Verification approach
- Don't reintroduce the `[PickerPerf]` diagnostic logs — they cluttered files and made diffs noisy.
- If you need timing data during the rebuild, use **Instruments** (Time Profiler + SwiftUI template). Much better signal than `print` timestamps and doesn't touch source.

---

## 8. Open questions for the rebuild

1. **Is the `MediaPickerConfiguration` API stable enough to keep?** It's a value type passed as a let on every view that uses `.mediaPicker`. Works fine but the value-vs-reference semantics interact awkwardly with SwiftUI's diffing.
2. **Should `CameraService` and `PhotoKitService` be one combined `PickerEnvironment` actor?** They're related (the picker uses both) and currently coordinated implicitly via `UnifiedCreatorViewModel`. A combined environment could simplify the View layer.
3. **Should the pre-warm fire on app launch instead of `.mediaPicker.onAppear`?** App-launch pre-warm gets the picker fully warm before the user even navigates to PostCreateView. Trade-off: uses some CPU/battery on launch for users who never open the picker.
4. **Is the iOS sheet animation worth replacing with a custom presentation?** Native `.sheet` has a ~500ms slide that we can't tune. A custom presentation could be instant but loses gesture-to-dismiss and iOS-native feel. Almost certainly not worth it, but it's an option.

---

## 9. Quick sanity checks before merging anything from the rebuild

- `git diff --stat` should be ≤8 files touched in `UniversalMediaPicker/`. More than that = scope creep.
- No `print()` or `pickerPerfLog` calls anywhere in the diff. Diagnostic logs belong in feature branches, not main.
- Build clean on both Meetsta AND NavigationFrame3.
- Manual test on real device (not simulator) — simulator's camera + PhotoKit behave very differently from real hardware. The whole reason for this push was a device-only perf regression.

---

**End of handoff.** Tag/contact the original author of this push for context if anything in here is unclear.

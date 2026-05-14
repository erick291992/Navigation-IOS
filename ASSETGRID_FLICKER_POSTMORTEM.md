# AssetGrid Flicker — Postmortem & Reference

> **Scope:** This doc explains a specific picker flicker bug that surfaced in the
> Meetsta iOS app, **and** the broader architectural issue in
> `SheetNavigationContainer` that made it possible. It's intentionally written
> for engineers in *other* projects that share the same picker / navigation
> codebase, so it can be read cold.

---

## 1. The symptom

When the iOS system popup *"Would Like to Access Your Photos"* (the automatic
Limited-Access prompt) is dismissed by tapping **Keep Current Selection**, the
photo grid in the bottom panel of `UnifiedCreatorView` visibly **flickers** —
the whole grid disappears for a moment and reappears black, all cells flashing
at once. Reproduces only on the **first** popup dismiss per picker session;
subsequent picker re-opens are clean (because iOS only shows that automatic
prompt once per app launch).

---

## 2. What you'd expect to find vs. what's actually happening

You'd reasonably guess one of:

- `PHAuthorizationStatus` is flipping to `.notDetermined` and back, which would
  trigger any `if authStatus == .notDetermined` branch in the view tree to swap
  the grid out for placeholder UI.
- The `PHPhotoLibraryChangeObserver` is firing with a transient empty fetch
  result and the diff guard isn't catching it.
- Some unknown second observer somewhere outside the picker module is calling
  `fetchRecentAssets()`.

**None of those is the cause.** Diagnostic logs prove `authStatus` stays
`.limited` throughout, no observer fires during the popup window, and grep
finds zero other PhotoKit subscribers in the codebase.

The real cause is a **SwiftUI view-identity instability** in the layers *above*
the picker:

1. `NavigationCoordinator` presents the picker host via
   `.sheet(item: topSheetContext)`, where `topSheetContext` is a custom binding
   whose getter reads `navigationManager.modalStack.last(where: …)`.
2. `SheetNavigationContainer.body` wraps its content in nested `AnyView`
   instances **inside conditional `if let` blocks**, recreating those wrappers
   on every body re-eval.
3. `NavigationManager` is `@Observable` with several actively-read properties
   (`modalStack`, `rootPushPath`, `modalPushPaths`, …). Any mutation — including
   ones unrelated to the picker — triggers a body re-eval on the coordinator,
   which cascades down through the `AnyView` wrappers.
4. SwiftUI cannot peek inside an `AnyView` to verify structural equivalence
   against the previous re-eval. It conservatively **re-mounts** the wrapped
   content.
5. Re-mounting tears down `@State` everywhere downstream — including
   `UnifiedCreatorView.@State viewModel: UnifiedCreatorViewModel`.
6. Each fresh `UnifiedCreatorViewModel.init` constructs a brand-new
   `AssetGridViewModel(selectionLimit:)` with `state.assets == []`.
7. The grid renders empty until the async `loadInitialData` task wins the race
   and refills `state.assets` with the user's recents.

**The race in step 7 is the visible flicker.** Each cell renders against
`Rectangle().fill(Color.black)` while `displayThumbnail` is nil. Visually: grid
goes black, all cells flash, then thumbnails paint a few frames later. The popup
dismiss doesn't *cause* the bug — the architecture is already re-mounting on
its own throughout the session. The popup just happens to trigger one extra
re-mount at a moment the user is staring at the grid.

---

## 3. How we proved it

Five `[FlickerDx-…]` `#if DEBUG` log probes installed at the layers of interest:

| Tag | Site | What it answers |
|---|---|---|
| `A` | `UnifiedCreatorView.bottomPanel` body | Does `authStatus` ever come through as `.notDetermined`? |
| `B` | both `AssetGridView.init` variants | Is the `AssetGridViewModel` pointer (`ObjectIdentifier`) stable? Does its `state.assets.count` bounce to 0? |
| `C` | `UnifiedCreatorViewModel.init` | How many times is the VM constructed per session? |
| `D` | `PhotoKitService.setAuthStatus` + `clearRecentAssetsIfNeeded` | Does anything *attempt* to flip `authStatus`, even if guarded into a no-op? |
| `E` | `MediaPickerFlowContainer.body` | How often does the container body re-eval? |
| `F` | `MediaPickerFlowContainer.@State instanceID` (UUID) | Is the *container itself* being remounted? |

Reading the logs from one repro session:

- **Hypothesis A is dead** — every `[FlickerDx-A]` says `authStatus=limited`.
- **Hypothesis "iOS observer storm" is dead** — every `[FlickerDx-D]` is a no-op.
- **`[FlickerDx-C]` fires 7 times in one session** — the VM is being constructed
  7 times per picker open, mostly by SwiftUI's eager evaluation of
  `State(initialValue: UnifiedCreatorViewModel(...))` (Swift evaluates the
  argument on every parent body re-eval; `@State` only adopts the *first* one,
  but the side-effect of `init` already ran).
- **`[FlickerDx-F]` instanceID changes 4 times** — `MediaPickerFlowContainer`
  itself is being remounted four times in a single picker session.
- **`[FlickerDx-B] passedVM` cycles through 5 different ObjectIdentifiers** —
  even within stretches where `[FlickerDx-F].instanceID` *is* stable, the
  `AssetGridViewModel` pointer changes. Translation: `UnifiedCreatorView.@State`
  is being reset *inside* an otherwise stable parent.
- **`[FlickerDx-B] state.assets.count` flips 0 → 6 → 0 → 6 → 0 → 6** — every
  `@State` reset gives the view a fresh `AssetGridViewModel` whose `state.assets`
  starts empty, and a few frames later the async `loadInitialData` task
  repopulates it.

That last bullet is the visible flicker. Multiply by however many times the
identity churn happens to coincide with the user's gaze.

---

## 4. The fix that landed

**Cache `AssetGridViewModel` by `selectionLimit`** so it survives the upstream
identity churn intact. Process-wide, `@MainActor`-isolated, keyed dictionary.

```swift
// AssetGridViewModel.swift
@MainActor private static var cache: [Int: AssetGridViewModel] = [:]

@MainActor public static func shared(selectionLimit: Int) -> AssetGridViewModel {
    if let cached = cache[selectionLimit] { return cached }
    let fresh = AssetGridViewModel(selectionLimit: selectionLimit)
    cache[selectionLimit] = fresh
    return fresh
}

@MainActor public func prepareForNewSession() {
    state.selectedAssets = []
    state.isMultiSelectActive = false
    state.errorMessage = nil
}
```

```swift
// UnifiedCreatorViewModel.swift — one-line swap in init
self.gridViewModel = AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
```

```swift
// MediaPickerModifier.swift — clear per-session state when the sheet really dismisses
.sheet(isPresented: $isPresented, onDismiss: {
    AssetGridViewModel.shared(selectionLimit: configuration.selectionLimit)
        .prepareForNewSession()
}) { … }
```

### Why this works

Every fresh `UnifiedCreatorViewModel.init` — including all the throwaway ones
generated by SwiftUI's eager `State(initialValue:)` evaluation, *and* the ones
where `@State` is actually reset by identity churn — now resolves to the
**same** `AssetGridViewModel` for a given `selectionLimit`. Its `state.assets`,
album list, current-album choice, and the on-disk thumbnail cache stay warm
across the churn. The async `loadInitialData` race no longer paints empty
frames because there's nothing empty to paint.

### Why this isn't a hack

`AssetGridViewModel` already behaves as a long-lived per-user-library cache
(it's a `PHPhotoLibraryChangeObserver`, it owns an album list, it diffs
identifier sets to skip writes when nothing changed). Promoting it from
"per-picker-mount" to "per-selectionLimit, process-wide" matches its real
semantics. The per-session reset hook keeps the contract honest: when the sheet
actually goes away, the user's selection set is cleared so the next open is
fresh.

### Limits of the fix

This fix only solves the *visible* symptom. It doesn't fix the underlying
identity instability — the upstream re-mount churn is still happening. The
logs in `[FlickerDx-C]` (7 throwaway `UnifiedCreatorViewModel` constructions
per session, each running `setup()` → `fetchRecentAssets()`) and `[FlickerDx-F]`
(4 `MediaPickerFlowContainer` remounts) will still be there until the *real*
root cause in the navigation layer is fixed. See §5.

---

## 5. The deeper issue — `SheetNavigationContainer` and `AnyView`

### What the code does

```swift
// SheetNavigationContainer.body  (excerpt)
let baseView: AnyView = {
    if let backgroundColor = backgroundColor {
        return AnyView(navigationStack.background(backgroundColor))
    } else {
        return AnyView(navigationStack)
    }
}()

let viewWithPresentationModifiers: some View = {
    if let options = presentationOptions {
        var view: AnyView = AnyView(baseView)
        if let detents = options.detents {
            view = AnyView(view.presentationDetents(detents))
        }
        if let dragIndicator = options.dragIndicator {
            view = AnyView(view.presentationDragIndicator(dragIndicator))
        }
        return view
    } else {
        return AnyView(baseView)
    }
}()

viewWithPresentationModifiers
    .id(currentID ?? context.id)
```

### Why `AnyView` is here (the legitimate reason)

Three *optional* presentation modifiers — `background`, `presentationDetents`,
`presentationDragIndicator` — applied conditionally based on the
`ModalContext`'s configuration. Every SwiftUI modifier changes the view's
static type:

```swift
navigationStack                                    // NavigationStack<…>
navigationStack.background(Color.red)              // ModifiedContent<NavigationStack<…>, _BackgroundStyleModifier<Color>>
navigationStack.presentationDetents([.large])      // ModifiedContent<…, _PresentationDetentsModifier>
```

The two branches of `if let backgroundColor { … } else { … }` therefore return
different types. Swift requires one return type per closure. With 3 optional
modifiers, you'd have up to 2³ = 8 distinct composite types to reconcile. The
mutable `var view: AnyView = …` pattern is the canonical Swift workaround —
type-erase to a common parent and chain modifiers through assignment. This is
*not* a code smell in isolation; it's an idiomatic answer to "build a modifier
chain whose composition is decided at runtime."

### Why this *specific* `AnyView` placement caused the flicker

`AnyView` is intentionally **opaque** to SwiftUI's structural diffing. When
`SheetNavigationContainer.body` re-evaluates (which it does on every
`NavigationManager` `@Observable` notification, because the
`.sheet(item: topSheetContext)` and `.fullScreenCover(item: topFullScreenContext)`
bindings on `NavigationCoordinator` both read `navigationManager.modalStack`),
fresh `AnyView` instances are constructed. SwiftUI can't peek inside to verify
the wrapped content is structurally equivalent to the previous re-eval, so it
**conservatively re-mounts the contents**, blowing away every `@State` below.

The `.id(currentID ?? context.id)` line was added in good faith to mitigate
this, but it's applied **outside** the outermost `AnyView`. That pins the
`AnyView`'s identity — not the wrapped content's identity. SwiftUI still
re-mounts the content because `.id()` on an opaque wrapper isn't a guarantee
about what's inside.

### How to remove the `AnyView` *without* losing the conditional-modifier
behavior

Two clean patterns, both rely on SwiftUI's `_ConditionalContent` (the type that
`@ViewBuilder` produces from `if/else` branches). `_ConditionalContent` is
**structural** — SwiftUI introspects it, diffs it, and preserves `@State`
across body re-evals as long as the branch doesn't flip.

**Pattern A — generic `ifLet` view extension** (recommended; one helper,
infinitely composable):

```swift
extension View {
    @ViewBuilder
    func ifLet<T, V: View>(_ value: T?, _ transform: (Self, T) -> V) -> some View {
        if let value { transform(self, value) } else { self }
    }
}
```

Then `SheetNavigationContainer.body` collapses to:

```swift
var body: some View {
    NavigationStack(path: pushPathBinding(for: context.id)) {
        context.rootView
            .environment(\.navigationManager, navigationManager)
            .navigationDestination(for: PushContext.self) { pushContext in
                pushContext.makeView()
                    .environment(\.navigationManager, navigationManager)
            }
    }
    .ifLet(backgroundColor) { $0.background($1) }
    .ifLet(context.sheetPresentationOptions?.detents) { $0.presentationDetents($1) }
    .ifLet(context.sheetPresentationOptions?.dragIndicator) { $0.presentationDragIndicator($1) }
    .id(currentID ?? context.id)
    .onAppear { … }
}
```

No `AnyView`. SwiftUI now sees the entire chain structurally. Since
`backgroundColor` and the presentation options are `let` properties (set once
at container init, never reassigned), the `_ConditionalContent` branches never
flip and downstream `@State` becomes rock-solid.

**Pattern B — purpose-built `ViewModifier` per option** (more verbose, more
self-documenting):

```swift
private struct OptionalBackgroundModifier: ViewModifier {
    let color: Color?
    @ViewBuilder func body(content: Content) -> some View {
        if let color { content.background(color) } else { content }
    }
}
// + analogous OptionalDetentsModifier, OptionalDragIndicatorModifier
```

Then `.modifier(OptionalBackgroundModifier(color: backgroundColor))` and so on.
Same identity-preserving properties, more explicit naming.

### Whether to apply this fix

This is a **systemic** fix that hardens *every* sheet your navigation system
presents, not just the picker. It's also a change to shared navigation
infrastructure with a wider blast radius than the per-bug fix in §4. The
practical recommendation:

1. **Ship the `AssetGridViewModel` cache fix first** (already done in this repo).
   It solves the visible flicker today, scoped to the picker module.
2. **Schedule the `SheetNavigationContainer` refactor** as a separate change
   when you have bandwidth to retest every sheet in the app. Once it lands,
   you can simplify or even remove the per-module workarounds it was masking
   (the `AssetGridViewModel` cache becomes a nice-to-have rather than a
   requirement).

---

## 6. Other gotchas surfaced along the way

Worth knowing even if they didn't directly cause this bug:

- **Eager `State(initialValue: SomeClass(…))`.** Swift evaluates the argument
  expression on every parent body re-eval. `@State` only *adopts* the very
  first value, but the construction (and any side effects in `init`) runs every
  time. In our case, `UnifiedCreatorViewModel.init` called
  `self.setup()` → `photoKit.fetchRecentAssets()` → `cameraService.setup()` on
  every throwaway VM. The PhotoKit fetches were guarded into no-ops by ID
  diffing, so they were invisible — but `CameraService.setup()` writes
  `self.isSourceReady = (status == .authorized)` *unconditionally* (no equality
  guard), which fires an `@Observable` notification on every call. Independent
  bug, doesn't affect the grid, but worth fixing for performance and
  diagnostic-noise reasons. **Mitigation:** hoist `self.setup()` out of `init`
  into an `.onAppear` or `.task` modifier on `UnifiedCreatorView`, and add an
  equality guard around the `isSourceReady` write.

- **`AnyView` + `.id(…)` is *not* equivalent to applying `.id(…)` to the
  underlying view.** `.id()` on `AnyView` pins the `AnyView`'s identity; the
  wrapped content's identity stays opaque to SwiftUI's diffing.

- **`@Observable` writes fire notifications even when the value didn't change.**
  Equality-guarded setters (`guard newValue != oldValue else { return }; …`)
  are not optional — they're the only way to stop the cascade in a high-fanout
  service.

- **`@Observable` computed properties propagate the access through their
  getter.** `var authStatus: PHAuthorizationStatus { photoKit.authStatus }`
  reads as a subscription to `photoKit.authStatus`, not to "the computed
  getter." Good when you want it; surprising when you don't.

- **`ForEach(items, id: \.id)`** preserves cell identity correctly *only if
  the surrounding view tree's identity is preserved too*. When the parent's
  `@State` resets, the `ForEach`'s storage starts from scratch even when
  identifiers match. The thumbnail cache `NSCache<NSString, UIImage>` keyed on
  `"\(localIdentifier)|\(modificationDate)"` is what saves us here — fresh
  cells still render correct pixels on their first frame because the cache
  hits before `displayThumbnail` falls back to nil.

---

## 7. Diagnostic logs — keep or strip

The five `[FlickerDx-…]` probes are all `#if DEBUG`. They're cheap, but verbose
in the console once the bug is sealed. Recommendation:

- **Keep them** while validating the fix across a few real-device runs and
  edge cases (background → foreground, sheet dismiss + reopen, multi-picker).
- **Strip them** once the fix is sealed in production builds. Grep the
  codebase for `[FlickerDx-` and remove the `#if DEBUG` blocks they sit in,
  plus the `dxName` extension on `PHAuthorizationStatus` in `PhotoKitService.swift`.

---

## 8. TL;DR for the engineer reading this in the other project

- **If you're seeing a flicker / `@State`-reset symptom in any view downstream
  of `SheetNavigationContainer`, suspect the `AnyView` wrapping first.** It
  defeats SwiftUI's structural diffing and causes conservative re-mounts on
  every `NavigationManager` `@Observable` notification.
- **The local fix** (cache the long-lived state outside the unstable `@State`)
  works module-by-module and is safe to apply in any picker, list, or detail
  view that shows up inside a navigation-managed sheet.
- **The systemic fix** is the `.ifLet` refactor in §5. Tackle it when you can
  retest every sheet in the app.
- **Don't trust `.id(…)` on top of `AnyView`** to preserve content identity.
  It doesn't.
- **Don't put side-effecting class constructors inside `State(initialValue: …)`**
  unless those side effects are idempotent (equality-guarded, ID-diffed). The
  expression evaluates every parent body re-eval whether `@State` adopts the
  value or not.

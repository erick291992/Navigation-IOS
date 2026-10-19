# Stacked Modals — Migration Notes

For apps that vendor the navigation library (`NavigationFrame3/Navigation/`). For how to use the library as a whole, see [`NAVIGATION_GUIDE.md`](NAVIGATION_GUIDE.md).

## TL;DR

- **Nothing changes until you opt in.** The default is `.swap`, which keeps today's look: one sheet at a time.
- **Opt in with `.stacked`.** Sheets then pile up like cards, and a sheet under another one keeps all its state: `@State`, text fields, scroll position, pushed screens, running tasks.
- **No call sites change.** `presentSheet`, `presentFullScreen`, `push`, `dismissSheet`, `dismissTo`, `dismiss()`, `dismissBack()` and the `NavigationCoordinator` init all compile as before.

## Files to copy

Copy the whole `Navigation/` folder. One file is new:

| File | Change |
|---|---|
| `ModalPresenter.swift` | **New.** The per-level presenter. |
| `NavigationManager.swift` | Changed |
| `NavigationCoordinator.swift` | Changed |
| `SheetNavigationContainer.swift` | Changed |
| `ModalContext.swift` | Changed |

## Opting in

```swift
// Whole coordinator
NavigationCoordinator(rootView: FeedView(), customKey: "feed", modalPresentationMode: .stacked)

// Or one presentation at a time (overrides the coordinator default)
navigationManager.presentSheet(presentation: .stacked) { GifPickerView() }
navigationManager.presentSheet(presentation: .swap) { OtherView() }
```

`enum NavigationManager.ModalPresentationMode { case swap, stacked }`

| | On screen when B opens over A | When B closes |
|---|---|---|
| `.swap` (default) | A slides away, B slides up | A comes back **rebuilt fresh** |
| `.stacked` | B slides up over A; A stays, pushed back | The **same** A, untouched |

Both modes keep every modal in `modalStack`. The mode only decides what's on screen.

**Mixing modes:**
- A `.swap` sheet takes the place of the sheet below it. A `.stacked` sheet goes on top.
- So `A`, then `B(.swap)`, then `C(.stacked)` shows B with C over it. A stays hidden until B closes.

**Don't confuse this with `style:`.**
- `style: .replaceLast` / `.replaceAll` **removes** sheets from the stack. Closing the new sheet does not bring them back.
- `presentation: .swap` only **hides** the sheet below it.

## The visual change (`.stacked` only)

- **Sheets stack like iOS cards.** The lower sheet stays visible, slightly pushed back and dimmed, behind the new one.
- **No more dismiss-then-present animation.** Under `.swap`, the lower sheet slid down before the new one slid up. Under `.stacked`, only the new sheet moves.
- **Closing reveals the sheet underneath** without re-presenting it.

## Behavior changes in both modes (bug fixes)

1. **Mixed sheet / full-screen stacks work.**
   - Before: `[sheet A, fullScreen B]` tried to present both from the root at once, and one silently never appeared.
   - Before: swipe-dismissing one of them popped `modalStack.last`, which could be the other one.
   - Now: every level presents exactly one child, and a swipe removes the modal that was actually swiped.
2. **`fullNavigationHistory` stays in sync.**
   - Before: `dismissSheet`, `.replaceLast`, `.replaceAll`, swipe-down and native back-swipes left stale entries behind. For example, `dismiss()` right after `dismissSheet()` popped a *second* sheet.
   - Now: every removal trims history.
3. **`dismissTo` finds screens by identity, not by their original position.**
   - Before: after something below had been removed, it could skip or hit the wrong screen.
4. **`dismissTo(RootView.self)` reaches the coordinator's root again.**
   - Before: since the `key` → `customKey` rename, the root was recorded under the key (e.g. `"tab1"`), so `dismissTo(ViewB.self)` never matched the root ViewB.
   - Before: the mismatch could also make the zombie check wipe a whole tab's navigation after a stale-stack reset.
   - Now: the root is recorded by view type. Registry keys still use `customKey`.
5. **`.replaceLast` / `.replaceAll` follow your `DismissalMode`**, the same as `dismissSheet`.
   - Before: they always ran `onDismiss` for every removed modal root and never for screens pushed inside them.
   - Now: with the coordinator default `.topmost`, `.replaceAll` on A → B → C runs only the topmost removed screen's `onDismiss`. Pass `sheetDismissalMode: .all` on the coordinator for "everything".
6. **Swipe-down removes exactly the swiped sheet.**
   - It goes through the same cleanup as `dismissSheet`: the sheet and its pushed screens are removed, history is trimmed, and `onDismiss` runs per `sheetDismissalMode`.
   - If SwiftUI reports a dismissal twice, or after a programmatic removal, the extra report is ignored.
7. **`onDismiss` runs after the stack is updated.** Code inside `onDismiss` that presents or pushes sees the post-dismissal stack.
8. **Removed:** `SheetNavigationContainer`'s `currentID` / `.id(...)`. It was internal and never had any effect.

New public API:
- `dismissModal(id:dismissalMode:)` dismisses a specific modal and everything above it.
- `childModal(of:)` is what each level uses to find its child.

## Workarounds you can delete

After switching the relevant coordinator, or the specific presentation, to `.stacked`:

- **Static view-model caches that keep a sheet's state alive while another sheet opens on top**, such as the comments sheet's per-post draft cache that survived opening the GIF picker. The comments sheet now stays mounted under the GIF picker, so a plain `@State` view model keeps the draft.
- **`onAppear` / `.task` guards against re-firing when returning to a sheet.** Under `.stacked`, a sheet that was covered by another *sheet* doesn't re-fire them.

**Measure before deleting:**
- **`AssetGridSelectionCache`.** The picker opens through its own `.sheet` in `MediaPickerModifier`, not through `modalStack`, so this change may not cover the 4–5 remounts it compensates for.
  - Re-run the `[FlickerDx-F]` instance-ID probe from `ASSETGRID_FLICKER_POSTMORTEM.md` on a device, with the picker opened from inside a `.stacked` library sheet.
  - Delete the cache only if the instance ID stays stable for a whole session.

## Known limitations

- **A full-screen cover hides what's under it.** When a full-screen cover sits over a sheet, iOS takes the sheet off screen, so `.onAppear` fires again when you return to it. Its `@State` and view models survive; only the appear callbacks repeat. Sheets over sheets don't have this.
- **A sheet that contains its own `NavigationCoordinator`.** If that inner coordinator has a sheet open while the outer manager stacks another sheet on the same sheet, iOS allows only one presentation per screen. The outer sheet waits in `modalStack` and appears as soon as the inner sheet closes (covered by `testInnerCoordinatorSheetThenOuterStack`).

## How it's verified

- `NavigationFrame3Tests/ModalStackTests.swift`: stack contents and exact `onDismiss` order for `.all` / `.topmost` / `.landing` across:
  - `dismissSheet`
  - `dismissModal` (idempotent)
  - `.replaceLast` / `.replaceAll`
  - `dismissTo`, including the stale-index regression
  - native back-swipes
  - history trimming
  - rung resolution for `.swap` / `.stacked` / mixed
- `NavigationFrame3UITests/ModalStackUITests.swift` drives the **Stack** tab (`ModalStackHarness.swift`):
  - A → B → C and back, with counters, text, view-model instance and appear/task counts unchanged
  - a pushed screen inside a sheet survives a nested sheet
  - swipe-dismiss of the top sheet
  - mixed sheet / full-screen
  - `dismissTo`, `.replaceLast`, `.replaceAll`
  - two sheets presented in one tap
  - `.swap` rebuilding the covered sheet
  - the inner-coordinator limitation
- `SwapModeRegressionUITests` checks that the default `.swap` mode on Tab 1 still behaves as before.
- `ReplaceDemoPathUITests` drives the demo path ViewC → ViewD → ViewE and runs `.replaceLast` / `.replaceAll` from ViewE.

To try it by hand: on Tab 1, open ViewC and use the "Present ViewD as…" box. From ViewD, use "Present ViewE · stacked", then ViewE's "Present ViewF as…" box. Each screen shows the open sheets.

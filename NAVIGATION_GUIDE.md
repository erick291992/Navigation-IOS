# Navigation Library Guide

How to use the SwiftUI navigation library in `NavigationFrame3/Navigation/`: pushing screens, presenting sheets, dismissing, and reaching another tab's navigation.

To see what changed in the stacked-modal update, read [`MODAL_STACKING_MIGRATION.md`](MODAL_STACKING_MIGRATION.md).

---

## 1. The pieces

| Type | What it is |
|---|---|
| `NavigationCoordinator` | Wrap a tab or flow in one. It owns the push stack and presents sheets. |
| `NavigationManager` | The state behind a coordinator. Your views call methods on it. |
| `NavigationManagerRegistry` | Finds a coordinator's manager by key, from anywhere (e.g. another tab). |

Inside any view under a coordinator:

```swift
@Environment(\.navigationManager) var navigationManager
```

## 2. Setting up a coordinator

```swift
NavigationCoordinator(rootView: FeedView(), customKey: "feed")
```

Every option, with its default:

```swift
NavigationCoordinator(
    rootView: FeedView(),
    customKey: "feed",                    // registry key; defaults to the root view's type name
    dismissalMode: .topmost,              // which onDismiss runs for dismissTo (§5)
    sheetDismissalMode: .topmost,         // which onDismiss runs when a sheet closes (§5)
    dismissToMode: .recent,               // which copy dismissTo targets (§6)
    logLevel: .default,                   // .info in DEBUG, .none in release
    navigationStackColor: nil,
    sheetBackgroundColor: nil,
    modalPresentationMode: .swap          // how sheets appear (§4)
)
```

Use a unique `customKey` for each coordinator. Two coordinators with the same key share one manager.

## 3. Push and present

```swift
navigationManager.push { ProfileView() }
navigationManager.push { ProfileView() } onDismiss: { print("profile closed") }

navigationManager.presentSheet { CommentsView() }
navigationManager.presentSheet(detents: [.medium, .large], dragIndicator: .visible) { CommentsView() }
navigationManager.presentFullScreen { CameraView() }
```

**Where `push` lands.** It pushes onto the top sheet's own stack if a sheet is open. Otherwise it pushes onto the tab's root stack.

```
No sheet open:   Root ─push→ Profile
Sheet A open:    Root   [Sheet A ─push→ Profile]    ← pushed inside A
```

## 4. How sheets appear: `.swap` vs `.stacked`

`enum ModalPresentationMode { case swap, stacked }`. Set the default on the coordinator, or override it for one presentation:

```swift
navigationManager.presentSheet(presentation: .stacked) { GifPickerView() }
```

```
.swap (default)                          .stacked
┌──────────┐      ┌──────────┐          ┌──────────┐      ┌──────────┐
│┌────────┐│      │┌────────┐│          │┌────────┐│      │┌────────┐│
││Sheet A ││ ──▶  ││Sheet B ││          ││Sheet A ││ ──▶  ││┌──────┐││  A stays behind,
││typed:hi││      ││        ││          ││typed:hi││      │││  B   │││  pushed back
└┴────────┴┘      └┴────────┴┘          └┴────────┴┘      └┴┴──────┴┴┘
A slides away, B slides up               B slides up over A

close B → A slides back in, FRESH        close B → the SAME A, "hi" still typed
         (typed text, scroll lost)
```

Both modes keep every sheet in the list. The mode only changes what's on screen, and whether a covered sheet keeps its state.

**When to use which:**
- **`.stacked`** when the user will come back to the lower sheet. Examples: a comments sheet that opens a GIF picker, a form that opens a chooser.
- **`.swap`** for a one-sheet-at-a-time look, where losing the covered sheet's state doesn't matter.

**Mixing them.** A `.swap` sheet takes the place of the sheet below it. A `.stacked` sheet goes on top of it:

```
present A, then B(.swap), then C(.stacked)

On screen:   B with C on top        (A hidden)
close C  →   B, untouched
close B  →   A, rebuilt fresh
```

## 5. Closing screens and which `onDismiss` runs

```swift
navigationManager.dismissSheet()            // closes the top sheet
navigationManager.dismissPush()             // pops the top pushed screen
navigationManager.dismiss()                 // closes whatever was opened last (sheet or push)
navigationManager.dismissBack()             // goes back to the previous screen in history
navigationManager.dismissTo(ProfileView.self)
navigationManager.dismissModal(id: someModalID)   // that sheet and everything above it
```

When several screens close at once, `DismissalMode` decides whose `onDismiss` runs:

```
Open:  A → B → C        dismissTo(A)   (C and B close)

.all      → C, then B      everything that closed, top first
.topmost  → C only         the one you were looking at
.landing  → B only         the last to close, right above where you land
```

**Which setting applies where:**
- **`sheetDismissalMode`:** `dismissSheet`, swipe-down, `.replaceLast` and `.replaceAll`.
- **`dismissalMode`:** `dismissTo`.
- **`dismissBack` and `dismissPush`** close one screen and always run its `onDismiss`. `dismiss()` uses `sheetDismissalMode` when the last thing opened was a sheet.
- **Per call:** pass the mode directly, e.g. `dismissSheet(dismissalMode: .all)` or `dismissTo(A.self, dismissalMode: .landing)`.

Screens pushed inside a closing sheet count too: they close before the sheet itself.

**`onDismiss` runs after the stack is updated.** Code inside it that presents or pushes sees the new state.

### Swipe-down

Swiping a sheet away runs the same cleanup as `dismissSheet`, for that exact sheet only:

```
Open: A → B → C     user swipes C down     →   Open: A → B   (B untouched)
```

- **Full-screen covers can't be swiped.** That's iOS behavior; give them a button.
- **A swipe released early** (the sheet bounces back) changes nothing.
- **Detents:** dragging to a smaller detent isn't a dismissal.
- **Blocking it:** add `.interactiveDismissDisabled()` in a sheet's content to prevent swiping it away.

## 6. `dismissTo` targets

`dismissTo` takes a view type, never a string:

```swift
navigationManager.dismissTo(ViewB.self)
```

- **It can land on the coordinator's root.** `dismissTo(FeedView.self)` closes everything above a root `FeedView`.
- **If the type appears more than once,** `dismissToMode` picks which copy:
  - `.recent` (default): the most recent copy. If you're already on it, the copy before that.
  - `.root`: the first copy.

## 7. Replacing sheets: `style:`

```
Open:  A → B → C

presentSheet { D() }                         →  A → B → C → D   (default .stack)
presentSheet(style: .replaceLast) { D() }    →  A → B → D       close D → back to B
presentSheet(style: .replaceAll)  { D() }    →  D               close D → back to root
```

Removed sheets run `onDismiss` according to `sheetDismissalMode` (§5).

**Not the same as `presentation: .swap`:**
- **`style:`** *removes* sheets from the list. They never come back.
- **`.swap`** only *hides* the sheet below. It comes back (fresh) when the top one closes.

## 8. Reaching another tab: the registry

```swift
// Present on tab 2 from anywhere (e.g. a deep link or another tab)
NavigationManagerRegistry.shared.manager(forCustomKey: "tab2")?.presentSheet { ViewE() }

// Run once that coordinator exists (queued if it doesn't yet)
NavigationManagerRegistry.shared.perform(onCustomKey: "tab2") { $0.push { ViewE() } }
```

**Why it exists.** A coordinator is a struct, and SwiftUI rebuilds it every time its parent redraws. The registry hands the same manager back on each rebuild, so your stack isn't wiped.

**Lifetime.** Managers are held weakly and unregistered when their coordinator really goes away. Don't keep your own strong references to them.

## 9. Things to know

- **A full-screen cover over a sheet makes iOS take that sheet off screen.** When you return, the sheet's `.onAppear` runs again. Its state is kept. Sheets over sheets don't do this.
- **A sheet that contains its own `NavigationCoordinator`.** If the inner coordinator has a sheet open while the outer manager presents another sheet on top of that same sheet, the outer sheet waits and appears as soon as the inner sheet closes. iOS allows only one presentation per screen.
- **Logs.** Set `logLevel: .debug` on the coordinator to print every push, present and dismissal.

## 10. Trying it in the demo app

- **Tab 1, ViewB → Present ViewC:**
  - ViewC's "Present ViewD as…" box: stacked / swap / full screen / replace last / replace all.
  - ViewD → "Present ViewE · stacked" → ViewE's box for replace last / replace all from three levels deep.
  - Each screen shows "Open sheets: …".
- **Stack tab:** every level shows its counter, text, view-model instance and appear count, so you can see what survives.
- **Tests:**
  - `NavigationFrame3Tests/ModalStackTests.swift` covers the logic.
  - `NavigationFrame3UITests/ModalStackUITests.swift` covers the real app in the simulator.

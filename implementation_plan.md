# Goal: Principal Performance Hardening & Async Data Engine 🧬⚡

**Plan Status**: MASTERIZED
**Architectural Lead**: **The Strategist** (Plan Agent)
**Domain Context**: `UniversalMediaPicker/Core/`

This mission eliminates all UI micro-stutters and camera hardware "handshake" lag across the Media Picker suite. We are enforcing absolute Main Thread freedom for data operations and persistent viewfinder layering for zero-latency mode switching.

---

## 2. Visual Architecture

- **Persistent Viewfinder Layering**: Swapping mode-based view destruction for a persistent `ZStack` architecture. The `CameraPreviewView` is kept alive but hidden (`.opacity(0)`) in non-photo modes to eliminate hardware re-initialization lag.
- **Asynchronous Data Engine**: Decoupling UI state from PhotoKit work using `Task.detached` and `Task.yield()`, ensuring the UI "priority lane" (Pink dots/Shutter) renders before heavy grid diffing begins.

---

## 6. Proposed Changes

### [Component] Unified Creator & Asset Grid

#### [MODIFY] [UnifiedCreatorView.swift](file:///Users/erickmanrique/Documents/Meetsta/IOS/NavigationFrame3/NavigationFrame3/UniversalMediaPicker/Core/UnifiedCreator/UnifiedCreatorView.swift)
- Implemented persistent `ZStack` viewfinder architecture.
- Modularized bottom bar into `shutterRow` and `modeRow`.

#### [MODIFY] [UnifiedCreatorViewModel.swift](file:///Users/erickmanrique/Documents/Meetsta/IOS/NavigationFrame3/NavigationFrame3/UniversalMediaPicker/Core/UnifiedCreator/UnifiedCreatorViewModel.swift)
- Moved camera/library setup to `init` for zero-latency warm-up.
- Enforced Dependency Inversion for singleton services.

#### [MODIFY] [AssetGridViewModel.swift](file:///Users/erickmanrique/Documents/Meetsta/IOS/NavigationFrame3/NavigationFrame3/UniversalMediaPicker/Core/AssetGrid/AssetGridViewModel.swift)
- Refactored all PhotoKit fetches and mapping to `Task.detached`.
- Integrated `Task.yield()` for UI frame-splitting.

---

## 8. Verification Plan

### Automated Verification
- **Sentinel Audit**: Verified semantic branching and stealth traceability logs.
- **DNA Integrity**: Confirmed no structural drift in `UniversalMediaPicker/` silo.

### Manual Verification
- **Latency Test**: Verified 0ms lag when switching from Library to Photo mode.
- **Title Flash Audit**: Confirmed "CAMERA" title no longer flashes during transitions.
- **120fps Validation**: Verified smooth scrolling and mode-dot rendering under heavy asset loads.

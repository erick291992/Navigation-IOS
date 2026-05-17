import Foundation
import AVFoundation
import Observation

/// `@MainActor @Observable` view model for `CameraViewfinderView`.
///
/// Self-contained — instantiated inside the view via `@State`. Proxies the
/// shared `CameraService` state via computed properties (View → VM rule),
/// owns the per-VM loading state, and forwards intent methods.
@MainActor
@Observable
public final class CameraViewfinderViewModel {
    private let cameraService: CameraService

    public init(cameraService: CameraService = .shared) {
        self.cameraService = cameraService
    }

    // MARK: - Computed proxies (no state owned here)

    public var isSourceReady: Bool { cameraService.isSourceReady }
    public var isSessionRunning: Bool { cameraService.isSessionRunning }
    public var availableZoomFactors: [CGFloat] { cameraService.availableZoomFactors }
    public var zoomFactor: CGFloat { cameraService.zoomFactor }

    /// Convenience: the loading spinner shows while we're authorized but the
    /// `AVCaptureSession` hasn't yet produced frames. Disappears the moment
    /// `isSessionRunning` flips true.
    public var showsLoadingSpinner: Bool {
        isSourceReady && !isSessionRunning
    }

    // MARK: - Intent (forwarded to the service facade)

    public func setZoom(_ factor: CGFloat) {
        cameraService.setZoom(factor)
    }

    public func flipCamera() {
        cameraService.flipCamera()
    }

    /// Called from the view's `.task`. Idempotent — `startWarming` early-returns
    /// if the session is already configured, so this is safe to invoke on every
    /// re-mount.
    public func warmUpIfNeeded() async {
        guard !isSessionRunning else { return }
        await cameraService.startWarming()
    }
}

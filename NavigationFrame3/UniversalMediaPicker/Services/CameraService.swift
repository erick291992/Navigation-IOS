import Foundation
import AVFoundation
import UIKit
import Observation

/// `@Observable` facade exposing the picker's published camera state.
///
/// Holds the `AVCaptureSession` for the UIKit preview-layer bridge to read
/// synchronously on the main thread, plus observable lifecycle/zoom state for
/// SwiftUI views to observe. Uses `CameraDeviceService` (the mini-repository)
/// for the heavy off-main AVFoundation work.
///
/// Architecture notes:
/// - NO class-level `@MainActor`. Async lifecycle methods (`startWarming`) are
///   nonisolated so awaiting them hops to the cooperative thread pool per
///   SE-0338, and the heavy AVFoundation calls inside `CameraDeviceService`
///   run off the main thread.
/// - Observable-state writers and sync UI-facing helpers are individually
///   `@MainActor`-annotated; `await MainActor.run` is used inside async
///   methods to hop back to main for observable writes.
/// - `AVCapturePhotoCaptureDelegate` conformance lives in a dedicated extension.
@Observable
public final class CameraService: NSObject {
    @MainActor public static let shared = CameraService()

    /// Owned here so the UIKit `AVCaptureVideoPreviewLayer` bridge can bind
    /// to it synchronously on the main thread. Reference-typed; safe to read
    /// from any context (`AVCaptureSession` is thread-safe).
    public let session = AVCaptureSession()

    public var isSessionRunning = false
    public var isSourceReady = false
    public var zoomFactor: CGFloat = 1.0
    public var availableZoomFactors: [CGFloat] = [1.0, 2.0, 5.0]

    private let device = CameraDeviceService.shared
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?

    @MainActor
    private override init() {
        super.init()
    }

    // MARK: - Prewarm / setup

    /// Asynchronous setup of the capture session. Resolves authorization,
    /// discovers the best back-facing camera, configures the session, and
    /// starts it running. Idempotent: calling repeatedly is safe (early-returns
    /// if the session already has inputs).
    public func startWarming() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run { setIsSourceReady(status == .authorized) }

        if status == .notDetermined {
            let granted = await device.requestVideoAuthorization()
            await MainActor.run { setIsSourceReady(granted) }
            if granted {
                await startWarming()
            }
            return
        }

        guard status == .authorized else { return }

        // Idempotency guard — `session.inputs` is thread-safe to read.
        guard session.inputs.isEmpty else { return }

        guard let captureDevice = await device.discoverDevice(for: .back) else { return }

        await MainActor.run { updateZoomFactors(for: captureDevice) }

        guard let input = try? AVCaptureDeviceInput(device: captureDevice) else { return }

        await device.configureSession(session, with: input, output: output)
        await device.startSession(session)

        await MainActor.run { setIsSessionRunning(true) }
    }

    // MARK: - Zoom

    @MainActor
    public func setZoom(_ factor: CGFloat) {
        guard let captureDevice = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        do {
            try captureDevice.lockForConfiguration()
            let clamped = max(
                captureDevice.minAvailableVideoZoomFactor,
                min(factor, captureDevice.maxAvailableVideoZoomFactor)
            )
            captureDevice.videoZoomFactor = clamped
            setZoomFactor(captureDevice.videoZoomFactor)
            captureDevice.unlockForConfiguration()
        } catch {
            // Silent; zoom is a best-effort UI affordance.
        }
    }

    // MARK: - Capture

    /// Captures a high-resolution photo. Completion fires when the delegate
    /// callback resolves (see `AVCapturePhotoCaptureDelegate` extension).
    @MainActor
    public func capture(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Flip camera

    /// Swaps between front and back camera. Fire-and-forget: spawns an async
    /// Task internally so call-sites stay synchronous.
    @MainActor
    public func flipCamera() {
        Task { await performFlip() }
    }

    private func performFlip() async {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let newPosition: AVCaptureDevice.Position =
            (currentInput.device.position == .back) ? .front : .back

        guard let newDevice = await device.discoverDevice(for: newPosition) else { return }
        let success = await device.swapInput(on: session, to: newDevice)
        guard success else { return }

        await MainActor.run {
            updateZoomFactors(for: newDevice)
            setZoomFactor(1.0)
        }
    }

    // MARK: - Private (state writers + computed helpers)

    /// Equality-guarded `isSourceReady` setter. Without the guard, `setup()`
    /// fires an `@Observable` cascade on every throwaway VM construction
    /// during SwiftUI's upstream identity churn — each one re-evaluates every
    /// downstream consumer of `isSourceReady`.
    @MainActor
    private func setIsSourceReady(_ value: Bool) {
        guard isSourceReady != value else { return }
        isSourceReady = value
    }

    /// Equality-guarded `isSessionRunning` setter.
    @MainActor
    private func setIsSessionRunning(_ value: Bool) {
        guard isSessionRunning != value else { return }
        isSessionRunning = value
    }

    /// Equality-guarded `zoomFactor` setter.
    @MainActor
    private func setZoomFactor(_ value: CGFloat) {
        guard zoomFactor != value else { return }
        zoomFactor = value
    }

    /// Computes available zoom presets based on the device's physical lens range.
    @MainActor
    private func updateZoomFactors(for captureDevice: AVCaptureDevice) {
        var factors: [CGFloat] = []

        // 0.5x only if the device has an ultra-wide lens.
        if captureDevice.minAvailableVideoZoomFactor <= 0.5 {
            factors.append(0.5)
        }

        // Always include 1.0x as the base.
        factors.append(1.0)

        // 2.0x and 5.0x only if reachable.
        if captureDevice.maxAvailableVideoZoomFactor >= 2.0 {
            factors.append(2.0)
        }
        if captureDevice.maxAvailableVideoZoomFactor >= 5.0 {
            factors.append(5.0)
        }

        let computed = Array(Set(factors)).sorted()
        guard availableZoomFactors != computed else { return }
        availableZoomFactors = computed
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in self.completion?(nil) }
            return
        }
        Task { @MainActor in self.completion?(image) }
    }
}

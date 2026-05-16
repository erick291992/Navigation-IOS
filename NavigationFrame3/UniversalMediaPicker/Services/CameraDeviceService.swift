import Foundation
import AVFoundation

/// Mini-repository for raw AVFoundation operations.
///
/// Plain class — no isolation, no observable state. All methods are `async`;
/// awaiting them from any context hops execution to the cooperative thread
/// pool per SE-0338, so the heavy sync AVFoundation calls (`startRunning`,
/// `beginConfiguration`/`commitConfiguration`) run off the main thread
/// automatically — no `Task.detached` ceremony.
///
/// The `AVCaptureSession` is owned by `CameraService` (the `@Observable`
/// facade) so the UIKit bridge (`CameraPreviewView`'s
/// `AVCaptureVideoPreviewLayer`) can read it synchronously on the main thread.
/// This repository takes the session as a parameter — it never owns one.
public final class CameraDeviceService {
    public static let shared = CameraDeviceService()
    private init() {}

    // MARK: - Authorization

    /// Bridges `AVCaptureDevice.requestAccess(for: .video)` (callback-based)
    /// into structured async via `withCheckedContinuation`.
    public func requestVideoAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Device discovery

    /// Finds the best available camera at `position`. For back-facing, walks
    /// the device's physical lens stack (Triple → Dual Wide → Dual → Wide);
    /// for front-facing, returns the standard wide-angle. Falls back to the
    /// default wide-angle camera if discovery returns nothing.
    public func discoverDevice(for position: AVCaptureDevice.Position) async -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = (position == .back) ? [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ] : [.builtInWideAngleCamera]

        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )

        return discoverySession.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Session lifecycle

    /// Starts the capture session. Heavy sync call (`startRunning` can take
    /// 500–1500ms on a cold session) — runs off-main here.
    public func startSession(_ session: AVCaptureSession) async {
        session.startRunning()
    }

    /// Stops the capture session.
    public func stopSession(_ session: AVCaptureSession) async {
        session.stopRunning()
    }

    /// Configures the session by adding the given input and output inside a
    /// `beginConfiguration`/`commitConfiguration` block. Caller is responsible
    /// for clearing any existing inputs/outputs first if needed.
    public func configureSession(
        _ session: AVCaptureSession,
        with input: AVCaptureDeviceInput,
        output: AVCapturePhotoOutput
    ) async {
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    /// Swaps the session's primary input to a new device (used by flipCamera).
    /// Returns `true` if the swap succeeded, `false` if the new input could
    /// not be created or added (in which case the original input is restored).
    public func swapInput(
        on session: AVCaptureSession,
        to newDevice: AVCaptureDevice
    ) async -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let originalInput = session.inputs.first as? AVCaptureDeviceInput
        if let originalInput { session.removeInput(originalInput) }

        guard let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            if let originalInput, session.canAddInput(originalInput) {
                session.addInput(originalInput)
            }
            return false
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            return true
        } else {
            if let originalInput, session.canAddInput(originalInput) {
                session.addInput(originalInput)
            }
            return false
        }
    }
}

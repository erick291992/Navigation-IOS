import SwiftUI
import AVFoundation

// MARK: - Infrastructure Exception
//
// `CameraPreviewView` is the picker module's UIKit-bridge for the live
// camera feed. It is one of TWO documented places in the module that calls
// services directly from view code (the other being `MediaPickerModifier`).
// The strict View → ViewModel → Service rule (see DATA_FLOW_PATTERNS.md)
// does NOT apply here because:
//
// 1. The whole purpose of `UIViewRepresentable` is to bridge a UIKit
//    primitive into SwiftUI. Here that primitive is `AVCaptureVideoPreviewLayer`,
//    which requires a direct reference to the live `AVCaptureSession` owned
//    by `CameraService`. Routing through a VM would mean exposing the raw
//    session on the VM's public surface — that defeats the encapsulation
//    we get from the service layer.
//
// 2. The wiring (`videoPreviewLayer.session = cameraService.session`)
//    happens inside `makeUIView`, a UIKit lifecycle method called during
//    SwiftUI's representable construction. There is no async/await
//    moment to "ask a VM for the session" — UIViewRepresentable's
//    lifecycle is synchronous by design.
//
// The self-warm fallback below covers direct consumers that mount this
// without wrapping it in a `CameraViewfinderViewModel` (e.g., the
// EliteGeometricPicker variant). For the primary picker flow, the VM's
// `.task` already warmed the session before this view mounts;
// `startWarming` is idempotent so the fallback is a no-op in that case.

/// A high-performance preview layer for the live camera session.
public struct CameraPreviewView: UIViewRepresentable {
    private var cameraService = CameraService.shared
    
    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.videoPreviewLayer.session = cameraService.session

        // Self-warm fallback for direct consumers that don't wrap this in a
        // CameraViewfinderViewModel (e.g., EliteGeometricPickerView). The
        // primary picker's CameraViewfinderViewModel warms via its own .task
        // first, so this is a no-op in that flow (startWarming is idempotent).
        if !cameraService.isSessionRunning {
            Task { await cameraService.startWarming() }
        }

        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        // Update session if it changed (e.g. flip camera)
        if uiView.videoPreviewLayer.session != cameraService.session {
            uiView.videoPreviewLayer.session = cameraService.session
        }
    }
}

/// Native UIView subclass to seamlessly host the AV layer and automatically handle layout resizes.
public class VideoPreviewUIView: UIView {
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

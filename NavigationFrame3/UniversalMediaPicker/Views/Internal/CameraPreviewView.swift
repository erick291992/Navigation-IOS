import SwiftUI
import AVFoundation

/// A high-performance preview layer for the live camera session.
public struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraService = CameraService.shared
    
    public func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraService.session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        
        view.layer.addSublayer(previewLayer)
        
        // Start session if not already running
        if !cameraService.isSessionRunning {
            cameraService.setup()
        }
        
        return view
    }
    
    public func updateUIView(_ uiView: UIView, context: Context) {
        // Update layer frame on orientation change if needed
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

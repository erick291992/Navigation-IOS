import SwiftUI
import AVFoundation

/// A high-performance preview layer for the live camera session.
public struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraService = CameraService.shared
    
    public func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.videoPreviewLayer.session = cameraService.session
        
        // Start session if not already running
        if !cameraService.isSessionRunning {
            cameraService.setup()
        }
        
        return view
    }
    
    public func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        // The UIView naturally handles layout updates through its custom layerClass
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

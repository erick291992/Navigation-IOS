import Foundation
import AVFoundation
import UIKit

/// A dedicated service to manage the live camera preview and capture for V3.
public class CameraService: NSObject, ObservableObject {
    public static let shared = CameraService()
    
    @Published public var session = AVCaptureSession()
    @Published public var isSessionRunning = false
    
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Sets up the capture session.
    public func setup() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
            }
        } catch {
            print("❌ Camera setup failed: \(error)")
        }
    }
    
    /// Captures a high-resolution photo.
    public func capture(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion?(nil)
            return
        }
        completion?(image)
    }
}

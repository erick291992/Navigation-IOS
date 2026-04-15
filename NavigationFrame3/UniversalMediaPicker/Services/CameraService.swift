import Foundation
import AVFoundation
import UIKit

/// A dedicated service to manage the live camera preview and capture for V3.
public class CameraService: NSObject, ObservableObject {
    public static let shared = CameraService()
    
    @Published public var session = AVCaptureSession()
    @Published public var isSessionRunning = false
    @Published public var isSourceReady = false
    
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Sets up the capture session.
    public func setup() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        DispatchQueue.main.async {
            self.isSourceReady = (status == .authorized)
        }
        
        guard status == .authorized else {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { authorized in
                    if authorized { self.setup() }
                }
            }
            return
        }
        
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
    
    /// Flips between front and back camera.
    public func flipCamera() {
        guard !session.inputs.isEmpty else { return }
        
        session.beginConfiguration()
        
        if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(currentInput)
            
            let newPosition: AVCaptureDevice.Position = (currentInput.device.position == .back) ? .front : .back
            if let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
               let newInput = try? AVCaptureDeviceInput(device: newDevice) {
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                }
            } else {
                // Fallback to original if something fails
                session.addInput(currentInput)
            }
        }
        
        session.commitConfiguration()
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

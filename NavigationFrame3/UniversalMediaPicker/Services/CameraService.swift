import Foundation
import AVFoundation
import UIKit
import Observation

/// A dedicated service to manage the live camera preview and capture for V3.
@MainActor
@Observable
public class CameraService: NSObject {
    public static let shared = CameraService()
    
    public var session = AVCaptureSession()
    public var isSessionRunning = false
    public var isSourceReady = false
    public var zoomFactor: CGFloat = 1.0
    public var availableZoomFactors: [CGFloat] = [1.0, 2.0, 5.0] // Default wide-angle set
    
    private let output = AVCapturePhotoOutput()
    private var completion: ((UIImage?) -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func setZoom(_ factor: CGFloat) {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            self.zoomFactor = device.videoZoomFactor
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to set zoom: \(error)")
        }
    }
    
    /// Sets up the capture session.
    public func setup() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        self.isSourceReady = (status == .authorized)
        
        guard status == .authorized else {
            if status == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { authorized in
                    Task { @MainActor in
                        if authorized { self.setup() }
                    }
                }
            }
            return
        }
        
        guard session.inputs.isEmpty else { return } // Already setup
        
        // Find the best available camera (Triple -> Dual -> Wide)
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        
        guard let device = discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        
        // Detect available zoom factors
        updateZoomFactors(for: device)
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            
            let currentSession = self.session
            Task.detached(priority: .userInitiated) {
                currentSession.startRunning()
                await MainActor.run {
                    self.isSessionRunning = true
                }
            }
        } catch {
            print("❌ Camera setup failed: \(error)")
        }
    }
    
    private func updateZoomFactors(for device: AVCaptureDevice) {
        var factors: [CGFloat] = []
        
        // Add 0.5x only if the device physically supports it (Ultra Wide lens)
        if device.minAvailableVideoZoomFactor <= 0.5 {
            factors.append(0.5)
        }
        
        // Always include 1.0x and 2.0x as standard
        factors.append(1.0)
        
        // Only include 2.0x and 5.0x if the device can actually reach them
        if device.maxAvailableVideoZoomFactor >= 2.0 {
            factors.append(2.0)
        }
        
        if device.maxAvailableVideoZoomFactor >= 5.0 {
            factors.append(5.0)
        }
        
        // Ensure we don't have duplicates and they are sorted
        self.availableZoomFactors = Array(Set(factors)).sorted()
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
            
            let deviceTypes: [AVCaptureDevice.DeviceType] = (newPosition == .back) ? [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ] : [.builtInWideAngleCamera]
            
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: newPosition
            )
            
            if let newDevice = discoverySession.devices.first,
               let newInput = try? AVCaptureDeviceInput(device: newDevice) {
                if session.canAddInput(newInput) {
                    session.addInput(newInput)
                    updateZoomFactors(for: newDevice)
                    self.zoomFactor = 1.0
                }
            } else {
                // Fallback
                session.addInput(currentInput)
            }
        }
        
        session.commitConfiguration()
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in
                self.completion?(nil)
            }
            return
        }
        Task { @MainActor in
            self.completion?(image)
        }
    }
}

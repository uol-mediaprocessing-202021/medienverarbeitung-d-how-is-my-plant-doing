//
//  ViewController.swift
//  MyPlant
//
//  Created by Sandro Wehrhahn on 28.10.20.
//


import UIKit
import Vision
import AVKit


/// Main App Controller which handles the main interface
class ViewController: UIViewController {
    
    // MARK: - Outlets
    /// Outlets are views tied to the interface in Main.storyboard
    
    @IBOutlet weak var cameraView: UIView!
    @IBOutlet weak var labelClassification: UILabel!
    @IBOutlet weak var labelDisease: UILabel!
    @IBOutlet weak var labelAccuracy: UILabel!
    @IBOutlet weak var viewResult: UIView!
    @IBOutlet weak var lcBottomSheet: NSLayoutConstraint!
    @IBOutlet weak var imageViewFocus: UIImageView!
    
    /// handler for the vision ai requests
    private let visionSequenceHandler = VNSequenceRequestHandler()
    /// camera layer holds the camera stream
    private lazy var cameraLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)

    // set up the capture session with the backcamera
    private lazy var captureSession: AVCaptureSession = {
        let session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        guard
            let backCamera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video,
                                                     position: .back),
            let input = try? AVCaptureDeviceInput(device: backCamera)
        else { return session }
        
        session.addInput(input)
        return session
    }()
    
    /// override to add Camera to the main view and start the focus animation
    override func viewDidLoad() {
        super.viewDidLoad()
        
        addCameraView()
        startCameraFocus()
    }
    
    /// Hide results view initialy
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.4,
                       delay: 1,
                       usingSpringWithDamping: 0.8,
                       initialSpringVelocity: 0.8,
                       options: .curveEaseInOut) {
            // prepare move animation
            self.viewResult.transform = .init(translationX: 0, y: 300)
        } completion: { done in }
    }
    
    // Starts the camera focus animation
    func startCameraFocus() {
        UIView.animate(withDuration: 3,
                       delay: 0,
                       options: [.autoreverse, .repeat], animations: {
            self.imageViewFocus.transform = .init(scaleX: 1.1, y: 1.1)
            self.imageViewFocus.alpha = 0.5
        }, completion: nil)
    }
    
    // Adds the camera layer to the main view
    func addCameraView() {
        self.cameraView.layer.addSublayer(self.cameraLayer)
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "DispatchQueue"))
        
        self.captureSession.addOutput(videoOutput)
        cameraLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        self.captureSession.startRunning()
    }
    
    /// override behaviour to make the cameralayer adapt to the whole screen
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        self.cameraLayer.frame = self.cameraView.frame
    }

    /// Animate Focus View
    func focusView(_ bool: Bool) {
        DispatchQueue.main.async {
            if bool {
                UIView.animate(withDuration: 0.2, delay: 0, animations: {
                    self.imageViewFocus.transform = .init(scaleX: 0.8, y: 0.8)
                    self.imageViewFocus.alpha = 1
                }, completion: nil)
            } else {
                UIView.animate(withDuration: 0.2, delay: 0, animations: {
                    self.imageViewFocus.transform = .identity
                    self.imageViewFocus.alpha = 0.5
                }, completion: nil)
            }
        }
    }

}


// The Buffer Delegate returns images from the camera to perform Vision Requests on it

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        // Safely generate AI Models and the pixelbuffer
        guard
            let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let plantModel = try? VNCoreMLModel(for: PlantClassifier().model),
            let diseaseModel = try? VNCoreMLModel(for: DiseaseClassifier().model)
        else { return }

        let requests = [
            VNCoreMLRequest(model: plantModel, completionHandler: handlePlant),
            VNCoreMLRequest(model: diseaseModel, completionHandler: handleDisease)
        ]
        requests.forEach { $0.imageCropAndScaleOption = .centerCrop }
        
        do {
            // perform vision requests
            try self.visionSequenceHandler.perform(requests, on: pixelBuffer)
        } catch {
            print("Error: \(error)")
        }
    }
}


extension ViewController {
    
    /// Handle Plant classification results
    func handlePlant(request: VNRequest, error: Error?) {
        guard let observations = request.results else { return }
        
        let classification = observations
            .compactMap { $0 as? VNClassificationObservation}
            .filter { $0.confidence > 0.7 }
            .first
        
        if let classification = classification {
            updatePlantWith(classification: classification)
            focusView(true)
        } else {
            focusView(false)
        } 
    }
    
    /// Handle Disease classification results
    func handleDisease(request: VNRequest, error: Error?) {
        guard let observations = request.results else { return }
        
        let classification = observations
            .compactMap { $0 as? VNClassificationObservation }
            .filter { $0.confidence > 0.7 }
            .first
        
        if let classification = classification {
            updateDiseaseWith(classification: classification)
        }
    }

    /// Update labels from Disesase observation
    func updateDiseaseWith(classification: VNClassificationObservation) {
        let accuracy = Int(classification.confidence * 100)
        let diseaseName = classification.identifier.capitalized
        
        updateLabels(plantName: nil, acc: accuracy, disease: diseaseName)
    }

    /// Update labels from Plant observation
    func updatePlantWith(classification: VNClassificationObservation) {
        let accuracy = Int(classification.confidence * 100)
        let plantName = classification.identifier.capitalized
        
        updateLabels(plantName: plantName, acc: accuracy, disease: nil)
    }
    
    func updateLabels(plantName: String?, acc: Int, disease: String?) {
        DispatchQueue.main.async {
            // only update labels if value is not nil
            if let plantName = plantName {
                self.labelClassification.text = plantName
            }
            if let disease = disease {
                self.labelDisease.text = disease
            }
            self.labelAccuracy.text = "\(acc)%"
            
            // show results sheet
            UIView.animate(withDuration: 0.8, delay: 0.5, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.8, options: .curveEaseIn) {
                self.viewResult.transform = .identity
            } completion: { success in }
        }
    }
    
}

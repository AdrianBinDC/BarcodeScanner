//
//  BarcodeScanner.swift
//  BarcodeLocalizer
//
//  Adapted from BarcodeLocalizer by Luca Torella
//  Copyright © 2018 Adrian Bolinger. All rights reserved.
//

import AVFoundation
import Vision
import UIKit

protocol BarcodeScannerDelegate: class {
  func detectedString(_ string: String)
}

class BarcodeScanner: UIViewController {
  
  // Add your own button in case you need extra light to scan a barcode
  @IBOutlet weak var torchButton: UIButton!
  
  private var requests = [VNRequest]()
  private let session = AVCaptureSession()
  private lazy var drawLayer: CAShapeLayer = {
    let drawLayer = CAShapeLayer()
    self.view.layer.addSublayer(drawLayer)
    drawLayer.frame = self.view.bounds
    drawLayer.strokeColor = UIColor.blue.cgColor
    drawLayer.lineWidth = 1
    drawLayer.lineJoin = kCALineJoinRound
    drawLayer.fillColor = UIColor.clear.cgColor
    return drawLayer
  }()
  private let bufferQueue = DispatchQueue(label: "com.adrianbolinger.BufferQueue",
                                          qos: .userInteractive,
                                          attributes: .concurrent)
  
  weak var delegate: BarcodeScannerDelegate?
  
  private var detectedString: String? {
    didSet {
      if let barcode = detectedString {
        DispatchQueue.main.async {
          self.delegate?.detectedString(barcode)
          // Depending upon your config, you could do a vanilla
          self.navigationController?.popToRootViewController(animated: true)
        }
      }
    }
  }
  
  // MARK: Lifecycle Methods
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setupCamera()
    setupVision()
    view.bringSubview(toFront: torchButton)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    session.stopRunning()
  }
  
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    toggleTorch(on: false)
  }
  
  deinit {
//    print("BarcodeScanner deinitialized")
  }
  
  // MARK: Helpers
  func toggleTorch(on: Bool) {
    guard let device = AVCaptureDevice.default(for: AVMediaType.video)
      else {return}
    
    if device.hasTorch {
      do {
        try device.lockForConfiguration()
        
        if on == true {
          device.torchMode = .on
        } else {
          device.torchMode = .off
        }
        
        device.unlockForConfiguration()
      } catch {
        print("Torch could not be used")
      }
    } else {
      print("Torch is not available")
    }
  }

  
  // MARK: IBActions
  
  @IBAction func torchButtonAction(_ sender: UIButton) {
    torchButton.isSelected = !torchButton.isSelected
    
    toggleTorch(on: torchButton.isSelected)
  }
  
  // MARK: - Vision
  
  func setupVision() {
    let barcodeRequest = VNDetectBarcodesRequest(completionHandler: barcodeDetectionHandler)
    barcodeRequest.symbologies = [.QR, .code39, .DataMatrix, .Aztec, .code128] // VNDetectBarcodesRequest.supportedSymbologies
    self.requests = [barcodeRequest]
  }
  
  func barcodeDetectionHandler(request: VNRequest, error: Error?) {
    guard let results = request.results else { return }
    
    DispatchQueue.main.async() {
      // Loop through the results found.
      let path = CGMutablePath()
      
      for result in results {
        guard let barcode = result as? VNBarcodeObservation else { continue }
        self.reportResults(results: [barcode])
        let topLeft = self.convert(point: barcode.topLeft)
        path.move(to: topLeft)
        let topRight = self.convert(point: barcode.topRight)
        path.addLine(to: topRight)
        let bottomRight = self.convert(point: barcode.bottomRight)
        path.addLine(to: bottomRight)
        let bottomLeft = self.convert(point: barcode.bottomLeft)
        path.addLine(to: bottomLeft)
        path.addLine(to: topLeft)
      }
      
      self.drawLayer.path = path
    }
  }
  
  private func convert(point: CGPoint) -> CGPoint {
    return CGPoint(x: point.x * view.bounds.size.width,
                   y: (1 - point.y) * view.bounds.size.height)
  }
  
  private func reportResults(results: [Any]?) {
    
    guard let results = results else {
      return print("No results found.")
    }
    
    //    print("Results found: \(results.count)")
    
    for result in results {
      
      // Cast the result to a barcode-observation
      if let barcode = result as? VNBarcodeObservation {
        
        if let payload = barcode.payloadStringValue {
          print("Payload: \(payload)")
          detectedString = payload
          session.stopRunning()
          }
        
        // Print barcode-values
        print("Symbology: \(barcode.symbology.rawValue)")
        
        if let desc = barcode.barcodeDescriptor as? CIQRCodeDescriptor {
          let content = String(data: desc.errorCorrectedPayload, encoding: .utf8)
          
          // FIXME: This currently returns nil. I did not find any docs on how to encode the data properly so far.
          print("Payload: \(String(describing: content))")
          detectedString = content ?? ""
          
          print("Error-Correction-Level: \(desc.errorCorrectionLevel)")
          print("Symbol-Version: \(desc.symbolVersion)")
        }
      }
    }
  } // end report results
  
  // MARK: - Setup Camera
  
  func setupCamera() {
    let availableCameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                  mediaType: .video,
                                                                  position: .back)
    
    guard let activeDevice = (availableCameraDevices.devices.first { $0.position == .back }) else {
      return
    }
    
    do {
      let deviceInput = try AVCaptureDeviceInput(device: activeDevice)
      if session.canAddInput(deviceInput) {
        session.addInput(deviceInput)
      }
    } catch {
      print("no camera")
    }
    
    guard cameraAuthorization() else {return}
    
    let videoOutput = AVCaptureVideoDataOutput()
    
    videoOutput.setSampleBufferDelegate(self, queue: bufferQueue)
    
    if session.canAddOutput(videoOutput) {
      session.addOutput(videoOutput)
    }
    
    let previewLayer = AVCaptureVideoPreviewLayer(session: session)
    previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
    previewLayer.frame = view.bounds
    view.layer.addSublayer(previewLayer)
    
    session.startRunning()
  }
  
  private func cameraAuthorization() -> Bool{
    let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
    switch authorizationStatus {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        if granted {
          DispatchQueue.main.async {
            self.view.setNeedsDisplay()
          }
        }
      }
      return true
    case .authorized:
      return true
    case .denied, .restricted:
      return false
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension BarcodeScanner: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    
    var requestOptions: [VNImageOption: Any] = [:]
    
    if let data = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
      requestOptions = [.cameraIntrinsics: data]
    }
    
    let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: requestOptions)
    
    do {
      try imageRequestHandler.perform(self.requests)
    } catch {
      print(error)
    }
  }
}

#if os(iOS)
// AVFoundation predates Swift Sendable; @preconcurrency suppresses false-positive
// data-race diagnostics from the Obj-C framework under Swift 6 strict concurrency.
@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
  var onCapture: (Data) -> Void
  var onError: (String) -> Void

  func makeUIViewController(context: Context) -> CameraCaptureController {
    let controller = CameraCaptureController()
    controller.onCapture = onCapture
    controller.onError = onError
    return controller
  }

  func updateUIViewController(_ controller: CameraCaptureController, context: Context) {}
}

final class CameraCaptureController: UIViewController, AVCapturePhotoCaptureDelegate {
  var onCapture: ((Data) -> Void)?
  var onError: ((String) -> Void)?

  private let session = AVCaptureSession()
  private let output = AVCapturePhotoOutput()
  private var preview: AVCaptureVideoPreviewLayer?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    addShutterButton()
    Task { await configureSession() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  private func configureSession() async {
    let granted = await AVCaptureDevice.requestAccess(for: .video)
    guard granted else {
      onError?("Camera access is off. Enable it in Settings to snap labels.")
      return
    }
    guard
      let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input),
      session.canAddOutput(output)
    else {
      onError?("Couldn't start the camera on this device.")
      return
    }
    session.beginConfiguration()
    session.addInput(input)
    session.addOutput(output)
    session.commitConfiguration()

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.insertSublayer(layer, at: 0)
    preview = layer

    // startRunning() is a synchronous blocking call; run it off the main thread.
    // Capture the session into a local before entering Task.detached so we don't
    // cross the @MainActor isolation boundary inside the detached closure.
    let captureSession = session
    await withCheckedContinuation { continuation in
      Task.detached {
        captureSession.startRunning()
        continuation.resume()
      }
    }
  }

  private func addShutterButton() {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "camera.circle.fill"), for: .normal)
    button.tintColor = .white
    button.contentVerticalAlignment = .fill
    button.contentHorizontalAlignment = .fill
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "Snap label"
    button.addTarget(self, action: #selector(snap), for: .touchUpInside)
    view.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
      button.widthAnchor.constraint(equalToConstant: 72),
      button.heightAnchor.constraint(equalToConstant: 72),
    ])
  }

  @objc private func snap() {
    output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: (any Error)?
  ) {
    if let error {
      onError?(error.localizedDescription)
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      onError?("Couldn't read the captured photo.")
      return
    }
    onCapture?(data)
  }
}
#endif

import Flutter
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// System photo library picker for feedback attachments.
///
/// Asks for photo-library permission first, then presents
/// PHPickerViewController (Photos, Recents, Albums) — never
/// UIDocumentPicker / Files. No camera APIs, so this does not reintroduce
/// the ITMS-90683 NSCameraUsageDescription rejection that forced the
/// vendored file_picker document-only patch.
final class MediaLibraryPicker: NSObject, PHPickerViewControllerDelegate {
  static let shared = MediaLibraryPicker()

  private var channel: FlutterMethodChannel?
  private var flutterResult: FlutterResult?

  private override init() {
    super.init()
  }

  func configure(binaryMessenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.chessever/media_picker",
      binaryMessenger: binaryMessenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "pickImage":
        self.pickImage(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickImage(result: @escaping FlutterResult) {
    if flutterResult != nil {
      result(
        FlutterError(
          code: "BUSY",
          message: "A picture picker is already open.",
          details: nil
        )
      )
      return
    }
    flutterResult = result
    requestPhotoAccessThenPresent()
  }

  private func requestPhotoAccessThenPresent() {
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    switch status {
    case .authorized, .limited:
      presentPicker()
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] nextStatus in
        DispatchQueue.main.async {
          if nextStatus == .authorized || nextStatus == .limited {
            self?.presentPicker()
          } else {
            self?.finishDenied()
          }
        }
      }
    case .denied, .restricted:
      finishDenied()
    @unknown default:
      finishDenied()
    }
  }

  private func presentPicker() {
    var configuration = PHPickerConfiguration()
    configuration.filter = .images
    configuration.selectionLimit = 1
    configuration.preferredAssetRepresentationMode = .current

    let picker = PHPickerViewController(configuration: configuration)
    picker.delegate = self

    guard let presenter = Self.topViewController() else {
      finish(
        FlutterError(
          code: "NO_VIEW_CONTROLLER",
          message: "Could not present the photo library.",
          details: nil
        )
      )
      return
    }
    presenter.present(picker, animated: true)
  }

  private func finishDenied() {
    finish(
      FlutterError(
        code: "PERMISSION_DENIED",
        message: "Photo library permission is required to attach a picture.",
        details: nil
      )
    )
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let provider = results.first?.itemProvider else {
      finish(nil)
      return
    }
    loadImage(from: provider)
  }

  private func loadImage(from provider: NSItemProvider) {
    if provider.canLoadObject(ofClass: UIImage.self) {
      provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
        if let image = object as? UIImage, let data = Self.jpegData(from: image) {
          self?.finishPayload(data: data, fileName: Self.fileName(for: provider, ext: "jpg"))
          return
        }
        self?.loadRawData(from: provider)
      }
      return
    }
    loadRawData(from: provider)
  }

  private func loadRawData(from provider: NSItemProvider) {
    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
      guard let data, !data.isEmpty else {
        self?.finish(
          FlutterError(
            code: "READ_FAILED",
            message: "Could not read the selected picture.",
            details: nil
          )
        )
        return
      }
      if let image = UIImage(data: data), let jpeg = Self.jpegData(from: image) {
        self?.finishPayload(data: jpeg, fileName: Self.fileName(for: provider, ext: "jpg"))
        return
      }
      self?.finishPayload(data: data, fileName: Self.fileName(for: provider, ext: "jpg"))
    }
  }

  private func finishPayload(data: Data, fileName: String) {
    finish([
      "bytes": FlutterStandardTypedData(bytes: data),
      "fileName": fileName,
    ])
  }

  private func finish(_ value: Any?) {
    let reply = flutterResult
    flutterResult = nil
    guard let reply else { return }
    if Thread.isMainThread {
      reply(value)
    } else {
      DispatchQueue.main.async { reply(value) }
    }
  }

  private static func jpegData(from image: UIImage) -> Data? {
    image.jpegData(compressionQuality: 0.9)
  }

  private static func fileName(for provider: NSItemProvider, ext: String) -> String {
    let suggested = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if suggested.isEmpty {
      return "photo.\(ext)"
    }
    if suggested.contains(".") {
      return (suggested as NSString).deletingPathExtension + ".\(ext)"
    }
    return "\(suggested).\(ext)"
  }

  private static func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }
}

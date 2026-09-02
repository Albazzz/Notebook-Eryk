import Flutter
import Foundation
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SharedImportPlugin"
    ) {
      SharedImportPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "AppleVisionOcrPlugin"
    ) {
      AppleVisionOcrPlugin.register(with: registrar)
    }
  }
}

/// Native Japanese OCR for the iPad build. Vision runs on-device; Flutter
/// receives only the recognized text.
final class AppleVisionOcrPlugin: NSObject, FlutterPlugin {
  private static let channelName = "noteeryk/apple_vision_ocr"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = AppleVisionOcrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognizeJapaneseText" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let imagePath = arguments["imagePath"] as? String,
          !imagePath.isEmpty else {
      result(FlutterError(
        code: "invalid_arguments",
        message: "Missing image path for OCR.",
        details: nil
      ))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let text = try Self.recognizeJapaneseText(at: imagePath)
        DispatchQueue.main.async { result(text) }
      } catch let error as NSError {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "vision_ocr_failed",
            message: error.localizedDescription,
            details: nil
          ))
        }
      }
    }
  }

  private static func recognizeJapaneseText(at imagePath: String) throws -> String {
    let url = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(
        domain: "NoteEryk.VisionOCR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "OCR image file was not found."]
      )
    }

    var recognizedText = ""
    let request = VNRecognizeTextRequest { request, _ in
      let observations = (request.results as? [VNRecognizedTextObservation] ?? [])
        .sorted {
          if abs($0.boundingBox.minY - $1.boundingBox.minY) > 0.02 {
            return $0.boundingBox.minY > $1.boundingBox.minY
          }
          return $0.boundingBox.minX < $1.boundingBox.minX
        }
      recognizedText = observations.compactMap {
        $0.topCandidates(1).first?.string
      }.joined(separator: "\n")
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(url: url, options: [:])
    try handler.perform([request])
    let text = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      throw NSError(
        domain: "NoteEryk.VisionOCR",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Vision OCR returned no text."]
      )
    }
    return text
  }
}

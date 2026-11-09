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
/// receives the recognized text and, for furigana, where each word sits.
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
    let wantsLayout = call.method == "recognizeJapaneseLayout"
    guard wantsLayout || call.method == "recognizeJapaneseText" else {
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
        let value: Any
        if wantsLayout {
          value = try Self.recognizeJapaneseLayout(at: imagePath)
        } else {
          value = try Self.recognizeJapaneseText(at: imagePath)
        }
        DispatchQueue.main.async { result(value) }
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

  private static func recognizeJapaneseLayout(at imagePath: String) throws -> [[String: Any]] {
    let url = URL(fileURLWithPath: imagePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw NSError(
        domain: "NoteEryk.VisionOCR",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "OCR image file was not found."]
      )
    }

    var lines: [[String: Any]] = []
    let request = VNRecognizeTextRequest { request, _ in
      for observation in request.results as? [VNRecognizedTextObservation] ?? [] {
        if let candidate = observation.topCandidates(1).first {
          lines.append(Self.layoutLine(observation, candidate))
        }
      }
    }
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ja-JP"]
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(url: url, options: [:])
    try handler.perform([request])
    return lines
  }

  /// Vision's origin is bottom-left; Flutter's is top-left.
  private static func topLeftBox(_ rect: CGRect) -> [Double] {
    return [
      Double(rect.minX),
      Double(1 - rect.maxY),
      Double(rect.width),
      Double(rect.height),
    ]
  }

  private static func layoutLine(
    _ observation: VNRecognizedTextObservation,
    _ candidate: VNRecognizedText
  ) -> [String: Any] {
    let text = candidate.string

    // One entry per UTF-16 unit, matching Dart string offsets.
    var characterBoxes: [[Double]] = []
    var index = text.startIndex
    while index < text.endIndex {
      let next = text.index(after: index)
      let box = (try? candidate.boundingBox(for: index..<next)) ?? nil
      let values = box.map { Self.topLeftBox($0.boundingBox) } ?? []
      for _ in 0..<text[index..<next].utf16.count {
        characterBoxes.append(values)
      }
      index = next
    }

    var tokens: [[String: Any]] = []
    let cfText = text as CFString
    let tokenizer: CFStringTokenizer = CFStringTokenizerCreate(
      kCFAllocatorDefault,
      cfText,
      CFRangeMake(0, CFStringGetLength(cfText)),
      kCFStringTokenizerUnitWordBoundary,
      Locale(identifier: "ja") as CFLocale
    )
    while !CFStringTokenizerAdvanceToNextToken(tokenizer).isEmpty {
      let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
      let attribute = CFStringTokenizerCopyCurrentTokenAttribute(
        tokenizer,
        kCFStringTokenizerAttributeLatinTranscription
      )
      if let latin = attribute as? String,
         let reading = latin.applyingTransform(.latinToHiragana, reverse: false) {
        tokens.append([
          "start": range.location,
          "length": range.length,
          "reading": reading,
        ])
      }
    }

    return [
      "text": text,
      "box": topLeftBox(observation.boundingBox),
      "characterBoxes": characterBoxes,
      "tokens": tokens,
    ]
  }
}

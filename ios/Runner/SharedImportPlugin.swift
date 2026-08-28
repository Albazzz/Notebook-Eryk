import Flutter
import Foundation
import Security
import UIKit

final class SharedImportPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.example.noteeryk/shared_import"
  private static let fallbackAppGroup = "group.com.example.noteeryk"
  private static let inboxName = "SharedInbox"
  private static let acceptedExtensions = Set([
    "pdf", "doc", "docx", "jpg", "jpeg", "png", "webp", "gif", "heic", "heif"
  ])

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = SharedImportPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pendingFiles":
      result(Self.pendingFiles())
    case "acknowledge":
      guard let paths = call.arguments as? [String] else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "Expected a list of shared file paths.",
          details: nil
        ))
        return
      }
      Self.removeAcknowledgedFiles(paths)
      result(nil)
    case "cropImage":
      guard let arguments = call.arguments as? [String: Any],
            let sourcePath = arguments["sourcePath"] as? String,
            let outputPath = arguments["outputPath"] as? String,
            let left = (arguments["left"] as? NSNumber)?.doubleValue,
            let top = (arguments["top"] as? NSNumber)?.doubleValue,
            let right = (arguments["right"] as? NSNumber)?.doubleValue,
            let bottom = (arguments["bottom"] as? NSNumber)?.doubleValue else {
        result(FlutterError(
          code: "invalid_crop_arguments",
          message: "Missing image path or crop bounds.",
          details: nil
        ))
        return
      }
      do {
        result(try Self.cropImage(
          sourcePath: sourcePath,
          outputPath: outputPath,
          left: left,
          top: top,
          right: right,
          bottom: bottom
        ))
      } catch {
        result(FlutterError(
          code: "crop_failed",
          message: error.localizedDescription,
          details: nil
        ))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var inboxURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: resolvedAppGroup)?
      .appendingPathComponent(inboxName, isDirectory: true)
  }

  /// Sideloadly may rewrite identifiers while signing. Read the effective
  /// App Group entitlement from the signed process instead of assuming the
  /// identifier embedded in the unsigned project is still unchanged.
  private static var resolvedAppGroup: String {
    guard let task = SecTaskCreateFromSelf(nil),
          let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.application-groups" as CFString,
            nil
          ) as? [String],
          !value.isEmpty else {
      return fallbackAppGroup
    }
    return value.first {
      $0.localizedCaseInsensitiveContains("noteeryk")
    } ?? value[0]
  }

  private static func pendingFiles() -> [String] {
    guard let inboxURL else { return [] }
    let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey]
    guard let enumerator = FileManager.default.enumerator(
      at: inboxURL,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else { return [] }

    var files: [(url: URL, date: Date)] = []
    for case let url as URL in enumerator {
      guard acceptedExtensions.contains(url.pathExtension.lowercased()),
            let values = try? url.resourceValues(forKeys: Set(keys)),
            values.isRegularFile == true else { continue }
      files.append((url, values.creationDate ?? .distantPast))
    }
    return files
      .sorted { lhs, rhs in
        lhs.date == rhs.date ? lhs.url.path < rhs.url.path : lhs.date < rhs.date
      }
      .map { $0.url.path }
  }

  private static func removeAcknowledgedFiles(_ paths: [String]) {
    guard let inboxURL else { return }
    let inboxPath = inboxURL.standardizedFileURL.path
    let manager = FileManager.default
    for path in paths {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard url.path.hasPrefix(inboxPath + "/") else { continue }
      try? manager.removeItem(at: url)
    }

    // Each share is stored in its own session folder. Remove empty sessions.
    if let children = try? manager.contentsOfDirectory(
      at: inboxURL,
      includingPropertiesForKeys: nil
    ) {
      for child in children {
        if (try? manager.contentsOfDirectory(atPath: child.path).isEmpty) == true {
          try? manager.removeItem(at: child)
        }
      }
    }
  }

  private static func cropImage(
    sourcePath: String,
    outputPath: String,
    left: Double,
    top: Double,
    right: Double,
    bottom: Double
  ) throws -> String {
    guard let image = UIImage(contentsOfFile: sourcePath) else {
      throw NSError(
        domain: "NoteErykImageCrop",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Không đọc được ảnh đã chọn."]
      )
    }

    // Draw once to apply the HEIC/JPEG orientation metadata before cropping.
    let pixelSize = CGSize(
      width: image.size.width * image.scale,
      height: image.size.height * image.scale
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let normalized = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: pixelSize))
    }
    guard let cgImage = normalized.cgImage else {
      throw NSError(
        domain: "NoteErykImageCrop",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Không thể chuẩn hóa ảnh."]
      )
    }

    let bounds = CGRect(
      x: 0,
      y: 0,
      width: CGFloat(cgImage.width),
      height: CGFloat(cgImage.height)
    )
    let leftFraction = CGFloat(max(0, min(left, 0.4)))
    let topFraction = CGFloat(max(0, min(top, 0.4)))
    let rightFraction = CGFloat(max(0, min(right, 0.4)))
    let bottomFraction = CGFloat(max(0, min(bottom, 0.4)))
    let cropRect = CGRect(
      x: bounds.width * leftFraction,
      y: bounds.height * topFraction,
      width: bounds.width * max(0.01, 1 - leftFraction - rightFraction),
      height: bounds.height * max(0.01, 1 - topFraction - bottomFraction)
    ).integral.intersection(bounds)
    guard !cropRect.isEmpty,
          let croppedCGImage = cgImage.cropping(to: cropRect),
          let data = UIImage(cgImage: croppedCGImage).pngData() else {
      throw NSError(
        domain: "NoteErykImageCrop",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "Vùng cắt không hợp lệ."]
      )
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    try data.write(to: outputURL, options: .atomic)
    return outputPath
  }
}

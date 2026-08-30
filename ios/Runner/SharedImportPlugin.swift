import Flutter
import Foundation
import PDFKit
import UIKit

final class SharedImportPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.example.noteeryk/shared_import"
  private static let fallbackAppGroup = "group.com.example.noteeryk"
  private static let inboxName = "SharedInbox"
  private static let pasteboardDataType = "com.example.noteeryk.shared-import.data"
  private static let pasteboardFilenameType = "com.example.noteeryk.shared-import.filename"
  private static let diagnosticsPasteboardName = UIPasteboard.Name(
    "com.example.noteeryk.share-diagnostics"
  )
  private static let diagnosticsType = "com.example.noteeryk.share-diagnostics.text"
  private static let diagnosticsDefaultsKey = "noteeryk.share-extension.diagnostics"
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
    case "shareDiagnostics":
      result(Self.shareDiagnostics())
    case "clearShareDiagnostics":
      Self.clearShareDiagnostics()
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
    case "exportPdfWithAnnotations":
      guard let arguments = call.arguments as? [String: Any],
            let sourcePath = arguments["sourcePath"] as? String,
            let outputPath = arguments["outputPath"] as? String,
            let canvasWidth = (arguments["canvasWidth"] as? NSNumber)?.doubleValue,
            let canvasHeight = (arguments["canvasHeight"] as? NSNumber)?.doubleValue,
            let pages = arguments["pages"] as? [[String: Any]] else {
        result(FlutterError(
          code: "invalid_pdf_arguments",
          message: "Missing PDF path, canvas size, or page annotations.",
          details: nil
        ))
        return
      }
      do {
        result(try Self.exportPdfWithAnnotations(
          sourcePath: sourcePath,
          outputPath: outputPath,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          pages: pages
        ))
      } catch {
        result(FlutterError(
          code: "pdf_export_failed",
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

  private static var fallbackInboxURL: URL? {
    try? FileManager.default
      .url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      .appendingPathComponent(inboxName, isDirectory: true)
  }

  /// Sideloadly may rewrite identifiers while signing. Read the App Group
  /// from the signed provisioning profile instead of assuming the identifier
  /// embedded in the unsigned project is still unchanged.
  private static var resolvedAppGroup: String {
    for group in provisionedAppGroups {
      if FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group
      ) != nil {
        return group
      }
    }
    return fallbackAppGroup
  }

  /// The signed provisioning profile is present after Sideloadly re-signs the
  /// IPA. Reading its plist payload avoids relying on SecTask APIs, which are
  /// unavailable to iOS app-extension targets.
  private static var provisionedAppGroups: [String] {
    guard let profileURL = Bundle.main.url(
      forResource: "embedded",
      withExtension: "mobileprovision"
    ),
    let profileData = try? Data(contentsOf: profileURL),
    let plistStart = profileData.range(of: Data("<plist".utf8)),
    let plistEnd = profileData.range(of: Data("</plist>".utf8)),
    plistEnd.upperBound > plistStart.lowerBound else {
      return []
    }

    let plistData = Data(profileData[plistStart.lowerBound..<plistEnd.upperBound])
    guard let profile = try? PropertyListSerialization.propertyList(
      from: plistData,
      options: [],
      format: nil
    ) as? [String: Any],
    let entitlements = profile["Entitlements"] as? [String: Any],
    let groups = entitlements["com.apple.security.application-groups"] as? [String]
    else {
      return []
    }
    return groups
  }

  private static func pendingFiles() -> [String] {
    if let inboxURL {
      let sharedFiles = files(in: inboxURL)
      if !sharedFiles.isEmpty {
        persistDiagnostics(from: UIPasteboard.general)
        clearPasteboard()
        return sharedFiles
      }
    }

    // Personal/free provisioning can strip App Groups. The extension then
    // publishes custom file items on the system pasteboard, which survives
    // after the short-lived extension process exits.
    _ = importPasteboardFiles()
    guard let fallbackInboxURL else { return [] }
    return files(in: fallbackInboxURL)
  }

  private static func files(in directory: URL) -> [String] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .creationDateKey]
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
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

  private static func importPasteboardFiles() -> Int {
    let pasteboard = UIPasteboard.general
    guard pasteboard.contains(pasteboardTypes: [pasteboardDataType]),
          let fallbackInboxURL else { return 0 }
    persistDiagnostics(from: pasteboard)
    let session = fallbackInboxURL
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: session,
        withIntermediateDirectories: true
      )
    } catch {
      return 0
    }

    var importedCount = 0
    for (index, item) in pasteboard.items.enumerated() {
      guard let data = item[pasteboardDataType] as? Data,
            let filenameData = item[pasteboardFilenameType] as? Data,
            let rawFilename = String(data: filenameData, encoding: .utf8) else {
        continue
      }
      let filename = URL(fileURLWithPath: rawFilename).lastPathComponent
      guard acceptedExtensions.contains(
        URL(fileURLWithPath: filename).pathExtension.lowercased()
      ) else { continue }
      var target = session.appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: target.path) {
        let stem = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        target = session.appendingPathComponent("\(stem)_\(index).\(ext)")
      }
      do {
        try data.write(to: target, options: .atomic)
        importedCount += 1
      } catch {
        continue
      }
    }
    if importedCount > 0 {
      pasteboard.items = []
    } else {
      try? FileManager.default.removeItem(at: session)
    }
    return importedCount
  }

  private static func clearPasteboard() {
    let pasteboard = UIPasteboard.general
    guard pasteboard.items.contains(where: { $0[pasteboardDataType] != nil }) else {
      return
    }
    pasteboard.items = []
  }

  private static func persistDiagnostics(from pasteboard: UIPasteboard) {
    guard pasteboard.contains(pasteboardTypes: [diagnosticsType]),
          let data = pasteboard.data(forPasteboardType: diagnosticsType),
          let text = String(data: data, encoding: .utf8),
          !text.isEmpty else { return }
    UserDefaults.standard.set(text, forKey: diagnosticsDefaultsKey)
  }

  private static func shareDiagnostics() -> String {
    persistDiagnostics(from: UIPasteboard.general)
    let extensionLog: String
    if let persisted = UserDefaults.standard.string(
      forKey: diagnosticsDefaultsKey
    ), !persisted.isEmpty {
      extensionLog = persisted
    } else if let pasteboard = UIPasteboard(
      name: diagnosticsPasteboardName,
      create: false
    ),
    let data = pasteboard.data(forPasteboardType: diagnosticsType),
    let text = String(data: data, encoding: .utf8) {
      extensionLog = text
    } else {
      extensionLog = "<no extension log>"
    }
    let groupPath = inboxURL?.path ?? "<unavailable>"
    let groupCount = inboxURL.map { files(in: $0).count } ?? 0
    let fallbackPath = fallbackInboxURL?.path ?? "<unavailable>"
    let fallbackCount = fallbackInboxURL.map { files(in: $0).count } ?? 0
    let transferItems = UIPasteboard.general.items.filter {
      $0[pasteboardDataType] != nil
    }.count
    return """
    \(extensionLog)

    --- MAIN APP CHECK ---
    transport=system-pasteboard-v3
    appGroup=\(resolvedAppGroup)
    groupInbox=\(groupPath)
    groupFiles=\(groupCount)
    fallbackInbox=\(fallbackPath)
    fallbackFiles=\(fallbackCount)
    transferPasteboardItems=\(transferItems)
    """
  }

  private static func clearShareDiagnostics() {
    UserDefaults.standard.removeObject(forKey: diagnosticsDefaultsKey)
    let systemPasteboard = UIPasteboard.general
    if systemPasteboard.items.contains(where: {
      $0[diagnosticsType] != nil && $0[pasteboardDataType] == nil
    }) {
      systemPasteboard.items = []
    }
    guard let pasteboard = UIPasteboard(
      name: diagnosticsPasteboardName,
      create: false
    ) else { return }
    pasteboard.items = []
  }

  private static func removeAcknowledgedFiles(_ paths: [String]) {
    let inboxes = [inboxURL, fallbackInboxURL].compactMap { $0 }
    guard !inboxes.isEmpty else { return }
    let inboxPaths = inboxes.map { $0.standardizedFileURL.path }
    let manager = FileManager.default
    for path in paths {
      let url = URL(fileURLWithPath: path).standardizedFileURL
      guard inboxPaths.contains(where: { url.path.hasPrefix($0 + "/") }) else {
        continue
      }
      try? manager.removeItem(at: url)
    }

    // Each share is stored in its own session folder. Remove empty sessions.
    for inbox in inboxes {
      if let children = try? manager.contentsOfDirectory(
        at: inbox,
        includingPropertiesForKeys: nil
      ) {
        for child in children {
          if (try? manager.contentsOfDirectory(atPath: child.path).isEmpty) == true {
            try? manager.removeItem(at: child)
          }
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

  private static func exportPdfWithAnnotations(
    sourcePath: String,
    outputPath: String,
    canvasWidth: Double,
    canvasHeight: Double,
    pages: [[String: Any]]
  ) throws -> String {
    guard canvasWidth > 0, canvasHeight > 0,
          let document = PDFDocument(url: URL(fileURLWithPath: sourcePath)) else {
      throw NSError(
        domain: "NoteErykPdfExport",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Không mở được PDF nguồn."]
      )
    }

    for pageData in pages {
      guard let pageNumber = (pageData["page"] as? NSNumber)?.intValue,
            let page = document.page(at: pageNumber - 1),
            let strokes = pageData["strokes"] as? [[String: Any]] else {
        continue
      }
      let bounds = page.bounds(for: .mediaBox)
      for stroke in strokes {
        guard let rawPoints = stroke["points"] as? [[String: Any]],
              !rawPoints.isEmpty else { continue }
        let path = UIBezierPath()
        for (index, rawPoint) in rawPoints.enumerated() {
          guard let x = (rawPoint["x"] as? NSNumber)?.doubleValue,
                let y = (rawPoint["y"] as? NSNumber)?.doubleValue else {
            continue
          }
          let pdfPoint = CGPoint(
            x: bounds.minX + CGFloat(x / canvasWidth) * bounds.width,
            y: bounds.maxY - CGFloat(y / canvasHeight) * bounds.height
          )
          if index == 0 {
            path.move(to: pdfPoint)
          } else {
            path.addLine(to: pdfPoint)
          }
        }
        guard !path.isEmpty else { continue }
        let annotation = PDFAnnotation(
          bounds: bounds,
          forType: .ink,
          withProperties: nil
        )
        let colorValue = (stroke["color"] as? NSNumber)?.uint32Value ?? 0xff20242b
        let alpha = CGFloat((colorValue >> 24) & 0xff) / 255.0
        let color = UIColor(
          red: CGFloat((colorValue >> 16) & 0xff) / 255.0,
          green: CGFloat((colorValue >> 8) & 0xff) / 255.0,
          blue: CGFloat(colorValue & 0xff) / 255.0,
          alpha: max(alpha, 0.05)
        )
        annotation.color = color
        let border = PDFBorder()
        let width = (stroke["width"] as? NSNumber)?.doubleValue ?? 2
        border.lineWidth = CGFloat(max(0.5, width * bounds.width / canvasWidth))
        annotation.border = border
        annotation.add(path)
        page.addAnnotation(annotation)
      }
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: nil
    )
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    guard document.write(to: outputURL) else {
      throw NSError(
        domain: "NoteErykPdfExport",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Không ghi được PDF đã chú thích."]
      )
    }
    return outputPath
  }
}

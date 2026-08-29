import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let fallbackAppGroup = "group.com.example.noteeryk"
  private let inboxName = "SharedInbox"
  private let pasteboardDataType = "com.example.noteeryk.shared-import.data"
  private let pasteboardFilenameType = "com.example.noteeryk.shared-import.filename"
  private let diagnosticsPasteboardName = UIPasteboard.Name(
    "com.example.noteeryk.share-diagnostics"
  )
  private let diagnosticsType = "com.example.noteeryk.share-diagnostics.text"
  private let acceptedExtensions = Set([
    "pdf", "doc", "docx", "jpg", "jpeg", "png", "webp", "gif", "heic", "heif"
  ])
  private var didStart = false
  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let finishButton = UIButton(type: .system)
  private var finishSucceeded = false
  private var finishMessage = ""
  private let diagnosticsLock = NSLock()
  private var diagnostics: [String] = []
  private let diagnosticsSession = UUID().uuidString.prefix(8)
  private var usesPasteboardFallback = false
  private var didPublishTransfer = false

  override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    recordDiagnostic("extension init")
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    recordDiagnostic("extension init(coder)")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    let bundleID = Bundle.main.bundleIdentifier ?? "<nil>"
    let bundleVersion = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleVersion"
    ) as? String ?? "<nil>"
    recordDiagnostic(
      "viewDidLoad · bundle=\(bundleID) · version=\(bundleVersion)"
    )
    view.backgroundColor = .systemBackground

    statusLabel.text = "Đang nhập vào Note Eryk…"
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0

    finishButton.configuration = .filled()
    finishButton.configuration?.cornerStyle = .large
    finishButton.isHidden = true
    finishButton.addTarget(
      self,
      action: #selector(closeExtension),
      for: .touchUpInside
    )

    spinner.startAnimating()
    let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, finishButton])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    recordDiagnostic("viewDidAppear")
    guard !didStart else { return }
    didStart = true
    stageAttachments()
  }

  @objc private func closeExtension() {
    recordDiagnostic("User closed extension · success=\(finishSucceeded)")
    if finishSucceeded {
      extensionContext?.completeRequest(returningItems: nil)
    } else {
      extensionContext?.cancelRequest(
        withError: NSError(
          domain: "NoteErykShareExtension",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: finishMessage]
        )
      )
    }
  }

  private func recordDiagnostic(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] [\(diagnosticsSession)] \(message)"
    NSLog("[NoteErykShare] %@", line)

    diagnosticsLock.lock()
    let isFirstDiagnostic = diagnostics.isEmpty
    diagnostics.append(line)
    if diagnostics.count > 120 {
      diagnostics.removeFirst(diagnostics.count - 120)
    }
    let payload = diagnostics.joined(separator: "\n")
    diagnosticsLock.unlock()

    let pasteboardName = diagnosticsPasteboardName
    let pasteboardType = diagnosticsType
    let persist = {
      guard let data = payload.data(using: .utf8) else { return }
      if let pasteboard = UIPasteboard(name: pasteboardName, create: true) {
        pasteboard.setData(data, forPasteboardType: pasteboardType)
      }
      if (self.usesPasteboardFallback || isFirstDiagnostic) && !self.didPublishTransfer {
        UIPasteboard.general.setItems(
          [[pasteboardType: data]],
          options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(15 * 60),
          ]
        )
      }
    }
    if Thread.isMainThread {
      persist()
    } else {
      DispatchQueue.main.sync(execute: persist)
    }
  }

  private func recordProviders(_ providers: [NSItemProvider]) {
    recordDiagnostic("Providers · count=\(providers.count)")
    for (index, provider) in providers.enumerated() {
      let name = provider.suggestedName ?? "<nil>"
      let types = provider.registeredTypeIdentifiers.joined(separator: ",")
      recordDiagnostic("Provider[\(index)] · name=\(name) · types=\(types)")
    }
  }

  private func stageAttachments() {
    let appGroup = resolvedAppGroup
    let sharedContainer = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroup
    )
    recordDiagnostic(
      "App Group · id=\(appGroup) · available=\(sharedContainer != nil)"
    )
    if sharedContainer == nil {
      usesPasteboardFallback = true
      recordDiagnostic("Using system-pasteboard fallback")
      stageAttachmentsUsingPasteboard()
      return
    }
    guard let container = sharedContainer else {
      finish(message: "Không truy cập được vùng chia sẻ của Note Eryk.", success: false)
      return
    }

    let session = container
      .appendingPathComponent(inboxName, isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: session,
        withIntermediateDirectories: true
      )
      recordDiagnostic("Created shared session · \(session.lastPathComponent)")
    } catch {
      recordDiagnostic("Create shared session failed · \(error.localizedDescription)")
      finish(message: "Không thể tạo thư mục nhập tệp.", success: false)
      return
    }

    // inputItems is exposed by UIKit as [Any]. Do not require the whole array
    // to bridge to [NSExtensionItem], otherwise one unexpected host item can
    // make the cast fail and silently produce an empty import.
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
    recordProviders(providers)
    let group = DispatchGroup()
    let lock = NSLock()
    var importedCount = 0

    for (index, provider) in providers.enumerated() {
      group.enter()
      stage(provider: provider, index: index, in: session) { success in
        if success {
          lock.lock()
          importedCount += 1
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      self.recordDiagnostic("Shared staging finished · imported=\(importedCount)")
      if importedCount == 0 {
        try? FileManager.default.removeItem(at: session)
        self.finish(message: "Tệp này chưa được hỗ trợ. Hãy chọn PDF hoặc ảnh.", success: false)
      } else {
        // Keep a second transport even when the extension can see an App
        // Group. Sideloadly may provision the extension and containing app
        // with different entitlements; the app can then recover this backup.
        let backupCount = self.publishToPasteboard(filesIn: session)
        self.recordDiagnostic("System pasteboard backup · files=\(backupCount)")
        self.finish(
          message: "Đã gửi \(importedCount) tệp vào Note Eryk.",
          success: true
        )
      }
    }
  }

  private func stageAttachmentsUsingPasteboard() {
    let session = FileManager.default.temporaryDirectory
      .appendingPathComponent(inboxName, isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: session,
        withIntermediateDirectories: true
      )
      recordDiagnostic("Created temporary session · \(session.lastPathComponent)")
    } catch {
      recordDiagnostic("Create temporary session failed · \(error.localizedDescription)")
      finish(message: "Không thể tạo vùng nhập tệp tạm thời.", success: false)
      return
    }

    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
    recordProviders(providers)
    let group = DispatchGroup()
    let lock = NSLock()
    var importedCount = 0
    for (index, provider) in providers.enumerated() {
      group.enter()
      stage(provider: provider, index: index, in: session) { success in
        if success {
          lock.lock()
          importedCount += 1
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self else { return }
      self.recordDiagnostic("Temporary staging finished · imported=\(importedCount)")
      let publishedCount = importedCount > 0
        ? self.publishToPasteboard(filesIn: session)
        : 0
      try? FileManager.default.removeItem(at: session)
      guard publishedCount > 0 else {
        self.finish(
          message: "Không thể chuyển tệp sang Note Eryk. Hãy chọn PDF hoặc ảnh rồi thử lại.",
          success: false
        )
        return
      }
      self.finish(
        message: "Đã gửi \(publishedCount) tệp vào Note Eryk.",
        success: true
      )
    }
  }

  /// The system pasteboard survives after the extension process exits. The
  /// custom item types distinguish this package from normal copied content and
  /// let free-provisioned builds work when App Groups have been stripped.
  private func publishToPasteboard(filesIn directory: URL) -> Int {
    guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
          ) else {
      recordDiagnostic("Pasteboard unavailable or session cannot be listed")
      return 0
    }

    let maximumPasteboardBytes = 32 * 1024 * 1024
    var totalBytes = 0
    var items: [[String: Any]] = []
    for file in files {
      guard acceptedExtensions.contains(file.pathExtension.lowercased()),
            let values = try? file.resourceValues(
              forKeys: [.isRegularFileKey, .fileSizeKey]
            ),
            values.isRegularFile == true else {
        continue
      }
      let fileBytes = values.fileSize ?? 0
      recordDiagnostic(
        "Pasteboard candidate · name=\(file.lastPathComponent) · bytes=\(fileBytes)"
      )
      guard fileBytes > 0,
            totalBytes + fileBytes <= maximumPasteboardBytes else {
        recordDiagnostic(
          "Pasteboard limit exceeded · max=\(maximumPasteboardBytes)"
        )
        return 0
      }
      guard let data = try? Data(contentsOf: file, options: .mappedIfSafe),
            let filename = file.lastPathComponent.data(using: .utf8) else {
        recordDiagnostic("Read for pasteboard failed · \(file.lastPathComponent)")
        return 0
      }
      items.append([
        pasteboardDataType: data,
        pasteboardFilenameType: filename,
      ])
      totalBytes += fileBytes
    }
    guard !items.isEmpty else {
      recordDiagnostic("No valid files to publish to pasteboard")
      return 0
    }
    recordDiagnostic("Publishing pasteboard · files=\(items.count) · bytes=\(totalBytes)")
    diagnosticsLock.lock()
    let diagnosticText = diagnostics.joined(separator: "\n")
    diagnosticsLock.unlock()
    if let diagnosticData = diagnosticText.data(using: .utf8) {
      items[0][diagnosticsType] = diagnosticData
    }
    didPublishTransfer = true
    UIPasteboard.general.setItems(
      items,
      options: [
        .localOnly: true,
        .expirationDate: Date().addingTimeInterval(15 * 60),
      ]
    )
    recordDiagnostic("Pasteboard publish completed")
    return items.count
  }

  /// Use the App Group actually granted by the provisioning profile. This
  /// remains correct when Sideloadly rewrites identifiers for a free team.
  private var resolvedAppGroup: String {
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
  private var provisionedAppGroups: [String] {
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

  private func stage(
    provider: NSItemProvider,
    index: Int,
    in directory: URL,
    completion: @escaping (Bool) -> Void
  ) {
    var candidates = provider.registeredTypeIdentifiers.filter {
      isSupportedTypeIdentifier($0)
    }
    let suggestedExtension = provider.suggestedName
      .map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
    if candidates.isEmpty,
       let suggestedExtension,
       acceptedExtensions.contains(suggestedExtension) {
      // Some Files providers advertise only public.data even though the
      // suggested filename clearly identifies a PDF, Word file, or image.
      candidates = provider.registeredTypeIdentifiers
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
      candidates.append(UTType.pdf.identifier)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      candidates.append(UTType.image.identifier)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      candidates.append(UTType.url.identifier)
    }
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      // A concrete data/file representation is more reliable than file-url.
      candidates.append(UTType.fileURL.identifier)
    }

    var seen = Set<String>()
    candidates = candidates.filter { seen.insert($0).inserted }
    candidates.sort { representationPriority($0) < representationPriority($1) }
    recordDiagnostic(
      "Stage[\(index)] candidates · \(candidates.joined(separator: ","))"
    )
    tryRepresentation(
      provider: provider,
      candidates: candidates,
      position: 0,
      index: index,
      in: directory,
      completion: completion
    )
  }

  private func representationPriority(_ identifier: String) -> Int {
    if identifier == UTType.fileURL.identifier { return 3 }
    if identifier == UTType.url.identifier { return 2 }
    return 1
  }

  private func isSupportedTypeIdentifier(_ identifier: String) -> Bool {
    if identifier == UTType.fileURL.identifier || identifier == UTType.url.identifier {
      return true
    }
    guard let type = UTType(identifier) else { return false }
    if type.conforms(to: .pdf) || type.conforms(to: .image) { return true }
    guard let ext = type.preferredFilenameExtension?.lowercased() else {
      return false
    }
    return acceptedExtensions.contains(ext)
  }

  private func tryRepresentation(
    provider: NSItemProvider,
    candidates: [String],
    position: Int,
    index: Int,
    in directory: URL,
    completion: @escaping (Bool) -> Void
  ) {
    guard position < candidates.count else {
      completion(false)
      return
    }
    let identifier = candidates[position]
    recordDiagnostic(
      "Stage[\(index)] attempt \(position + 1)/\(candidates.count) · \(identifier)"
    )
    let tryNext = { [weak self] in
      guard let self else { completion(false); return }
      self.tryRepresentation(
        provider: provider,
        candidates: candidates,
        position: position + 1,
        index: index,
        in: directory,
        completion: completion
      )
    }

    if identifier == UTType.fileURL.identifier || identifier == UTType.url.identifier {
      provider.loadItem(forTypeIdentifier: identifier, options: nil) {
        [weak self] item, error in
        guard let self else { completion(false); return }
        let source = (item as? URL)
          ?? (item as? NSURL).map { $0 as URL }
          ?? (item as? String).flatMap(URL.init(string:))
        guard let source else {
          self.recordDiagnostic(
            "Stage[\(index)] URL load failed · \(error?.localizedDescription ?? "no URL")"
          )
          tryNext()
          return
        }
        if source.isFileURL {
          guard self.copy(
            source: source,
            suggestedName: provider.suggestedName,
            fallbackExtension: nil,
            index: index,
            into: directory
          ) else {
            self.recordDiagnostic("Stage[\(index)] file URL copy failed")
            tryNext()
            return
          }
          self.recordDiagnostic("Stage[\(index)] file URL copied")
          completion(true)
          return
        }
        guard source.scheme == "https" || source.scheme == "http" else {
          tryNext()
          return
        }
        self.download(
          source: source,
          suggestedName: provider.suggestedName,
          index: index,
          into: directory
        ) { success in
          if success {
            completion(true)
          } else {
            tryNext()
          }
        }
      }
      return
    }

    let fallbackExtension = UTType(identifier)?.preferredFilenameExtension
    provider.loadFileRepresentation(forTypeIdentifier: identifier) {
      [weak self] source, fileError in
      guard let self else { completion(false); return }
      if let source,
         self.copy(
           source: source,
           suggestedName: provider.suggestedName,
           fallbackExtension: fallbackExtension,
           index: index,
           into: directory
         ) {
        self.recordDiagnostic("Stage[\(index)] file representation copied")
        completion(true)
        return
      }

      self.recordDiagnostic(
        "Stage[\(index)] file representation failed · \(fileError?.localizedDescription ?? "nil source")"
      )
      provider.loadDataRepresentation(forTypeIdentifier: identifier) {
        [weak self] data, dataError in
        guard let self else { completion(false); return }
        guard let data,
              self.write(
                data: data,
                suggestedName: provider.suggestedName,
                fallbackExtension: fallbackExtension,
                index: index,
                into: directory
              ) else {
          self.recordDiagnostic(
            "Stage[\(index)] data representation failed · \(dataError?.localizedDescription ?? "nil data/write failed")"
          )
          tryNext()
          return
        }
        self.recordDiagnostic("Stage[\(index)] data representation written")
        completion(true)
      }
    }
  }

  private func download(
    source: URL,
    suggestedName: String?,
    index: Int,
    into directory: URL,
    completion: @escaping (Bool) -> Void
  ) {
    recordDiagnostic("Download started · \(source.absoluteString)")
    var request = URLRequest(url: source)
    request.timeoutInterval = 30
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self else {
        completion(false)
        return
      }
      guard error == nil, let data, !data.isEmpty else {
        self.recordDiagnostic(
          "Download failed · \(error?.localizedDescription ?? "empty response")"
        )
        completion(false)
        return
      }
      if let http = response as? HTTPURLResponse,
         !(200...299).contains(http.statusCode) {
        self.recordDiagnostic("Download HTTP status · \(http.statusCode)")
        completion(false)
        return
      }
      let responseName = response?.suggestedFilename
      let urlName = source.lastPathComponent.removingPercentEncoding
      let name = responseName?.isEmpty == false
        ? responseName
        : (suggestedName?.isEmpty == false ? suggestedName : urlName)
      let mimeExtension = (response as? HTTPURLResponse)
        .flatMap { $0.mimeType }
        .flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
      let written = self.write(
        data: data,
        suggestedName: name,
        fallbackExtension: mimeExtension,
        index: index,
        into: directory
      )
      self.recordDiagnostic(
        "Download completed · bytes=\(data.count) · written=\(written)"
      )
      completion(written)
    }.resume()
  }

  private func copy(
    source: URL,
    suggestedName: String?,
    fallbackExtension: String?,
    index: Int,
    into directory: URL
  ) -> Bool {
    let hasAccess = source.startAccessingSecurityScopedResource()
    defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }

    guard let target = targetURL(
      sourceName: source.lastPathComponent,
      suggestedName: suggestedName,
      fallbackExtension: fallbackExtension,
      index: index,
      in: directory
    ) else { return false }
    do {
      try FileManager.default.copyItem(at: source, to: target)
      return true
    } catch {
      recordDiagnostic(
        "Copy failed · source=\(source.lastPathComponent) · \(error.localizedDescription)"
      )
      return false
    }
  }

  private func write(
    data: Data,
    suggestedName: String?,
    fallbackExtension: String?,
    index: Int,
    into directory: URL
  ) -> Bool {
    guard let target = targetURL(
      sourceName: suggestedName ?? "",
      suggestedName: suggestedName,
      fallbackExtension: fallbackExtension,
      index: index,
      in: directory
    ) else { return false }
    do {
      try data.write(to: target, options: .atomic)
      return true
    } catch {
      recordDiagnostic(
        "Write failed · target=\(target.lastPathComponent) · \(error.localizedDescription)"
      )
      return false
    }
  }

  private func targetURL(
    sourceName: String,
    suggestedName: String?,
    fallbackExtension: String?,
    index: Int,
    in directory: URL
  ) -> URL? {
    var name = sourceName
    let sourceExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
    if !acceptedExtensions.contains(sourceExtension),
       let suggestedName,
       !suggestedName.isEmpty {
      name = suggestedName
    }
    if URL(fileURLWithPath: name).pathExtension.isEmpty,
       let suggestedName,
       !suggestedName.isEmpty {
      name = suggestedName
    }
    if URL(fileURLWithPath: name).pathExtension.isEmpty,
       let fallbackExtension,
       !fallbackExtension.isEmpty {
      name += ".\(fallbackExtension)"
    }
    if name.isEmpty {
      name = "shared_\(index).\(fallbackExtension ?? "bin")"
    }
    name = name.replacingOccurrences(of: "/", with: "_")
    guard acceptedExtensions.contains(
      URL(fileURLWithPath: name).pathExtension.lowercased()
    ) else { return nil }

    var target = directory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: target.path) {
      let stem = target.deletingPathExtension().lastPathComponent
      let ext = target.pathExtension
      target = directory.appendingPathComponent("\(stem)_\(index).\(ext)")
    }
    return target
  }

  private func finish(message: String, success: Bool) {
    recordDiagnostic("Finish · success=\(success) · \(message)")
    spinner.stopAnimating()
    finishSucceeded = success
    finishMessage = message
    statusLabel.text = success
      ? "\(message)\nMở Note Eryk để hoàn tất nhập."
      : message
    statusLabel.textColor = success ? .label : .systemRed
    finishButton.configuration?.title = success ? "Xong" : "Đóng"
    finishButton.isHidden = false
  }
}

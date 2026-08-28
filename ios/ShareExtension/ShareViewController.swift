import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private let fallbackAppGroup = "group.com.example.noteeryk"
  private let inboxName = "SharedInbox"
  private let acceptedExtensions = Set([
    "pdf", "doc", "docx", "jpg", "jpeg", "png", "webp", "gif", "heic", "heif"
  ])
  private var didStart = false
  private let statusLabel = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground

    statusLabel.text = "Đang nhập vào Note Eryk…"
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0

    spinner.startAnimating()
    let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
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
    guard !didStart else { return }
    didStart = true
    stageAttachments()
  }

  private func stageAttachments() {
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: resolvedAppGroup
    ) else {
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
    } catch {
      finish(message: "Không thể tạo thư mục nhập tệp.", success: false)
      return
    }

    // inputItems is exposed by UIKit as [Any]. Do not require the whole array
    // to bridge to [NSExtensionItem], otherwise one unexpected host item can
    // make the cast fail and silently produce an empty import.
    let providers = (extensionContext?.inputItems ?? [])
      .compactMap { $0 as? NSExtensionItem }
      .flatMap { $0.attachments ?? [] }
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
      if importedCount == 0 {
        try? FileManager.default.removeItem(at: session)
        self.finish(message: "Tệp này chưa được hỗ trợ. Hãy chọn PDF hoặc ảnh.", success: false)
      } else {
        self.finish(
          message: "Đã gửi \(importedCount) tệp vào Note Eryk.",
          success: true
        )
      }
    }
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
    let typeIdentifier: String?
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      typeIdentifier = UTType.fileURL.identifier
    } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
      typeIdentifier = UTType.pdf.identifier
    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
      typeIdentifier = provider.registeredTypeIdentifiers.first {
        UTType($0)?.conforms(to: .image) == true
      } ?? UTType.image.identifier
    } else {
      typeIdentifier = nil
    }

    guard let typeIdentifier else {
      completion(false)
      return
    }

    if typeIdentifier == UTType.fileURL.identifier {
      provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) {
        [weak self] item, _ in
        guard let self else { completion(false); return }
        let source = (item as? URL) ?? (item as? NSURL).map { $0 as URL }
        guard let source else { completion(false); return }
        completion(self.copy(
          source: source,
          suggestedName: provider.suggestedName,
          fallbackExtension: nil,
          index: index,
          into: directory
        ))
      }
      return
    }

    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) {
      [weak self] source, _ in
      guard let self else { completion(false); return }
      if let source {
        let copied = self.copy(
          source: source,
          suggestedName: provider.suggestedName,
          fallbackExtension: UTType(typeIdentifier)?.preferredFilenameExtension,
          index: index,
          into: directory
        )
        if copied {
          completion(true)
          return
        }
      }

      // Some Files/Photos providers expose data but decline a temporary file
      // representation. Fall back to data loading so the Share button still
      // imports the item instead of appearing to do nothing.
      provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) {
        [weak self] data, _ in
        guard let self, let data else { completion(false); return }
        completion(self.write(
          data: data,
          suggestedName: provider.suggestedName,
          fallbackExtension: UTType(typeIdentifier)?.preferredFilenameExtension,
          index: index,
          into: directory
        ))
      }
    }
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
    spinner.stopAnimating()
    statusLabel.text = message
    statusLabel.textColor = success ? .label : .systemRed
    DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 1.2 : 2.5)) {
      if success {
        self.extensionContext?.completeRequest(returningItems: nil)
      } else {
        self.extensionContext?.cancelRequest(
          withError: NSError(
            domain: "NoteErykShareExtension",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
          )
        )
      }
    }
  }
}

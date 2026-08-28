import UIKit
import Security
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

    let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
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
      guard let self, let source else { completion(false); return }
      completion(self.copy(
        source: source,
        suggestedName: provider.suggestedName,
        fallbackExtension: UTType(typeIdentifier)?.preferredFilenameExtension,
        index: index,
        into: directory
      ))
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

    var name = source.lastPathComponent
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
      name = "shared_\(index).\(source.pathExtension)"
    }
    name = name.replacingOccurrences(of: "/", with: "_")
    guard acceptedExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()) else {
      return false
    }

    var target = directory.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: target.path) {
      let stem = target.deletingPathExtension().lastPathComponent
      let ext = target.pathExtension
      target = directory.appendingPathComponent("\(stem)_\(index).\(ext)")
    }
    do {
      try FileManager.default.copyItem(at: source, to: target)
      return true
    } catch {
      return false
    }
  }

  private func finish(message: String, success: Bool) {
    spinner.stopAnimating()
    statusLabel.text = message
    statusLabel.textColor = success ? .label : .systemRed
    DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.65 : 1.5)) {
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

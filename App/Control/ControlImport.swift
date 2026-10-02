import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// How pictures reach the Control tab: dropped files, the paste command, the file panel.
/// Failures are returned as words for the message bar, never thrown at the interface.
@MainActor
enum ControlImport {
  /// The first usable file of a drop. nil when it worked, the message when it did not.
  static func take(urls: [URL], into control: ControlStore) async -> String? {
    // A link from a browser is not a file: say so instead of doing nothing.
    guard let url = urls.first(where: { $0.isFileURL }) else {
      guard let link = urls.first else { return nil }
      return ControlText.error(.unreadable(link.lastPathComponent.isEmpty ? (link.host ?? link.absoluteString) : link.lastPathComponent))
    }
    do throws(ControlError) {
      try await control.setImage(fileURL: url)
      return nil
    } catch {
      return ControlText.error(error)
    }
  }

  /// What the paste command offers: a file copied in the Finder, or the picture itself.
  static func take(providers: [NSItemProvider], into control: ControlStore) async -> String? {
    if let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) {
      let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
      }
      // A copied image of a web page carries its link too: only a file is taken from the link,
      // the picture itself is read below otherwise.
      if let url, url.isFileURL { return await take(urls: [url], into: control) }
    }
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
      let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
          continuation.resume(returning: data)
        }
      }
      let name = String(localized: "control.pasted.name")
      guard let data else { return ControlText.error(.unreadable(name)) }
      do throws(ControlError) {
        try control.setImage(data: data, name: name, source: .pasteboard)
        return nil
      } catch {
        return ControlText.error(error)
      }
    }
    return nil
  }

  /// Every file of a drop is added to the Moodboard; the first problem is the message.
  static func takeMoodboard(urls: [URL], into control: ControlStore) async -> String? {
    var message: String?
    for url in urls {
      guard url.isFileURL else {
        message = message ?? ControlText.error(.unreadable(url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent))
        continue
      }
      do throws(ControlError) {
        try await control.addMoodboardImage(fileURL: url)
      } catch {
        message = message ?? ControlText.error(error)
      }
    }
    return message
  }

  /// A file dropped on a Moodboard picture takes its place.
  static func replaceMoodboard(id: UUID, urls: [URL], into control: ControlStore) async -> String? {
    guard let url = urls.first(where: { $0.isFileURL }) else {
      return await takeMoodboard(urls: urls, into: control)
    }
    do throws(ControlError) {
      try await control.replaceMoodboardImage(id: id, fileURL: url)
      return nil
    } catch {
      return ControlText.error(error)
    }
  }

  /// The file panel of "Add…" in the Moodboard: several files at once.
  static func chooseMoodboard(into control: ControlStore) async -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return nil }
    return await takeMoodboard(urls: panel.urls, into: control)
  }

  /// The file panel of "Choose…" and "Replace…".
  static func choose(into control: ControlStore) async -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return await take(urls: [url], into: control)
  }
}

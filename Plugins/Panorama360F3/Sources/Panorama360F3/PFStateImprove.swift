import CoreGraphics
import DTHubPluginKit
import Foundation
import ImageIO

extension PFState {
  /// Rewrites the description with the language model (`ask(prompt, system, pictures)` is the app's answer): only the description changes, and «Undo»
  /// brings back the one before. An Italian answer is asked again once; an answer that holds a trigger word or a reference is refused.
  func improve(using ask: @MainActor (String, String, [String]) async -> DTHubLLMAnswer) async {
    let original = doc.description
    // The pictures that are on go along, small; with pictures the text is only a guide and may be empty.
    let pictures = improvePictures()
    defer { for path in pictures { try? FileManager.default.removeItem(atPath: path) } }
    guard !pictures.isEmpty || !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      error = text(.emptyDescription)
      return
    }
    error = nil
    let folder = projectFolder
    isImproving = true
    defer { isImproving = false }
    var request = PFPrompt.request(description: original, imageCount: pictures.count)
    var answer = await ask(request.prompt, request.system, pictures)
    if case .text(let first) = answer, PFPrompt.looksItalian(PFPrompt.clean(first)) {
      request = PFPrompt.request(description: original, reminder: true, imageCount: pictures.count)
      answer = await ask(request.prompt, request.system, pictures)
    }
    // The answer comes after a wait: if the project or the text changed meanwhile it no longer fits and is dropped.
    guard projectFolder == folder, doc.description == original else {
      error = text(.improveStale)
      return
    }
    switch answer {
    case .failure(let reason):
      error = reason
    case .text(let raw):
      let improved = PFPrompt.clean(raw)
      if improved.isEmpty || PFPrompt.containsTrigger(improved) {
        error = text(.answerRejected)
      } else if PFPrompt.looksItalian(improved) {
        error = text(.answerNotEnglish)
      } else {
        previousDescription = original
        mutate { $0.description = improved }
      }
    }
  }

  /// The pictures that are on, reduced to 1024 px, as PNG files in the exchange folder; empty when none can be written.
  private func improvePictures() -> [String] {
    var paths: [String] = []
    try? FileManager.default.createDirectory(at: exchangeFolder, withIntermediateDirectories: true)
    for image in visibleImages {
      guard let url = imageURL(image), let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let small = CGImageSourceCreateThumbnailAtIndex(
          source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024] as CFDictionary),
        let data = PFPixels.pngData(small)
      else { continue }
      let file = exchangeFolder.appendingPathComponent("improve-\(UUID().uuidString).png")
      if (try? data.write(to: file)) != nil { paths.append(file.path) }
    }
    return paths
  }

  /// Puts back the description from before the last «Improve prompt» (once).
  func undoImprove() {
    guard let previous = previousDescription else { return }
    previousDescription = nil
    mutate { $0.description = previous }
  }
}

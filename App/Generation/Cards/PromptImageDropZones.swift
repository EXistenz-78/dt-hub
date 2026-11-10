import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// «Soggetto» and «Stile», beside Enhance Prompt: two places to drop a picture (from the gallery or from Finder). Dropping
/// it asks the language model at once, with the usual Generate Prompt request and the text of the prompt field; the picture is
/// not loaded anywhere else. Soggetto takes the subject, the setting and the action from the picture (the style comes from the
/// text); Stile takes the style from the picture (the subject comes from the text).
struct PromptImageDropZones: View {
  let controller: GenerationController
  /// A drop that held no picture.
  @Binding var notAnImage: Bool

  var body: some View {
    HStack(spacing: DS.controlGap) {
      PromptImageDropZone(
        title: String(localized: "prompt.drop.subject"), help: String(localized: "prompt.drop.subject.help"),
        systemImage: "person.crop.rectangle", focus: .subject, controller: controller,
        notAnImage: $notAnImage)
      PromptImageDropZone(
        title: String(localized: "prompt.drop.style"), help: String(localized: "prompt.drop.style.help"),
        systemImage: "paintpalette", focus: .style, controller: controller,
        notAnImage: $notAnImage)
    }
  }
}

private struct PromptImageDropZone: View {
  let title: String
  let help: String
  let systemImage: String
  let focus: DescribeFocus
  let controller: GenerationController
  @Binding var notAnImage: Bool
  @State private var isTargeted = false
  @State private var isRunning = false

  private var isBusy: Bool { controller.assistant.working != nil }

  var body: some View {
    HStack(spacing: 6) {
      if isRunning {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: systemImage)
      }
      Text(verbatim: title).font(.callout.weight(.semibold))
    }
    .foregroundStyle(isTargeted ? DS.accent : Color.secondary)
    .frame(maxWidth: .infinity, minHeight: 34)
    .background(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .fill(isTargeted ? DS.accent.opacity(0.12) : Color.primary.opacity(0.04)))
    .overlay(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(
          isTargeted ? DS.accent : Color.secondary.opacity(0.5),
          style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [5, 4])))
    .opacity(isBusy && !isRunning ? 0.5 : 1)
    .help(help)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityHint(help)
    .dropDestination(for: URL.self) { urls, _ in
      guard !isBusy else { return false }
      guard let picture = urls.first(where: Self.isPicture) else {
        notAnImage = true
        return false
      }
      notAnImage = false
      Task {
        isRunning = true
        await controller.promptFromImage(at: picture, focus: focus)
        isRunning = false
      }
      return true
    } isTargeted: { isTargeted = $0 }
  }

  private static func isPicture(_ url: URL) -> Bool {
    UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
  }
}

import AppKit
import HubCore
import HubKit
import LLMBridge
import SwiftUI
import UniformTypeIdentifiers

/// Preferences › LLM (spec §9): the models folder, the model in use, downloading the
/// recommended one (only when asked), the memory behavior, and a test question with or
/// without an image.
struct LanguagePreferencesView: View {
  @Bindable var manager: LanguageModelManager
  let download: LanguageModelDownloadController
  let connection: DrawThingsConnection

  @State private var models: [LanguageModelDescriptor] = []
  @State private var confirmingDownload = false
  /// A sample question, so the test can be tried at once.
  @State private var question = String(localized: "prefs.llm.test.sample")
  @State private var imageURL: URL?
  @State private var answer = ""
  @State private var asking = false
  @State private var askError: LanguageModelError?

  private var folderURL: URL { URL(fileURLWithPath: manager.settings.folder, isDirectory: true) }
  private var hasRecommended: Bool {
    models.contains { $0.name == RecommendedLanguageModel.folderName }
  }

  var body: some View {
    Form {
      folderSection
      memorySection
      testSection
    }
    .formStyle(.grouped)
    .onAppear(perform: refresh)
    .onChange(of: download.completed) { refresh() }
    .confirmationDialog(
      String(localized: "prefs.llm.download.confirm.title"), isPresented: $confirmingDownload, titleVisibility: .visible
    ) {
      Button("prefs.llm.download.confirm.button", action: startDownload)
    } message: {
      Text(
        String(
          format: String(localized: "prefs.llm.download.confirm.message"), RecommendedLanguageModel.repository,
          ByteCountFormatter.string(fromByteCount: RecommendedLanguageModel.approximateBytes, countStyle: .file),
          manager.settings.folder))
    }
  }

  // MARK: Folder and model

  private var folderSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.llm.folder", text: $manager.settings.folder)
          .onSubmit(refresh)
        Button("prefs.server.choose", action: chooseFolder)
      }
      if models.isEmpty {
        Text(String(format: String(localized: "prefs.llm.noModels"), manager.settings.folder))
          .foregroundStyle(.secondary)
      } else {
        Picker("prefs.llm.model", selection: $manager.settings.selectedModel) {
          Text("prefs.llm.model.none").tag("")
          ForEach(models) { model in
            Text(verbatim: label(of: model)).tag(model.path)
          }
        }
      }
      downloadRow
    } footer: {
      Text("prefs.llm.folder.note")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var downloadRow: some View {
    if let progress = download.progress {
      HStack(spacing: DS.controlGap) {
        ProgressView(value: progress)
        Button("prefs.llm.download.cancel") { download.cancel() }
      }
    } else if !hasRecommended {
      Button {
        confirmingDownload = true
      } label: {
        Text(
          String(
            format: String(localized: "prefs.llm.download.button"),
            ByteCountFormatter.string(fromByteCount: RecommendedLanguageModel.approximateBytes, countStyle: .file)))
      }
    }
    if let failure = download.failure {
      Text(String(format: String(localized: "prefs.llm.download.error"), LanguageModelErrorText.message(failure)))
        .foregroundStyle(DS.remove)
        .font(.caption)
    }
  }

  private func label(of model: LanguageModelDescriptor) -> String {
    let size = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
    return model.supportsImages
      ? String(format: String(localized: "prefs.llm.model.vision"), model.name, size) : "\(model.name) · \(size)"
  }

  private func refresh() {
    models = manager.availableModels()
    if !manager.settings.selectedModel.isEmpty, !models.contains(where: { $0.path == manager.settings.selectedModel }) {
      manager.settings.selectedModel = ""
    }
    if manager.settings.selectedModel.isEmpty, let first = models.first { manager.settings.selectedModel = first.path }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      manager.settings.folder = url.path
      refresh()
    }
  }

  /// Downloads the recommended model into `<folder>/mlx-community/…` (only after the user
  /// confirmed the dialog that names it, its size and where it goes). The download belongs to
  /// the app: it goes on if this window is closed.
  private func startDownload() {
    download.start(
      repository: RecommendedLanguageModel.repository,
      to: folderURL.appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true))
  }

  // MARK: Memory

  private var memorySection: some View {
    Section {
      Toggle("prefs.llm.freeAtRun", isOn: $manager.settings.freeAtRun)
      Toggle("prefs.llm.freeImageModel", isOn: $manager.settings.freeImageModelForLanguageModel)
        .disabled(connection.managed.mode != .managed)
      Stepper(
        value: $manager.settings.idleMinutes, in: LanguageModelSettings.idleRange, step: 5
      ) {
        Text(
          manager.settings.idleMinutes == 0
            ? String(localized: "prefs.llm.idle.never")
            : String(format: String(localized: "prefs.llm.idle"), manager.settings.idleMinutes))
      }
    } header: {
      Text("prefs.llm.memory")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if connection.managed.mode != .managed {
          Text("prefs.llm.freeImageModel.unavailable")
        } else if manager.settings.freeImageModelForLanguageModel {
          Text("prefs.llm.freeImageModel.cost")
        }
      }
      .foregroundStyle(.secondary)
    }
  }

  // MARK: Test

  private var testSection: some View {
    Section {
      TextField("prefs.llm.test.question", text: $question, axis: .vertical)
        .lineLimit(1...4)
      HStack(spacing: DS.controlGap) {
        Button("prefs.llm.test.image", action: chooseImage)
        if let imageURL {
          Text(verbatim: imageURL.lastPathComponent)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Button {
            self.imageURL = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(localized: "prefs.llm.test.removeImage"))
        }
        Spacer(minLength: DS.controlGap)
        Button("prefs.llm.test.ask", action: ask)
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      HStack(spacing: DS.controlGap) {
        if asking { ProgressView().controlSize(.small) }
        Text(verbatim: stateLine)
          .font(.caption)
          .foregroundStyle(askError == nil ? Color.secondary : DS.remove)
      }
      if !answer.isEmpty {
        Text(verbatim: answer)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } header: {
      Text("prefs.llm.test")
    }
  }

  private var stateLine: String {
    if let askError { return LanguageModelErrorText.message(askError) }
    switch manager.state {
    case .unloaded: return String(localized: "prefs.llm.state.unloaded")
    case .loading(let name): return String(format: String(localized: "prefs.llm.state.loading"), name)
    case .ready(let name): return String(format: String(localized: "prefs.llm.state.ready"), name)
    case .failed(let error): return LanguageModelErrorText.message(error)
    }
  }

  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK { imageURL = panel.url }
  }

  private func ask() {
    asking = true
    askError = nil
    answer = ""
    Task {
      do {
        answer = try await manager.respond(to: question, images: imageURL.map { [$0] } ?? [])
      } catch {
        askError = error as? LanguageModelError ?? .generationFailed(error.localizedDescription)
      }
      asking = false
    }
  }
}

/// The words for what went wrong with the language model.
/// The line under the Enhance/Generate Prompt buttons when an operation did not produce a prompt.
enum PromptAssistantText {
  static func message(_ failure: PromptAssistant.Failure) -> String {
    switch failure {
    case .model(let error): return LanguageModelErrorText.message(error)
    case .emptyPrompt: return String(localized: "prompt.assist.error.empty")
    case .noImage: return String(localized: "prompt.assist.error.noImage")
    case .emptyAnswer: return String(localized: "prompt.assist.error.noAnswer")
    }
  }
}

enum LanguageModelErrorText {
  static func message(_ error: any Error) -> String {
    guard let error = error as? LanguageModelError else { return error.localizedDescription }
    switch error {
    case .noModelSelected: return String(localized: "llm.error.noModel")
    case .imagesNotSupported: return String(localized: "llm.error.noImages")
    case .interrupted: return String(localized: "llm.error.interrupted")
    case .modelNotFound(let name): return String(format: String(localized: "llm.error.modelNotFound"), name)
    case .notEnoughMemory(let needed, let available):
      return String(
        format: String(localized: "llm.error.memory"), ByteCountFormatter.string(fromByteCount: needed, countStyle: .memory),
        ByteCountFormatter.string(fromByteCount: available, countStyle: .memory))
    case .loadFailed(let detail): return String(format: String(localized: "llm.error.load"), detail)
    case .generationFailed(let detail): return String(format: String(localized: "llm.error.generation"), detail)
    case .downloadFailed(let detail): return detail
    }
  }
}

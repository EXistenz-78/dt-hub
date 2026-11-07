import AppKit
import HubCore
import HubKit
import LLMBridge
import SwiftUI

/// Setup step › Language model (optional): LM Studio's server or a folder of MLX models, with the recommended model
/// downloadable. The family and use of each model stay in Preferences.
struct OnboardingLanguageStep: View {
  @Bindable var manager: LanguageModelManager
  let download: LanguageModelDownloadController

  @State private var models: [LanguageModelDescriptor] = []
  @State private var folderAccess: FolderAccess = .readable
  @State private var confirmingDownload = false
  @State private var serverAddress = ""
  @State private var addressInvalid = false
  @State private var serverStatus: String?

  private var folderURL: URL { URL(fileURLWithPath: manager.settings.folder, isDirectory: true) }
  private var hasRecommended: Bool { models.contains { $0.name == RecommendedLanguageModel.folderName } }

  var body: some View {
    Form {
      Section {
        Text("onboarding.language.intro").foregroundStyle(.secondary)
        Picker("prefs.llm.backend", selection: $manager.settings.backend) {
          Text("prefs.llm.backend.folder").tag(LanguageModelBackend.folder)
          Text("prefs.llm.backend.lmStudio").tag(LanguageModelBackend.lmStudio)
        }
        .pickerStyle(.segmented)
      }
      if manager.settings.backend == .folder { folderSection } else { serverSection }
    }
    .formStyle(.grouped)
    .onAppear {
      serverAddress = manager.settings.serverURL
      reload()
    }
    .onChange(of: manager.settings.backend) { reload() }
    .onChange(of: download.completed) {
      manager.reconcileAssignments(downloaded: RecommendedLanguageModel.folderName)
      models = manager.availableModels()
    }
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

  // MARK: LM Studio

  private var serverSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.llm.server.address", text: $serverAddress)
          .onSubmit(applyAddress)
        Button("prefs.llm.server.test", action: testServer)
      }
      if addressInvalid {
        Text("prefs.llm.server.invalid").foregroundStyle(DS.remove)
      }
      if let serverStatus {
        Text(verbatim: serverStatus).font(.caption)
          .foregroundStyle(manager.serverError == nil ? Color.secondary : DS.remove)
      } else if let error = manager.serverError {
        Text(verbatim: LanguageModelErrorText.message(error)).font(.caption).foregroundStyle(DS.remove)
      }
      if models.isEmpty, manager.serverError == nil {
        Text("prefs.llm.server.noModels").foregroundStyle(.secondary)
      }
      ForEach(models) { model in Text(verbatim: model.name) }
    } footer: {
      Text("prefs.llm.server.note").foregroundStyle(.secondary)
    }
  }

  private func applyAddress() {
    guard let url = LMStudioAddress.validated(serverAddress) else {
      addressInvalid = true
      return
    }
    addressInvalid = false
    serverAddress = url.absoluteString
    manager.settings.serverURL = url.absoluteString
    reload()
  }

  private func testServer() {
    applyAddress()
    guard !addressInvalid else { return }
    Task {
      await manager.refreshServerModels()
      models = manager.availableModels()
      serverStatus =
        manager.serverError == nil
        ? String(format: String(localized: "prefs.llm.server.connected"), manager.serverModels.count) : nil
    }
  }

  // MARK: Folder of MLX models

  private var folderSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.llm.folder", text: $manager.settings.folder)
          .onSubmit(refresh)
        Button("prefs.server.choose", action: chooseFolder)
      }
      if models.isEmpty {
        switch folderAccess {
        case .missing:
          Text("prefs.llm.folder.missing").foregroundStyle(.secondary)
        case .denied:
          Text("prefs.folder.denied").foregroundStyle(DS.remove)
          PrivacySettingsLink()
        case .readable:
          Text(String(format: String(localized: "prefs.llm.noModels"), manager.settings.folder))
            .foregroundStyle(.secondary)
        }
      } else {
        ForEach(models) { model in Text(verbatim: model.name) }
      }
      downloadRow
    } footer: {
      Text("prefs.llm.folder.note").foregroundStyle(.secondary)
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
      if case .folderNotWritable = failure {
        Text(String(format: String(localized: "llm.download.noWritePermission"), manager.settings.folder))
          .foregroundStyle(DS.remove).font(.caption)
        PrivacySettingsLink()
      } else {
        Text(String(format: String(localized: "prefs.llm.download.error"), LanguageModelErrorText.message(failure)))
          .foregroundStyle(DS.remove).font(.caption)
      }
    }
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

  /// Only after the user confirmed the dialog that names the model, its size and where it goes.
  private func startDownload() {
    download.start(
      repository: RecommendedLanguageModel.repository,
      to: folderURL.appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true))
  }

  private func reload() {
    refresh()
    Task {
      await manager.refreshServerModels()
      refresh()
    }
  }

  private func refresh() {
    manager.reconcileAssignments()
    models = manager.availableModels()
    folderAccess = FolderAccess.access(of: manager.settings.folder)
  }
}

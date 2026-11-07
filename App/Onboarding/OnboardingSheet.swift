import HubCore
import HubKit
import SwiftUI

/// The first-launch setup: title, the steps, the step on screen and Back / Skip / Next. Closing it in any way
/// (Start, Skip, Esc) goes through `OnboardingState.finish()`.
struct OnboardingSheet: View {
  let state: OnboardingState
  let connection: DrawThingsConnection
  let generation: GenerationController
  let languageModel: LanguageModelManager
  let download: LanguageModelDownloadController
  let projects: ProjectManager

  @State private var server: OnboardingServerDraft
  @State private var isAdvancing = false

  init(
    state: OnboardingState, connection: DrawThingsConnection, generation: GenerationController,
    languageModel: LanguageModelManager, download: LanguageModelDownloadController, projects: ProjectManager
  ) {
    self.state = state
    self.connection = connection
    self.generation = generation
    self.languageModel = languageModel
    self.download = download
    self.projects = projects
    _server = State(initialValue: OnboardingServerDraft(connection: connection))
  }

  private var step: OnboardingStep { state.flow.step }

  /// Next is held back on the server step until one server is set up.
  private var canGoNext: Bool {
    !isAdvancing && (step != .server || server.plan.canAdvance)
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
    }
    .frame(width: 600, height: 620)
    .background(DSBackground())
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("onboarding.title").font(.title3.bold())
      HStack(spacing: 6) {
        ForEach(OnboardingStep.allCases, id: \.self) { item in
          Capsule()
            .fill(item.rawValue <= step.rawValue ? DS.accent : Color.secondary.opacity(0.25))
            .frame(height: 4)
        }
      }
      Text(stepTitle(step)).font(.caption).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }

  @ViewBuilder private var content: some View {
    switch step {
    case .welcome: OnboardingWelcomeStep()
    case .server: OnboardingServerStep(connection: connection, draft: server)
    case .output: OnboardingOutputStep(controller: generation, projects: projects)
    case .language: OnboardingLanguageStep(manager: languageModel, download: download)
    case .done:
      OnboardingDoneStep(
        connection: connection, controller: generation, manager: languageModel, onStart: { state.finish() })
    }
  }

  private var footer: some View {
    HStack(spacing: DS.controlGap) {
      if !state.flow.isFirst {
        Button("onboarding.back") { state.flow.back() }
          .buttonStyle(DSPillButtonStyle())
      }
      Spacer(minLength: 0)
      if !state.flow.isLast {
        Button("onboarding.skip") { state.finish() }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        Button("onboarding.next") { Task { await advance() } }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(!canGoNext)
      }
    }
    .padding(16)
  }

  /// Leaving the server step applies what was typed, if it changed since Connect.
  private func advance() async {
    isAdvancing = true
    if step == .server { await server.applyIfNeeded() }
    state.flow.next()
    isAdvancing = false
  }

  private func stepTitle(_ step: OnboardingStep) -> LocalizedStringKey {
    switch step {
    case .welcome: "onboarding.step.welcome"
    case .server: "onboarding.step.server"
    case .output: "onboarding.step.output"
    case .language: "onboarding.step.language"
    case .done: "onboarding.step.done"
    }
  }
}

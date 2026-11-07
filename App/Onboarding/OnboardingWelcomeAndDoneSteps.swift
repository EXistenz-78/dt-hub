import HubCore
import HubKit
import SwiftUI

/// Setup step › Welcome: what the next steps are for.
struct OnboardingWelcomeStep: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("onboarding.welcome.headline").font(.title2.bold())
      Text("onboarding.welcome.body").foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }
}

/// Setup step › Done: what was set up, and the button that closes the sheet.
struct OnboardingDoneStep: View {
  let connection: DrawThingsConnection
  let controller: GenerationController
  let manager: LanguageModelManager
  let onStart: () -> Void

  var body: some View {
    Form {
      Section {
        LabeledContent(String(localized: "onboarding.step.server")) {
          HStack(spacing: 6) {
            DSStatusDot(status: connection.indicator)
            Text(connection.managed.mode == .managed ? "onboarding.done.server.managed" : "onboarding.done.server.attach")
          }
        }
        LabeledContent(String(localized: "onboarding.step.output")) {
          Text(verbatim: controller.outputFolder.path).lineLimit(2).truncationMode(.middle)
        }
        LabeledContent(String(localized: "onboarding.step.language")) {
          Text(manager.availableModels().isEmpty ? "onboarding.done.language.none" : "onboarding.done.language.ready")
        }
      } footer: {
        Text("onboarding.done.note").foregroundStyle(.secondary)
      }
      Section {
        HStack {
          Spacer(minLength: 0)
          Button("onboarding.finish", action: onStart)
            .buttonStyle(DSPillButtonStyle(prominent: true))
            .keyboardShortcut(.defaultAction)
        }
      }
    }
    .formStyle(.grouped)
  }
}

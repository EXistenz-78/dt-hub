import HubCore
import HubKit
import SwiftUI

/// Preferences › Updates: the version in use, the check at launch, «Controlla ora» and what is on offer.
struct UpdatesPreferencesView: View {
  @Bindable var controller: UpdateController
  @State private var showsDetails = false

  private var isChecking: Bool { controller.state == .checking }

  var body: some View {
    Form {
      Section {
        Text(verbatim: String(format: String(localized: "updates.prefs.current"), controller.appVersion))
        Text(
          verbatim: String(
            format: String(localized: "updates.prefs.lastCheck"),
            controller.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) }
              ?? String(localized: "updates.prefs.never"))
        )
        .foregroundStyle(.secondary)
        Toggle("updates.prefs.checkOnLaunch", isOn: $controller.checkOnLaunchEnabled)
        HStack(spacing: DS.controlGap) {
          if let message = controller.message.flatMap(UpdateText.message) {
            Text(verbatim: message).foregroundStyle(.secondary)
          }
          Spacer(minLength: 0)
          Button(isChecking ? "updates.prefs.checking" : "updates.prefs.checkNow") {
            Task { await controller.checkNow() }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(isChecking)
        }
      } footer: {
        Text("updates.prefs.note").foregroundStyle(.secondary)
      }
      if !controller.offers.isEmpty {
        Section("updates.prefs.available") {
          ForEach(controller.offers) { offer in
            HStack {
              Text(verbatim: offer.item.name)
              Spacer(minLength: DS.controlGap)
              Text(verbatim: "\(offer.installed) → \(offer.item.version)").foregroundStyle(.secondary)
            }
          }
          HStack {
            Spacer(minLength: 0)
            Button("updates.details") { showsDetails = true }
              .buttonStyle(DSPillButtonStyle(prominent: true))
          }
        }
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $showsDetails) { UpdateDetailsSheet(controller: controller) }
  }
}

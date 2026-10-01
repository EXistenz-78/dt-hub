import HubCore
import HubKit
import SwiftUI

/// Under the header when the managed server could not start or ended without being asked
/// (spec §10): what happened, with Restart and a way to the Preferences.
struct ManagedServerBanner: View {
  let connection: DrawThingsConnection
  @State private var restarting = false

  var body: some View {
    if connection.managed.mode == .managed, let problem = ManagedServerText.problem(connection.managedServer.state) {
      HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(DS.remove)
          .accessibilityHidden(true)
        Text(problem)
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: DS.controlGap)
        Button {
          Task {
            restarting = true
            await connection.restartManagedServer()
            restarting = false
          }
        } label: {
          Text("server.restart")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .disabled(restarting)
        SettingsLink {
          Text("server.preferences")
        }
        .buttonStyle(DSPillButtonStyle())
      }
      .padding(DS.boxPadding)
      .background(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(DS.remove.opacity(0.10)))
      .overlay(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .strokeBorder(DS.remove.opacity(0.35), lineWidth: 1))
    }
  }
}

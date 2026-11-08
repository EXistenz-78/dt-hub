import HubMCP
import Observation
import SwiftUI

/// The one question an agent's request can raise (spec 2026-11-08 §6): shown as a sheet, answered by the user. The
/// wait ends when the gate gives up (the time is up): `ask` returns promptly when its task is cancelled.
@MainActor
@Observable
final class ConsentCoordinator: ConsentPrompter {
  struct Pending: Identifiable, Equatable {
    let id = UUID()
    let summary: String
  }

  var pending: Pending?
  /// Called when the user allows and also authorises the session.
  @ObservationIgnored var onAuthoriseSession: (() -> Void)?
  @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?

  func ask(_ summary: String, timeoutSeconds: Int) async -> Bool {
    resolve(false)
    pending = Pending(summary: summary)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (next: CheckedContinuation<Bool, Never>) in
        continuation = next
        if Task.isCancelled { resolve(false) }
      }
    } onCancel: {
      Task { @MainActor in self.resolve(false) }
    }
  }

  func resolve(_ allow: Bool, authoriseSession: Bool = false) {
    pending = nil
    guard let next = continuation else { return }
    continuation = nil
    if allow && authoriseSession { onAuthoriseSession?() }
    next.resume(returning: allow)
  }
}

/// The sheet that asks.
struct RemoteConsentModifier: ViewModifier {
  let coordinator: ConsentCoordinator

  func body(content: Content) -> some View {
    @Bindable var coordinator = coordinator
    content.sheet(item: $coordinator.pending, onDismiss: { coordinator.resolve(false) }) { pending in
      VStack(alignment: .leading, spacing: 14) {
        Text(String(format: String(localized: "remote.consent.title"), pending.summary)).font(.headline)
        HStack {
          Spacer()
          Button(String(localized: "remote.consent.refuse"), role: .cancel) { coordinator.resolve(false) }
          Button(String(localized: "remote.consent.allowSession")) { coordinator.resolve(true, authoriseSession: true) }
          Button(String(localized: "remote.consent.allow")) { coordinator.resolve(true) }.keyboardShortcut(.defaultAction)
        }
      }
      .padding(20)
      .frame(minWidth: 420)
    }
  }
}

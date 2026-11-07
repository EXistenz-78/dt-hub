import HubCore
import Observation
import SwiftUI

/// The first-launch setup sheet: whether it is on screen and which step it shows. Closing it in any way (Start, Skip,
/// Esc) remembers that the setup was seen, so it does not come back by itself; the Help menu opens it again.
@MainActor
@Observable
final class OnboardingState {
  var flow = OnboardingFlow()
  var isPresented = false

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// Shows the setup on a clean install, once.
  func presentIfFirstLaunch() {
    guard flow.isFirst, !isPresented else { return }
    isPresented = OnboardingGate.shouldShow(defaults: defaults)
  }

  /// From the Help menu: starts again from the welcome step, whatever the flag says.
  func reopen() {
    flow = OnboardingFlow()
    isPresented = true
  }

  func finish() {
    OnboardingGate.markCompleted(defaults: defaults)
    isPresented = false
    flow = OnboardingFlow()
  }
}

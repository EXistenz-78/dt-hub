import HubCore

/// The words for the managed server's state, shared by the Preferences and the banner.
enum ManagedServerText {
  /// One line saying what is wrong; nil when nothing is.
  static func problem(_ state: ManagedServer.State) -> String? {
    switch state {
    case .stopped, .running: nil
    case .failedToStart(let failure): headline(failure)
    case .exitedUnexpectedly(let exit):
      exit.bySignal
        ? String(format: String(localized: "server.exited.signal"), Int(exit.status))
        : String(format: String(localized: "server.exited.code"), Int(exit.status))
    }
  }

  static func headline(_ failure: ManagedServer.Failure) -> String {
    switch failure {
    case .settings(let error): headline(error)
    case .portInUse(let port): String(format: String(localized: "server.error.portInUse"), port)
    case .launchFailed(let detail): String(format: String(localized: "server.error.launchFailed"), detail)
    }
  }

  static func headline(_ error: ManagedServerSettings.ValidationError) -> String {
    switch error {
    case .noBinary: String(localized: "server.error.noBinary")
    case .binaryNotExecutable: String(localized: "server.error.binaryNotExecutable")
    case .noModelsFolder: String(localized: "server.error.noModelsFolder")
    case .modelsFolderMissing: String(localized: "server.error.modelsFolderMissing")
    case .invalidPort: String(localized: "server.error.invalidPort")
    }
  }

  /// What the Preferences say about a server that is not in trouble.
  static func status(_ state: ManagedServer.State) -> String {
    switch state {
    case .stopped: String(localized: "server.state.stopped")
    case .running: String(localized: "server.state.running")
    case .failedToStart, .exitedUnexpectedly: problem(state) ?? ""
    }
  }
}

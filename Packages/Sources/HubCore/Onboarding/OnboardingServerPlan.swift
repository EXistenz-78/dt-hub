/// The rules of the server step: Draw Things already running, the gRPCServerCLI DT Hub starts, or both. At least one
/// must be set up to go on.
public struct OnboardingServerPlan: Sendable {
  public let attach: ConnectionSettings
  /// True once the user pressed Connect: the default settings are always valid, so they do not count before that.
  public let attachConfirmed: Bool
  public let managed: ManagedServerSettings
  public let files: FileSystemProbe
  /// Which one to use when both are set up.
  public let choice: ServerMode

  public init(
    attach: ConnectionSettings, attachConfirmed: Bool, managed: ManagedServerSettings,
    files: FileSystemProbe = .live, choice: ServerMode = .attach
  ) {
    self.attach = attach
    self.attachConfirmed = attachConfirmed
    self.managed = managed
    self.files = files
    self.choice = choice
  }

  public var attachConfigured: Bool { attachConfirmed && attach.validationError == nil }
  public var managedConfigured: Bool { managed.validationError(files) == nil }
  public var canAdvance: Bool { attachConfigured || managedConfigured }
  public var needsChoice: Bool { attachConfigured && managedConfigured }

  /// The mode to apply, nil while nothing is set up.
  public var resolvedMode: ServerMode? {
    switch (attachConfigured, managedConfigured) {
    case (true, true): choice
    case (true, false): .attach
    case (false, true): .managed
    case (false, false): nil
    }
  }
}

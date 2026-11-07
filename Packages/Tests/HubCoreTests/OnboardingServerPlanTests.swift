import Testing

@testable import HubCore

struct OnboardingServerPlanTests {
  let files = FileSystemProbe(
    isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" })

  private func managed(binary: String = "", folder: String = "") -> ManagedServerSettings {
    ManagedServerSettings(mode: .attach, binaryPath: binary, modelsFolder: folder)
  }

  private func plan(
    attachConfirmed: Bool = false, managed: ManagedServerSettings, choice: ServerMode = .attach
  ) -> OnboardingServerPlan {
    OnboardingServerPlan(
      attach: .default, attachConfirmed: attachConfirmed, managed: managed, files: files, choice: choice)
  }

  @Test func nothingConfiguredBlocksAdvancing() {
    let plan = plan(managed: managed())
    #expect(!plan.canAdvance)
    #expect(plan.resolvedMode == nil)
  }

  @Test func theDefaultAttachSettingsAreValidButDoNotCountUntilConfirmed() {
    #expect(!plan(attachConfirmed: false, managed: managed()).attachConfigured)
  }

  @Test func aConfirmedAttachAloneAdvancesWithAttach() {
    let plan = plan(attachConfirmed: true, managed: managed())
    #expect(plan.canAdvance)
    #expect(!plan.needsChoice)
    #expect(plan.resolvedMode == .attach)
  }

  @Test func aValidCLIAloneAdvancesWithManaged() {
    let plan = plan(managed: managed(binary: "/bin/cli", folder: "/models"))
    #expect(plan.canAdvance)
    #expect(!plan.needsChoice)
    #expect(plan.resolvedMode == .managed)
  }

  @Test func bothConfiguredAsksAndFollowsTheChoice() {
    let both = managed(binary: "/bin/cli", folder: "/models")
    let attach = plan(attachConfirmed: true, managed: both, choice: .attach)
    let cli = plan(attachConfirmed: true, managed: both, choice: .managed)
    #expect(attach.needsChoice && cli.needsChoice)
    #expect(attach.resolvedMode == .attach)
    #expect(cli.resolvedMode == .managed)
  }

  @Test func aCLIWithANonExecutableBinaryDoesNotCount() {
    let plan = plan(managed: managed(binary: "/nowhere/cli", folder: "/models"))
    #expect(!plan.managedConfigured)
    #expect(!plan.canAdvance)
  }
}

import Foundation
import Testing

@testable import HubCore

struct ManagedServerSettingsTests {
  let files = FileSystemProbe(
    isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" })

  @Test func theDefaultIsAttachingToARunningServer() {
    #expect(ManagedServerSettings.default.mode == .attach)
    #expect(ManagedServerSettings.default.port == 7860)
  }

  @Test func reportsWhatIsMissingInOrder() {
    var settings = ManagedServerSettings(mode: .managed)
    #expect(settings.validationError(files) == .noBinary)
    settings.binaryPath = "/nowhere/cli"
    #expect(settings.validationError(files) == .binaryNotExecutable)
    settings.binaryPath = "/bin/cli"
    #expect(settings.validationError(files) == .noModelsFolder)
    settings.modelsFolder = "/missing"
    #expect(settings.validationError(files) == .modelsFolderMissing)
    settings.modelsFolder = "/models"
    #expect(settings.validationError(files) == nil)
    settings.port = 80
    #expect(settings.validationError(files) == .invalidPort)
    settings.port = 70000
    #expect(settings.validationError(files) == .invalidPort)
  }

  @Test func warnsWhenTheModelsFolderHoldsNoModelFiles() {
    let empty = FileSystemProbe(
      isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" }, hasModelFiles: { _ in false })
    let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models")
    #expect(settings.validationError(empty) == nil)
    #expect(settings.warning(empty) == .noModelFiles)
    #expect(settings.warning(files) == nil)
  }

  @Test func noWarningWhileSomethingElseIsWrong() {
    let empty = FileSystemProbe(isExecutableFile: { _ in false }, isDirectory: { _ in true }, hasModelFiles: { _ in false })
    #expect(ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models").warning(empty) == nil)
  }

  @Test func spacesAroundThePathsAreIgnored() {
    let settings = ManagedServerSettings(binaryPath: " /bin/cli ", modelsFolder: " /models\n")
    #expect(settings.validationError(files) == nil)
  }

  @Test func settingsSurviveARoundTripAndOldFilesLoad() throws {
    let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models", port: 7861)
    let decoded = try JSONDecoder().decode(ManagedServerSettings.self, from: JSONEncoder().encode(settings))
    #expect(decoded == settings)
    #expect(try JSONDecoder().decode(ManagedServerSettings.self, from: Data("{}".utf8)) == .default)
    #expect(try JSONDecoder().decode(ManagedServerSettings.self, from: Data(#"{"mode": "other"}"#.utf8)).mode == .attach)
  }

  @Test func theStoreRemembersAndFallsBackToTheDefault() {
    let defaults = UserDefaults(suiteName: "ManagedServerSettingsTests-\(UUID())")!
    let store = ManagedServerSettingsStore(defaults: defaults)
    #expect(store.load() == .default)
    let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models", port: 7861)
    store.save(settings)
    #expect(store.load() == settings)
    defaults.set(Data("garbage".utf8), forKey: ManagedServerSettingsStore.key)
    #expect(store.load() == .default)
  }
}

struct CLILocatorTests {
  @Test func findsTheFirstInstalledCandidate() {
    let home = "/Users/me"
    let installed: Set<String> = ["/usr/local/bin/gRPCServerCLI-macOS", "/opt/homebrew/bin/gRPCServerCLI-macOS"]
    let files = FileSystemProbe(isExecutableFile: { installed.contains($0) }, isDirectory: { _ in false })
    #expect(CLILocator.find(home: home, files: files) == "/opt/homebrew/bin/gRPCServerCLI-macOS")
  }

  @Test func prefersTheUsersApplicationsFolder() {
    let home = "/Users/me"
    let files = FileSystemProbe(isExecutableFile: { _ in true }, isDirectory: { _ in false })
    #expect(CLILocator.find(home: home, files: files) == "/Users/me/Applications/DrawThings-CLI/gRPCServerCLI-macOS")
  }

  @Test func findsNothingWhenItIsNotInstalled() {
    let files = FileSystemProbe(isExecutableFile: { _ in false }, isDirectory: { _ in false })
    #expect(CLILocator.find(home: "/Users/me", files: files) == nil)
  }
}

struct ServerArgumentsTests {
  let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/Volumes/Models", port: 7861)

  @Test func theServerListensOnThisMacOnly() {
    let arguments = ServerArguments.make(settings)
    let address = arguments.firstIndex(of: "--address").map { arguments[$0 + 1] }
    #expect(address == "127.0.0.1")
  }

  @Test func theModelsFolderIsTheFirstArgumentAndModelBrowsingIsOn() {
    let arguments = ServerArguments.make(settings)
    #expect(arguments.first == "/Volumes/Models")
    #expect(arguments.contains("--model-browser"))
    #expect(arguments.firstIndex(of: "--port").map { arguments[$0 + 1] } == "7861")
  }

  @Test func noSecretGoesOnTheCommandLine() {
    let arguments = ServerArguments.make(settings)
    #expect(!arguments.contains("--shared-secret"))
    #expect(!arguments.contains("-s"))
    #expect(!arguments.contains("--no-tls"))
  }
}

# M5 Server gestito — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DT Hub funziona senza l'app Draw Things aperta: nelle Preferenze si sceglie "Avvia gRPCServerCLI", e DT Hub avvia il server all'apertura, lo ferma alla chiusura, avvisa se si chiude da solo (con "Riavvia") e chiude un server rimasto aperto da una sessione finita male.

**Architecture:**
- **HubCore** riceve il modulo `Server`:
  - impostazioni (`ManagedServerSettings`), ricerca del programma (`CLILocator`), riga di comando (`ServerArguments`);
  - `ManagedServer`, che gestisce il processo tramite il protocollo `ProcessLauncher` (provato con un lanciatore finto; il vero usa `Process`);
  - il controllo della porta (`PortProbe`) e il file con l'id del processo (`ServerPidFile`).
- **L'app** aggiunge:
  - alla connessione, la modalità gestita (indirizzo 127.0.0.1, la porta scelta, senza segreto);
  - alle Preferenze, la scelta della modalità e i campi del server;
  - un avviso sotto l'header;
  - il pallino giallo "server in avvio";
  - l'arresto del server all'uscita.
- **DTBridge non cambia:** il server gestito è un normale server gRPC.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, Foundation `Process`.

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 5, 7, 10, 12, 15-M5).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m5-server-gestito` da `main`;
  - macOS 26, Swift 6, Xcode 27.
- **gRPCServerCLI resta fuori dal pacchetto (deciso con l'utente, 1 ottobre 2026):**
  - DT Hub lo avvia solo se è installato;
  - lo cerca nel percorso scelto dall'utente e, per proporlo, in `~/Applications/DrawThings-CLI/`, `~/Applications/`, `/opt/homebrew/bin`, `/usr/local/bin` (nomi `gRPCServerCLI-macOS` e `gRPCServerCLI`);
  - non scarica nulla: se manca, le Preferenze mostrano un link alla pagina delle release di Draw Things (`github.com/drawthingsai/draw-things-community/releases`);
  - motivi: aggiornamenti legati alle versioni di Draw Things, licenza di ridistribuzione non verificata, peso (~250 MB).
- **Riga di comando (verificata con `--help`, v26.0928.0), nell'ordine:**
  - la cartella dei modelli;
  - `--address 127.0.0.1`: il predefinito del programma, `0.0.0.0`, offrirebbe il server a tutta la rete locale (la spec dice "solo locale");
  - `--port <porta>`;
  - `--model-browser`: senza, DT Hub non vede i modelli.
  - **Mai** `--shared-secret` (sulla riga di comando lo leggerebbe qualunque programma) né `--no-tls`.
- **Connessione in modalità gestita:** host `127.0.0.1`, la porta scelta (predefinita **7860**, accanto alla 7859 dell'app Draw Things), TLS acceso, nessun segreto. La modalità "collegati a un server già attivo" resta com'è (indirizzo, porta, TLS, segreto).
- **Avvio e arresto (spec §5):**
  - all'apertura dell'app, se la modalità è gestita, il server parte;
  - "Collega" nelle Preferenze applica le impostazioni e (ri)avvia;
  - all'uscita dell'app il server si ferma (SIGTERM, poi SIGKILL dopo 3 s);
  - passando alla modalità "server già attivo" il server gestito si ferma.
- **Uscita inattesa (spec §10):** avviso sotto l'header con "Riavvia" e "Preferenze…", pallino rosso, Run spento. **DT Hub non lo riavvia da solo:** un server che continua a cadere deve vedersi. Il registro (ultime 30 righe) è nelle Preferenze.
- **Server rimasto da una sessione finita male:**
  - DT Hub scrive l'id del processo in `~/Library/Application Support/DT Hub/managed-server.pid`;
  - al prossimo avvio chiude quel processo **solo se esegue ancora lo stesso programma** (un id riciclato da un altro programma non si tocca);
  - una porta occupata da altro (l'app Draw Things, un altro server) non viene mai liberata: l'avvio si ferma con "porta già in uso".
- **Pallino (spec §7):** giallo finché il server gestito è partito ma non risponde; poi come sempre (verde = collegato, rosso = non raggiungibile).
- **Messaggio senza modelli:** per il server gestito, un server che risponde ma elenca 0 file significa **cartella senza file `.ckpt`**, non "Model browsing" spento: il testo cambia (`DrawThingsConnection.noModelsText`).
- **Cartella dei modelli dell'app Draw Things:** un pulsante propone `~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models`. Sul Mac dell'utente è quasi vuota (i modelli sono su un volume esterno): un avviso arancio dice che la cartella non contiene `.ckpt`. DT Hub non guarda quella cartella da solo.
- **Stringhe:**
  - ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo;
  - `String(format: String(localized:), …)` per i valori.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Fuori da M5:** scaricare o aggiornare il programma; opzioni avanzate del programma (cache dei pesi, offload su CPU, blob store, `--join`); più server insieme; esporre il server in rete; riavvio automatico.

## Review Focus

- **Programma mancante, non eseguibile o percorso vuoto:** nessun avvio, messaggio chiaro, link per scaricarlo (test `reportsWhatIsMissingInOrder`, `doesNotStartWithSettingsThatCannotWork`, Task 1–2).
- **Porta già occupata** (app Draw Things sulla stessa porta, altro server): nessun avvio, messaggio con il numero, nessun processo toccato (test `doesNotStartOnAPortSomethingElseUses`, `aPortWithAListenerIsNotFree`, Task 2).
- **Il server si chiude da solo o cade** (uscita con codice o per segnale, anche subito dopo l'avvio): stato "uscito", avviso con Riavvia, nessun riavvio automatico, registro conservato (test `tellsWhenTheServerEndsOnItsOwn`, `aCrashBySignalIsToldToo`, Task 2).
- **Uscita dall'app o arresto richiesto:** il server si ferma e non conta come uscita inattesa; un server che ignora il SIGTERM viene ucciso (test `stoppingIsNotAnUnexpectedExit`, `aServerThatIgnoresTheStopRequestIsKilled`, `terminateNowStopsItAtOnce`, Task 2).
- **DT Hub finisce male e lascia il server aperto:** il successivo avvio lo chiude; mai un altro programma che ha riusato l'id (test `closesAServerLeftRunningByAPreviousRun`, `neverClosesAnotherProgramThatReusedTheProcessID`, Task 2).
- **Il server non è raggiungibile dalla rete e non porta segreti sulla riga di comando** (test `theServerListensOnThisMacOnly`, `noSecretGoesOnTheCommandLine`, Task 1).
- **Cartella dei modelli senza `.ckpt`:** avviso prima dell'avvio e, a server acceso, un messaggio che nomina la cartella e non il "Model browsing" (test `warnsWhenTheModelsFolderHoldsNoModelFiles`, Task 1).

---

### Task 1: Impostazioni, ricerca del programma e riga di comando (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Server/ManagedServerSettings.swift`
- Test: `Packages/Tests/HubCoreTests/ManagedServerSettingsTests.swift`

**Interfaces:**
- Produces (HubCore, `public`):
  - `enum ServerMode: String, Codable, CaseIterable, Identifiable, Sendable { attach, managed }`;
  - `struct FileSystemProbe: Sendable` (`isExecutableFile`, `isDirectory`, `hasModelFiles`, `static let live`);
  - `struct ManagedServerSettings: Equatable, Codable, Sendable` (`mode`, `binaryPath`, `modelsFolder`, `port`, `static let defaultPort = 7860`, `static let default`, `enum ValidationError { noBinary, binaryNotExecutable, noModelsFolder, modelsFolderMissing, invalidPort }`, `enum Warning { noModelFiles }`, `validationError(_:)`, `warning(_:)`), decodifica tollerante;
  - `struct ManagedServerSettingsStore` (`load()`, `save(_:)`, chiave UserDefaults `drawThings.managedServer`);
  - `enum CLILocator` (`find(home:files:)`, `candidatePaths(home:)`, `drawThingsAppModelsFolder(home:)`);
  - `enum ServerArguments { static func make(_: ManagedServerSettings) -> [String] }`.

- [ ] **Step 1: Creare il branch**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m5-server-gestito
```

- [ ] **Step 2: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/ManagedServerSettingsTests.swift` con:

```swift
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
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'FileSystemProbe' in scope`.

- [ ] **Step 4: Creare `Packages/Sources/HubCore/Server/ManagedServerSettings.swift`**

```swift
import Foundation

/// How DT Hub reaches Draw Things (spec §5): a server already running, or one DT Hub starts.
public enum ServerMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case attach
  case managed

  public var id: String { rawValue }
}

/// What the file system says, so the checks below can be tested without touching disk.
public struct FileSystemProbe: Sendable {
  public var isExecutableFile: @Sendable (String) -> Bool
  public var isDirectory: @Sendable (String) -> Bool
  /// Whether the folder holds at least one model file (`.ckpt`, Draw Things' format).
  public var hasModelFiles: @Sendable (String) -> Bool

  public init(
    isExecutableFile: @escaping @Sendable (String) -> Bool, isDirectory: @escaping @Sendable (String) -> Bool,
    hasModelFiles: @escaping @Sendable (String) -> Bool = { _ in true }
  ) {
    self.isExecutableFile = isExecutableFile
    self.isDirectory = isDirectory
    self.hasModelFiles = hasModelFiles
  }

  public static let live = FileSystemProbe(
    isExecutableFile: { FileManager.default.isExecutableFile(atPath: $0) },
    isDirectory: {
      var isDirectory: ObjCBool = false
      return FileManager.default.fileExists(atPath: $0, isDirectory: &isDirectory) && isDirectory.boolValue
    },
    hasModelFiles: { folder in
      let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
      return names.contains { $0.hasSuffix(".ckpt") }
    })
}

/// The gRPCServerCLI DT Hub starts (spec §5, "Avvia gRPCServerCLI"): where the program is, the
/// models folder, and the port. The server only ever listens on this Mac (127.0.0.1).
public struct ManagedServerSettings: Equatable, Codable, Sendable {
  public var mode: ServerMode
  public var binaryPath: String
  public var modelsFolder: String
  public var port: Int

  /// 7860, next to the Draw Things app's own API server on 7859.
  public static let defaultPort = 7860

  public init(
    mode: ServerMode = .attach, binaryPath: String = "", modelsFolder: String = "", port: Int = defaultPort
  ) {
    self.mode = mode
    self.binaryPath = binaryPath
    self.modelsFolder = modelsFolder
    self.port = port
  }

  public static let `default` = ManagedServerSettings()

  public enum ValidationError: Equatable, Sendable {
    case noBinary
    case binaryNotExecutable
    case noModelsFolder
    case modelsFolderMissing
    case invalidPort
  }

  /// Why the server cannot be started with these settings, or nil when it can.
  public func validationError(_ files: FileSystemProbe = .live) -> ValidationError? {
    let binary = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    let folder = modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines)
    if binary.isEmpty { return .noBinary }
    if !files.isExecutableFile(binary) { return .binaryNotExecutable }
    if folder.isEmpty { return .noModelsFolder }
    if !files.isDirectory(folder) { return .modelsFolderMissing }
    if !(1024...65535).contains(port) { return .invalidPort }
    return nil
  }

  public enum Warning: Equatable, Sendable {
    /// The folder exists but holds no `.ckpt` file: the server would list no models. The
    /// Draw Things app may keep its models elsewhere (an external disk, for instance).
    case noModelFiles
  }

  /// Something worth saying about settings that can be used, or nil.
  public func warning(_ files: FileSystemProbe = .live) -> Warning? {
    guard validationError(files) == nil else { return nil }
    return files.hasModelFiles(modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines)) ? nil : .noModelFiles
  }

  /// Lenient: a missing or unreadable field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    mode = value(.mode, .attach)
    binaryPath = value(.binaryPath, "")
    modelsFolder = value(.modelsFolder, "")
    port = value(.port, Self.defaultPort)
  }
}

/// Persists `ManagedServerSettings` in UserDefaults as JSON (spec §11).
public struct ManagedServerSettingsStore {
  private let defaults: UserDefaults
  static let key = "drawThings.managedServer"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func load() -> ManagedServerSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(ManagedServerSettings.self, from: data)
    else { return .default }
    return settings
  }

  public func save(_ settings: ManagedServerSettings) {
    defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
  }
}

/// Where gRPCServerCLI may already be installed, in the order they are tried.
public enum CLILocator {
  public static let fileName = "gRPCServerCLI-macOS"

  public static func candidatePaths(home: String = NSHomeDirectory()) -> [String] {
    [
      "\(home)/Applications/DrawThings-CLI/\(fileName)",
      "\(home)/Applications/\(fileName)",
      "/opt/homebrew/bin/\(fileName)",
      "/usr/local/bin/\(fileName)",
      "/opt/homebrew/bin/gRPCServerCLI",
      "/usr/local/bin/gRPCServerCLI",
    ]
  }

  /// The first candidate that is an executable file, nil when none is.
  public static func find(
    home: String = NSHomeDirectory(), files: FileSystemProbe = .live
  ) -> String? {
    candidatePaths(home: home).first { files.isExecutableFile($0) }
  }

  /// The models folder of the Draw Things app, offered by a button (reading it asks the user
  /// for permission the first time, so DT Hub never looks at it unprompted).
  public static func drawThingsAppModelsFolder(home: String = NSHomeDirectory()) -> String {
    "\(home)/Library/Containers/com.liuliu.draw-things/Data/Documents/Models"
  }
}

/// The command line of the managed server (spec §5).
public enum ServerArguments {
  /// The models folder first, then: `--address 127.0.0.1` (the program's default,
  /// `0.0.0.0`, would offer the server to the whole network), the port, and `--model-browser`
  /// (without it DT Hub cannot list the models). No shared secret: on the command line any
  /// program could read it, and the server is not reachable from outside.
  public static func make(_ settings: ManagedServerSettings) -> [String] {
    [
      settings.modelsFolder.trimmingCharacters(in: .whitespacesAndNewlines),
      "--address", "127.0.0.1",
      "--port", String(settings.port),
      "--model-browser",
    ]
  }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: HubCore `121 tests … passed` (108 + 13); HubKit 44, DTBridge 47, Catalog 6 come prima.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && mkdir -p Packages/Sources/HubCore/Server && git add Packages && git commit -m "feat: impostazioni del server gestito, ricerca di gRPCServerCLI e riga di comando

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Il processo gestito (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Server/ProcessLauncher.swift`
- Create: `Packages/Sources/HubCore/Server/ServerSupport.swift`
- Create: `Packages/Sources/HubCore/Server/ManagedServer.swift`
- Test: `Packages/Tests/HubCoreTests/ManagedServerTests.swift`

**Interfaces:**
- Consumes: `ManagedServerSettings`, `FileSystemProbe`, `ServerArguments` (Task 1).
- Produces (HubCore, `public`):
  - `struct ProcessExit: Equatable, Sendable` (`status`, `bySignal`);
  - `protocol ServerProcess: Sendable` (`processID`, `isRunning`, `terminate()`, `kill()`), `protocol ProcessLauncher: Sendable` (`launch(executable:arguments:onLine:onExit:) throws`), `struct FoundationProcessLauncher`;
  - `enum PortProbe { static func isFree(_: Int) -> Bool }` (prova di connessione, non di bind: un bind fallisce anche per le connessioni residue di un server appena fermato);
  - `struct ServerPidFile` (`read()`, `write(_:)`, `remove()`, `defaultURL`), `struct ProcessInspector` (`isAlive`, `isRunning(pid, executable)`, `terminate`, `kill`, `live`);
  - `@MainActor @Observable final class ManagedServer` con `State { stopped, running(pid:), failedToStart(Failure), exitedUnexpectedly(ProcessExit) }`, `Failure { settings(ValidationError), portInUse(Int), launchFailed(String) }`, `state`, `logTail` (30 righe), `isRunning`, `start(_:) async`, `stop()`, `stopAndWait(timeout:) async`, `terminateNow(timeout:)`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/ManagedServerTests.swift` con:

```swift
import Foundation
import Testing

@testable import HubCore

/// A program that is never really started: tests say what it prints and when it ends.
final class FakeProcess: ServerProcess, @unchecked Sendable {
  let processID: Int32
  private let lock = NSLock()
  private var running = true
  private(set) var terminated = false
  private(set) var killed = false
  let onExit: @Sendable (ProcessExit) -> Void
  let ignoresTerminate: Bool

  init(processID: Int32, ignoresTerminate: Bool = false, onExit: @escaping @Sendable (ProcessExit) -> Void) {
    self.processID = processID
    self.ignoresTerminate = ignoresTerminate
    self.onExit = onExit
  }

  var isRunning: Bool { lock.withLock { running } }

  func terminate() {
    lock.withLock { terminated = true }
    if !ignoresTerminate { finish(ProcessExit(status: 15, bySignal: true)) }
  }

  func kill() {
    lock.withLock { killed = true }
    finish(ProcessExit(status: 9, bySignal: true))
  }

  func finish(_ exit: ProcessExit) {
    let wasRunning = lock.withLock { () -> Bool in
      defer { running = false }
      return running
    }
    if wasRunning { onExit(exit) }
  }
}

final class FakeLauncher: ProcessLauncher, @unchecked Sendable {
  private let lock = NSLock()
  private(set) var launches: [(executable: String, arguments: [String])] = []
  private(set) var processes: [FakeProcess] = []
  private var lineHandlers: [@Sendable (String) -> Void] = []
  var failWith: (any Error)?
  var ignoresTerminate = false

  func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess {
    if let failWith { throw failWith }
    return lock.withLock {
      launches.append((executable, arguments))
      let process = FakeProcess(processID: Int32(1000 + processes.count), ignoresTerminate: ignoresTerminate, onExit: onExit)
      processes.append(process)
      lineHandlers.append(onLine)
      return process
    }
  }

  func print(_ line: String, launch index: Int = 0) { lock.withLock { lineHandlers[index] }(line) }
  var last: FakeProcess { lock.withLock { processes.last! } }
}

struct LaunchFailure: Error, LocalizedError {
  var errorDescription: String? { "no such file" }
}

@MainActor
struct ManagedServerTests {
  let settings = ManagedServerSettings(mode: .managed, binaryPath: "/bin/cli", modelsFolder: "/models", port: 7861)
  let files = FileSystemProbe(isExecutableFile: { $0 == "/bin/cli" }, isDirectory: { $0 == "/models" })

  func pidFile() -> ServerPidFile {
    ServerPidFile(
      url: FileManager.default.temporaryDirectory.appendingPathComponent("ManagedServerTests-\(UUID())/server.pid"))
  }

  func inspector(alive: Set<Int32> = [], running: Set<Int32> = [], log: Log = Log()) -> ProcessInspector {
    ProcessInspector(
      isAlive: { log.alive($0, alive) }, isRunning: { pid, _ in running.contains(pid) },
      terminate: { log.terminated($0) }, kill: { log.killed($0) })
  }

  /// What the inspector was asked to do; a closed pid stops being alive.
  final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var gone: Set<Int32> = []
    private(set) var terminatedPIDs: [Int32] = []
    private(set) var killedPIDs: [Int32] = []
    func alive(_ pid: Int32, _ alive: Set<Int32>) -> Bool { lock.withLock { alive.contains(pid) && !gone.contains(pid) } }
    func terminated(_ pid: Int32) { lock.withLock { terminatedPIDs.append(pid); gone.insert(pid) } }
    func killed(_ pid: Int32) { lock.withLock { killedPIDs.append(pid); gone.insert(pid) } }
  }

  func server(_ launcher: FakeLauncher, portFree: Bool = true, pidFile: ServerPidFile? = nil, inspector: ProcessInspector? = nil)
    -> ManagedServer
  {
    ManagedServer(
      launcher: launcher, files: files, isPortFree: { _ in portFree }, pidFile: pidFile ?? self.pidFile(),
      inspector: inspector ?? self.inspector())
  }

  func settle() async { try? await Task.sleep(for: .milliseconds(60)) }

  @Test func startsTheServerWithTheCommandLine() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    #expect(server.state == .running(pid: 1000))
    #expect(server.isRunning)
    #expect(launcher.launches.count == 1)
    #expect(launcher.launches[0].executable == "/bin/cli")
    #expect(launcher.launches[0].arguments == ServerArguments.make(settings))
  }

  @Test func doesNotStartWithSettingsThatCannotWork() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(ManagedServerSettings(mode: .managed, binaryPath: "/nowhere", modelsFolder: "/models"))
    #expect(server.state == .failedToStart(.settings(.binaryNotExecutable)))
    #expect(launcher.launches.isEmpty)
  }

  @Test func doesNotStartOnAPortSomethingElseUses() async {
    let launcher = FakeLauncher()
    let server = server(launcher, portFree: false)
    await server.start(settings)
    #expect(server.state == .failedToStart(.portInUse(7861)))
    #expect(launcher.launches.isEmpty)
  }

  @Test func reportsAProgramThatCannotBeLaunched() async {
    let launcher = FakeLauncher()
    launcher.failWith = LaunchFailure()
    let server = server(launcher)
    await server.start(settings)
    #expect(server.state == .failedToStart(.launchFailed("no such file")))
  }

  @Test func keepsTheLastLinesTheServerWrote() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    for number in 1...45 { launcher.print("line \(number)") }
    await settle()
    #expect(server.logTail.count == ManagedServer.logLimit)
    #expect(server.logTail.first == "line 16")
    #expect(server.logTail.last == "line 45")
  }

  @Test func tellsWhenTheServerEndsOnItsOwn() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    let server = server(launcher, pidFile: file)
    await server.start(settings)
    launcher.print("Address already in use")
    launcher.last.finish(ProcessExit(status: 1, bySignal: false))
    await settle()
    #expect(server.state == .exitedUnexpectedly(ProcessExit(status: 1, bySignal: false)))
    #expect(server.logTail == ["Address already in use"])
    #expect(file.read() == nil)
    // It is never started again by itself.
    #expect(launcher.launches.count == 1)
  }

  @Test func aCrashBySignalIsToldToo() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    launcher.last.finish(ProcessExit(status: 5, bySignal: true))
    await settle()
    #expect(server.state == .exitedUnexpectedly(ProcessExit(status: 5, bySignal: true)))
  }

  @Test func stoppingIsNotAnUnexpectedExit() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    let server = server(launcher, pidFile: file)
    await server.start(settings)
    #expect(file.read() == 1000)
    server.stop()
    await settle()
    #expect(server.state == .stopped)
    #expect(launcher.last.terminated)
    #expect(file.read() == nil)
  }

  @Test func startingAgainClosesTheRunningServerFirst() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    let first = launcher.last
    await server.start(settings)
    #expect(first.terminated)
    #expect(launcher.launches.count == 2)
    #expect(server.state == .running(pid: 1001))
    // The old one's end must not be mistaken for the new one's.
    await settle()
    #expect(server.state == .running(pid: 1001))
  }

  @Test func aServerThatIgnoresTheStopRequestIsKilled() async {
    let launcher = FakeLauncher()
    launcher.ignoresTerminate = true
    let server = server(launcher)
    await server.start(settings)
    let first = launcher.last
    await server.stopAndWait(timeout: .milliseconds(200))
    #expect(first.terminated && first.killed)
    #expect(server.state == .stopped)
  }

  @Test func terminateNowStopsItAtOnce() async {
    let launcher = FakeLauncher()
    let server = server(launcher)
    await server.start(settings)
    server.terminateNow()
    #expect(launcher.last.terminated)
    #expect(!launcher.last.isRunning)
    #expect(server.state == .stopped)
  }

  @Test func closesAServerLeftRunningByAPreviousRun() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(777)
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [777], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs == [777])
    #expect(server.state == .running(pid: 1000))
    #expect(file.read() == 1000)
    #expect(server.logTail.contains { $0.contains("777") })
  }

  @Test func neverClosesAnotherProgramThatReusedTheProcessID() async {
    let launcher = FakeLauncher()
    let file = pidFile()
    file.write(777)
    let log = Log()
    let server = server(launcher, pidFile: file, inspector: inspector(alive: [777], running: [], log: log))
    await server.start(settings)
    #expect(log.terminatedPIDs.isEmpty && log.killedPIDs.isEmpty)
    #expect(server.state == .running(pid: 1000))
  }
}

struct PortProbeTests {
  @Test func aPortNobodyListensOnIsFree() {
    #expect(PortProbe.isFree(59_999))
  }

  @Test func aPortWithAListenerIsNotFree() throws {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0
    _ = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    #expect(listen(descriptor, 1) == 0)
    var bound = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &bound) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
    }
    #expect(!PortProbe.isFree(Int(UInt16(bigEndian: bound.sin_port))))
  }
}

struct ServerPidFileTests {
  @Test func writesReadsAndRemoves() {
    let file = ServerPidFile(
      url: FileManager.default.temporaryDirectory.appendingPathComponent("ServerPidFileTests-\(UUID())/p.pid"))
    #expect(file.read() == nil)
    file.write(4242)
    #expect(file.read() == 4242)
    file.remove()
    #expect(file.read() == nil)
  }

  @Test func aGarbledFileReadsAsNothing() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ServerPidFileTests-\(UUID()).pid")
    try "not a number".write(to: url, atomically: true, encoding: .utf8)
    #expect(ServerPidFile(url: url).read() == nil)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ServerProcess' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Server/ProcessLauncher.swift`**

```swift
import Darwin
import Foundation

/// How a process ended.
public struct ProcessExit: Equatable, Sendable {
  public let status: Int32
  /// True when a signal ended it (a crash, or a SIGTERM), false when it exited by itself.
  public let bySignal: Bool

  public init(status: Int32, bySignal: Bool) {
    self.status = status
    self.bySignal = bySignal
  }
}

/// A running program DT Hub started.
public protocol ServerProcess: Sendable {
  var processID: Int32 { get }
  var isRunning: Bool { get }
  /// SIGTERM: ask it to stop.
  func terminate()
  /// SIGKILL: make it stop.
  func kill()
}

/// Starts programs (spec §4: HubCore reaches the system only through protocols like this one).
public protocol ProcessLauncher: Sendable {
  /// Starts `executable`; `onLine` receives each line of its output (errors included),
  /// `onExit` how it ended. Both may be called from any thread.
  func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess
}

/// The real thing, on Foundation's `Process`.
public struct FoundationProcessLauncher: ProcessLauncher {
  public init() {}

  public func launch(
    executable: String, arguments: [String],
    onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (ProcessExit) -> Void
  ) throws -> any ServerProcess {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    process.standardInput = FileHandle.nullDevice
    let lines = LineBuffer(onLine)
    pipe.fileHandleForReading.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        lines.flush()
      } else {
        lines.append(data)
      }
    }
    process.terminationHandler = { finished in
      onExit(
        ProcessExit(status: finished.terminationStatus, bySignal: finished.terminationReason == .uncaughtSignal))
    }
    try process.run()
    return FoundationServerProcess(process)
  }
}

private final class FoundationServerProcess: ServerProcess, @unchecked Sendable {
  private let process: Process

  init(_ process: Process) {
    self.process = process
  }

  var processID: Int32 { process.processIdentifier }
  var isRunning: Bool { process.isRunning }
  func terminate() { process.terminate() }
  func kill() { Darwin.kill(process.processIdentifier, SIGKILL) }
}

/// Cuts a stream of bytes into lines.
private final class LineBuffer: @unchecked Sendable {
  private let lock = NSLock()
  private var pending = Data()
  private let onLine: @Sendable (String) -> Void

  init(_ onLine: @escaping @Sendable (String) -> Void) {
    self.onLine = onLine
  }

  func append(_ data: Data) {
    var complete: [String] = []
    lock.withLock {
      pending.append(data)
      while let newline = pending.firstIndex(of: 0x0A) {
        complete.append(String(decoding: pending[pending.startIndex..<newline], as: UTF8.self))
        pending.removeSubrange(pending.startIndex...newline)
      }
    }
    complete.forEach(onLine)
  }

  func flush() {
    let rest = lock.withLock { () -> String? in
      defer { pending = Data() }
      return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
    }
    if let rest { onLine(rest) }
  }
}
```

- [ ] **Step 4: Creare `Packages/Sources/HubCore/Server/ServerSupport.swift`**

```swift
import Darwin
import Foundation

/// Whether something already listens on a port of this Mac. A connection attempt, not a
/// bind: a bind also fails for leftover connections of a server that just stopped.
public enum PortProbe {
  public static func isFree(_ port: Int) -> Bool {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return true }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port)).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    return result != 0
  }
}

/// The process id of the server DT Hub started, kept in a file so that a server left running
/// by a DT Hub that crashed or was killed can be recognized and closed at the next start.
public struct ServerPidFile: Sendable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  /// ~/Library/Application Support/DT Hub/managed-server.pid.
  public static var defaultURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("managed-server.pid")
  }

  public func read() -> Int32? {
    (try? String(contentsOf: url, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
  }

  public func write(_ pid: Int32) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? String(pid).write(to: url, atomically: true, encoding: .utf8)
  }

  public func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Facts about running processes, replaceable in tests.
public struct ProcessInspector: Sendable {
  /// Whether the process exists.
  public var isAlive: @Sendable (Int32) -> Bool
  /// Whether the process runs this program: a recycled process id must never be closed.
  public var isRunning: @Sendable (_ pid: Int32, _ executable: String) -> Bool
  public var terminate: @Sendable (Int32) -> Void
  public var kill: @Sendable (Int32) -> Void

  public init(
    isAlive: @escaping @Sendable (Int32) -> Bool,
    isRunning: @escaping @Sendable (Int32, String) -> Bool,
    terminate: @escaping @Sendable (Int32) -> Void, kill: @escaping @Sendable (Int32) -> Void
  ) {
    self.isAlive = isAlive
    self.isRunning = isRunning
    self.terminate = terminate
    self.kill = kill
  }

  public static let live = ProcessInspector(
    isAlive: { Darwin.kill($0, 0) == 0 },
    isRunning: { pid, executable in
      var buffer = [CChar](repeating: 0, count: 4096)
      guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
      return String(cString: buffer) == executable
    },
    terminate: { _ = Darwin.kill($0, SIGTERM) },
    kill: { _ = Darwin.kill($0, SIGKILL) })
}
```

- [ ] **Step 5: Creare `Packages/Sources/HubCore/Server/ManagedServer.swift`**

```swift
import Foundation
import Observation

/// The gRPCServerCLI that DT Hub starts and stops (spec §5, §10): starts it when the app
/// opens, stops it when the app quits, tells when it ended without being asked, and offers
/// to start it again. It never restarts by itself: a server that keeps crashing must be seen.
@MainActor
@Observable
public final class ManagedServer {
  public enum Failure: Equatable, Sendable {
    case settings(ManagedServerSettings.ValidationError)
    /// Something already listens on the port (the Draw Things app's own server, another
    /// program, a server of a previous run that is not DT Hub's).
    case portInUse(Int)
    case launchFailed(String)
  }

  public enum State: Equatable, Sendable {
    case stopped
    case running(pid: Int32)
    /// DT Hub could not start it.
    case failedToStart(Failure)
    /// It started and then ended without DT Hub asking: a crash, or a port or models folder
    /// the program itself refused.
    case exitedUnexpectedly(ProcessExit)
  }

  public private(set) var state: State = .stopped
  /// The last lines the server wrote, for the Preferences and for bug reports.
  public private(set) var logTail: [String] = []
  public static let logLimit = 30

  @ObservationIgnored private let launcher: any ProcessLauncher
  @ObservationIgnored private let files: FileSystemProbe
  @ObservationIgnored private let isPortFree: @Sendable (Int) -> Bool
  @ObservationIgnored private let pidFile: ServerPidFile
  @ObservationIgnored private let inspector: ProcessInspector
  @ObservationIgnored private var process: (any ServerProcess)?
  /// Names the launch a callback belongs to, so a late callback of an old one is dropped.
  @ObservationIgnored private var launchID = 0

  public init(
    launcher: any ProcessLauncher = FoundationProcessLauncher(), files: FileSystemProbe = .live,
    isPortFree: @escaping @Sendable (Int) -> Bool = PortProbe.isFree,
    pidFile: ServerPidFile = ServerPidFile(url: ServerPidFile.defaultURL),
    inspector: ProcessInspector = .live
  ) {
    self.launcher = launcher
    self.files = files
    self.isPortFree = isPortFree
    self.pidFile = pidFile
    self.inspector = inspector
  }

  public var isRunning: Bool {
    if case .running = state { return true }
    return false
  }

  /// Starts the server (closing the one DT Hub already started first). Returns when it has
  /// been launched or has failed to; the program needs a few more seconds before it answers.
  public func start(_ settings: ManagedServerSettings) async {
    await stopAndWait()
    logTail = []
    if let problem = settings.validationError(files) {
      state = .failedToStart(.settings(problem))
      return
    }
    let binary = settings.binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
    await closeServerLeftByAPreviousRun(binary: binary)
    guard isPortFree(settings.port) else {
      state = .failedToStart(.portInUse(settings.port))
      return
    }
    launchID += 1
    let id = launchID
    do {
      let started = try launcher.launch(
        executable: binary, arguments: ServerArguments.make(settings),
        onLine: { [weak self] line in Task { @MainActor in self?.append(line, launch: id) } },
        onExit: { [weak self] exit in Task { @MainActor in self?.ended(exit, launch: id) } })
      process = started
      pidFile.write(started.processID)
      state = .running(pid: started.processID)
    } catch {
      state = .failedToStart(.launchFailed(error.localizedDescription))
    }
  }

  /// Stops the server DT Hub started; the next `start` launches a new one.
  public func stop() {
    guard let process else {
      if case .running = state { state = .stopped }
      return
    }
    launchID += 1  // its exit is expected: the callback of the old launch is dropped
    self.process = nil
    state = .stopped
    pidFile.remove()
    process.terminate()
    Task {
      try? await Task.sleep(for: .seconds(3))
      if process.isRunning { process.kill() }
    }
  }

  /// Stops the server and waits until it is gone (up to `timeout`).
  public func stopAndWait(timeout: Duration = .seconds(5)) async {
    guard let running = process else {
      stop()
      return
    }
    stop()
    let deadline = ContinuousClock.now + timeout
    while running.isRunning, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(50))
    }
    if running.isRunning { running.kill() }
  }

  /// For the moment the app quits: no waiting for the main actor, only a short pause for
  /// the program to leave.
  public func terminateNow(timeout: TimeInterval = 3) {
    guard let running = process else { return }
    stop()
    let deadline = Date().addingTimeInterval(timeout)
    while running.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if running.isRunning { running.kill() }
  }

  // MARK: Callbacks

  private func append(_ line: String, launch id: Int) {
    guard id == launchID else { return }
    logTail.append(line)
    if logTail.count > Self.logLimit { logTail.removeFirst(logTail.count - Self.logLimit) }
  }

  private func ended(_ exit: ProcessExit, launch id: Int) {
    guard id == launchID else { return }
    process = nil
    pidFile.remove()
    state = .exitedUnexpectedly(exit)
  }

  // MARK: A server left by a previous run

  /// A DT Hub that crashed or was killed leaves its server running, holding the port and the
  /// models in memory. The process id in the file is closed when it still is this program.
  private func closeServerLeftByAPreviousRun(binary: String) async {
    guard let pid = pidFile.read() else { return }
    defer { pidFile.remove() }
    guard inspector.isAlive(pid), inspector.isRunning(pid, binary) else { return }
    inspector.terminate(pid)
    for _ in 0..<60 where inspector.isAlive(pid) { try? await Task.sleep(for: .milliseconds(50)) }
    if inspector.isAlive(pid) { inspector.kill(pid) }
    logTail.append("Closed a server left running by a previous run (pid \(pid)).")
  }
}
```

Note:
- Un `launchID` per ogni avvio: la fine di un processo vecchio, arrivata dopo un riavvio, non cambia lo stato del nuovo.
- `stop()` cambia `launchID` prima di fermare il processo: la sua uscita è attesa e non diventa `exitedUnexpectedly`.
- Il registro (`logTail`) si azzera a ogni `start`.

- [ ] **Step 6: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: HubCore `138 tests … passed` (121 + 17); totale 44 + 138 + 47 + 6 = **235**.

- [ ] **Step 7: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: ManagedServer — avvio, arresto, uscita inattesa e server rimasto da una sessione precedente

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Testi del server gestito (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (28 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `prefs.server.*`, `server.*`, `status.serverStarting` usate da `ManagedServerText`, `ManagedServerBanner`, `DrawThingsPreferencesView`, `DrawThingsConnection` e `HeaderBar` (Task 4); `server.error.portInUse` (`%lld`), `server.error.launchFailed` (`%@`), `server.exited.code` e `server.exited.signal` (`%lld`) si usano con `String(format:)`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'EOF'
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "prefs.server.binary": ("gRPCServerCLI program", "Programma gRPCServerCLI"),
    "prefs.server.choose": ("Choose…", "Scegli…"),
    "prefs.server.get": ("Get gRPCServerCLI from Draw Things (GitHub)", "Scarica gRPCServerCLI da Draw Things (GitHub)"),
    "prefs.server.log": ("Server log", "Registro del server"),
    "prefs.server.mode": ("Server", "Server"),
    "prefs.server.mode.attach": ("Connect to a running server", "Collegati a un server già attivo"),
    "prefs.server.mode.managed": ("Start gRPCServerCLI", "Avvia gRPCServerCLI"),
    "prefs.server.models": ("Models folder", "Cartella dei modelli"),
    "prefs.server.models.useApp": ("Use the Draw Things app's default models folder", "Usa la cartella dei modelli predefinita dell'app Draw Things"),
    "prefs.server.noModelFiles": ("This folder holds no model files (.ckpt). The Draw Things app may keep its models elsewhere, on an external disk for instance: choose that folder.", "Questa cartella non contiene modelli (.ckpt). L'app Draw Things può tenerli altrove, ad esempio su un disco esterno: scegli quella cartella."),
    "prefs.server.note": ("DT Hub starts the server with the app and stops it when you quit. It listens on this Mac only.", "DT Hub avvia il server con l'app e lo ferma quando esci. Resta raggiungibile solo da questo Mac."),
    "prefs.server.port": ("Port", "Porta"),
    "prefs.server.stop": ("Stop the server", "Ferma il server"),
    "server.error.binaryNotExecutable": ("The gRPCServerCLI program was not found or cannot be run.", "Il programma gRPCServerCLI non c'è o non si può eseguire."),
    "server.error.invalidPort": ("The port must be between 1024 and 65535.", "La porta deve essere tra 1024 e 65535."),
    "server.error.launchFailed": ("The server could not be started: %@", "Il server non è partito: %@"),
    "server.error.modelsFolderMissing": ("The models folder does not exist.", "La cartella dei modelli non esiste."),
    "server.error.noBinary": ("Choose the gRPCServerCLI program.", "Scegli il programma gRPCServerCLI."),
    "server.error.noModelsFolder": ("Choose the models folder.", "Scegli la cartella dei modelli."),
    "server.error.portInUse": ("Port %lld is already in use: another server, or the Draw Things app, is listening there.", "La porta %lld è già in uso: un altro server, o l'app Draw Things, è in ascolto."),
    "server.exited.code": ("The server stopped by itself (exit code %lld). See the log in the Preferences.", "Il server si è chiuso da solo (codice %lld). Guarda il registro nelle Preferenze."),
    "server.exited.signal": ("The server crashed (signal %lld). See the log in the Preferences.", "Il server si è interrotto (segnale %lld). Guarda il registro nelle Preferenze."),
    "server.noModels": ("The server lists no models: the models folder holds no .ckpt file.", "Il server non vede modelli: la cartella dei modelli non contiene file .ckpt."),
    "server.preferences": ("Preferences…", "Preferenze…"),
    "server.restart": ("Restart", "Riavvia"),
    "server.state.running": ("Server running", "Server in esecuzione"),
    "server.state.stopped": ("Server stopped", "Server fermo"),
    "status.serverStarting": ("Starting the server…", "Avvio del server…"),
}
for key, (en, it) in new.items():
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
EOF
git diff --stat App/Localizable.xcstrings
```

Expected: `1 file changed, 476 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi del server gestito (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Modalità gestita nell'app (App)

**Files:**
- Modify: `App/Connection/DrawThingsConnection.swift` (server gestito, modalità, pallino, testo senza modelli)
- Create: `App/Connection/ManagedServerText.swift`
- Create: `App/Connection/ManagedServerBanner.swift`
- Modify: `App/Preferences/DrawThingsPreferencesView.swift`
- Modify: `App/MainWindow/HeaderBar.swift` (pallino e testi)
- Modify: `App/MainWindow/MainWindowView.swift` (avviso)
- Modify: `App/DTHubApp.swift` (arresto del server all'uscita)

**Interfaces:**
- Consumes: `ManagedServer`, `ManagedServerSettings`, `ManagedServerSettingsStore`, `CLILocator`, `ServerMode` (Task 1–2); le chiavi del Task 3.
- Produces: `DrawThingsConnection.managedServer`, `managed`, `indicator`, `noModelsText`, `restartManagedServer()`, `apply(_:secret:managed:)`; `ManagedServerText`; `ManagedServerBanner(connection:)`.

- [ ] **Step 1: Sostituire `App/Connection/DrawThingsConnection.swift` con:**

```swift
import DTBridge
import HubCore
import HubKit
import Observation

/// App-level wiring of the Draw Things link (spec §5): settings, the Keychain secret, the
/// connection monitor and the model selection. It starts checking the server when it is
/// created and keeps doing so for the life of the app, whatever windows are open.
@MainActor
@Observable
final class DrawThingsConnection {
  let monitor = ConnectionMonitor()
  let selection = ModelSelection()
  /// The gRPCServerCLI DT Hub starts in "managed" mode (spec §5).
  let managedServer = ManagedServer()
  private(set) var settings: ConnectionSettings
  private(set) var managed: ManagedServerSettings
  /// True when the last Apply could not save the shared secret in the Keychain.
  private(set) var secretSaveFailed = false

  @ObservationIgnored private let settingsStore = ConnectionSettingsStore()
  @ObservationIgnored private let managedStore = ManagedServerSettingsStore()
  @ObservationIgnored private let secretStore: any SecretStore = KeychainSecretStore()
  @ObservationIgnored private var loop: Task<Void, Never>?

  init() {
    settings = settingsStore.load()
    managed = managedStore.load()
    loop = Task {
      // Managed mode: the server starts with the app (spec §5).
      if managed.mode == .managed { await managedServer.start(managed) }
      await monitor.replaceBackend(makeBackend())
      await monitor.run()
    }
  }

  /// The saved shared secret, empty when there is none.
  func savedSecret() -> String {
    secretStore.read() ?? ""
  }

  /// What the header dot shows: yellow while the managed server is starting, until it answers
  /// (spec §7), whatever the monitor says meanwhile.
  var indicator: ConnectionStatus {
    if managed.mode == .managed, managedServer.isRunning, monitor.status != .connected { return .connecting }
    return monitor.indicator
  }

  /// What to say when the server answers but lists no model: with "Model browsing" off (a
  /// server of the Draw Things app), or, for the server DT Hub starts (which always has
  /// it on), with no model file in the chosen folder.
  var noModelsText: String {
    managed.mode == .managed
      ? String(localized: "server.noModels") : String(localized: "header.model.browsingDisabled")
  }

  /// Starts the managed server again (after it ended or failed).
  func restartManagedServer() async {
    guard managed.mode == .managed else { return }
    await managedServer.start(managed)
  }

  /// Saves the settings and the secret, starts or stops the managed server, then reconnects.
  func apply(_ newSettings: ConnectionSettings, secret: String, managed newManaged: ManagedServerSettings) async {
    settings = newSettings
    settingsStore.save(newSettings)
    managed = newManaged
    managedStore.save(newManaged)
    if newManaged.mode == .managed {
      await managedServer.start(newManaged)
    } else {
      await managedServer.stopAndWait()
    }
    do {
      try secretStore.write(secret)
      secretSaveFailed = false
    } catch {
      secretSaveFailed = true
    }
    await monitor.replaceBackend(makeBackend())
  }

  /// Managed mode talks to its own server: this Mac, its port, TLS, no shared secret (the
  /// server is started without one, and listens on this Mac only).
  private var effectiveSettings: ConnectionSettings {
    managed.mode == .managed ? ConnectionSettings(host: "127.0.0.1", port: managed.port, useTLS: true) : settings
  }

  private func makeBackend() -> (any GenerationBackend)? {
    let effective = effectiveSettings
    guard effective.validationError == nil else { return nil }
    return DrawThingsBackend(
      host: effective.trimmedHost, port: effective.port, useTLS: effective.useTLS,
      sharedSecret: managed.mode == .managed ? nil : secretStore.read())
  }
}
```

- [ ] **Step 2: Creare `App/Connection/ManagedServerText.swift`**

```swift
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
```

- [ ] **Step 3: Creare `App/Connection/ManagedServerBanner.swift`**

```swift
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
```

- [ ] **Step 4: Sostituire `App/Preferences/DrawThingsPreferencesView.swift` con:**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI

/// Preferences › Draw Things: how DT Hub reaches the server — one already running, or a
/// gRPCServerCLI that DT Hub starts — and whether it is reached (spec §5, §7). Edits stay
/// local until Connect, so typing does not reconnect on every keystroke.
struct DrawThingsPreferencesView: View {
  let connection: DrawThingsConnection

  @State private var draft = ConnectionSettings.default
  @State private var managedDraft = ManagedServerSettings.default
  @State private var secret = ""
  /// The ports as typed: parsed on every keystroke, so Connect never uses a stale value.
  @State private var portText = ""
  @State private var managedPortText = ""
  @State private var isApplying = false

  private var monitor: ConnectionMonitor { connection.monitor }
  private var server: ManagedServer { connection.managedServer }
  private var isManaged: Bool { managedDraft.mode == .managed }

  /// Where Draw Things publishes the releases that include gRPCServerCLI.
  private static let releasesURL = URL(string: "https://github.com/drawthingsai/draw-things-community/releases")!

  var body: some View {
    Form {
      Section {
        Picker("prefs.server.mode", selection: $managedDraft.mode) {
          Text("prefs.server.mode.attach").tag(ServerMode.attach)
          Text("prefs.server.mode.managed").tag(ServerMode.managed)
        }
        .pickerStyle(.segmented)
      }

      if isManaged {
        managedSection
      } else {
        attachSection
      }

      Section {
        HStack(spacing: DS.controlGap) {
          DSStatusDot(status: connection.indicator)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
            if case .unreachable(let detail)? = monitor.lastError, !isManaged {
              Text(verbatim: detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
          }
          Spacer(minLength: DS.controlGap)
          Button("prefs.dt.connect") {
            Task {
              isApplying = true
              await connection.apply(draft, secret: secret, managed: managedDraft)
              isApplying = false
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(!canApply || isApplying)
        }
        if connection.secretSaveFailed {
          Text("prefs.dt.secret.saveError")
            .foregroundStyle(DS.remove)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear {
      draft = connection.settings
      managedDraft = connection.managed
      portText = String(connection.settings.port)
      managedPortText = String(connection.managed.port)
      secret = connection.savedSecret()
      // A program found in the usual places is offered; nothing is looked for elsewhere.
      if managedDraft.binaryPath.isEmpty, let found = CLILocator.find() { managedDraft.binaryPath = found }
    }
  }

  // MARK: Attach to a running server

  private var attachSection: some View {
    Section {
      TextField("prefs.dt.host", text: $draft.host)
      TextField("prefs.dt.port", text: $portText)
        .onChange(of: portText) {
          draft.port = ConnectionSettings.parsePort(portText) ?? 0
        }
      Toggle("prefs.dt.tls", isOn: $draft.useTLS)
      SecureField("prefs.dt.secret", text: $secret, prompt: Text("prefs.dt.secret.placeholder"))
    } footer: {
      if let validationMessage {
        Text(validationMessage)
          .foregroundStyle(DS.remove)
      } else {
        Text("prefs.dt.note")
          .foregroundStyle(.secondary)
      }
    }
  }

  // MARK: DT Hub starts the server

  @ViewBuilder private var managedSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.server.binary", text: $managedDraft.binaryPath)
        Button("prefs.server.choose") { choose(directories: false) { managedDraft.binaryPath = $0 } }
      }
      HStack(spacing: DS.controlGap) {
        TextField("prefs.server.models", text: $managedDraft.modelsFolder)
        Button("prefs.server.choose") { choose(directories: true) { managedDraft.modelsFolder = $0 } }
      }
      Button("prefs.server.models.useApp") {
        managedDraft.modelsFolder = CLILocator.drawThingsAppModelsFolder()
      }
      TextField("prefs.server.port", text: $managedPortText)
        .onChange(of: managedPortText) {
          managedDraft.port = ConnectionSettings.parsePort(managedPortText) ?? 0
        }
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if let problem = managedDraft.validationError() {
          Text(ManagedServerText.headline(problem))
            .foregroundStyle(DS.remove)
        } else if managedDraft.warning() == .noModelFiles {
          Text("prefs.server.noModelFiles")
            .foregroundStyle(DS.remove)
        }
        Text("prefs.server.note")
          .foregroundStyle(.secondary)
        if managedDraft.binaryPath.isEmpty || managedDraft.validationError() == .binaryNotExecutable {
          Link("prefs.server.get", destination: Self.releasesURL)
        }
      }
    }

    if !server.logTail.isEmpty || server.isRunning {
      Section {
        if server.isRunning {
          Button("prefs.server.stop") { server.stop() }
        }
        if !server.logTail.isEmpty {
          DisclosureGroup("prefs.server.log") {
            Text(verbatim: server.logTail.joined(separator: "\n"))
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }

  private func choose(directories: Bool, _ pick: (String) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = !directories
    panel.canChooseDirectories = directories
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url { pick(url.path) }
  }

  // MARK: Status

  private var canApply: Bool {
    isManaged ? managedDraft.validationError() == nil : draft.validationError == nil
  }

  private var validationMessage: String? {
    switch draft.validationError {
    case .emptyHost: String(localized: "prefs.dt.error.emptyHost")
    case .invalidHost: String(localized: "prefs.dt.error.invalidHost")
    case .invalidPort: String(localized: "prefs.dt.error.invalidPort")
    case nil: nil
    }
  }

  private var statusLine: String {
    if connection.managed.mode == .managed, monitor.status != .connected, connection.indicator == .connecting {
      return String(localized: "status.serverStarting")
    }
    if connection.managed.mode == .managed, let problem = ManagedServerText.problem(server.state) {
      return problem
    }
    guard monitor.status == .connected else {
      return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
    }
    if monitor.catalog.isModelBrowsingDisabled {
      return connection.noModelsText
    }
    return String(format: String(localized: "prefs.dt.models"), monitor.catalog.models.count)
  }
}
```

- [ ] **Step 5: Sostituire `App/MainWindow/HeaderBar.swift` con:**

```swift
import HubCore
import HubKit
import SwiftUI

/// [Plug-ins ▾] [Model ▾ · family] … ● DT [⚙︎] [▶ Run] (spec §7).
struct HeaderBar: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  @Environment(\.openWindow) private var openWindow

  private var monitor: ConnectionMonitor { connection.monitor }
  private var selection: ModelSelection { connection.selection }
  private var selectedModel: CatalogModel? { selection.selectedModel(in: monitor.catalog) }

  private var runBlocker: RunBlocker? {
    RunAvailability.blocker(
      connection: monitor.status, selectedModel: selection.selectedFile, catalog: monitor.catalog)
  }

  var body: some View {
    HStack(spacing: DS.controlGap) {
      pluginsMenu
      modelMenu
      Spacer(minLength: DS.groupGap)
      DSStatusDot(status: connection.indicator)
        .padding(.horizontal, 6)
        .help(statusText)
        .accessibilityLabel(statusText)
      SettingsLink {
        Image(systemName: "gearshape")
      }
      .buttonStyle(DSGlassCircleButtonStyle())
      .help(String(localized: "header.preferences"))
      .accessibilityLabel(String(localized: "header.preferences"))
      runButton
    }
    .padding(.horizontal, DS.panelPadding)
    .padding(.vertical, 10)
    .dsPanel()
  }

  private var pluginsMenu: some View {
    Menu {
      Text("header.plugins.none")
    } label: {
      DSMenuLabel(String(localized: "header.plugins"), systemImage: "puzzlepiece.extension")
    }
    .dsMenuPill()
  }

  private var modelMenu: some View {
    Menu {
      modelMenuContent
    } label: {
      DSMenuLabel(modelTitle, detail: modelDetail, systemImage: "cube")
    }
    .dsMenuPill()
  }

  /// Models grouped by family, the selected one checked (spec §5, §7).
  @ViewBuilder private var modelMenuContent: some View {
    if monitor.status != .connected {
      Text("header.model.unavailable")
    } else if monitor.catalog.isModelBrowsingDisabled {
      Text(verbatim: connection.noModelsText)
    } else if monitor.catalog.models.isEmpty {
      Text("header.model.empty")
    } else {
      ForEach(monitor.catalog.modelsByFamily) { group in
        Section {
          ForEach(group.models) { model in
            Toggle(
              isOn: Binding(
                get: { selection.selectedFile == model.file },
                set: { _ in selection.select(model.file) })
            ) {
              Text(verbatim: model.name)
            }
          }
        } header: {
          Text(verbatim: group.family ?? "—")
        }
      }
    }
  }

  private var modelTitle: String {
    if let selectedModel { return selectedModel.name }
    return selection.selectedFile ?? String(localized: "header.model.none")
  }

  /// The family of the selected model, or a warning when the server lacks it.
  private var modelDetail: String? {
    if let selectedModel { return selectedModel.family }
    if selection.selectedFile != nil, monitor.status == .connected,
      !monitor.catalog.isModelBrowsingDisabled
    {
      return String(localized: "header.model.missing")
    }
    return nil
  }

  /// RUN, or Stop with the progress while a generation runs (spec §7). ⌘↩ and ⌘. are in the
  /// Generation menu (`GenerationCommands`), so they work from every window.
  @ViewBuilder private var runButton: some View {
    if case .running(let step, let total) = generation.session.phase {
      Button {
        generation.session.cancel()
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "stop.fill")
            .font(.system(size: 14, weight: .semibold))
            .accessibilityHidden(true)
          Text("header.stop")
          if let step {
            Text(verbatim: "\(step)/\(total)")
              .monospacedDigit()
          }
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .help(String(localized: "header.stop.help"))
    } else {
      Button {
        if generation.run(with: connection) { openWindow(id: ResultsWindow.id) }
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "play.fill")
            .font(.system(size: 14, weight: .semibold))
            .accessibilityHidden(true)
          Text("header.run")
        }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
      .disabled(runBlocker != nil)
      .help(runHelp)
    }
  }

  private var runHelp: String {
    switch runBlocker {
    case .notConnected: String(localized: "run.blocked.notConnected")
    case .noModelSelected: String(localized: "run.blocked.noModel")
    case .modelBrowsingDisabled: connection.noModelsText
    case .modelNotOnServer: String(localized: "run.blocked.modelMissing")
    case nil: String(localized: "header.run.help")
    }
  }

  private var statusText: String {
    if connection.managed.mode == .managed, connection.managedServer.isRunning, monitor.status != .connected {
      return String(localized: "status.serverStarting")
    }
    if monitor.status == .connected, monitor.catalog.isModelBrowsingDisabled {
      return connection.noModelsText
    }
    return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
  }
}
```

- [ ] **Step 6: Sostituire `App/MainWindow/MainWindowView.swift` con:**

```swift
import HubCore
import HubKit
import SwiftUI

/// Header, tab bar, and the content of the selected tab (spec §7).
struct MainWindowView: View {
  let workspace: WorkspaceState
  let connection: DrawThingsConnection
  let generation: GenerationController

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      HeaderBar(connection: connection, generation: generation)
      ManagedServerBanner(connection: connection)
      WorkspaceTabBar(workspace: workspace)
      tabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(20)
    .frame(minWidth: 900, idealWidth: 1100, minHeight: 640, idealHeight: 820)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
  }

  @ViewBuilder private var tabContent: some View {
    if workspace.selectedTabID == WorkspaceTab.generationID {
      GenerationTabView(controller: generation, connection: connection)
    } else {
      // Plug-in tabs arrive with the plug-in contract (M7).
      EmptyView()
    }
  }
}
```

- [ ] **Step 7: Sostituire `App/DTHubApp.swift` con:**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI

@main
struct DTHubApp: App {
  @State private var workspace = WorkspaceState(
    generationTab: WorkspaceTab(
      id: WorkspaceTab.generationID,
      title: String(localized: "tab.generation"),
      systemImage: "slider.horizontal.3"))
  @State private var connection = DrawThingsConnection()
  @State private var generation = GenerationController()

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection, generation: generation)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          generation.saveSessionNow()
          connection.managedServer.terminateNow()
        }
    }
    .windowResizability(.contentMinSize)
    .commands {
      CommandMenu(String(localized: "tab.generation")) {
        GenerationCommands(generation: generation, connection: connection)
      }
    }

    Window(String(localized: "results.title"), id: ResultsWindow.id) {
      ResultsView(controller: generation, connection: connection)
    }
    .windowResizability(.contentMinSize)

    Settings {
      PreferencesView(connection: connection, generation: generation)
    }
  }
}
```

- [ ] **Step 8: Build e test**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with|Missing|Not in|Pass String" | grep -v started`
Expected: `** BUILD SUCCEEDED **`; test HubKit 44, HubCore 138, DTBridge 47, Catalog 6: **235** passati.

- [ ] **Step 9: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: modalità server gestito — Preferenze, avviso con Riavvia, pallino giallo, arresto all'uscita

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Verifica dal vivo

Nessun codice nuovo. Serve gRPCServerCLI installato (sul Mac dell'utente in `~/Applications/DrawThings-CLI/gRPCServerCLI-macOS`) e la cartella dei modelli reale (`/Volumes/LLM-VLM/Models`). Prima si annota che l'impostazione `drawThings.managedServer` non esiste ancora; alla fine si toglie.

- [ ] **Step 1: Avviare l'app** (le Preferenze si aprono con ⌘, o dal menu "DT Hub › Impostazioni…")

```bash
defaults read com.exiztenz.DTHub drawThings.managedServer 2>&1 | head -1; open "/Users/existenz/Software developement/DT Hub/build/Build/Products/Debug/DT Hub.app"
```

- [ ] **Step 2: Checklist (screenshot)**

1. Preferenze › Draw Things: in cima il selettore "Collegati a un server già attivo" / "Avvia gRPCServerCLI". Scegliendo il secondo, il programma è già proposto (se è in uno dei percorsi usuali) e "Collega" è spento finché manca la cartella dei modelli.
2. "Usa la cartella dei modelli predefinita dell'app Draw Things" riempie il campo e, se la cartella non ha `.ckpt`, compare l'avviso arancio che dice di scegliere la cartella dove Draw Things tiene i modelli.
3. Con la cartella giusta (`/Volumes/LLM-VLM/Models`) e "Collega": entro pochi secondi `pgrep -fl gRPCServerCLI` mostra una sola riga con `--address 127.0.0.1 --port 7860 --model-browser` e **senza** `--shared-secret`.
4. Il pallino è giallo mentre il server parte, poi verde; il menu modello elenca i modelli; Run è attivo (anche con l'app Draw Things chiusa).
5. Un crash simulato con `pkill -9 -f gRPCServerCLI-macOS`: pallino rosso, Run spento, banner "Il server si è interrotto (segnale 9)…" con "Riavvia" e "Preferenze…". "Riavvia" riporta tutto al verde e toglie l'avviso; nessun riavvio da solo.
6. `pkill -9 -f "DT Hub.app/Contents/MacOS"` (DT Hub finisce male): il server resta; riaprendo l'app resta **un solo** server, con un id nuovo.
7. Uscire dall'app (⌘Q): `pgrep -fl gRPCServerCLI` non mostra nulla.
8. Una porta già occupata (per esempio quella dell'API Server dell'app Draw Things, se acceso): "Collega" non avvia nulla e il banner dice "Porta … già in uso".
9. Tornando a "Collegati a un server già attivo" e "Collega", il server gestito si ferma e l'app usa indirizzo, porta, TLS e segreto di prima.

Punti che servono all'utente (la scelta dei file con il pannello di apertura e le prove sulla porta occupata): lasciare **l'app aperta** per le sue prove.

- [ ] **Step 3: Pulizia**

```bash
osascript -e 'quit app "DT Hub"'; defaults delete com.exiztenz.DTHub drawThings.managedServer; pgrep -fl gRPCServerCLI || echo "nessun server rimasto"
```

---

## Fine della M5

Esito atteso sul branch `m5-server-gestito`:
- **235 test verdi**, di cui 3 live eseguiti solo con `DTHUB_LIVE_DT`;
- build Xcode pulita;
- DT Hub funziona senza l'app Draw Things aperta, con il server avviato, controllato e chiuso da DT Hub.

Poi: revisione indipendente, correzioni, merge, e il piano di M6 (servizio LLM con MLX).

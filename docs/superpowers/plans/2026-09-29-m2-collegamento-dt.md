# M2 Collegamento DT — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DT Hub si collega da solo al server gRPC di Draw Things: il pallino di stato diventa reale, il menu modello elenca i modelli installati raggruppati per famiglia, la scelta viene ricordata e RUN si abilita quando server e modello ci sono; le Preferenze › Draw Things configurano indirizzo, porta, TLS e codice di accesso.

**Architecture:** HubKit riceve il contratto (`ModelCatalog`, protocollo `GenerationBackend`). Un nuovo modulo `DTBridge` lo implementa con DrawThings-Swift (chiamata `Echo` + specifiche dei modelli). HubCore aggiunge impostazioni, Portachiavi, `ConnectionMonitor` (controllo ogni 5 s, risposte di backend sostituiti scartate), `ModelSelection` e la regola di RUN estesa. L'app collega tutto in `DrawThingsConnection`, che parte con l'app e vive quanto lei.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, DrawThings-Swift 2.2.x (`DrawThingsClient`), Security.framework (Portachiavi).

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 4, 5, 7, 10, 11, 12, 15-M2).

## Global Constraints

- Radice del repository: `<repo>` (percorsi sempre tra virgolette).
- Branch `m2-collegamento-dt`, creato da `m1-ossatura` (M1 non è ancora in `main`).
- macOS 26.0, Apple Silicon, Xcode 27, Swift 6, pacchetto `swift-tools-version: 6.2`.
- Regole di dipendenza (spec §4): `HubKit` nessuna dipendenza; `HubCore` → solo `HubKit`; `DTBridge` → `HubKit` + `DrawThingsClient`; l'app → tutti e tre. **Solo `DTBridge` importa DrawThings-Swift.**
- DrawThings-Swift: `https://github.com/euphoriacyberware-ai/DrawThings-Swift.git`, `.upToNextMinor(from: "2.2.0")` (un solo manutentore: solo aggiornamenti di patch). `Packages/Package.resolved` va nel commit.
- Server predefinito: `localhost`, porta `7859`, TLS attivo (spec §5). Codice di accesso nel Portachiavi, servizio `com.exiztenz.DTHub`, account `drawThings.sharedSecret` (spec §5, §11).
- Specifiche dei modelli: solo quelle incluse in DrawThings-Swift (`ModelSpecSource.bundled`) più quelle comunicate dal server. Niente lista remota: senza rete verrebbe riscaricata per ogni file sconosciuto.
- Controllo del server ogni 5 s, anche da collegato; timeout della chiamata `Echo` 5 s.
- Ogni testo visibile in `App/Localizable.xcstrings`, `en` + `it` (spec §12). **Nessuna interpolazione nei letterali localizzati**: il test del catalogo legge il sorgente, quindi per i numeri si usa `String(format: String(localized: "chiave"), n)`.
- Colori solo dai token `DS`; un solo pulsante principale colorato per schermata.
- Indentazione a 2 spazi. Ogni commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Avvisi `DVTCoreDeviceCore` / `CoreSimulator` di `xcodebuild` innocui: contano `error:` e `** BUILD SUCCEEDED **`.
- Il server Draw Things dell'utente è l'API Server dell'app DT su `localhost:7859` (TLS, model browsing attivo, 15 modelli). I test "live" girano solo con `DTHUB_LIVE_DT=localhost:7859`.

## Review Focus

- L'utente cambia indirizzo o porta mentre un controllo è in corso → la risposta del server vecchio non deve sovrascrivere lo stato del nuovo (test `ignoresAReplyFromAReplacedBackend`, Task 5).
- Il server DT si chiude mentre DT Hub è collegato → entro ~5 s pallino rosso, catalogo vuoto, RUN disabilitato; quando il server torna, pallino verde da solo senza toccare nulla (test `losingTheServerClearsTheCatalog` e `reconnectsWhenTheServerComesBack`, Task 5; verifica dal vivo in Task 9).
- Il modello scelto non c'è sul server collegato (altro Mac, modello cancellato) → header con nome del file e "non presente sul server", RUN disabilitato con il motivo, scelta conservata (test `modelMissingFromServerBlocks` Task 7, `resolvesTheSelectedModelOnlyWhenInstalled` Task 7).
- "Model browsing" spento nel server → pallino verde ma menu e Preferenze spiegano come attivarlo invece di un menu vuoto muto (test `noFilesMeansModelBrowsingIsOff` Task 2, `emptyCatalogReportsModelBrowsingDisabled` Task 1).
- Indirizzo con `http://`, spazi o percorso, porta fuori da 1–65535 → messaggio sotto i campi, "Collega" disabilitato, nessun tentativo di connessione (test `rejectsBadHosts`, `rejectsPortsOutOfRange` Task 3; `invalidSettingsLeaveItDisconnected` Task 5).

---

## File Structure

```
Packages/
├── Package.swift                                   + dipendenza DrawThings-Swift, target DTBridge, HubKitTests, DTBridgeTests
├── Package.resolved                                (nuovo, generato da SwiftPM)
├── Sources/
│   ├── HubKit/
│   │   ├── Catalog/ModelCatalog.swift              CatalogModel, CatalogLoRA, ModelFamilyGroup, ModelCatalog
│   │   ├── Backend/GenerationBackend.swift         BackendError, protocollo GenerationBackend
│   │   └── DesignSystem/DSButtons.swift            (modifica) DSMenuLabel con `detail`
│   ├── DTBridge/
│   │   ├── CatalogBuilder.swift                    echo → ModelCatalog (funzioni pure)
│   │   └── DrawThingsBackend.swift                 GenerationBackend su DrawThingsService
│   └── HubCore/
│       ├── Connection/ConnectionSettings.swift     ConnectionSettings (+ validazione), ConnectionSettingsStore
│       ├── Connection/SecretStore.swift            SecretStore, KeychainSecretStore
│       ├── Connection/ConnectionMonitor.swift      stato, catalogo, errore, controllo periodico
│       ├── Selection/ModelSelection.swift          modello scelto, ricordato
│       └── Run/RunAvailability.swift               (modifica) + modelNotOnServer
└── Tests/
    ├── HubKitTests/ModelCatalogTests.swift
    ├── DTBridgeTests/CatalogBuilderTests.swift
    ├── DTBridgeTests/LiveServerTests.swift
    ├── HubCoreTests/ConnectionSettingsTests.swift
    ├── HubCoreTests/KeychainSecretStoreTests.swift
    ├── HubCoreTests/FakeBackend.swift
    ├── HubCoreTests/ConnectionMonitorTests.swift
    ├── HubCoreTests/ModelSelectionTests.swift
    ├── HubCoreTests/RunAvailabilityTests.swift     (riscritto)
    └── CatalogTests/LocalizationCatalogTests.swift (modifica) riconosce TextField e SecureField
App/
├── DTHubApp.swift                                  (modifica) crea DrawThingsConnection
├── Localizable.xcstrings                           (modifica) 17 chiavi nuove
├── Connection/DrawThingsConnection.swift           collegamento a livello app
├── Connection/ConnectionStatusText.swift           testi dello stato, condivisi
├── MainWindow/MainWindowView.swift                 (modifica)
├── MainWindow/HeaderBar.swift                      (riscritto) menu modelli, stato e RUN reali
├── Preferences/PreferencesView.swift               (modifica)
└── Preferences/DrawThingsPreferencesView.swift     pannello Draw Things
DTHub.xcodeproj/project.pbxproj                     (modifica) l'app collega il prodotto DTBridge
```

---

### Task 1: Contratto HubKit — catalogo e backend

**Files:**
- Modify: `Packages/Package.swift`
- Create: `Packages/Sources/HubKit/Catalog/ModelCatalog.swift`
- Create: `Packages/Sources/HubKit/Backend/GenerationBackend.swift`
- Test: `Packages/Tests/HubKitTests/ModelCatalogTests.swift`

**Interfaces:**
- Consumes: niente.
- Produces (HubKit, tutti `public`):
  - `struct CatalogModel: Identifiable, Equatable, Sendable` — `file: String`, `name: String`, `family: String?`, `id` = `file`, `init(file:name:family:)`
  - `struct CatalogLoRA: Identifiable, Equatable, Sendable` — stessi campi e init
  - `struct ModelFamilyGroup: Identifiable, Equatable, Sendable` — `family: String?`, `models: [CatalogModel]`
  - `struct ModelCatalog: Equatable, Sendable` — `models`, `loras`, `fileCount: Int`, `init(models:loras:fileCount:)`, `static let empty`, `var isModelBrowsingDisabled: Bool`, `func model(forFile:) -> CatalogModel?`, `var modelsByFamily: [ModelFamilyGroup]`
  - `enum BackendError: Error, Equatable, Sendable { case unauthorized; case unreachable(String) }`
  - `protocol GenerationBackend: Sendable { func fetchCatalog() async throws -> ModelCatalog; func shutdown() async }`

- [ ] **Step 1: Creare il branch**

```bash
cd "<repo>" && git switch m1-ossatura && git switch -c m2-collegamento-dt
```

Expected: `Switched to a new branch 'm2-collegamento-dt'`

- [ ] **Step 2: Aggiungere il target di test `HubKitTests` a `Packages/Package.swift`**

Sostituire il blocco `targets:` con:

```swift
  targets: [
    .target(name: "HubKit"),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
```

- [ ] **Step 3: Scrivere i test che falliscono — `Packages/Tests/HubKitTests/ModelCatalogTests.swift`**

```swift
import Testing

@testable import HubKit

struct ModelCatalogTests {
  let klein = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b")
  let kleinKV = CatalogModel(file: "flux_2_klein_9b_kv_q8p.ckpt", name: "FLUX.2 [klein] 9B KV", family: "flux2_9b")
  let qwen = CatalogModel(file: "qwen_image_2.1_q8p.ckpt", name: "Qwen Image 2.1", family: "qwen_image_2.1")
  let mystery = CatalogModel(file: "custom.ckpt", name: "Custom", family: nil)

  @Test func emptyCatalogReportsModelBrowsingDisabled() {
    #expect(ModelCatalog.empty.isModelBrowsingDisabled)
    #expect(!ModelCatalog(models: [], loras: [], fileCount: 3).isModelBrowsingDisabled)
  }

  @Test func findsModelByFile() {
    let catalog = ModelCatalog(models: [klein, qwen], loras: [], fileCount: 2)
    #expect(catalog.model(forFile: qwen.file) == qwen)
    #expect(catalog.model(forFile: "missing.ckpt") == nil)
  }

  @Test func groupsModelsByFamilyWithUnknownFamilyLast() {
    let catalog = ModelCatalog(models: [mystery, qwen, kleinKV, klein], loras: [], fileCount: 4)
    #expect(catalog.modelsByFamily.map(\.family) == ["flux2_9b", "qwen_image_2.1", nil])
    #expect(catalog.modelsByFamily[0].models == [klein, kleinKV])
  }
}
```

- [ ] **Step 4: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'CatalogModel' in scope`

- [ ] **Step 5: Implementare — `Packages/Sources/HubKit/Catalog/ModelCatalog.swift`**

```swift
/// A generative model installed on the Draw Things server.
public struct CatalogModel: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Draw Things model version, e.g. "flux2_9b": the model family key of spec §5.
  public let family: String?

  public init(file: String, name: String, family: String?) {
    self.file = file
    self.name = name
    self.family = family
  }
}

/// A LoRA installed on the Draw Things server.
public struct CatalogLoRA: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Model family the LoRA was made for; nil when the server does not say.
  public let family: String?

  public init(file: String, name: String, family: String?) {
    self.file = file
    self.name = name
    self.family = family
  }
}

/// Models of one family, for the grouped model menu.
public struct ModelFamilyGroup: Identifiable, Equatable, Sendable {
  public var id: String { family ?? "" }
  /// nil groups the models whose family is unknown.
  public let family: String?
  public let models: [CatalogModel]
}

/// What the Draw Things server has installed, as DT Hub needs it.
public struct ModelCatalog: Equatable, Sendable {
  public let models: [CatalogModel]
  public let loras: [CatalogLoRA]
  /// How many files the server listed. Zero when its "Model browsing" option is off (spec §10).
  public let fileCount: Int

  public init(models: [CatalogModel], loras: [CatalogLoRA], fileCount: Int) {
    self.models = models
    self.loras = loras
    self.fileCount = fileCount
  }

  public static let empty = ModelCatalog(models: [], loras: [], fileCount: 0)

  /// True when a reachable server lists no files at all: its model browsing is off.
  public var isModelBrowsingDisabled: Bool { fileCount == 0 }

  public func model(forFile file: String) -> CatalogModel? {
    models.first { $0.file == file }
  }

  /// Models grouped by family: families in alphabetical order, the unknown family last,
  /// models by name inside each group.
  public var modelsByFamily: [ModelFamilyGroup] {
    let grouped = Dictionary(grouping: models, by: \.family)
    let families = grouped.keys.sorted { lhs, rhs in
      switch (lhs, rhs) {
      case (nil, _): false
      case (_, nil): true
      case let (l?, r?): l.localizedStandardCompare(r) == .orderedAscending
      }
    }
    return families.map { family in
      ModelFamilyGroup(
        family: family,
        models: grouped[family, default: []].sorted {
          $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }
  }
}
```

- [ ] **Step 6: Implementare — `Packages/Sources/HubKit/Backend/GenerationBackend.swift`**

```swift
/// Why the Draw Things server could not be used.
public enum BackendError: Error, Equatable, Sendable {
  /// The server wants a shared secret, or rejected the one sent.
  case unauthorized
  /// The server could not be reached; the detail is the underlying error, for display.
  case unreachable(String)
}

/// The generation server as HubCore sees it (spec §4). DTBridge implements it with gRPC;
/// tests use a fake. M3 adds generation.
public protocol GenerationBackend: Sendable {
  /// Asks the server what it has installed. Doubles as the connection check.
  func fetchCatalog() async throws -> ModelCatalog
  /// Closes the connection. The backend is not used afterwards.
  func shutdown() async
}
```

- [ ] **Step 7: Verificare che i test passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "Test run|error:"`
Expected: `Test run with 3 tests in 1 suite passed` (HubKitTests), `Test run with 12 tests in 2 suites passed` (HubCoreTests), `Test run with 4 tests in 1 suite passed` (CatalogTests).

- [ ] **Step 8: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: contratto HubKit per il catalogo dei modelli e il backend di generazione

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: DTBridge — dal server Draw Things al catalogo

**Files:**
- Modify: `Packages/Package.swift`
- Create: `Packages/Sources/DTBridge/CatalogBuilder.swift`
- Create: `Packages/Sources/DTBridge/DrawThingsBackend.swift`
- Test: `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift`
- Test: `Packages/Tests/DTBridgeTests/LiveServerTests.swift`
- Create (generato): `Packages/Package.resolved`

**Interfaces:**
- Consumes: `ModelCatalog`, `CatalogModel`, `CatalogLoRA`, `BackendError`, `GenerationBackend` (Task 1).
- Produces:
  - `public final class DrawThingsBackend: GenerationBackend` con `public init(host: String, port: Int, useTLS: Bool, sharedSecret: String?)`
  - interni: `struct ModelSpecInfo: Equatable, Sendable { let name: String; let family: String? }`, `enum CatalogBuilder` con `static func build(files: [String], modelSpecs: [String: ModelSpecInfo], loraMetadata: Data) -> ModelCatalog`, `static func parseLoRAMetadata(_ data: Data) -> [CatalogLoRA]`, `static func specInfo(json: Data, file: String) -> ModelSpecInfo`

Regola di classificazione, verificata sul server dell'utente (155 file → 15 modelli, 102 LoRA, il resto encoder/VAE/ControlNet/upscaler): un file è un **modello** se ha una specifica di modello; le **LoRA** sono quelle dei metadati del server più i file `…_lora_…` senza metadati; tutto il resto non entra nel catalogo.

- [ ] **Step 1: Dipendenza e target in `Packages/Package.swift`**

Sostituire l'intero file con:

```swift
// swift-tools-version: 6.2
import PackageDescription

// One package, one target per module: the compiler enforces the dependency
// rules of spec §4 (a target can only import what it declares).
let package = Package(
  name: "DTHubPackages",
  defaultLocalization: "en",
  platforms: [.macOS(.v26)],
  products: [
    .library(name: "HubKit", targets: ["HubKit"]),
    .library(name: "HubCore", targets: ["HubCore"]),
    .library(name: "DTBridge", targets: ["DTBridge"]),
  ],
  dependencies: [
    // Single maintainer, frequent releases: accept patch updates only (spec §5, §16).
    .package(
      url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift.git",
      .upToNextMinor(from: "2.2.0")),
  ],
  targets: [
    .target(name: "HubKit"),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    // The only module that knows DrawThings-Swift and gRPC (spec §4).
    .target(
      name: "DTBridge",
      dependencies: ["HubKit", .product(name: "DrawThingsClient", package: "DrawThings-Swift")]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
)
```

- [ ] **Step 2: Scrivere i test che falliscono — `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift`**

```swift
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct CatalogBuilderTests {
  let klein = "flux_2_klein_9b_f16.ckpt"
  let vae = "flux_2_vae_f16.ckpt"
  let describedLoRA = "sun_direction_lora_f16.ckpt"
  let bareLoRA = "hyper_sdxl_8_step_lora_f16.ckpt"
  let specs = ["flux_2_klein_9b_f16.ckpt": ModelSpecInfo(name: "FLUX.2 [klein] 9B", family: "flux2_9b")]
  let loraJSON = Data(
    """
    [{"file": "sun_direction_lora_f16.ckpt", "name": "Sun direction", "version": "flux2_9b"},
     {"file": "not_installed_lora_f16.ckpt", "name": "Gone", "version": "flux2_9b"},
     {"name": "No file"}]
    """.utf8)

  @Test func modelsAreTheFilesWithASpec() {
    let catalog = CatalogBuilder.build(
      files: [klein, vae, describedLoRA, bareLoRA], modelSpecs: specs, loraMetadata: loraJSON)
    #expect(catalog.models == [CatalogModel(file: klein, name: "FLUX.2 [klein] 9B", family: "flux2_9b")])
    #expect(catalog.fileCount == 4)
  }

  @Test func loRAsComeFromMetadataPlusUndescribedLoRAFiles() {
    let catalog = CatalogBuilder.build(
      files: [klein, vae, describedLoRA, bareLoRA], modelSpecs: specs, loraMetadata: loraJSON)
    #expect(
      catalog.loras == [
        CatalogLoRA(file: describedLoRA, name: "Sun direction", family: "flux2_9b"),
        CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil),
      ])
  }

  @Test func unreadableLoRAMetadataIsNotFatal() {
    let catalog = CatalogBuilder.build(
      files: [klein, bareLoRA], modelSpecs: specs, loraMetadata: Data("not json".utf8))
    #expect(catalog.models.count == 1)
    #expect(catalog.loras == [CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil)])
  }

  @Test func noFilesMeansModelBrowsingIsOff() {
    let catalog = CatalogBuilder.build(files: [], modelSpecs: [:], loraMetadata: Data())
    #expect(catalog.isModelBrowsingDisabled)
  }

  @Test func specInfoFallsBackToTheFileName() {
    let named = CatalogBuilder.specInfo(json: Data(#"{"name": "Z Image", "version": "z_image"}"#.utf8), file: "z.ckpt")
    let unnamed = CatalogBuilder.specInfo(json: Data(#"{"file": "z.ckpt"}"#.utf8), file: "z.ckpt")
    #expect(named == ModelSpecInfo(name: "Z Image", family: "z_image"))
    #expect(unnamed == ModelSpecInfo(name: "z.ckpt", family: nil))
  }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter CatalogBuilderTests 2>&1 | grep -E "error:" | head -3`
Expected: FAIL. La prima volta SwiftPM scarica DrawThings-Swift e le sue dipendenze (gRPC, protobuf, flatbuffers: qualche minuto). Poi errore di compilazione `cannot find 'ModelSpecInfo' in scope`, oppure un errore di target `DTBridge` senza sorgenti: entrambi valgono come "fallisce".

- [ ] **Step 4: Implementare — `Packages/Sources/DTBridge/CatalogBuilder.swift`**

```swift
import Foundation
import HubKit

/// Name and family of a model file, read from its Draw Things model specification.
struct ModelSpecInfo: Equatable, Sendable {
  let name: String
  let family: String?
}

/// Turns what the server's echo reports into a `ModelCatalog` (spec §5).
///
/// A file is a model when a model specification describes it: the specs bundled with
/// DrawThings-Swift cover the official models, the server's own cover the imported ones.
/// Every other file (text encoders, VAEs, ControlNets, upscalers…) is not a model.
/// LoRAs come from the server's LoRA metadata; a file named `…_lora_…` without metadata
/// is still listed, with no family.
enum CatalogBuilder {
  static func build(files: [String], modelSpecs: [String: ModelSpecInfo], loraMetadata: Data) -> ModelCatalog {
    let installed = Set(files)
    let loraEntries = parseLoRAMetadata(loraMetadata).filter { installed.contains($0.file) }
    let loraFiles = Set(loraEntries.map(\.file))

    let models = files
      .filter { !loraFiles.contains($0) }
      .compactMap { file in
        modelSpecs[file].map { CatalogModel(file: file, name: $0.name, family: $0.family) }
      }
    let unlistedLoRAs = files
      .filter { $0.contains("_lora_") && !loraFiles.contains($0) && modelSpecs[$0] == nil }
      .map { CatalogLoRA(file: $0, name: $0, family: nil) }

    return ModelCatalog(models: models, loras: loraEntries + unlistedLoRAs, fileCount: files.count)
  }

  /// The server's LoRA metadata: a JSON array of objects with `file`, `name`, `version`.
  /// Unreadable data or entries without `file` are skipped, never fatal.
  static func parseLoRAMetadata(_ data: Data) -> [CatalogLoRA] {
    guard !data.isEmpty,
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return array.compactMap { entry in
      guard let file = entry["file"] as? String else { return nil }
      return CatalogLoRA(
        file: file, name: entry["name"] as? String ?? file, family: entry["version"] as? String)
    }
  }

  /// Name and family from a spec's JSON object; the file name stands in for a missing name.
  static func specInfo(json: Data, file: String) -> ModelSpecInfo {
    let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    return ModelSpecInfo(name: object["name"] as? String ?? file, family: object["version"] as? String)
  }
}
```

- [ ] **Step 5: Implementare — `Packages/Sources/DTBridge/DrawThingsBackend.swift`**

```swift
import DrawThingsClient
import HubKit

/// `GenerationBackend` over the Draw Things gRPC server, through DrawThings-Swift.
public final class DrawThingsBackend: GenerationBackend {
  private let service: DrawThingsService

  /// - Parameters:
  ///   - useTLS: the Draw Things API server uses TLS by default (spec §5).
  ///   - sharedSecret: sent with every request when the server requires one.
  public init(host: String, port: Int, useTLS: Bool, sharedSecret: String?) {
    let options = ConnectionOptions(
      security: useTLS ? .tls() : .plaintext,
      sharedSecret: sharedSecret,
      // The echo doubles as the connection check: fail fast instead of the 30 s default.
      requestTimeout: .seconds(5),
      // Bundled specs only: the remote list would be re-fetched for every unknown file
      // while offline. Official models newer than the bundled snapshot need a package update.
      modelSpecs: .bundled)
    service = DrawThingsService(endpoint: ServerEndpoint(host: host, port: port), options: options)
  }

  public func fetchCatalog() async throws -> ModelCatalog {
    let reply: EchoReply
    do {
      reply = try await service.echo(name: "DT Hub")
    } catch DrawThingsError.unauthenticated {
      throw BackendError.unauthorized
    } catch {
      throw BackendError.unreachable(error.localizedDescription)
    }
    var specs: [String: ModelSpecInfo] = [:]
    for file in reply.files {
      if let spec = await service.modelSpecs.spec(for: file) {
        specs[file] = CatalogBuilder.specInfo(json: spec.json, file: file)
      }
    }
    return CatalogBuilder.build(files: reply.files, modelSpecs: specs, loraMetadata: reply.override.loras)
  }

  public func shutdown() async {
    await service.shutdown()
  }
}
```

- [ ] **Step 6: Test sul server vero — `Packages/Tests/DTBridgeTests/LiveServerTests.swift`**

```swift
import Foundation
import HubKit
import Testing

@testable import DTBridge

/// Needs a real Draw Things gRPC server with "Model browsing" on. Run with:
/// `DTHUB_LIVE_DT=localhost:7859 swift test --filter LiveServerTests`
struct LiveServerTests {
  static let address = ProcessInfo.processInfo.environment["DTHUB_LIVE_DT"]

  @Test(.enabled(if: address != nil))
  func fetchesTheInstalledModels() async throws {
    let parts = try #require(Self.address?.split(separator: ":"))
    let backend = DrawThingsBackend(
      host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
    let catalog = try await backend.fetchCatalog()
    await backend.shutdown()
    #expect(!catalog.models.isEmpty)
    #expect(catalog.models.allSatisfy { !$0.name.isEmpty })
  }

  @Test(.enabled(if: address != nil))
  func reportsAnUnreachableServer() async {
    let backend = DrawThingsBackend(host: "localhost", port: 1, useTLS: true, sharedSecret: nil)
    await #expect(throws: BackendError.self) { try await backend.fetchCatalog() }
    await backend.shutdown()
  }
}
```

- [ ] **Step 7: Verificare che i test passino, poi i test sul server vero**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "Test run|error:"`
Expected: tutte le righe `passed`; DTBridgeTests `Test run with 7 tests in 2 suites passed` (i 2 test live risultano saltati).

Run: `cd "<repo>/Packages" && DTHUB_LIVE_DT=localhost:7859 swift test --filter LiveServerTests 2>&1 | grep -E "Test run|failed"`
Expected: `Test run with 2 tests in 1 suite passed`. Se il server DT non è in ascolto su 7859 (verificare con `lsof -nP -iTCP:7859 -sTCP:LISTEN`), annotare nel registro che il test live non è stato eseguito e proseguire.

- [ ] **Step 8: Commit (con `Package.resolved`)**

```bash
cd "<repo>" && git add Packages && git status --short && git commit -m "feat: DTBridge, catalogo dei modelli dal server Draw Things via gRPC

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected da `git status --short`: compare `Packages/Package.resolved`; nessun file sotto `.build/`.

---

### Task 3: Impostazioni di connessione

**Files:**
- Create: `Packages/Sources/HubCore/Connection/ConnectionSettings.swift`
- Test: `Packages/Tests/HubCoreTests/ConnectionSettingsTests.swift`

**Interfaces:**
- Consumes: niente.
- Produces (HubCore, `public`):
  - `struct ConnectionSettings: Equatable, Codable, Sendable` — `var host: String`, `var port: Int`, `var useTLS: Bool`, `init(host: String = "localhost", port: Int = 7859, useTLS: Bool = true)`, `static let default`, `enum ValidationError: Equatable, Sendable { case emptyHost, invalidHost, invalidPort }`, `var trimmedHost: String`, `var validationError: ValidationError?`
  - `struct ConnectionSettingsStore` — `init(defaults: UserDefaults = .standard)`, `func load() -> ConnectionSettings`, `func save(_:)`; `static let key = "drawThings.connection"` (interno)

- [ ] **Step 1: Scrivere i test che falliscono — `Packages/Tests/HubCoreTests/ConnectionSettingsTests.swift`**

```swift
import Foundation
import Testing

@testable import HubCore

struct ConnectionSettingsTests {
  @Test func defaultsPointAtTheLocalDrawThingsServer() {
    #expect(ConnectionSettings.default == ConnectionSettings(host: "localhost", port: 7859, useTLS: true))
    #expect(ConnectionSettings.default.validationError == nil)
  }

  @Test(arguments: [
    ("", ConnectionSettings.ValidationError.emptyHost),
    ("   ", .emptyHost),
    ("http://localhost", .invalidHost),
    ("local host", .invalidHost),
    ("localhost/api", .invalidHost),
  ])
  func rejectsBadHosts(host: String, expected: ConnectionSettings.ValidationError) {
    #expect(ConnectionSettings(host: host).validationError == expected)
  }

  @Test(arguments: [0, -1, 65536])
  func rejectsPortsOutOfRange(port: Int) {
    #expect(ConnectionSettings(port: port).validationError == .invalidPort)
  }

  @Test func acceptsIPAddressesAndTrimsSpaces() {
    let settings = ConnectionSettings(host: " 192.168.1.20 ", port: 7859)
    #expect(settings.validationError == nil)
    #expect(settings.trimmedHost == "192.168.1.20")
  }

  @Test func storeRoundTripsAndFallsBackToDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "ConnectionSettingsTests-\(UUID())"))
    let store = ConnectionSettingsStore(defaults: defaults)
    #expect(store.load() == .default)

    let custom = ConnectionSettings(host: "studio.local", port: 7860, useTLS: false)
    store.save(custom)
    #expect(ConnectionSettingsStore(defaults: defaults).load() == custom)

    defaults.set(Data("garbage".utf8), forKey: ConnectionSettingsStore.key)
    #expect(store.load() == .default)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter ConnectionSettingsTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ConnectionSettings' in scope`

- [ ] **Step 3: Implementare — `Packages/Sources/HubCore/Connection/ConnectionSettings.swift`**

```swift
import Foundation

/// Where the Draw Things gRPC server is (spec §5). The shared secret is not here: it lives
/// in the Keychain (`SecretStore`).
public struct ConnectionSettings: Equatable, Codable, Sendable {
  public var host: String
  public var port: Int
  public var useTLS: Bool

  public init(host: String = "localhost", port: Int = 7859, useTLS: Bool = true) {
    self.host = host
    self.port = port
    self.useTLS = useTLS
  }

  public static let `default` = ConnectionSettings()

  public enum ValidationError: Equatable, Sendable {
    case emptyHost
    /// A URL or text with spaces instead of a host name or IP address.
    case invalidHost
    case invalidPort
  }

  /// The host without surrounding spaces, as sent to the server.
  public var trimmedHost: String { host.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// Why these settings cannot be used, or nil when they can.
  public var validationError: ValidationError? {
    let host = trimmedHost
    if host.isEmpty { return .emptyHost }
    if host.contains("://") || host.contains(where: \.isWhitespace) || host.contains("/") {
      return .invalidHost
    }
    if !(1...65535).contains(port) { return .invalidPort }
    return nil
  }
}

/// Persists `ConnectionSettings` in UserDefaults as JSON (spec §11).
public struct ConnectionSettingsStore {
  private let defaults: UserDefaults
  static let key = "drawThings.connection"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The saved settings; the defaults when nothing was saved or the data is unreadable.
  public func load() -> ConnectionSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data)
    else { return .default }
    return settings
  }

  public func save(_ settings: ConnectionSettings) {
    defaults.set(try? JSONEncoder().encode(settings), forKey: Self.key)
  }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `cd "<repo>/Packages" && swift test --filter ConnectionSettingsTests 2>&1 | grep -E "Test run|error:"`
Expected: `Test run with 5 tests in 1 suite passed`

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: impostazioni di connessione a Draw Things con validazione e salvataggio

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Codice di accesso nel Portachiavi

**Files:**
- Create: `Packages/Sources/HubCore/Connection/SecretStore.swift`
- Test: `Packages/Tests/HubCoreTests/KeychainSecretStoreTests.swift`

**Interfaces:**
- Consumes: niente.
- Produces (HubCore, `public`): `protocol SecretStore: Sendable { func read() -> String?; func write(_ secret: String?) throws }`, `struct KeychainError: Error, Equatable, Sendable { let status: OSStatus }`, `struct KeychainSecretStore: SecretStore` con `init(service: String = "com.exiztenz.DTHub", account: String = "drawThings.sharedSecret")`

- [ ] **Step 1: Scrivere il test che fallisce — `Packages/Tests/HubCoreTests/KeychainSecretStoreTests.swift`**

```swift
import Foundation
import Testing

@testable import HubCore

/// Uses the real login Keychain, under a throwaway service name removed at the end.
struct KeychainSecretStoreTests {
  @Test func writesReadsReplacesAndRemovesTheSecret() throws {
    let store = KeychainSecretStore(service: "com.exiztenz.DTHub.tests.\(UUID())", account: "secret")
    defer { try? store.write(nil) }

    #expect(store.read() == nil)
    try store.write("first")
    #expect(store.read() == "first")
    try store.write("second")
    #expect(store.read() == "second")
    try store.write("")
    #expect(store.read() == nil)
  }
}
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "<repo>/Packages" && swift test --filter KeychainSecretStoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'KeychainSecretStore' in scope`

- [ ] **Step 3: Implementare — `Packages/Sources/HubCore/Connection/SecretStore.swift`**

```swift
import Foundation
import Security

/// Where the Draw Things shared secret is kept (spec §5, §11: the Keychain).
public protocol SecretStore: Sendable {
  func read() -> String?
  /// Saves the secret; nil or an empty string removes it.
  func write(_ secret: String?) throws
}

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

/// A generic-password Keychain item, one per service/account pair.
public struct KeychainSecretStore: SecretStore {
  let service: String
  let account: String

  public init(service: String = "com.exiztenz.DTHub", account: String = "drawThings.sharedSecret") {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  public func read() -> String? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func write(_ secret: String?) throws {
    let deleteStatus = SecItemDelete(query as CFDictionary)
    guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
      throw KeychainError(status: deleteStatus)
    }
    guard let secret, !secret.isEmpty else { return }
    var item = query
    item[kSecValueData as String] = Data(secret.utf8)
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
}
```

- [ ] **Step 4: Verificare che il test passi**

Run: `cd "<repo>/Packages" && swift test --filter KeychainSecretStoreTests 2>&1 | grep -E "Test run|error:"`
Expected: `Test run with 1 test in 1 suite passed`. Se macOS mostra una richiesta di accesso al Portachiavi, va accettata dall'utente: annotarlo e proseguire.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: codice di accesso di Draw Things nel Portachiavi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: ConnectionMonitor — stato, catalogo e controllo periodico

**Files:**
- Create: `Packages/Sources/HubCore/Connection/ConnectionMonitor.swift`
- Test: `Packages/Tests/HubCoreTests/FakeBackend.swift`
- Test: `Packages/Tests/HubCoreTests/ConnectionMonitorTests.swift`

**Interfaces:**
- Consumes: `GenerationBackend`, `ModelCatalog`, `BackendError`, `ConnectionStatus` (HubKit).
- Produces (HubCore): `@MainActor @Observable public final class ConnectionMonitor` con `init()`, `private(set) var status: ConnectionStatus`, `private(set) var catalog: ModelCatalog`, `private(set) var lastError: BackendError?`, `static let defaultInterval: Duration` (5 s), `func replaceBackend(_ newBackend: (any GenerationBackend)?) async`, `func refresh() async`, `func run(every interval: Duration = defaultInterval, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async`

- [ ] **Step 1: Backend finto per i test — `Packages/Tests/HubCoreTests/FakeBackend.swift`**

```swift
import HubKit

/// A `GenerationBackend` whose answer and delay the test controls.
actor FakeBackend: GenerationBackend {
  private var result: Result<ModelCatalog, BackendError>
  private let delay: Duration?
  private(set) var fetchCount = 0
  private(set) var didShutDown = false

  init(_ result: Result<ModelCatalog, BackendError>, delay: Duration? = nil) {
    self.result = result
    self.delay = delay
  }

  func setResult(_ newResult: Result<ModelCatalog, BackendError>) {
    result = newResult
  }

  func fetchCatalog() async throws -> ModelCatalog {
    fetchCount += 1
    if let delay { try await Task.sleep(for: delay) }
    return try result.get()
  }

  func shutdown() async {
    didShutDown = true
  }
}
```

- [ ] **Step 2: Scrivere i test che falliscono — `Packages/Tests/HubCoreTests/ConnectionMonitorTests.swift`**

```swift
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ConnectionMonitorTests {
  let catalogA = ModelCatalog(
    models: [CatalogModel(file: "a.ckpt", name: "A", family: "flux2_9b")], loras: [], fileCount: 1)
  let catalogB = ModelCatalog(
    models: [CatalogModel(file: "b.ckpt", name: "B", family: "z_image")], loras: [], fileCount: 1)

  @Test func startsDisconnectedWithAnEmptyCatalog() async {
    let monitor = ConnectionMonitor()
    await monitor.refresh()
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func connectsAndLoadsTheCatalog() async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.success(catalogA)))
    #expect(monitor.status == .connected)
    #expect(monitor.catalog == catalogA)
    #expect(monitor.lastError == nil)
  }

  @Test(arguments: [BackendError.unreachable("refused"), .unauthorized])
  func reportsFailures(error: BackendError) async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.failure(error)))
    #expect(monitor.status == .disconnected)
    #expect(monitor.lastError == error)
  }

  @Test func losingTheServerClearsTheCatalog() async {
    let backend = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    await backend.setResult(.failure(.unreachable("gone")))
    await monitor.refresh()
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func reconnectsWhenTheServerComesBack() async {
    let backend = FakeBackend(.failure(.unreachable("down")))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    await backend.setResult(.success(catalogA))
    await monitor.refresh()
    #expect(monitor.status == .connected)
    #expect(monitor.lastError == nil)
  }

  @Test func replacingTheBackendShutsTheOldOneDown() async {
    let old = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(old)
    await monitor.replaceBackend(FakeBackend(.success(catalogB)))
    #expect(await old.didShutDown)
    #expect(monitor.catalog == catalogB)
  }

  @Test func invalidSettingsLeaveItDisconnected() async {
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(FakeBackend(.success(catalogA)))
    await monitor.replaceBackend(nil)
    #expect(monitor.status == .disconnected)
    #expect(monitor.catalog == .empty)
  }

  @Test func showsConnectingWhileTheFirstCheckRuns() async throws {
    let monitor = ConnectionMonitor()
    let check = Task { await monitor.replaceBackend(FakeBackend(.success(catalogA), delay: .milliseconds(300))) }
    try await Task.sleep(for: .milliseconds(100))
    #expect(monitor.status == .connecting)
    await check.value
    #expect(monitor.status == .connected)
  }

  @Test func staysConnectedDuringAPeriodicCheck() async throws {
    let backend = FakeBackend(.success(catalogA), delay: .milliseconds(300))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let check = Task { await monitor.refresh() }
    try await Task.sleep(for: .milliseconds(100))
    #expect(monitor.status == .connected)
    await check.value
  }

  @Test func ignoresAReplyFromAReplacedBackend() async throws {
    let monitor = ConnectionMonitor()
    let slow = Task { await monitor.replaceBackend(FakeBackend(.success(catalogA), delay: .milliseconds(300))) }
    try await Task.sleep(for: .milliseconds(100))
    await monitor.replaceBackend(FakeBackend(.success(catalogB)))
    await slow.value
    #expect(monitor.catalog == catalogB)
    #expect(monitor.status == .connected)
  }

  @Test func runChecksAfterEachIntervalUntilCancelled() async {
    let backend = FakeBackend(.success(catalogA))
    let monitor = ConnectionMonitor()
    await monitor.replaceBackend(backend)
    let sleeps = SleepCounter(stopAfter: 3)
    await monitor.run(every: .seconds(5)) { _ in try await sleeps.tick() }
    // replaceBackend checked once, then one check after each of the two completed sleeps.
    #expect(await backend.fetchCount == 3)
  }
}

/// A `sleep` stand-in that returns immediately and throws (like a cancelled task) on call `stopAfter`.
actor SleepCounter {
  private let stopAfter: Int
  private var calls = 0

  init(stopAfter: Int) { self.stopAfter = stopAfter }

  func tick() throws {
    calls += 1
    if calls >= stopAfter { throw CancellationError() }
  }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter ConnectionMonitorTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'ConnectionMonitor' in scope`

- [ ] **Step 4: Implementare — `Packages/Sources/HubCore/Connection/ConnectionMonitor.swift`**

```swift
import HubKit
import Observation

/// Keeps the link to Draw Things: status for the header dot, the model catalog, the last
/// error (spec §7, §10). The backend is replaced when the connection settings change.
@MainActor
@Observable
public final class ConnectionMonitor {
  public private(set) var status: ConnectionStatus = .disconnected
  public private(set) var catalog: ModelCatalog = .empty
  public private(set) var lastError: BackendError?

  /// How often the server is checked, connected or not.
  public static let defaultInterval: Duration = .seconds(5)

  @ObservationIgnored private var backend: (any GenerationBackend)?
  /// Bumped on every backend change, so a reply from a replaced backend is dropped.
  @ObservationIgnored private var generation = 0

  public init() {}

  /// Uses a new backend (nil when the settings are invalid): shuts the old one down,
  /// forgets its catalog and connects with the new one.
  public func replaceBackend(_ newBackend: (any GenerationBackend)?) async {
    let old = backend
    backend = newBackend
    generation += 1
    status = .disconnected
    catalog = .empty
    lastError = nil
    await old?.shutdown()
    await refresh()
  }

  /// Asks the server for its catalog once. Shows "connecting" only when not already
  /// connected, so a periodic check does not make the dot blink.
  public func refresh() async {
    guard let backend else {
      status = .disconnected
      catalog = .empty
      return
    }
    let requestGeneration = generation
    if status != .connected { status = .connecting }
    do {
      let newCatalog = try await backend.fetchCatalog()
      guard requestGeneration == generation else { return }
      if catalog != newCatalog { catalog = newCatalog }
      status = .connected
      lastError = nil
    } catch {
      guard requestGeneration == generation else { return }
      status = .disconnected
      catalog = .empty
      lastError = error as? BackendError ?? .unreachable(String(describing: error))
    }
  }

  /// Checks the server every `interval` until the calling task is cancelled
  /// (spec §10: automatic periodic reconnection).
  public func run(
    every interval: Duration = defaultInterval,
    sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) async {
    while true {
      do { try await sleep(interval) } catch { return }
      await refresh()
    }
  }
}
```

- [ ] **Step 5: Verificare che i test passino (tre volte: alcuni usano tempi brevi)**

Run: `cd "<repo>/Packages" && for i in 1 2 3; do swift test --filter ConnectionMonitorTests 2>&1 | grep -E "Test run with|error:"; done`
Expected: tre volte `Test run with 11 tests in 1 suite passed`.

- [ ] **Step 6: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: ConnectionMonitor, stato della connessione e controllo periodico del server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Stringhe di M2 e test del catalogo esteso ai campi di testo

Il test del catalogo (M1) riconosce i letterali di `Text`, `Label`, `Button`, `Toggle`… ma non di `TextField` e `SecureField`, che arrivano con le Preferenze. Qui lo si estende e si aggiungono al catalogo tutte le chiavi usate dai Task 7–9.

**Files:**
- Modify: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift`
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: il test del catalogo di M1 (`localizedLiterals(in:)`).
- Produces: le chiavi `header.model.browsingDisabled`, `header.model.empty`, `header.model.missing`, `run.blocked.modelMissing`, `status.unauthorized`, `prefs.dt.host`, `prefs.dt.port`, `prefs.dt.tls`, `prefs.dt.secret`, `prefs.dt.secret.placeholder`, `prefs.dt.note`, `prefs.dt.connect`, `prefs.dt.models` (formato `%lld`), `prefs.dt.error.emptyHost`, `prefs.dt.error.invalidHost`, `prefs.dt.error.invalidPort`, `prefs.dt.secret.saveError`.

- [ ] **Step 1: Estendere il test di riconoscimento (fallisce)**

In `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift`, dentro `findsLocalizedLiteralsInSource`, sostituire:

```swift
      .help(String(localized: "c.key"))
      """
    #expect(Self.localizedLiterals(in: source) == ["a.key", "b.key", "c.key"])
```

con:

```swift
      .help(String(localized: "c.key"))
      TextField("d.key", text: $host)
      SecureField("e.key", text: $secret)
      """
    #expect(Self.localizedLiterals(in: source) == ["a.key", "b.key", "c.key", "d.key", "e.key"])
```

- [ ] **Step 2: Verificare che fallisca**

Run: `cd "<repo>/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run|failed" | head -3`
Expected: `findsLocalizedLiteralsInSource` fallisce (mancano `d.key` ed `e.key`).

- [ ] **Step 3: Estendere l'espressione regolare**

Nella stessa funzione `localizedLiterals(in:)`, sostituire `Text|Label|Tab|Button|Toggle|Menu|Section|Picker|WindowGroup|ContentUnavailableView` con `Text|TextField|SecureField|Label|Tab|Button|Toggle|Menu|Section|Picker|WindowGroup|ContentUnavailableView`, e nel commento sopra la funzione nulla da cambiare.

- [ ] **Step 4: Aggiungere le chiavi di M2 al catalogo**

```bash
cd "<repo>" && python3 - App/Localizable.xcstrings <<'EOF'
import json, sys
p = sys.argv[1]
catalog = json.load(open(p))
rows = [
 ("header.model.browsingDisabled", "Turn on “Model browsing” in the Draw Things API server settings", "Attiva “Model browsing” nelle impostazioni dell’API Server di Draw Things"),
 ("header.model.empty", "No models installed on the server", "Nessun modello installato sul server"),
 ("header.model.missing", "not on the server", "non presente sul server"),
 ("run.blocked.modelMissing", "The selected model is not on the server", "Il modello scelto non è presente sul server"),
 ("status.unauthorized", "Draw Things refused the shared secret", "Draw Things ha rifiutato il codice di accesso"),
 ("prefs.dt.host", "Address", "Indirizzo"),
 ("prefs.dt.port", "Port", "Porta"),
 ("prefs.dt.tls", "Use TLS", "Usa TLS"),
 ("prefs.dt.secret", "Shared secret", "Codice di accesso (shared secret)"),
 ("prefs.dt.secret.placeholder", "Optional", "Facoltativo"),
 ("prefs.dt.note", "DT Hub connects to a Draw Things server that is already running: the Draw Things app’s API server in gRPC mode, or gRPCServerCLI. Its API server uses TLS by default.", "DT Hub si collega a un server Draw Things già avviato: l’API Server dell’app Draw Things in modalità gRPC, oppure gRPCServerCLI. L’API Server usa TLS per impostazione predefinita."),
 ("prefs.dt.connect", "Connect", "Collega"),
 ("prefs.dt.models", "%lld models available", "%lld modelli disponibili"),
 ("prefs.dt.error.emptyHost", "Enter the server address", "Inserisci l’indirizzo del server"),
 ("prefs.dt.error.invalidHost", "Enter a host name or IP address, without http:// or paths", "Inserisci un nome host o un indirizzo IP, senza http:// né percorsi"),
 ("prefs.dt.error.invalidPort", "The port must be between 1 and 65535", "La porta deve essere tra 1 e 65535"),
 ("prefs.dt.secret.saveError", "The shared secret could not be saved in the Keychain", "Impossibile salvare il codice di accesso nel Portachiavi"),
]
for key, en, it in rows:
    catalog["strings"][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
with open(p, "w") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2, sort_keys=True)
print(len(catalog["strings"]), "keys")
EOF
```

Expected: `38 keys`

- [ ] **Step 5: Verificare che i test passino**

Run: `cd "<repo>/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run|Missing|Not in"`
Expected: `Test run with 4 tests in 1 suite passed`

- [ ] **Step 6: Commit**

```bash
cd "<repo>" && git add App/Localizable.xcstrings Packages && git commit -m "feat: stringhe di M2 e test del catalogo esteso a TextField e SecureField

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Modello scelto e regola di RUN

**Files:**
- Create: `Packages/Sources/HubCore/Selection/ModelSelection.swift`
- Modify: `Packages/Sources/HubCore/Run/RunAvailability.swift` (sostituito per intero)
- Modify: `App/MainWindow/HeaderBar.swift` (solo l'adattamento alla nuova firma, perché l'app continui a compilare)
- Test: `Packages/Tests/HubCoreTests/ModelSelectionTests.swift`
- Test: `Packages/Tests/HubCoreTests/RunAvailabilityTests.swift` (sostituito per intero)

**Interfaces:**
- Consumes: `ModelCatalog`, `CatalogModel`, `ConnectionStatus` (HubKit); chiave `run.blocked.modelMissing` (Task 6).
- Produces (HubCore):
  - `@MainActor @Observable public final class ModelSelection` con `init(defaults: UserDefaults = .standard)`, `private(set) var selectedFile: String?`, `func select(_ file: String)`, `func selectedModel(in catalog: ModelCatalog) -> CatalogModel?`; chiave UserDefaults `drawThings.selectedModel`
  - `RunBlocker` con i casi `notConnected`, `noModelSelected`, `modelNotOnServer`
  - `RunAvailability.blocker(connection: ConnectionStatus, selectedModel: String?, catalog: ModelCatalog) -> RunBlocker?` (sostituisce la firma di M1)

- [ ] **Step 1: Scrivere i test che falliscono**

`Packages/Tests/HubCoreTests/ModelSelectionTests.swift`:

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct ModelSelectionTests {
  let klein = CatalogModel(file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b")

  func freshDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "ModelSelectionTests-\(UUID())"))
  }

  @Test func startsWithNothingSelected() throws {
    #expect(ModelSelection(defaults: try freshDefaults()).selectedFile == nil)
  }

  @Test func remembersTheSelectionAcrossLaunches() throws {
    let defaults = try freshDefaults()
    ModelSelection(defaults: defaults).select(klein.file)
    #expect(ModelSelection(defaults: defaults).selectedFile == klein.file)
  }

  @Test func resolvesTheSelectedModelOnlyWhenInstalled() throws {
    let selection = ModelSelection(defaults: try freshDefaults())
    selection.select(klein.file)
    #expect(selection.selectedModel(in: ModelCatalog(models: [klein], loras: [], fileCount: 1)) == klein)
    #expect(selection.selectedModel(in: .empty) == nil)
    #expect(selection.selectedFile == klein.file)
  }
}
```

`Packages/Tests/HubCoreTests/RunAvailabilityTests.swift` (sostituire tutto il file):

```swift
import HubKit
import Testing

@testable import HubCore

struct RunAvailabilityTests {
  let klein = "flux_2_klein_9b_f16.ckpt"
  var catalog: ModelCatalog {
    ModelCatalog(models: [CatalogModel(file: klein, name: "FLUX.2 [klein] 9B", family: "flux2_9b")], loras: [], fileCount: 1)
  }

  @Test func connectedWithInstalledModelCanRun() {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: klein, catalog: catalog) == nil)
  }

  @Test(arguments: [ConnectionStatus.disconnected, .connecting])
  func notConnectedBlocks(connection: ConnectionStatus) {
    #expect(RunAvailability.blocker(connection: connection, selectedModel: klein, catalog: catalog) == .notConnected)
  }

  @Test(arguments: [String?.none, ""])
  func missingModelBlocks(model: String?) {
    #expect(RunAvailability.blocker(connection: .connected, selectedModel: model, catalog: catalog) == .noModelSelected)
  }

  @Test func connectionIsReportedBeforeModel() {
    #expect(RunAvailability.blocker(connection: .disconnected, selectedModel: nil, catalog: .empty) == .notConnected)
  }

  @Test func modelMissingFromServerBlocks() {
    #expect(
      RunAvailability.blocker(connection: .connected, selectedModel: "gone.ckpt", catalog: catalog)
        == .modelNotOnServer)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: errori `cannot find 'ModelSelection' in scope` e/o `extra argument 'catalog' in call`.

- [ ] **Step 3: Implementare — `Packages/Sources/HubCore/Selection/ModelSelection.swift`**

```swift
import Foundation
import HubKit
import Observation

/// The model chosen in the header, kept across launches. The file is kept even when the
/// server does not have it, so reconnecting to the right server restores it.
@MainActor
@Observable
public final class ModelSelection {
  public private(set) var selectedFile: String?

  @ObservationIgnored private let defaults: UserDefaults
  static let key = "drawThings.selectedModel"

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.selectedFile = defaults.string(forKey: Self.key)
  }

  public func select(_ file: String) {
    selectedFile = file
    defaults.set(file, forKey: Self.key)
  }

  /// The selected model as the catalog describes it; nil if none is selected or installed.
  public func selectedModel(in catalog: ModelCatalog) -> CatalogModel? {
    selectedFile.flatMap(catalog.model(forFile:))
  }
}
```

- [ ] **Step 4: Implementare — `Packages/Sources/HubCore/Run/RunAvailability.swift` (sostituire tutto)**

```swift
import HubKit

/// Why RUN is disabled (spec §7, §10).
public enum RunBlocker: Equatable, Sendable {
  case notConnected
  case noModelSelected
  /// The selected model is not installed on the connected server.
  case modelNotOnServer
}

public enum RunAvailability {
  /// The reason RUN cannot start, or nil when it can. The connection is checked first,
  /// because without it the catalog is empty anyway.
  public static func blocker(
    connection: ConnectionStatus, selectedModel: String?, catalog: ModelCatalog
  ) -> RunBlocker? {
    guard connection == .connected else { return .notConnected }
    guard let selectedModel, !selectedModel.isEmpty else { return .noModelSelected }
    guard catalog.model(forFile: selectedModel) != nil else { return .modelNotOnServer }
    return nil
  }
}
```

- [ ] **Step 5: Adattare l'header di M1 alla nuova firma**

In `App/MainWindow/HeaderBar.swift` sostituire:

```swift
    RunAvailability.blocker(connection: connection, selectedModel: selectedModel)
```

con:

```swift
    RunAvailability.blocker(connection: connection, selectedModel: selectedModel, catalog: .empty)
```

e nello `switch runBlocker` di `runHelp` aggiungere, dopo il caso `.noModelSelected`:

```swift
    case .modelNotOnServer: String(localized: "run.blocked.modelMissing")
```

(Il Task 8 riscrive l'header per intero; qui serve solo che l'app continui a compilare.)

- [ ] **Step 6: Verificare test e build**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "Test run|error:"`
Expected: tutte `passed`; HubCoreTests `Test run with 33 tests in 6 suites passed`.

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
cd "<repo>" && git add App Packages && git commit -m "feat: modello scelto ricordato e RUN bloccato se il modello non è sul server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: L'app si collega da sola — header reale

**Files:**
- Modify: `DTHub.xcodeproj/project.pbxproj` (con lo script dello Step 1)
- Modify: `Packages/Sources/HubKit/DesignSystem/DSButtons.swift` (`DSMenuLabel` con `detail`)
- Create: `App/Connection/DrawThingsConnection.swift`
- Create: `App/Connection/ConnectionStatusText.swift`
- Modify: `App/DTHubApp.swift` (sostituito per intero)
- Modify: `App/MainWindow/MainWindowView.swift` (sostituito per intero)
- Modify: `App/MainWindow/HeaderBar.swift` (sostituito per intero)
- Modify: `App/Preferences/PreferencesView.swift` (solo la firma, vedi Step 7)

**Interfaces:**
- Consumes: `DrawThingsBackend` (Task 2); `ConnectionSettings`, `ConnectionSettingsStore` (Task 3); `SecretStore`, `KeychainSecretStore` (Task 4); `ConnectionMonitor` (Task 5); `ModelSelection`, `RunAvailability`, `RunBlocker` (Task 7); chiavi del Task 6.
- Produces:
  - `DSMenuLabel(_ title: String, detail: String? = nil, systemImage: String)` (HubKit)
  - `@MainActor @Observable final class DrawThingsConnection` (app) con `let monitor: ConnectionMonitor`, `let selection: ModelSelection`, `private(set) var settings: ConnectionSettings`, `private(set) var secretSaveFailed: Bool`, `func savedSecret() -> String`, `func apply(_ newSettings: ConnectionSettings, secret: String) async`
  - `enum ConnectionStatusText { static func headline(status: ConnectionStatus, error: BackendError?) -> String }` (app)
  - `PreferencesView(connection: DrawThingsConnection)`, usato dal Task 9

- [ ] **Step 1: Collegare il prodotto DTBridge al target dell'app**

Lo script aggiunge al progetto le stesse voci che XcodeGen ha scritto per HubCore (file di build, fase Frameworks, dipendenza di prodotto), con identificativi fissi.

```bash
cd "<repo>" && python3 - DTHub.xcodeproj/project.pbxproj <<'EOF'
# Links the DTBridge product of the local package to the DTHub app target,
# mirroring the entries XcodeGen wrote for HubCore.
import re, sys
path = sys.argv[1]
s = open(path).read()
if "/* DTBridge */" in s:
    sys.exit("DTBridge already linked")
BUILD, DEP = "D7B41D6E5C2A4F0B9E3A1C01", "D7B41D6E5C2A4F0B9E3A1C02"
def insert_after(pattern, addition):
    global s
    m = re.search(pattern, s)
    if not m:
        sys.exit(f"anchor not found: {pattern}")
    s = s[:m.end()] + addition + s[m.end():]
insert_after(r"\n\t\t\w+ /\* HubCore in Frameworks \*/ = \{isa = PBXBuildFile;[^\n]*",
    f"\n\t\t{BUILD} /* DTBridge in Frameworks */ = {{isa = PBXBuildFile; productRef = {DEP} /* DTBridge */; }};")
insert_after(r"\n\t\t\t\t\w+ /\* HubCore in Frameworks \*/,",
    f"\n\t\t\t\t{BUILD} /* DTBridge in Frameworks */,")
insert_after(r"packageProductDependencies = \(\n(?:\t\t\t\t\w+ /\* \w+ \*/,\n)*",
    f"\t\t\t\t{DEP} /* DTBridge */,\n")
insert_after(r"/\* Begin XCSwiftPackageProductDependency section \*/",
    f"\n\t\t{DEP} /* DTBridge */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = DTBridge;\n\t\t}};")
open(path, "w").write(s)
print("linked DTBridge")
EOF
grep -c "DTBridge" DTHub.xcodeproj/project.pbxproj
```

Expected: `linked DTBridge` e `5`.

- [ ] **Step 2: `DSMenuLabel` con il dettaglio (famiglia) — `Packages/Sources/HubKit/DesignSystem/DSButtons.swift`**

Sostituire l'intera struct `DSMenuLabel` con:

```swift
/// The label of a header menu: icon, title, an optional secondary detail (e.g. the model
/// family), and a small chevron. The chevron is drawn here because a plain-styled `Menu`
/// hides the system indicator.
public struct DSMenuLabel: View {
  let title: String
  let detail: String?
  let systemImage: String

  public init(_ title: String, detail: String? = nil, systemImage: String) {
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
  }

  public var body: some View {
    HStack(spacing: DS.pillIconGap) {
      Image(systemName: systemImage)
        .font(.system(size: 14, weight: .semibold))
        .accessibilityHidden(true)
      Text(title)
        .lineLimit(1)
      if let detail {
        Text(detail)
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Image(systemName: "chevron.down")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .accessibilityElement(children: .combine)
  }
}
```

- [ ] **Step 3: `App/Connection/DrawThingsConnection.swift`**

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
  private(set) var settings: ConnectionSettings
  /// True when the last Apply could not save the shared secret in the Keychain.
  private(set) var secretSaveFailed = false

  @ObservationIgnored private let settingsStore = ConnectionSettingsStore()
  @ObservationIgnored private let secretStore: any SecretStore = KeychainSecretStore()
  @ObservationIgnored private var loop: Task<Void, Never>?

  init() {
    settings = settingsStore.load()
    loop = Task {
      await monitor.replaceBackend(makeBackend())
      await monitor.run()
    }
  }

  /// The saved shared secret, empty when there is none.
  func savedSecret() -> String {
    secretStore.read() ?? ""
  }

  /// Saves the settings and the secret, then reconnects with them.
  func apply(_ newSettings: ConnectionSettings, secret: String) async {
    settings = newSettings
    settingsStore.save(newSettings)
    do {
      try secretStore.write(secret)
      secretSaveFailed = false
    } catch {
      secretSaveFailed = true
    }
    await monitor.replaceBackend(makeBackend())
  }

  private func makeBackend() -> (any GenerationBackend)? {
    guard settings.validationError == nil else { return nil }
    return DrawThingsBackend(
      host: settings.trimmedHost, port: settings.port, useTLS: settings.useTLS,
      sharedSecret: secretStore.read())
  }
}
```

- [ ] **Step 4: `App/Connection/ConnectionStatusText.swift`**

```swift
import HubKit

/// The words for the connection state, shared by the header dot and the Preferences.
enum ConnectionStatusText {
  static func headline(status: ConnectionStatus, error: BackendError?) -> String {
    switch status {
    case .connected: String(localized: "status.connected")
    case .connecting: String(localized: "status.connecting")
    case .disconnected:
      error == .unauthorized
        ? String(localized: "status.unauthorized") : String(localized: "status.disconnected")
    }
  }
}
```

- [ ] **Step 5: `App/DTHubApp.swift` (sostituire tutto)**

```swift
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

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection)
    }
    .windowResizability(.contentMinSize)

    Settings {
      PreferencesView(connection: connection)
    }
  }
}
```

- [ ] **Step 6: `App/MainWindow/MainWindowView.swift` (sostituire tutto)**

```swift
import HubCore
import HubKit
import SwiftUI

/// Header, tab bar, and the content of the selected tab (spec §7).
struct MainWindowView: View {
  let workspace: WorkspaceState
  let connection: DrawThingsConnection

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      HeaderBar(connection: connection)
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
      GenerationTabView()
    } else {
      // Plug-in tabs arrive with the plug-in contract (M7).
      EmptyView()
    }
  }
}
```

- [ ] **Step 7: `App/MainWindow/HeaderBar.swift` (sostituire tutto) e firma di `PreferencesView`**

```swift
import HubCore
import HubKit
import SwiftUI

/// [Plug-ins ▾] [Model ▾ · family] … ● DT [⚙︎] [▶ Run] (spec §7).
struct HeaderBar: View {
  let connection: DrawThingsConnection

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
      DSStatusDot(status: monitor.status)
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
      Text("header.model.browsingDisabled")
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
    if selection.selectedFile != nil, monitor.status == .connected {
      return String(localized: "header.model.missing")
    }
    return nil
  }

  private var runButton: some View {
    Button {
      // Generation arrives in M3.
    } label: {
      HStack(spacing: DS.pillIconGap) {
        Image(systemName: "play.fill")
          .font(.system(size: 14, weight: .semibold))
        Text("header.run")
      }
    }
    .buttonStyle(DSPillButtonStyle(prominent: true))
    .disabled(runBlocker != nil)
    .keyboardShortcut(.return, modifiers: .command)
    .help(runHelp)
  }

  private var runHelp: String {
    switch runBlocker {
    case .notConnected: String(localized: "run.blocked.notConnected")
    case .noModelSelected: String(localized: "run.blocked.noModel")
    case .modelNotOnServer: String(localized: "run.blocked.modelMissing")
    case nil: String(localized: "header.run.help")
    }
  }

  private var statusText: String {
    ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
  }
}
```

In `App/Preferences/PreferencesView.swift` sostituire:

```swift
struct PreferencesView: View {
  var body: some View {
```

con:

```swift
struct PreferencesView: View {
  let connection: DrawThingsConnection

  var body: some View {
```

(Il pannello Draw Things arriva nel Task 9; qui la vista riceve già la connessione.)

- [ ] **Step 8: Compilare e rieseguire i test**

```bash
cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "Test run|Missing|Not in"
```

Expected: `** BUILD SUCCEEDED **`; tutte le righe `Test run … passed`, nessuna `Missing` / `Not in the catalog`.

- [ ] **Step 9: Verifica dal vivo (server DT su 7859)**

```bash
open "<repo>/build/Build/Products/Debug/DT Hub.app"
```

Checklist (screenshot della finestra):
1. Entro pochi secondi il pallino diventa **verde**; RUN resta sbiadito con "Nessun modello".
2. Il menu modello elenca i modelli raggruppati per famiglia (sul server dell'utente: 15 modelli, sezioni come `flux2_9b`, `qwen_image_2.1`, `z_image`).
3. Scegliendo "FLUX.2 [klein] 9B (Exact)": l'header mostra nome e `flux2_9b`, RUN diventa pieno (attivo), il menu mostra la spunta.
4. Chiudendo e riaprendo l'app la scelta resta.
Se il menu non si può aprire da strumenti in background, basta impostare la scelta con `defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt` e riavviare per i punti 3–4, e lasciare il punto 2 alla verifica dell'utente. A fine verifica: `defaults delete com.exiztenz.DTHub`.

- [ ] **Step 10: Commit**

```bash
cd "<repo>" && git add App Packages DTHub.xcodeproj && git commit -m "feat: l'app si collega da sola a Draw Things, menu modelli per famiglia e RUN reale

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Preferenze › Draw Things

**Files:**
- Create: `App/Preferences/DrawThingsPreferencesView.swift`
- Modify: `App/Preferences/PreferencesView.swift` (sostituito per intero)

**Interfaces:**
- Consumes: `DrawThingsConnection`, `ConnectionStatusText` (Task 8); `ConnectionSettings` (Task 3); `DSStatusDot`, `DSPillButtonStyle`, `DS` (HubKit); chiavi `prefs.dt.*` (Task 6).
- Produces: il pannello Draw Things delle Preferenze.

- [ ] **Step 1: `App/Preferences/DrawThingsPreferencesView.swift`**

```swift
import HubCore
import HubKit
import SwiftUI

/// Preferences › Draw Things: where the server is, and whether DT Hub reaches it (spec §5, §7).
/// Edits stay local until Connect, so typing does not reconnect on every keystroke.
struct DrawThingsPreferencesView: View {
  let connection: DrawThingsConnection

  @State private var draft = ConnectionSettings.default
  @State private var secret = ""
  @State private var isApplying = false

  private var monitor: ConnectionMonitor { connection.monitor }

  var body: some View {
    Form {
      Section {
        TextField("prefs.dt.host", text: $draft.host)
        TextField("prefs.dt.port", value: $draft.port, format: .number.grouping(.never))
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

      Section {
        HStack(spacing: DS.controlGap) {
          DSStatusDot(status: monitor.status)
          VStack(alignment: .leading, spacing: 2) {
            Text(statusLine)
            if case .unreachable(let detail)? = monitor.lastError {
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
              await connection.apply(draft, secret: secret)
              isApplying = false
            }
          }
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(draft.validationError != nil || isApplying)
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
      secret = connection.savedSecret()
    }
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
    guard monitor.status == .connected else {
      return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
    }
    if monitor.catalog.isModelBrowsingDisabled {
      return String(localized: "header.model.browsingDisabled")
    }
    return String(format: String(localized: "prefs.dt.models"), monitor.catalog.models.count)
  }
}
```

- [ ] **Step 2: `App/Preferences/PreferencesView.swift` (sostituire tutto)**

```swift
import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7). LLM and Output arrive later.
struct PreferencesView: View {
  let connection: DrawThingsConnection

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        DrawThingsPreferencesView(connection: connection)
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        PreferencesPlaceholder()
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        PreferencesPlaceholder()
      }
    }
    .frame(width: 560, height: 420)
  }
}

private struct PreferencesPlaceholder: View {
  var body: some View {
    ContentUnavailableView(
      "prefs.empty.title",
      systemImage: "hammer",
      description: Text("prefs.empty.message"))
  }
}
```

- [ ] **Step 3: Compilare e rieseguire i test**

```bash
cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "Test run|Missing|Not in"
```

Expected: `** BUILD SUCCEEDED **`; tutte le righe `passed`; nessuna `Missing` / `Not in the catalog`.

- [ ] **Step 4: Verifica dal vivo delle Preferenze**

Aprire l'app, poi le Preferenze (menu DT Hub › Impostazioni… oppure ⌘,). Checklist:
1. Tab Draw Things: Indirizzo `localhost`, Porta `7859`, Usa TLS attivo, Codice di accesso vuoto con "Facoltativo"; sotto, la nota sul server già avviato.
2. In basso: pallino verde e "15 modelli disponibili" (sul server dell'utente), pulsante turchese "Collega".
3. Indirizzo `http://localhost` → messaggio arancione sotto i campi, "Collega" disabilitato.
4. Indirizzo inesistente (es. `99999`) + Collega → "Connessione a Draw Things…" giallo, poi rosso "Draw Things non raggiungibile" con il dettaglio tecnico; nell'header il pallino è rosso e RUN disabilitato.
5. Indirizzo `localhost` + Collega → di nuovo verde con il numero di modelli.
6. (Review Focus) Chiudere il server DT (spegnere l'API Server nell'app DT): entro ~5 s pallino rosso. Riaccenderlo: entro ~5 s di nuovo verde, senza toccare DT Hub. Questo punto lo esegue l'utente.
A fine verifica: `defaults delete com.exiztenz.DTHub`.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add App && git commit -m "feat: Preferenze › Draw Things (indirizzo, porta, TLS, codice di accesso, stato)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Fine della M2

Esito atteso sul branch `m2-collegamento-dt`: 47 test verdi con `swift test` in `Packages/` (di cui 2 live, eseguiti solo con `DTHUB_LIVE_DT`), build Xcode pulita, l'app si collega da sola al server DT, il menu elenca i modelli per famiglia, la scelta è ricordata e RUN si abilita. Merge e avvio della M3 (primo T2I) si decidono con l'utente.

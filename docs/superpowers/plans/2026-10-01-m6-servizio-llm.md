# M6 Servizio LLM — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DT Hub ha un LLM locale in-process (MLX) che risponde a domande di testo e, con un modello di visione, su immagini. Nelle Preferenze › LLM si sceglie la cartella dei modelli e il modello, si scarica il modello consigliato solo su richiesta esplicita, si regola l'uso della memoria e si prova una domanda. La memoria è condivisa con il modello immagine: l'LLM si libera quando si preme Run e dopo un po' di inattività; il server gestito da DT Hub può fermarsi per fare spazio all'LLM e ripartire al Run.

**Architecture:**
- **HubKit** riceve il contratto: `LanguageModelDescriptor`, `LanguageModelError`, `LanguageModelService`, `LanguageModelDownloader`, `RecommendedLanguageModel`.
- **HubCore** riceve:
  - la ricerca dei modelli in una cartella (`LanguageModelScanner`);
  - le impostazioni, con i predefiniti secondo la memoria del Mac (`LanguageModelSettings`);
  - la misura della memoria libera (`MemoryProbe`);
  - `LanguageModelManager`, che carica, risponde, libera (al Run, per inattività) e controlla la memoria, tutto provato con un servizio finto.
- **LLMBridge** (nuovo modulo, l'unico che importa MLX) implementa il servizio con mlx-swift-lm 3.x, l'adattatore del tokenizer e lo scaricamento da Hugging Face in una cartella di appoggio.
- **L'app** aggiunge la scheda LLM delle Preferenze e il collegamento al Run (libera l'LLM, riporta il server parcheggiato).

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27 con il componente Metal Toolchain, Swift Testing, mlx-swift-lm 3.31+, mlx-swift 0.32, swift-huggingface 0.9+, swift-transformers 1.3+.

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 4, 9, 10, 11, 12, 13, 15-M6).

## Global Constraints

- **Repository e dipendenze:**
  - radice `<repo>` (percorsi tra virgolette);
  - branch `m6-servizio-llm` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo `LLMBridge` importa MLX e Hugging Face; HubCore usa il modello solo tramite `LanguageModelService`.
- **Prerequisito di compilazione:** serve il componente Xcode **Metal Toolchain** (`xcodebuild -downloadComponent MetalToolchain`, scaricato dall'utente il 1 ottobre 2026): i shader di MLX si compilano con `xcodebuild`, non con `swift build`. `swift test` compila e prova tutto il resto; i test che usano MLX (`LLMBridgeTests`) si lanciano con `xcodebuild test` e restano inattivi senza le variabili d'ambiente. Il README lo dice.
- **Nessun macro:** il tokenizer si adatta a mano (`TokenizerBridge.swift`, la stessa struttura che il macro `#huggingFaceTokenizerLoader()` genera), così Xcode non chiede di approvare macro di pacchetti e `xcodebuild` non ha bisogno di `-skipMacroValidation`. Non si usa il prodotto `MLXHuggingFace`.
- **Modelli (decisi con l'utente, 1 ottobre 2026):**
  - un modello è una cartella in formato Hugging Face (`config.json` + `.safetensors`), la sola che MLX carichi; fino a due livelli sotto la cartella dei modelli (`modello/` o `autore/modello/`, il formato di LM Studio e dei download di Hugging Face);
  - i file `.ckpt` di Draw Things (anche quelli di Local Code) **non** sono utilizzabili: formato interno, senza configurazione né tokenizer;
  - un modello è "di visione" se il suo `config.json` ha `vision_config`;
  - modello consigliato: `mlx-community/Qwen3-VL-8B-Instruct-4bit` (17 file, circa 5,78 GB, Apache-2.0), verificato su Hugging Face il 1 ottobre 2026;
  - cartella predefinita `/Volumes/LLM-VLM/MLX` (spec §9).
- **Scaricamento:** mai in automatico. Un dialogo di conferma nomina repository, dimensione e cartella di destinazione; i file arrivano in una cartella nascosta `.dthub-download-<uuid>` accanto alla destinazione e si spostano al loro posto solo a fine scaricamento: un download fallito o annullato non lascia un modello a metà nell'elenco. Annullabile.
- **Memoria (spec §9, riscritta con l'utente il 1 ottobre 2026):**
  - **"Libera l'LLM quando premo Run":** attiva per impostazione predefinita solo sotto i 64 GB di memoria.
  - **"Libera il modello immagine quando uso l'LLM":** attiva per impostazione predefinita solo sotto i 64 GB; **disponibile solo con il server avviato da DT Hub** (Draw Things non ha nessuna chiamata per scaricare un modello da un altro server: verificato, le sue chiamate sono `GenerateImage`, `FilesExist`, `UploadFile`, `Echo`, `Pubkey`, `Hours`). Si usa solo **prima di caricare** l'LLM (non a ogni domanda). Il server si ferma; al Run successivo riparte e DT Hub aspetta che risponda (fino a 5 minuti). Nelle Preferenze l'avviso dice che il modello si ricarica al Run, e può volerci tempo.
  - **Scarico per inattività:** dopo N minuti senza usarlo (10 predefiniti, 0 = mai, massimo 240). Nessun pulsante "Libera ora".
  - **Controllo prima del caricamento:** il modello (dimensione dei file × 1,2) deve stare nella memoria libera (pagine libere, inattive, speculative e purgabili); altrimenti nessun caricamento e un errore con le due cifre. La misura avviene **dopo** aver liberato il modello immagine.
  - Le scelte non si basano sui tempi misurati con il disco esterno lento dell'utente.
- **Run con server parcheggiato:** il pallino è giallo ("modello immagine liberato per l'LLM"), Run resta attivo, e premendolo l'LLM si libera (se richiesto), il server riparte e la generazione parte dopo la risposta del server; il lavoro si compone **dopo** il ritorno del server (senza catalogo le LoRA verrebbero scartate). Durante la preparazione Run è spento e la finestra Risultati dice "Libero la memoria…".
- **Messaggi:** i messaggi di errore dell'LLM sono localizzati; il dettaglio tecnico della libreria resta in inglese dopo i due punti.
- **Prova nelle Preferenze:** una domanda (già scritta, di esempio) e un'immagine facoltativa; una domanda con immagini a un modello senza visione dà un errore chiaro.
- **Fuori da M6:** il miglioramento del prompt (plug-in PM2, M7); i modelli dedicati registrati dai plug-in e la scelta per famiglia (M7); la generazione strutturata con schema JSON (`MLXGuidedGeneration`, M7); lo streaming della risposta; conversazioni a più turni; opzioni avanzate di MLX (cache KV, decodifica speculativa).
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; `String(format: String(localized:), …)` per i valori.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- **Cartella dei modelli mancante, vuota o con file che non sono modelli MLX** (cartelle senza pesi, `.ckpt` di Draw Things): nessun modello nell'elenco, messaggio con il percorso, nessun errore (test `aMissingFolderHasNoModels`, `aFolderWithoutWeightsOrConfigIsNotAModel`, Task 3).
- **Modello più grande della memoria libera:** nessun caricamento, errore con le due cifre, memoria misurata dopo aver liberato il modello immagine (test `refusesToLoadWhatDoesNotFitInTheFreeMemory`, `theMemoryIsMeasuredAfterTheImageModelLeft`, Task 3).
- **Immagine data a un modello solo testo:** errore chiaro, nessun caricamento (test `imagesNeedAVisionModel`, Task 3).
- **Modello che non si carica o risposta che fallisce:** stato d'errore con il motivo, l'LLM resta scaricato, una nuova domanda riprova (test `aLoadFailureIsReported`, Task 3).
- **Run con l'LLM caricato, con il server parcheggiato e con tutte e due:** l'LLM si libera, il server riparte, il lavoro parte con catalogo e LoRA giusti (verifica dal vivo, Task 7; test `pressingRunFreesTheModelOnlyWhenTheSettingsSaySo`, Task 3).
- **Scaricamento annullato o fallito:** nessun modello a metà nell'elenco, nessuna cartella di appoggio rimasta (test dal vivo `aFailedDownloadLeavesNothingInTheFolder`, `downloadsIntoItsFolderAndLeavesNoStagingBehind`, Task 4).
- **Memoria libera dall'inattività:** si libera dopo il tempo, ogni uso lo riparte, 0 non libera mai (test `freesTheModelAfterTheIdleTime`, `useRestartsTheIdleTime`, `idleMinutesAtZeroNeverFreesTheModel`, Task 3).

---

### Task 1: Dipendenze MLX e modulo LLMBridge (infrastruttura)

**Files:**
- Modify: `Packages/Package.swift`
- Modify: `DTHub.xcodeproj/project.pbxproj` (prodotto LLMBridge collegato all'app)
- Modify: `Packages/Package.resolved` (si aggiorna da solo con la risoluzione)
- Create: `Packages/Sources/LLMBridge/TokenizerBridge.swift`
- Modify: `README.md` (prerequisito Metal Toolchain)

**Interfaces:**
- Produces: il prodotto `LLMBridge` (libreria) collegato all'app; `TransformersTokenizerLoader` (interno a LLMBridge), che implementa `MLXLMCommon.TokenizerLoader` con swift-transformers.

- [ ] **Step 1: Creare il branch**

```bash
cd "<repo>" && git switch main && git switch -c m6-servizio-llm
```

- [ ] **Step 2: Verificare il prerequisito**

Run: `xcodebuild -showComponent MetalToolchain 2>&1 | grep Status; xcrun metal --version 2>&1 | head -1`
Expected: `Status: installed` e `Apple metal version …`. Se manca, **fermarsi** e chiedere all'utente di eseguire `xcodebuild -downloadComponent MetalToolchain` (è un download di Apple e un'installazione di sistema: non lo si lancia da qui).

- [ ] **Step 3: Sostituire `Packages/Package.swift` con:**

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
    .library(name: "LLMBridge", targets: ["LLMBridge"]),
  ],
  dependencies: [
    // Single maintainer, frequent releases: accept patch updates only (spec §5, §16).
    .package(
      url: "https://github.com/euphoriacyberware-ai/DrawThings-Swift.git",
      .upToNextMinor(from: "2.2.0")),
    // The language-model engine (spec §9). 3.x asks for a downloader and a tokenizer package.
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
    .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
  ],
  targets: [
    .target(name: "HubKit"),
    .target(name: "HubCore", dependencies: ["HubKit"]),
    // The only module that knows DrawThings-Swift and gRPC (spec §4).
    .target(
      name: "DTBridge",
      dependencies: ["HubKit", .product(name: "DrawThingsClient", package: "DrawThings-Swift")]),
    // The only module that knows MLX (spec §4).
    .target(
      name: "LLMBridge",
      dependencies: [
        "HubKit",
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXVLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]),
    .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
    .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit"]),
    // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
    .testTarget(name: "CatalogTests"),
  ]
)
```

- [ ] **Step 4: Creare `Packages/Sources/LLMBridge/TokenizerBridge.swift`**

```swift
import Foundation
import MLXLMCommon
import Tokenizers

/// Adapts swift-transformers' tokenizers to mlx-swift-lm's protocols (the same adapter the
/// package's `#huggingFaceTokenizerLoader()` macro writes; spelled out here so building DT Hub
/// does not ask Xcode to trust a macro).
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
    return TokenizerBridge(upstream)
  }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
  private let upstream: any Tokenizers.Tokenizer

  init(_ upstream: any Tokenizers.Tokenizer) {
    self.upstream = upstream
  }

  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
  }

  // swift-transformers calls it `decode(tokens:)`.
  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }

  func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

  var bosToken: String? { upstream.bosToken }
  var eosToken: String? { upstream.eosToken }
  var unknownToken: String? { upstream.unknownToken }

  func applyChatTemplate(
    messages: [[String: any Sendable]], tools: [[String: any Sendable]]?,
    additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    do {
      return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    } catch Tokenizers.TokenizerError.missingChatTemplate {
      throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
  }
}
```

- [ ] **Step 5: Collegare il prodotto all'app con lo script**

```bash
cd "<repo>" && python3 - <<'EOF'
p = 'DTHub.xcodeproj/project.pbxproj'
s = open(p).read()
pairs = [
("""		D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */ = {isa = PBXBuildFile; productRef = D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */; };
""", """		D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */ = {isa = PBXBuildFile; productRef = D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */; };
		E8C52E7F6D3B5A1CAF4B2D11 /* LLMBridge in Frameworks */ = {isa = PBXBuildFile; productRef = E8C52E7F6D3B5A1CAF4B2D12 /* LLMBridge */; };
"""),
("""				D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */,
""", """				D7B41D6E5C2A4F0B9E3A1C01 /* DTBridge in Frameworks */,
				E8C52E7F6D3B5A1CAF4B2D11 /* LLMBridge in Frameworks */,
"""),
("""				D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */,
			);
			productName = DTHub;""", """				D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */,
				E8C52E7F6D3B5A1CAF4B2D12 /* LLMBridge */,
			);
			productName = DTHub;"""),
("""		D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */ = {
			isa = XCSwiftPackageProductDependency;
			productName = DTBridge;
		};
""", """		D7B41D6E5C2A4F0B9E3A1C02 /* DTBridge */ = {
			isa = XCSwiftPackageProductDependency;
			productName = DTBridge;
		};
		E8C52E7F6D3B5A1CAF4B2D12 /* LLMBridge */ = {
			isa = XCSwiftPackageProductDependency;
			productName = LLMBridge;
		};
"""),
]
for a, b in pairs:
    assert a in s, a[:60]
    s = s.replace(a, b, 1)
open(p, 'w').write(s)
EOF
git diff --stat DTHub.xcodeproj/project.pbxproj | tail -1
```

Expected: `1 file changed, 7 insertions(+)` e nessuna riga tolta.

- [ ] **Step 6: Aggiungere al README il prerequisito**

Sostituire in `README.md` la riga `- Requisiti: macOS 26, Apple Silicon, Xcode 27, un server gRPC di Draw Things.` con:

```markdown
- Requisiti: macOS 26, Apple Silicon, Xcode 27, un server gRPC di Draw Things (l'app o `gRPCServerCLI`, che DT Hub può avviare da solo).
- Per compilare serve il componente Xcode Metal Toolchain (i shader di MLX): `xcodebuild -downloadComponent MetalToolchain`, una volta sola.
- Per l'LLM serve un modello MLX in una cartella (per esempio `mlx-community/Qwen3-VL-8B-Instruct-4bit`): si scarica dalle Preferenze › LLM, solo se lo chiedi.
```

- [ ] **Step 7: Risolvere, compilare e provare**

Run: `cd "<repo>/Packages" && swift package resolve 2>&1 | tail -2; swift test 2>&1 | grep -E "error:|Test run with" | grep -v started; cd .. && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; find build -name "default.metallib" | head -2`
Expected: i test di prima passano (HubKit 44, HubCore 148, DTBridge 47, Catalog 6); `** BUILD SUCCEEDED **`; compare `default.metallib` nel pacchetto dell'app. La prima compilazione con MLX richiede qualche minuto.

- [ ] **Step 8: Commit**

```bash
cd "<repo>" && git add Packages DTHub.xcodeproj README.md && git commit -m "feat: dipendenze MLX e modulo LLMBridge collegato all'app

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Il contratto del modello linguistico (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Language/LanguageModel.swift`
- Test: `Packages/Tests/HubKitTests/LanguageModelContractTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct LanguageModelDescriptor: Identifiable, Equatable, Sendable` (`path`, `name`, `sizeBytes`, `supportsImages`, `id` = percorso);
  - `enum LanguageModelError: Error, Equatable, Sendable { noModelSelected, notEnoughMemory(neededBytes:availableBytes:), imagesNotSupported, loadFailed(String), generationFailed(String), downloadFailed(String) }`;
  - `protocol LanguageModelService: Sendable` (`load(_:)`, `unload()`, `respond(to:images:)`);
  - `protocol LanguageModelDownloader: Sendable` (`download(repository:to:progress:)`);
  - `enum RecommendedLanguageModel` (`repository`, `approximateBytes`, `folderName`).

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubKitTests/LanguageModelContractTests.swift` con:

```swift
import Testing

@testable import HubKit

struct LanguageModelContractTests {
  @Test func aModelIsIdentifiedByItsFolder() {
    let model = LanguageModelDescriptor(path: "/m/qwen", name: "qwen", sizeBytes: 10, supportsImages: false)
    #expect(model.id == "/m/qwen")
  }

  @Test func theRecommendedModelIsAHubRepositoryDownloadedIntoItsOwnFolder() {
    let parts = RecommendedLanguageModel.repository.split(separator: "/")
    #expect(parts.count == 2)
    #expect(RecommendedLanguageModel.folderName == RecommendedLanguageModel.repository)
    #expect(RecommendedLanguageModel.approximateBytes > 1_000_000_000)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'LanguageModelDescriptor' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubKit/Language/LanguageModel.swift`**

```swift
import Foundation

/// A language model found in the models folder: a folder in Hugging Face format
/// (`config.json` and `.safetensors` weights), the format MLX loads (spec §9).
public struct LanguageModelDescriptor: Identifiable, Equatable, Sendable {
  public var id: String { path }
  /// The folder of the model.
  public let path: String
  /// Its name: the path below the models folder (`mlx-community/Qwen3-VL-8B-Instruct-4bit`, or
  /// just the folder name).
  public let name: String
  /// The size of its files, a good measure of the memory it needs.
  public let sizeBytes: Int64
  /// True for a vision-language model: it can be given images.
  public let supportsImages: Bool

  public init(path: String, name: String, sizeBytes: Int64, supportsImages: Bool) {
    self.path = path
    self.name = name
    self.sizeBytes = sizeBytes
    self.supportsImages = supportsImages
  }
}

/// Why the language model could not do what was asked.
public enum LanguageModelError: Error, Equatable, Sendable {
  case noModelSelected
  /// The model does not fit in the memory that is free now.
  case notEnoughMemory(neededBytes: Int64, availableBytes: Int64)
  case imagesNotSupported
  case loadFailed(String)
  case generationFailed(String)
  case downloadFailed(String)
}

/// The language model as HubCore sees it (spec §4: HubCore reaches MLX only through this).
/// LLMBridge implements it with mlx-swift-lm; tests use a fake. One model at a time.
public protocol LanguageModelService: Sendable {
  /// Loads the model into memory, replacing the one loaded.
  func load(_ model: LanguageModelDescriptor) async throws
  /// Frees the memory of the loaded model; does nothing when none is loaded.
  func unload() async
  /// One question, with images for a vision model. The model must be loaded.
  func respond(to prompt: String, images: [URL]) async throws -> String
}

/// Downloads a model from Hugging Face into a folder, only when the user asked (spec §9).
public protocol LanguageModelDownloader: Sendable {
  /// `progress` goes from 0 to 1. The files land in `folder` (created when missing).
  func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws
}

/// The model DT Hub offers to download (spec §9). The exact repository was checked on
/// Hugging Face on 1 October 2026: 17 files, Apache-2.0.
public enum RecommendedLanguageModel {
  public static let repository = "mlx-community/Qwen3-VL-8B-Instruct-4bit"
  /// Rounded, for the question "download about 5.8 GB?".
  public static let approximateBytes: Int64 = 5_780_000_000
  /// Where it goes inside the models folder: the same layout the scanner reads.
  public static let folderName = repository
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: HubKit `46 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: contratto del modello linguistico (servizio, scaricamento, errori)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Cartella dei modelli, impostazioni, memoria e gestore (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Language/LanguageModelScanner.swift`
- Create: `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`
- Create: `Packages/Sources/HubCore/Language/LanguageModelManager.swift`
- Test: `Packages/Tests/HubCoreTests/LanguageModelTests.swift`

**Interfaces:**
- Consumes: `LanguageModelDescriptor`, `LanguageModelError`, `LanguageModelService` (Task 2).
- Produces (HubCore, `public`):
  - `enum LanguageModelScanner { static func models(in: URL, fileManager:) -> [LanguageModelDescriptor] }`;
  - `struct LanguageModelSettings: Equatable, Codable, Sendable` (`folder`, `selectedModel`, `freeAtRun`, `freeImageModelForLanguageModel`, `idleMinutes`, `defaultFolder`, `comfortableMemory`, `static func defaults(physicalMemory:)`, `idleRange`, `clamped()`), `struct LanguageModelSettingsStore` (`load()`, `save(_:)`), `struct MemoryProbe` (`availableBytes`, `live`);
  - `@MainActor @Observable final class LanguageModelManager` con `State { unloaded, loading(String), ready(String), failed(LanguageModelError) }`, `state`, `settings` (si salva a ogni modifica), `isLoaded`, `memoryMargin = 1.2`, `availableModels()`, `selectedModel()`, `respond(to:images:) async throws(LanguageModelError) -> String`, `unload() async`, `prepareForRun() async`; `init(service:store:memory:minute:releaseImageModel:)`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/LanguageModelTests.swift` con:

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

struct LanguageModelScannerTests {
  func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageModelScannerTests-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  /// A model folder: a config, weights of `size` bytes, optionally a vision section.
  func model(_ path: String, in root: URL, size: Int = 100, vision: Bool = false, weights: Bool = true) throws {
    let folder = root.appendingPathComponent(path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try (vision ? #"{"vision_config": {}}"# : #"{"model_type": "qwen3"}"#).write(
      to: folder.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
    if weights { try Data(count: size).write(to: folder.appendingPathComponent("model.safetensors")) }
  }

  @Test func findsModelsOneAndTwoLevelsDeep() throws {
    let root = try makeRoot()
    try model("Qwen3-4B-4bit", in: root)
    try model("mlx-community/Qwen3-VL-8B-Instruct-4bit", in: root, size: 5000, vision: true)
    let found = LanguageModelScanner.models(in: root)
    #expect(found.map(\.name) == ["mlx-community/Qwen3-VL-8B-Instruct-4bit", "Qwen3-4B-4bit"])
    #expect(found[0].supportsImages && !found[1].supportsImages)
    #expect(found[0].sizeBytes >= 5000)
    #expect(found[1].path == root.appendingPathComponent("Qwen3-4B-4bit").standardizedFileURL.path)
  }

  @Test func aFolderWithoutWeightsOrConfigIsNotAModel() throws {
    let root = try makeRoot()
    try model("no-weights", in: root, weights: false)
    let loose = root.appendingPathComponent("only-weights")
    try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
    try Data(count: 10).write(to: loose.appendingPathComponent("model.safetensors"))
    #expect(LanguageModelScanner.models(in: root).isEmpty)
  }

  @Test func doesNotLookDeeperThanTwoLevelsOrInsideAModel() throws {
    let root = try makeRoot()
    try model("a/b/c/too-deep", in: root)
    try model("outer", in: root)
    try model("outer/inner", in: root)
    #expect(LanguageModelScanner.models(in: root).map(\.name) == ["outer"])
  }

  @Test func aMissingFolderHasNoModels() {
    #expect(LanguageModelScanner.models(in: URL(fileURLWithPath: "/nowhere/\(UUID())")).isEmpty)
  }
}

struct LanguageModelSettingsTests {
  @Test func theMemoryOptionsAreOnlyOnForMacsWithLessThan64GB() {
    let gb: UInt64 = 1_073_741_824
    #expect(LanguageModelSettings.defaults(physicalMemory: 32 * gb).freeAtRun)
    #expect(LanguageModelSettings.defaults(physicalMemory: 32 * gb).freeImageModelForLanguageModel)
    #expect(!LanguageModelSettings.defaults(physicalMemory: 64 * gb).freeAtRun)
    #expect(!LanguageModelSettings.defaults(physicalMemory: 192 * gb).freeImageModelForLanguageModel)
    #expect(LanguageModelSettings.defaults(physicalMemory: 64 * gb).folder == "/Volumes/LLM-VLM/MLX")
    #expect(LanguageModelSettings.defaults(physicalMemory: 64 * gb).idleMinutes == 10)
  }

  @Test func theStoreRemembersAndFallsBackToTheMacsDefaults() {
    let defaults = UserDefaults(suiteName: "LanguageModelSettingsTests-\(UUID())")!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 16 * 1_073_741_824)
    #expect(store.load().freeAtRun)
    var settings = store.load()
    settings.freeAtRun = false
    settings.selectedModel = "/m"
    store.save(settings)
    #expect(store.load() == settings)
    defaults.set(Data("garbage".utf8), forKey: LanguageModelSettingsStore.key)
    #expect(store.load().freeAtRun)
  }

  @Test func idleMinutesStayInRangeAndOldFilesLoad() throws {
    #expect(LanguageModelSettings(idleMinutes: 9999).clamped().idleMinutes == 240)
    #expect(LanguageModelSettings(idleMinutes: -3).clamped().idleMinutes == 0)
    let decoded = try JSONDecoder().decode(LanguageModelSettings.self, from: Data(#"{"folder": "/x"}"#.utf8))
    #expect(decoded.folder == "/x")
    #expect(decoded.idleMinutes == 10)
  }

  @Test func theLiveProbeReportsSomeMemory() {
    #expect(MemoryProbe.live.availableBytes() > 0)
  }
}

/// A language model that is never really loaded.
actor FakeLanguageModelService: LanguageModelService {
  private(set) var loads: [String] = []
  private(set) var unloads = 0
  private(set) var questions: [(String, [URL])] = []
  var loadError: LanguageModelError?
  var answer = "an answer"

  func fail(with error: LanguageModelError?) { loadError = error }

  func load(_ model: LanguageModelDescriptor) async throws {
    if let loadError { throw loadError }
    loads.append(model.name)
  }

  func unload() async { unloads += 1 }

  func respond(to prompt: String, images: [URL]) async throws -> String {
    questions.append((prompt, images))
    return answer
  }
}

@MainActor
struct LanguageModelManagerTests {
  /// A folder with a 1000-byte text model and a 4000-byte vision model.
  func folder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("LanguageModelManagerTests-\(UUID())")
    for (name, size, vision) in [("text-model", 1000, false), ("vision-model", 4000, true)] {
      let dir = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try (vision ? #"{"vision_config": {}}"# : "{}").write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
      try Data(count: size).write(to: dir.appendingPathComponent("w.safetensors"))
    }
    return root
  }

  func manager(
    _ service: FakeLanguageModelService, root: URL, selected: String = "text-model", available: Int64 = 1_000_000,
    idle: Int = 10, freeAtRun: Bool = false, freeImage: Bool = false, release: @escaping @MainActor () async -> Void = {}
  ) -> LanguageModelManager {
    let defaults = UserDefaults(suiteName: "LanguageModelManagerTests-\(UUID())")!
    let store = LanguageModelSettingsStore(defaults: defaults, physicalMemory: 64 * 1_073_741_824)
    let manager = LanguageModelManager(
      service: service, store: store, memory: MemoryProbe { available }, minute: .milliseconds(40), releaseImageModel: release)
    manager.settings = LanguageModelSettings(
      folder: root.path, selectedModel: root.appendingPathComponent(selected).standardizedFileURL.path,
      freeAtRun: freeAtRun, freeImageModelForLanguageModel: freeImage, idleMinutes: idle)
    return manager
  }

  @Test func loadsTheChosenModelOnTheFirstQuestionOnly() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder())
    #expect(try await manager.respond(to: "hello") == "an answer")
    #expect(try await manager.respond(to: "again") == "an answer")
    #expect(await service.loads == ["text-model"])
    #expect(manager.state == .ready("text-model"))
  }

  @Test func withoutAChosenModelItSaysSo() async throws {
    let manager = manager(FakeLanguageModelService(), root: try folder(), selected: "missing")
    await #expect(throws: LanguageModelError.noModelSelected) { try await manager.respond(to: "hi") }
    #expect(manager.state == .failed(.noModelSelected))
  }

  @Test func imagesNeedAVisionModel() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let text = manager(service, root: root)
    await #expect(throws: LanguageModelError.imagesNotSupported) {
      try await text.respond(to: "what is this?", images: [URL(fileURLWithPath: "/tmp/a.png")])
    }
    let vision = manager(service, root: root, selected: "vision-model")
    _ = try await vision.respond(to: "what is this?", images: [URL(fileURLWithPath: "/tmp/a.png")])
    #expect(await service.questions.last?.1 == [URL(fileURLWithPath: "/tmp/a.png")])
  }

  @Test func refusesToLoadWhatDoesNotFitInTheFreeMemory() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), selected: "vision-model", available: 4000)
    // The model's files plus 20 % do not fit in 4000 bytes.
    let size = try #require(manager.selectedModel()).sizeBytes
    let needed = Int64(Double(size) * LanguageModelManager.memoryMargin)
    #expect(needed > 4000)
    await #expect(throws: LanguageModelError.notEnoughMemory(neededBytes: needed, availableBytes: 4000)) {
      try await manager.respond(to: "hi")
    }
    #expect(await service.loads.isEmpty)
    #expect(manager.state == .failed(.notEnoughMemory(neededBytes: needed, availableBytes: 4000)))
  }

  @Test func aLoadFailureIsReported() async throws {
    let service = FakeLanguageModelService()
    await service.fail(with: .loadFailed("bad weights"))
    let manager = manager(service, root: try folder())
    await #expect(throws: LanguageModelError.loadFailed("bad weights")) { try await manager.respond(to: "hi") }
    #expect(!manager.isLoaded)
  }

  @Test func switchingModelsFreesTheOldOneFirst() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let manager = manager(service, root: root)
    _ = try await manager.respond(to: "one")
    manager.settings.selectedModel = root.appendingPathComponent("vision-model").standardizedFileURL.path
    _ = try await manager.respond(to: "two")
    #expect(await service.loads == ["text-model", "vision-model"])
    #expect(await service.unloads == 1)
  }

  @Test func pressingRunFreesTheModelOnlyWhenTheSettingsSaySo() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let keep = manager(service, root: root, freeAtRun: false)
    _ = try await keep.respond(to: "hi")
    await keep.prepareForRun()
    #expect(keep.isLoaded)
    let free = manager(service, root: root, freeAtRun: true)
    _ = try await free.respond(to: "hi")
    await free.prepareForRun()
    #expect(!free.isLoaded)
    #expect(free.state == .unloaded)
    #expect(await service.unloads == 1)
  }

  @Test func freesTheModelAfterTheIdleTime() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 2)
    _ = try await manager.respond(to: "hi")
    #expect(manager.isLoaded)
    for _ in 0..<60 where manager.isLoaded { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!manager.isLoaded)
    #expect(await service.unloads == 1)
  }

  @Test func useRestartsTheIdleTime() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 5)
    _ = try await manager.respond(to: "one")
    try await Task.sleep(for: .milliseconds(100))
    _ = try await manager.respond(to: "two")
    try await Task.sleep(for: .milliseconds(120))
    // 5 × 40 ms = 200 ms since the second question: still loaded after 120 ms.
    #expect(manager.isLoaded)
    #expect(await service.loads.count == 1)
  }

  @Test func idleMinutesAtZeroNeverFreesTheModel() async throws {
    let service = FakeLanguageModelService()
    let manager = manager(service, root: try folder(), idle: 0)
    _ = try await manager.respond(to: "hi")
    try await Task.sleep(for: .milliseconds(150))
    #expect(manager.isLoaded)
  }

  @Test func theImageModelIsReleasedOnlyBeforeALoadAndOnlyWhenAsked() async throws {
    let service = FakeLanguageModelService()
    let root = try folder()
    let released = Counter()
    let on = manager(service, root: root, freeImage: true, release: { released.add() })
    _ = try await on.respond(to: "one")
    _ = try await on.respond(to: "two")
    #expect(released.count == 1)  // not again while the model stays loaded
    let off = manager(service, root: root, freeImage: false, release: { released.add() })
    _ = try await off.respond(to: "one")
    #expect(released.count == 1)
  }

  @Test func theMemoryIsMeasuredAfterTheImageModelLeft() async throws {
    let service = FakeLanguageModelService()
    let probe = MutableMemory(1000)
    let defaults = UserDefaults(suiteName: "LanguageModelManagerTests-\(UUID())")!
    let root = try folder()
    let manager = LanguageModelManager(
      service: service, store: LanguageModelSettingsStore(defaults: defaults), memory: MemoryProbe { probe.value },
      minute: .milliseconds(40), releaseImageModel: { probe.value = 1_000_000 })
    manager.settings = LanguageModelSettings(
      folder: root.path, selectedModel: root.appendingPathComponent("vision-model").standardizedFileURL.path,
      freeAtRun: false, freeImageModelForLanguageModel: true, idleMinutes: 10)
    _ = try await manager.respond(to: "needs the room")
    #expect(manager.isLoaded)
  }
}

final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0
  func add() { lock.withLock { value += 1 } }
  var count: Int { lock.withLock { value } }
}

final class MutableMemory: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: Int64
  init(_ value: Int64) { stored = value }
  var value: Int64 {
    get { lock.withLock { stored } }
    set { lock.withLock { stored = newValue } }
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'LanguageModelScanner' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Language/LanguageModelScanner.swift`**

```swift
import Foundation
import HubKit

/// Finds the language models in a folder (spec §9). A model is a folder with a `config.json`
/// and at least one `.safetensors` file, up to two levels below the models folder (the layout
/// of Hugging Face downloads and of LM Studio, `publisher/model`).
public enum LanguageModelScanner {
  public static let maxDepth = 2

  public static func models(in folder: URL, fileManager: FileManager = .default) -> [LanguageModelDescriptor] {
    var found: [LanguageModelDescriptor] = []
    scan(folder, root: folder, depth: 0, fileManager: fileManager, into: &found)
    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  private static func scan(
    _ directory: URL, root: URL, depth: Int, fileManager: FileManager, into found: inout [LanguageModelDescriptor]
  ) {
    let entries =
      (try? fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
        options: [.skipsHiddenFiles])) ?? []
    if depth > 0, let model = descriptor(of: directory, entries: entries, root: root) {
      found.append(model)
      return
    }
    guard depth < maxDepth else { return }
    for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
      scan(entry, root: root, depth: depth + 1, fileManager: fileManager, into: &found)
    }
  }

  private static func descriptor(of directory: URL, entries: [URL], root: URL) -> LanguageModelDescriptor? {
    let names = Set(entries.map(\.lastPathComponent))
    guard names.contains("config.json"), names.contains(where: { $0.hasSuffix(".safetensors") }) else { return nil }
    let size = entries.reduce(Int64(0)) { total, file in
      total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    let prefix = root.standardizedFileURL.path + "/"
    let path = directory.standardizedFileURL.path
    let name = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : directory.lastPathComponent
    return LanguageModelDescriptor(
      path: path, name: name, sizeBytes: size, supportsImages: hasVision(entries.first { $0.lastPathComponent == "config.json" }))
  }

  /// A vision-language model's `config.json` has a `vision_config` section.
  private static func hasVision(_ config: URL?) -> Bool {
    guard let config, let data = try? Data(contentsOf: config),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return object["vision_config"] != nil
  }
}
```

- [ ] **Step 4: Creare `Packages/Sources/HubCore/Language/LanguageModelSettings.swift`**

```swift
import Darwin
import Foundation

/// The language model's folder, choice and memory behavior (spec §9, §11).
public struct LanguageModelSettings: Equatable, Codable, Sendable {
  /// Where the models are (spec §9: `/Volumes/LLM-VLM/MLX` unless the user chooses another).
  public var folder: String
  /// The folder of the model in use; empty until one is chosen.
  public var selectedModel: String
  /// Frees the language model from memory when RUN is pressed, so Draw Things has the room.
  public var freeAtRun: Bool
  /// Stops the managed Draw Things server before the language model loads, so it has the room
  /// (the image model is reloaded at the next RUN, which takes time). Only with the server DT
  /// Hub starts: DT has no call to unload a model from another server.
  public var freeImageModelForLanguageModel: Bool
  /// Minutes without use after which the language model is freed; 0 = never.
  public var idleMinutes: Int

  public static let defaultFolder = "/Volumes/LLM-VLM/MLX"
  /// Macs with at least this much memory keep both models loaded unless told otherwise.
  public static let comfortableMemory: UInt64 = 64 * 1_073_741_824

  public init(
    folder: String = defaultFolder, selectedModel: String = "", freeAtRun: Bool = true,
    freeImageModelForLanguageModel: Bool = true, idleMinutes: Int = 10
  ) {
    self.folder = folder
    self.selectedModel = selectedModel
    self.freeAtRun = freeAtRun
    self.freeImageModelForLanguageModel = freeImageModelForLanguageModel
    self.idleMinutes = idleMinutes
  }

  /// The memory options on by default only on Macs with less than 64 GB (decided with the
  /// user, 1 October 2026): from 64 GB up both models fit.
  public static func defaults(physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> LanguageModelSettings {
    let tight = physicalMemory < comfortableMemory
    return LanguageModelSettings(freeAtRun: tight, freeImageModelForLanguageModel: tight)
  }

  public static let idleRange = 0...240

  /// The settings forced into their ranges.
  public func clamped() -> LanguageModelSettings {
    var copy = self
    copy.idleMinutes = min(max(idleMinutes, Self.idleRange.lowerBound), Self.idleRange.upperBound)
    return copy
  }

  /// Lenient: a missing field takes the default for this Mac.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = Self.defaults()
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    folder = value(.folder, fallback.folder)
    selectedModel = value(.selectedModel, fallback.selectedModel)
    freeAtRun = value(.freeAtRun, fallback.freeAtRun)
    freeImageModelForLanguageModel = value(.freeImageModelForLanguageModel, fallback.freeImageModelForLanguageModel)
    idleMinutes = value(.idleMinutes, fallback.idleMinutes)
  }
}

/// Persists `LanguageModelSettings` in UserDefaults as JSON (spec §11).
public struct LanguageModelSettingsStore {
  private let defaults: UserDefaults
  static let key = "languageModel.settings"
  private let physicalMemory: UInt64

  public init(defaults: UserDefaults = .standard, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
    self.defaults = defaults
    self.physicalMemory = physicalMemory
  }

  /// The saved settings; the defaults for this Mac's memory when nothing was saved.
  public func load() -> LanguageModelSettings {
    guard let data = defaults.data(forKey: Self.key),
      let settings = try? JSONDecoder().decode(LanguageModelSettings.self, from: data)
    else { return .defaults(physicalMemory: physicalMemory) }
    return settings.clamped()
  }

  public func save(_ settings: LanguageModelSettings) {
    defaults.set(try? JSONEncoder().encode(settings.clamped()), forKey: Self.key)
  }
}

/// Memory the system could give to a program right now.
public struct MemoryProbe: Sendable {
  public var availableBytes: @Sendable () -> Int64

  public init(availableBytes: @escaping @Sendable () -> Int64) {
    self.availableBytes = availableBytes
  }

  /// Free, inactive, speculative and purgeable pages: what the system hands out without
  /// pushing anything to disk.
  public static let live = MemoryProbe {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &statistics) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    guard result == KERN_SUCCESS else { return Int64.max }
    let pages = UInt64(statistics.free_count) + UInt64(statistics.inactive_count)
      + UInt64(statistics.speculative_count) + UInt64(statistics.purgeable_count)
    return Int64(pages) * Int64(sysconf(_SC_PAGESIZE))
  }
}
```

Nota: la dimensione della pagina si legge con `sysconf(_SC_PAGESIZE)` (la variabile `vm_kernel_page_size` non è utilizzabile con la concorrenza di Swift 6).

- [ ] **Step 5: Creare `Packages/Sources/HubCore/Language/LanguageModelManager.swift`**

```swift
import Foundation
import HubKit
import Observation

/// The one language model of DT Hub (spec §9): loads it when something needs it, frees it when
/// RUN is pressed or after a while without use, and checks the memory first. Everything that
/// asks the model a question goes through `respond`.
@MainActor
@Observable
public final class LanguageModelManager {
  public enum State: Equatable, Sendable {
    case unloaded
    case loading(String)
    case ready(String)
    case failed(LanguageModelError)
  }

  public private(set) var state: State = .unloaded
  public var settings: LanguageModelSettings {
    didSet { store.save(settings) }
  }

  /// Memory the model needs beyond its files (the cache of the answer, the working buffers).
  public static let memoryMargin = 1.2

  @ObservationIgnored private let service: any LanguageModelService
  @ObservationIgnored private let store: LanguageModelSettingsStore
  @ObservationIgnored private let memory: MemoryProbe
  @ObservationIgnored private let releaseImageModel: @MainActor () async -> Void
  @ObservationIgnored private let minute: Duration
  @ObservationIgnored private var loaded: LanguageModelDescriptor?
  @ObservationIgnored private var idleTask: Task<Void, Never>?
  /// Bumped by every request, so an idle timer that started before it gives up.
  @ObservationIgnored private var activity = 0

  /// - Parameters:
  ///   - releaseImageModel: stops the image model's server to make room; used before the
  ///     language model loads, when the settings ask for it.
  ///   - minute: how long a minute of idle time lasts (shortened in tests).
  public init(
    service: any LanguageModelService, store: LanguageModelSettingsStore = LanguageModelSettingsStore(),
    memory: MemoryProbe = .live, minute: Duration = .seconds(60),
    releaseImageModel: @escaping @MainActor () async -> Void = {}
  ) {
    self.service = service
    self.store = store
    self.memory = memory
    self.minute = minute
    self.releaseImageModel = releaseImageModel
    settings = store.load()
  }

  public var isLoaded: Bool { loaded != nil }

  /// The models in the chosen folder.
  public func availableModels() -> [LanguageModelDescriptor] {
    LanguageModelScanner.models(in: URL(fileURLWithPath: settings.folder, isDirectory: true))
  }

  /// The model chosen in the settings, when it still is in the folder.
  public func selectedModel() -> LanguageModelDescriptor? {
    availableModels().first { $0.path == settings.selectedModel }
  }

  /// Asks the model: loads it first when needed (after the memory check), then frees it after
  /// the idle time.
  public func respond(to prompt: String, images: [URL] = []) async throws(LanguageModelError) -> String {
    activity += 1
    idleTask?.cancel()
    guard let model = selectedModel() else {
      state = .failed(.noModelSelected)
      throw .noModelSelected
    }
    if !images.isEmpty, !model.supportsImages { throw .imagesNotSupported }
    try await ensureLoaded(model)
    do {
      let answer = try await service.respond(to: prompt, images: images)
      scheduleIdleUnload()
      return answer
    } catch let error as LanguageModelError {
      scheduleIdleUnload()
      throw error
    } catch {
      scheduleIdleUnload()
      throw .generationFailed(error.localizedDescription)
    }
  }

  /// Frees the model from memory now.
  public func unload() async {
    idleTask?.cancel()
    guard loaded != nil else {
      if case .failed = state { state = .unloaded }
      return
    }
    loaded = nil
    state = .unloaded
    await service.unload()
  }

  /// Called when RUN is pressed: frees the model when the settings say so.
  public func prepareForRun() async {
    guard settings.freeAtRun else { return }
    await unload()
  }

  // MARK: Loading

  private func ensureLoaded(_ model: LanguageModelDescriptor) async throws(LanguageModelError) {
    if let loaded, loaded.path == model.path { return }
    if loaded != nil { await unload() }
    // Room first: the image model's server is stopped when the settings ask for it, then the
    // free memory is measured, so what it gave back counts.
    if settings.freeImageModelForLanguageModel { await releaseImageModel() }
    let needed = Int64(Double(model.sizeBytes) * Self.memoryMargin)
    let available = memory.availableBytes()
    guard needed <= available else {
      let error = LanguageModelError.notEnoughMemory(neededBytes: needed, availableBytes: available)
      state = .failed(error)
      throw error
    }
    state = .loading(model.name)
    do {
      try await service.load(model)
      loaded = model
      state = .ready(model.name)
    } catch let error as LanguageModelError {
      state = .failed(error)
      throw error
    } catch {
      let failure = LanguageModelError.loadFailed(error.localizedDescription)
      state = .failed(failure)
      throw failure
    }
  }

  // MARK: Idle

  private func scheduleIdleUnload() {
    idleTask?.cancel()
    guard settings.idleMinutes > 0, loaded != nil else { return }
    let mark = activity
    let wait = minute * settings.idleMinutes
    idleTask = Task { [weak self] in
      try? await Task.sleep(for: wait)
      guard !Task.isCancelled, let self, self.activity == mark else { return }
      await self.unload()
    }
  }
}
```

- [ ] **Step 6: Verificare che passino (tre volte: ci sono test con tempi)**

Run: `cd "<repo>/Packages" && for i in 1 2 3; do swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started | tr '\n' ' '; echo; done`
Expected: HubCore `168 tests … passed` ogni volta (148 + 20); totale 46 + 168 + 47 + 6 = 267.

- [ ] **Step 7: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: LLM in HubCore — ricerca dei modelli, impostazioni di memoria, gestore con scarico al Run e per inattività

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Il motore MLX e lo scaricamento (LLMBridge)

**Files:**
- Create: `Packages/Sources/LLMBridge/MLXLanguageModelService.swift`
- Create: `Packages/Sources/LLMBridge/HubLanguageModelDownloader.swift`
- Modify: `Packages/Package.swift` (target di test `LLMBridgeTests`)
- Test: `Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift`

**Interfaces:**
- Consumes: `LanguageModelService`, `LanguageModelDownloader`, `LanguageModelDescriptor`, `LanguageModelError` (Task 2); `TransformersTokenizerLoader` (Task 1).
- Produces (LLMBridge, `public`): `actor MLXLanguageModelService: LanguageModelService` (`init()`); `struct HubLanguageModelDownloader: LanguageModelDownloader` (`init(matching: [String] = [])`).

- [ ] **Step 1: Aggiungere il target di test in `Packages/Package.swift`**

Inserire, subito prima della riga `.testTarget(name: "HubKitTests", dependencies: ["HubKit"]),`:

```swift
    // Live tests: need a model on disk or the network, and the Metal library, so they run with
    // `xcodebuild test` (`swift test` skips them: spec §13, "LLMBridge: test a mano").
    .testTarget(name: "LLMBridgeTests", dependencies: ["LLMBridge", "HubKit"]),
```

- [ ] **Step 2: Scrivere i test dal vivo.** Creare `Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift` con:

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import LLMBridge

/// Needs a real model: run with
/// `TEST_RUNNER_DTHUB_LIVE_LLM=/path/to/model-folder xcodebuild test -scheme DTHubPackages-Package -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:LLMBridgeTests`
/// (the Metal library is built by Xcode; `swift test` skips these).
struct LiveLanguageModelTests {
  static let modelPath = ProcessInfo.processInfo.environment["DTHUB_LIVE_LLM"]

  func descriptor() throws -> LanguageModelDescriptor {
    let path = try #require(Self.modelPath)
    return LanguageModelDescriptor(path: path, name: URL(fileURLWithPath: path).lastPathComponent, sizeBytes: 0, supportsImages: true)
  }

  /// A 224×224 image that is entirely red.
  func redImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("red-\(UUID()).png")
    let context = try #require(
      CGContext(
        data: nil, width: 224, height: 224, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 224, height: 224))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test(.enabled(if: modelPath != nil))
  func answersAQuestionAndFreesItsMemory() async throws {
    let service = MLXLanguageModelService()
    try await service.load(try descriptor())
    let answer = try await service.respond(to: "Reply with exactly one word: pong", images: [])
    print("LIVE text answer: \(answer)")
    #expect(answer.lowercased().contains("pong"))
    await service.unload()
    await #expect(throws: LanguageModelError.self) { try await service.respond(to: "hi", images: []) }
  }

  @Test(.enabled(if: modelPath != nil))
  func describesAnImage() async throws {
    let service = MLXLanguageModelService()
    try await service.load(try descriptor())
    let answer = try await service.respond(to: "What colour is this image? Answer with one word.", images: [try redImage()])
    print("LIVE vision answer: \(answer)")
    #expect(answer.lowercased().contains("red"))
    await service.unload()
  }
}

/// Needs the network: only two small files (a few KB) of the recommended small model are
/// fetched. Run with `TEST_RUNNER_DTHUB_LIVE_HF=1 xcodebuild test …`.
struct LiveDownloadTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_HF"] != nil))
  func downloadsIntoItsFolderAndLeavesNoStagingBehind() async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("LiveDownloadTests-\(UUID())")
    let destination = parent.appendingPathComponent("mlx-community/Qwen3-VL-2B-Instruct-4bit")
    try await HubLanguageModelDownloader(matching: ["config.json", "tokenizer_config.json"])
      .download(repository: "mlx-community/Qwen3-VL-2B-Instruct-4bit", to: destination, progress: { _ in })
    let files = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
    print("LIVE download files: \(files)")
    #expect(files.contains("config.json"))
    #expect(files.contains("tokenizer_config.json"))
    // The hidden staging folder is gone.
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: destination.deletingLastPathComponent().path)
    #expect(!leftovers.contains { $0.hasPrefix(".dthub-download-") })
    try? FileManager.default.removeItem(at: parent)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["DTHUB_LIVE_HF"] != nil))
  func aFailedDownloadLeavesNothingInTheFolder() async throws {
    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("LiveDownloadTests-\(UUID())")
    let destination = parent.appendingPathComponent("nobody/no-such-model")
    await #expect(throws: LanguageModelError.self) {
      try await HubLanguageModelDownloader().download(
        repository: "nobody/no-such-model-xyz-123", to: destination, progress: { _ in })
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
    let entries = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
    #expect(!entries.contains { $0.hasPrefix(".dthub-download-") })
    try? FileManager.default.removeItem(at: parent)
  }
}
```

- [ ] **Step 3: Verificare che non compilino ancora**

Run: `cd "<repo>/Packages" && swift build --build-tests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MLXLanguageModelService' in scope`.

- [ ] **Step 4: Creare `Packages/Sources/LLMBridge/MLXLanguageModelService.swift`**

```swift
import Foundation
import HubKit
import MLX
import MLXLLM
import MLXLMCommon
import MLXVLM

/// The language model on MLX (spec §9): loads a model from a folder in Hugging Face format,
/// answers one question at a time, with images for a vision-language model, and gives its
/// memory back on `unload`. The only module that knows MLX (spec §4).
public actor MLXLanguageModelService: LanguageModelService {
  private var container: ModelContainer?

  public init() {
    // The two model families register themselves when their modules are linked: touch both so
    // the linker keeps them.
    _ = LLMModelFactory.shared
    _ = VLMModelFactory.shared
  }

  public func load(_ model: LanguageModelDescriptor) async throws {
    await unload()
    do {
      container = try await loadModelContainer(
        from: URL(fileURLWithPath: model.path, isDirectory: true), using: TransformersTokenizerLoader())
    } catch {
      throw LanguageModelError.loadFailed(error.localizedDescription)
    }
  }

  public func unload() async {
    container = nil
    MLX.Memory.clearCache()
  }

  public func respond(to prompt: String, images: [URL]) async throws -> String {
    guard let container else { throw LanguageModelError.loadFailed("No model is loaded.") }
    // A new session per question: DT Hub asks single questions, with no conversation to keep.
    let session = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.6))
    do {
      return try await session.respond(
        to: prompt, role: .user, images: images.map { UserInput.Image.url($0) }, videos: [], audios: [])
    } catch {
      throw LanguageModelError.generationFailed(error.localizedDescription)
    }
  }
}
```

Note:
- `LLMModelFactory.shared` e `VLMModelFactory.shared` si toccano nell'`init` perché i due moduli si registrano da soli solo se il linker li tiene.
- Ogni domanda usa una nuova `ChatSession`: DT Hub fa domande singole, senza conversazione.
- `unload()` azzera il contenitore e svuota la cache GPU di MLX (`MLX.Memory.clearCache()`).

- [ ] **Step 5: Creare `Packages/Sources/LLMBridge/HubLanguageModelDownloader.swift`**

```swift
import Foundation
import HuggingFace
import HubKit

/// Downloads a model from Hugging Face into the models folder, only when the user asked
/// (spec §9). The files are fetched into a hidden folder next to the destination and moved to
/// it when everything has arrived, so a download that fails or is cancelled never leaves a
/// half model that the models list would offer.
public struct HubLanguageModelDownloader: LanguageModelDownloader {
  /// Glob patterns of the files to fetch; empty fetches the whole repository.
  private let patterns: [String]

  public init(matching patterns: [String] = []) {
    self.patterns = patterns
  }

  public func download(
    repository: String, to folder: URL, progress: @escaping @Sendable (Double) -> Void
  ) async throws {
    guard let id = HuggingFace.Repo.ID(rawValue: repository) else {
      throw LanguageModelError.downloadFailed("\(repository) is not a repository name.")
    }
    let fileManager = FileManager.default
    let parent = folder.deletingLastPathComponent()
    let staging = parent.appendingPathComponent(".dthub-download-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: staging) }
    do {
      try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
      _ = try await HuggingFace.HubClient().downloadSnapshot(
        of: id, to: staging, matching: patterns,
        progressHandler: { @MainActor update in progress(update.fractionCompleted) })
      if fileManager.fileExists(atPath: folder.path) { try fileManager.removeItem(at: folder) }
      try fileManager.moveItem(at: staging, to: folder)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw LanguageModelError.downloadFailed(error.localizedDescription)
    }
  }
}
```

- [ ] **Step 6: Provare con `swift test` (i test dal vivo restano inattivi)**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "error:|✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: tutto passa; la suite LLMBridge `4 tests … passed` (inattivi, saltati senza variabili d'ambiente).

- [ ] **Step 7: Prova dal vivo del motore (richiede un modello e Metal Toolchain)**

Sul Mac dell'utente è già scaricato `/Volumes/LLM-VLM/MLX/mlx-community/Qwen3-VL-2B-Instruct-4bit` (1,8 GB, scaricato con il suo permesso il 1 ottobre 2026). Se manca, **non scaricarlo senza chiedere**: chiedere il permesso indicando repository, file e dimensione.

Run: `cd "<repo>/Packages" && TEST_RUNNER_DTHUB_LIVE_LLM=/Volumes/LLM-VLM/MLX/mlx-community/Qwen3-VL-2B-Instruct-4bit xcodebuild test -scheme DTHubPackages-Package -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:LLMBridgeTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "LIVE|Test .*(passed|failed)|TEST (SUCCEEDED|FAILED)|recorded an issue"`
Expected: `LIVE text answer: pong`, `LIVE vision answer:  red`, i due test del motore passano, `** TEST SUCCEEDED **`.

- [ ] **Step 8: Prova dal vivo dello scaricamento (solo due file piccoli)**

Il test scarica `config.json` e `tokenizer_config.json` (pochi KB) dello stesso modello già autorizzato, in una cartella temporanea.

Run: `cd "<repo>/Packages" && TEST_RUNNER_DTHUB_LIVE_HF=1 xcodebuild test -scheme DTHubPackages-Package -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:LLMBridgeTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "LIVE|Test .*(passed|failed)|TEST (SUCCEEDED|FAILED)|recorded an issue"`
Expected: `LIVE download files: ["config.json", "tokenizer_config.json"]`, i due test di scaricamento passano.

- [ ] **Step 9: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: LLMBridge — servizio MLX (testo e immagini) e scaricamento da Hugging Face con cartella di appoggio

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Testi dell'LLM (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (35 chiavi nuove; tolte `prefs.empty.title` e `prefs.empty.message`, non più usate)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `prefs.llm.*`, `llm.error.*`, `results.preparingMemory`, `status.imageModelParked` usate dalla scheda LLM, dal controller, dalla finestra Risultati e dall'header (Task 6); `prefs.llm.download.confirm.message` (`%@` repository, `%@` dimensione, `%@` cartella), `prefs.llm.noModels` (`%@`), `prefs.llm.model.vision` (`%@`, `%@`), `prefs.llm.idle` (`%lld`), `llm.error.memory` (`%@`, `%@`), `llm.error.load` e `llm.error.generation` (`%@`) si usano con `String(format:)`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

```bash
cd "<repo>" && python3 - <<'EOF'
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "llm.error.generation": ("The model could not answer: %@", "Il modello non ha risposto: %@"),
    "llm.error.load": ("The model could not be loaded: %@", "Il modello non si è caricato: %@"),
    "llm.error.memory": ("Not enough free memory: the model needs about %@ and %@ are free.", "Memoria libera insufficiente: il modello ne richiede circa %@ e ne sono liberi %@."),
    "llm.error.noImages": ("This model cannot look at images: choose one with “images”.", "Questo modello non guarda le immagini: scegline uno con “immagini”."),
    "llm.error.noModel": ("Choose a model first.", "Scegli prima un modello."),
    "prefs.llm.download.button": ("Download the recommended model (%@)…", "Scarica il modello consigliato (%@)…"),
    "prefs.llm.download.cancel": ("Cancel", "Annulla"),
    "prefs.llm.download.confirm.button": ("Download", "Scarica"),
    "prefs.llm.download.confirm.message": ("%@ from huggingface.co, about %@, into %@. It can be removed by deleting its folder.", "%@ da huggingface.co, circa %@, in %@. Si toglie cancellando la sua cartella."),
    "prefs.llm.download.confirm.title": ("Download the recommended model?", "Scaricare il modello consigliato?"),
    "prefs.llm.download.error": ("The download failed: %@", "Lo scaricamento non è riuscito: %@"),
    "prefs.llm.folder": ("Models folder", "Cartella dei modelli"),
    "prefs.llm.folder.note": ("A model is a folder in Hugging Face format (config.json and .safetensors files), as MLX loads them: for instance from mlx-community, or from LM Studio. Draw Things' own .ckpt files cannot be used.", "Un modello è una cartella in formato Hugging Face (config.json e file .safetensors), come li carica MLX: per esempio da mlx-community o da LM Studio. I file .ckpt di Draw Things non si possono usare."),
    "prefs.llm.freeAtRun": ("Free the language model when I press Run", "Libera l'LLM quando premo Run"),
    "prefs.llm.freeImageModel": ("Free the image model when the language model is used", "Libera il modello immagine quando uso l'LLM"),
    "prefs.llm.freeImageModel.cost": ("The image model loads again at the next Run, which can take a while.", "Il modello immagine si ricarica al prossimo Run, e può richiedere del tempo."),
    "prefs.llm.freeImageModel.unavailable": ("Only with the server DT Hub starts: Draw Things has no call to unload a model from another server.", "Solo con il server avviato da DT Hub: Draw Things non ha una chiamata per scaricare un modello da un altro server."),
    "prefs.llm.idle": ("Free the language model after %lld minutes without use", "Libera l'LLM dopo %lld minuti senza usarlo"),
    "prefs.llm.idle.never": ("Never free the language model when idle", "Non liberare mai l'LLM per inattività"),
    "prefs.llm.memory": ("Memory", "Memoria"),
    "prefs.llm.model": ("Model", "Modello"),
    "prefs.llm.model.none": ("None", "Nessuno"),
    "prefs.llm.model.vision": ("%@ · %@ · images", "%@ · %@ · immagini"),
    "prefs.llm.noModels": ("No model found in %@.", "Nessun modello trovato in %@."),
    "prefs.llm.state.loading": ("Loading %@…", "Caricamento di %@…"),
    "prefs.llm.state.ready": ("Ready: %@", "Pronto: %@"),
    "prefs.llm.state.unloaded": ("No model loaded", "Nessun modello caricato"),
    "prefs.llm.test": ("Test", "Prova"),
    "prefs.llm.test.ask": ("Ask", "Chiedi"),
    "prefs.llm.test.image": ("Choose an image…", "Scegli un'immagine…"),
    "prefs.llm.test.question": ("Ask the model something", "Fai una domanda al modello"),
    "prefs.llm.test.removeImage": ("Remove the image", "Togli l'immagine"),
    "prefs.llm.test.sample": ("Reply with a short greeting.", "Rispondi con un breve saluto."),
    "results.preparingMemory": ("Freeing memory…", "Libero la memoria…"),
    "status.imageModelParked": ("The image model was freed for the language model; Run loads it again.", "Il modello immagine è stato liberato per l'LLM; Run lo ricarica."),
}
for key, (en, it) in new.items():
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
for key in ("prefs.empty.title", "prefs.empty.message"):
    d['strings'].pop(key, None)
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
EOF
git diff --stat App/Localizable.xcstrings
```

Expected: `1 file changed, 567 insertions(+), 6 deletions(-)` (le righe tolte sono le due chiavi `prefs.empty.*`).

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "<repo>/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`. (Le chiavi `prefs.empty.*` non sono più nel codice: il Task 6 toglie il segnaposto.)

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add App/Localizable.xcstrings && git commit -m "feat: testi dell'LLM (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Scheda LLM e collegamento al Run (App)

**Files:**
- Create: `App/Preferences/LanguagePreferencesView.swift`
- Modify: `App/Preferences/PreferencesView.swift` (la scheda LLM al posto del segnaposto)
- Modify: `App/Connection/DrawThingsConnection.swift` (modello immagine liberato e ripreso, `runBlocker`)
- Modify: `App/Generation/GenerationController.swift` (preparazione al Run)
- Modify: `App/MainWindow/HeaderBar.swift` (blocco di Run dalla connessione, preparazione, testo del pallino)
- Modify: `App/Results/ResultsView.swift` ("Libero la memoria…")
- Modify: `App/DTHubApp.swift` (crea il gestore con il servizio MLX)

**Interfaces:**
- Consumes: `LanguageModelManager`, `LanguageModelSettings`, `LanguageModelScanner`, `LanguageModelError` (Task 2–3); `MLXLanguageModelService`, `HubLanguageModelDownloader` (Task 4); le chiavi del Task 5; `ManagedServer.stopAndWait()`, `start(_:)` (M5).
- Produces: `DrawThingsConnection.releasedForLanguageModel`, `runBlocker`, `releaseImageModel()`, `ensureServerForRun()`; `GenerationController.languageModel`, `isPreparing`, `init(languageModel:sessionStore:)`; `LanguagePreferencesView(manager:connection:)`; `LanguageModelErrorText.message(_:)`.

- [ ] **Step 1: Sostituire `App/Connection/DrawThingsConnection.swift` con:**

```swift
import AppKit
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
    // Quitting stops the managed server whichever windows are open: this object lives as long
    // as the app, a window's view does not.
    NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [managedServer] _ in
      MainActor.assumeIsolated { managedServer.terminateNow() }
    }
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

  /// What the header dot shows: yellow while the managed server is starting (its first moments,
  /// until it answers: spec §7), whatever the monitor says meanwhile; after that a server that
  /// does not answer is red, with the reason.
  var indicator: ConnectionStatus {
    if releasedForLanguageModel { return .connecting }
    if managed.mode == .managed, managedServer.isStarting, monitor.status != .connected { return .connecting }
    return monitor.indicator
  }

  /// What to say when the server answers but lists no model: with "Model browsing" off (a
  /// server of the Draw Things app), or, for the server DT Hub starts (which always has
  /// it on), with no model file in the chosen folder.
  var noModelsText: String {
    managed.mode == .managed
      ? String(localized: "server.noModels") : String(localized: "header.model.browsingDisabled")
  }

  /// True while the managed server is stopped on purpose, to leave the memory to the language
  /// model (spec §9): the next RUN starts it again.
  private(set) var releasedForLanguageModel = false

  /// Why RUN cannot start now; nil when it can. A server parked for the language model is no
  /// reason: RUN brings it back.
  var runBlocker: RunBlocker? {
    if releasedForLanguageModel, selection.selectedFile != nil { return nil }
    return RunAvailability.blocker(
      connection: monitor.status, selectedModel: selection.selectedFile, catalog: monitor.catalog)
  }

  /// Stops the managed server so the language model has the room. Only the server DT Hub
  /// started can be stopped: Draw Things has no call to unload a model from another one.
  func releaseImageModel() async {
    guard managed.mode == .managed, managedServer.isRunning else { return }
    await managedServer.stopAndWait()
    releasedForLanguageModel = true
  }

  /// Brings the managed server back when it was released, and waits until it answers (the
  /// image model loads again, which takes time).
  func ensureServerForRun() async {
    guard releasedForLanguageModel else { return }
    await managedServer.start(managed)
    for _ in 0..<300 {
      await monitor.refresh()
      if monitor.status == .connected { break }
      try? await Task.sleep(for: .seconds(1))
    }
    releasedForLanguageModel = false
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

- [ ] **Step 2: Sostituire `App/Generation/GenerationController.swift` con:**

```swift
import DTBridge
import CoreGraphics
import Foundation
import HubCore
import HubKit
import Observation

/// App-level state of the Generation tab: prompt, parameters, card states, and the session
/// that runs them (spec §6, §7). Lives as long as the app.
@MainActor
@Observable
final class GenerationController {
  var prompt = "" {
    didSet { scheduleSessionSave() }
  }
  /// Sent only when the model's family uses it (`JobComposer`).
  var negativePrompt = "" {
    didSet { scheduleSessionSave() }
  }
  var parameters = GenerationParameters.default {
    didSet { scheduleSessionSave() }
  }
  /// When on, width and height move together to keep `lockedRatio`.
  var lockRatio = false {
    didSet {
      lockedRatio = lockRatio ? currentRatio : nil
      scheduleSessionSave()
    }
  }
  /// Width ÷ height kept while `lockRatio` is on.
  private(set) var lockedRatio: Double?
  let session = GenerationSession(store: CurrentFolderImageStore())
  let cards = CardExpansionStore(fileURL: CardExpansionStore.defaultFileURL)
  private(set) var outputFolder: URL

  /// The language model, freed when RUN is pressed if the settings say so (spec §9).
  @ObservationIgnored let languageModel: LanguageModelManager
  /// True between pressing RUN and the generation starting: the language model is being freed
  /// and a parked server brought back.
  private(set) var isPreparing = false

  @ObservationIgnored private let outputSettings = OutputSettingsStore()
  @ObservationIgnored private let sessionStore: SessionStore
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  /// Restores the last prompt and parameters (spec §11).
  init(
    languageModel: LanguageModelManager,
    sessionStore: SessionStore = SessionStore(fileURL: SessionStore.defaultFileURL)
  ) {
    self.languageModel = languageModel
    self.sessionStore = sessionStore
    outputFolder = outputSettings.folder()
    if let snapshot = sessionStore.load() {
      prompt = snapshot.prompt
      negativePrompt = snapshot.negativePrompt
      parameters = snapshot.parameters.clamped()
      lockRatio = snapshot.lockRatio
      // Observers do not run inside init: the locked ratio is set here.
      lockedRatio = lockRatio ? currentRatio : nil
    }
    pendingSave?.cancel()
    pendingSave = nil
  }

  /// The saved presets (spec §6).
  let presets = PresetStore(fileURL: PresetStore.defaultFileURL)
  /// Reads and writes the Draw Things configuration JSON (spec §6, level 3).
  @ObservationIgnored let codec: any ConfigurationCodec = DrawThingsConfigurationCodec()

  /// The model and parameters on the tab, as the JSON editor sees them.
  func configurationState(in connection: DrawThingsConnection) -> ConfigurationState {
    ConfigurationState(model: connection.selection.selectedFile ?? "", parameters: parameters)
  }

  func exportJSON(in connection: DrawThingsConnection) -> String {
    codec.exportJSON(configurationState(in: connection))
  }

  /// Applies a complete or partial Draw Things JSON to the tab: parameters, extra settings
  /// and, when the text names one, the model. Throws the reason when the text is not valid.
  func applyJSON(_ json: String, with connection: DrawThingsConnection) throws(ConfigurationError) {
    let result = try codec.apply(json: json, to: configurationState(in: connection))
    parameters = result.parameters.fillingTriggers(from: connection.monitor.catalog)
    if lockRatio { lockedRatio = currentRatio }
    if !result.model.isEmpty, result.model != connection.selection.selectedFile {
      connection.selection.select(result.model)
    }
  }

  /// Saves the tab as a preset (parameters, model, negative prompt; never the prompt).
  /// False when the name is empty.
  @discardableResult
  func savePreset(named name: String, with connection: DrawThingsConnection) -> Bool {
    presets.save(
      Preset(
        name: name, model: connection.selection.selectedFile ?? "", negativePrompt: negativePrompt,
        parameters: parameters))
  }

  /// Puts a preset on the tab; the prompt stays.
  func load(_ preset: Preset, with connection: DrawThingsConnection) {
    let load = PresetLoad.of(preset, currentNegativePrompt: negativePrompt, catalog: connection.monitor.catalog)
    parameters = load.parameters
    negativePrompt = load.negativePrompt
    if lockRatio { lockedRatio = currentRatio }
    if let model = load.model { connection.selection.select(model) }
  }

  /// Adds the presets of a file (a JSON list of `{name, configuration}`).
  func importPresets(from url: URL) -> PresetImportResult {
    guard let data = try? Data(contentsOf: url) else { return PresetImportResult(presets: [], skipped: 1) }
    let result = PresetImport.read(data, codec: codec)
    presets.add(imported: result.presets)
    return result
  }

  /// The chosen model as the server describes it; nil while the catalog is not loaded.
  func selectedModel(in connection: DrawThingsConnection) -> CatalogModel? {
    connection.selection.selectedModel(in: connection.monitor.catalog)
  }

  /// The family of the chosen model, nil when unknown or while the catalog is not loaded.
  func family(in connection: DrawThingsConnection) -> String? {
    selectedModel(in: connection)?.family
  }

  /// Which base fields the chosen model's family uses.
  func traits(in connection: DrawThingsConnection) -> FamilyTraits {
    FamilyTraits.of(family(in: connection))
  }

  /// Writes the session half a second after the last change, so typing does not write
  /// the file at every keystroke.
  private func scheduleSessionSave() {
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      self?.saveSessionNow()
    }
  }

  /// Writes the session at once (also when the app quits); a failure only loses the restore.
  func saveSessionNow() {
    pendingSave?.cancel()
    pendingSave = nil
    try? sessionStore.save(
      SessionSnapshot(prompt: prompt, negativePrompt: negativePrompt, parameters: parameters, lockRatio: lockRatio))
  }

  /// True when the server, the model and the session allow a RUN.
  func canRun(with connection: DrawThingsConnection) -> Bool {
    !session.isRunning && !isPreparing && connection.monitor.backend != nil && connection.runBlocker == nil
  }

  /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
  /// drawn for the first batch is shown in the Seed field.
  @discardableResult
  func run(with connection: DrawThingsConnection) -> Bool {
    guard canRun(with: connection) else { return false }
    isPreparing = true
    Task {
      // Memory first: the language model leaves, a server parked for it comes back.
      await languageModel.prepareForRun()
      await connection.ensureServerForRun()
      isPreparing = false
      start(with: connection)
    }
    return true
  }

  /// The generation itself, once the memory is ready. The job is composed now, not at the
  /// click: a parked server has no catalog until it is back.
  private func start(with connection: DrawThingsConnection) {
    guard !session.isRunning, let backend = connection.monitor.backend,
      let model = connection.selection.selectedFile,
      RunAvailability.blocker(
        connection: connection.monitor.status, selectedModel: model, catalog: connection.monitor.catalog) == nil
    else { return }
    let batches = JobComposer.batches(
      prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
      parameters: parameters, catalog: connection.monitor.catalog)
    if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
    session.start(batches, backend: backend, monitor: connection.monitor)
  }

  /// "Resume parameters": puts back the prompt, negative prompt, model and parameters of the
  /// batch that made the image (its seed, batch count 1, the LoRAs sent). A ratio lock
  /// follows the resumed size.
  func resume(_ result: GeneratedImage, with connection: DrawThingsConnection) {
    prompt = result.job.prompt
    negativePrompt = result.job.negativePrompt
    parameters = result.job.parameters
    if lockRatio { lockedRatio = currentRatio }
    connection.selection.select(result.job.model)
  }

  func apply(_ ratio: AspectRatio) {
    parameters.apply(ratio)
    if lockRatio { lockedRatio = currentRatio }
  }

  func swapDimensions() {
    parameters.swapDimensions()
    if lockRatio { lockedRatio = currentRatio }
  }

  private var currentRatio: Double {
    Double(parameters.width) / Double(max(parameters.height, 1))
  }

  func setOutputFolder(_ url: URL) {
    outputSettings.setFolder(url)
    outputFolder = url
  }
}

/// Saves into the Output folder chosen at the moment of saving.
struct CurrentFolderImageStore: ImageStore {
  func save(_ image: CGImage, job: GenerationJob, index: Int, date: Date) throws -> URL {
    try PNGImageStore(folder: OutputSettingsStore().folder()).save(image, job: job, index: index, date: date)
  }
}
```

- [ ] **Step 3: Sostituire `App/MainWindow/HeaderBar.swift` con:**

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

  private var runBlocker: RunBlocker? { connection.runBlocker }

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
      .disabled(runBlocker != nil || generation.isPreparing)
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
    if connection.releasedForLanguageModel { return String(localized: "status.imageModelParked") }
    if connection.managed.mode == .managed, connection.managedServer.isStarting, monitor.status != .connected {
      return String(localized: "status.serverStarting")
    }
    if monitor.status == .connected, monitor.catalog.isModelBrowsingDisabled {
      return connection.noModelsText
    }
    return ConnectionStatusText.headline(status: monitor.status, error: monitor.lastError)
  }
}
```

- [ ] **Step 4: Sostituire `App/Results/ResultsView.swift` con:**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI

/// The results window (spec §7): live preview while running, then the chosen image; the
/// session strip; for the chosen image: seed, Show in Finder, Resume parameters.
struct ResultsView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @State private var selectedID: GeneratedImage.ID?

  private var session: GenerationSession { controller.session }
  private var selected: GeneratedImage? {
    session.results.first { $0.id == selectedID } ?? session.results.first
  }

  var body: some View {
    VStack(spacing: DS.panelPadding) {
      imageArea
      statusLine
      if !session.results.isEmpty {
        strip
        if let selected { actions(for: selected) }
      }
    }
    .padding(20)
    .frame(minWidth: 520, idealWidth: 720, minHeight: 560, idealHeight: 820)
    .background(DSBackground())
    .background(DSWindowConfigurator())
    .tint(DS.accent)
    .onChange(of: session.results.first?.id) { selectedID = session.results.first?.id }
  }

  private var shownImage: CGImage? {
    if session.isRunning, let preview = session.preview { return preview }
    return selected?.image
  }

  private var imageArea: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.minorRadius, style: .continuous)
        .fill(Color.primary.opacity(0.06))
      if let shownImage {
        Image(decorative: shownImage, scale: 1)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .padding(6)
      } else if session.isRunning {
        ProgressView()
      } else {
        ContentUnavailableView(
          "results.empty.title", systemImage: "photo.on.rectangle",
          description: Text("results.empty.message"))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder private var statusLine: some View {
    switch session.phase {
    case .running(let step, let total):
      HStack(alignment: .center, spacing: DS.controlGap) {
        VStack(alignment: .leading, spacing: 4) {
          if let step {
            ProgressView(value: Double(step), total: Double(max(total, 1)))
          } else {
            ProgressView().progressViewStyle(.linear)
          }
          HStack(spacing: DS.controlGap) {
            if session.batch.count > 1 {
              Text(String(format: String(localized: "results.progress.batch"), session.batch.index, session.batch.count))
            }
            if let step {
              Text(String(format: String(localized: "results.progress.step"), step, total))
            } else {
              Text("results.progress.preparing")
            }
          }
          .font(.caption).foregroundStyle(.secondary)
        }
        Button {
          session.cancel()
        } label: {
          Label("header.stop", systemImage: "stop.fill")
        }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "header.stop.help"))
      }
    case .failed(let error):
      HStack(alignment: .top, spacing: DS.controlGap) {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.remove)
        VStack(alignment: .leading, spacing: 2) {
          Text(GenerationErrorText.headline(error))
          if let detail = GenerationErrorText.detail(error) {
            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
          }
        }
        Spacer(minLength: 0)
        Button("results.dismiss") { session.dismissFailure() }
          .buttonStyle(DSPillButtonStyle())
      }
    case .idle:
      if controller.isPreparing {
        HStack(spacing: DS.controlGap) {
          ProgressView().controlSize(.small)
          Text("results.preparingMemory").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var strip: some View {
    ScrollView(.horizontal) {
      HStack(spacing: DS.controlGap) {
        ForEach(session.results) { result in
          Button {
            selectedID = result.id
          } label: {
            Image(decorative: result.image, scale: 1)
              .resizable()
              .scaledToFill()
              .frame(width: 72, height: 72)
              .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
                  .strokeBorder(result.id == selected?.id ? DS.accent : Color.clear, lineWidth: 2))
          }
          .buttonStyle(.plain)
          .accessibilityLabel(result.job.prompt)
        }
      }
      .padding(2)
    }
    .frame(height: 80)
  }

  private func actions(for result: GeneratedImage) -> some View {
    HStack(spacing: DS.controlGap) {
      Text(String(format: String(localized: "results.seed"), String(result.job.parameters.seed)))
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
      if let error = result.saveError {
        Text("results.notSaved").font(.caption).foregroundStyle(DS.remove).help(error)
      }
      Spacer(minLength: 0)
      if let url = result.fileURL {
        Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
          .buttonStyle(DSPillButtonStyle())
      }
      Button("results.resume") { controller.resume(result, with: connection) }
        .buttonStyle(DSPillButtonStyle())
    }
  }
}
```

- [ ] **Step 5: Sostituire `App/DTHubApp.swift` con:**

```swift
import AppKit
import HubCore
import HubKit
import LLMBridge
import SwiftUI

@main
struct DTHubApp: App {
  @State private var workspace = WorkspaceState(
    generationTab: WorkspaceTab(
      id: WorkspaceTab.generationID,
      title: String(localized: "tab.generation"),
      systemImage: "slider.horizontal.3"))
  @State private var connection: DrawThingsConnection
  @State private var languageModel: LanguageModelManager
  @State private var generation: GenerationController

  init() {
    let connection = DrawThingsConnection()
    // The language model frees the managed server's memory when the settings ask for it.
    let languageModel = LanguageModelManager(
      service: MLXLanguageModelService(), releaseImageModel: { await connection.releaseImageModel() })
    _connection = State(initialValue: connection)
    _languageModel = State(initialValue: languageModel)
    _generation = State(initialValue: GenerationController(languageModel: languageModel))
  }

  var body: some Scene {
    WindowGroup(String(localized: "app.title")) {
      MainWindowView(workspace: workspace, connection: connection, generation: generation)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          generation.saveSessionNow()
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
      PreferencesView(connection: connection, generation: generation, languageModel: languageModel)
    }
  }
}
```

- [ ] **Step 6: Sostituire `App/Preferences/PreferencesView.swift` con:**

```swift
import HubCore
import SwiftUI

/// Preferences window (⌘,): Draw Things, LLM, Output (spec §7).
struct PreferencesView: View {
  let connection: DrawThingsConnection
  let generation: GenerationController
  let languageModel: LanguageModelManager

  var body: some View {
    TabView {
      Tab("prefs.tab.drawThings", systemImage: "server.rack") {
        DrawThingsPreferencesView(connection: connection)
      }
      Tab("prefs.tab.llm", systemImage: "text.bubble") {
        LanguagePreferencesView(manager: languageModel, connection: connection)
      }
      Tab("prefs.tab.output", systemImage: "folder") {
        OutputPreferencesView(controller: generation)
      }
    }
    .frame(width: 560, height: 420)
  }
}
```

- [ ] **Step 7: Creare `App/Preferences/LanguagePreferencesView.swift`**

```swift
import AppKit
import HubCore
import HubKit
import LLMBridge
import SwiftUI
import UniformTypeIdentifiers

/// Preferences › LLM (spec §9): the models folder, the model in use, downloading the
/// recommended one (only when asked), the memory behavior, and a test question with or
/// without an image.
struct LanguagePreferencesView: View {
  @Bindable var manager: LanguageModelManager
  let connection: DrawThingsConnection

  @State private var models: [LanguageModelDescriptor] = []
  @State private var confirmingDownload = false
  @State private var downloadProgress: Double?
  @State private var downloadTask: Task<Void, Never>?
  @State private var downloadError: String?
  /// A sample question, so the test can be tried at once.
  @State private var question = String(localized: "prefs.llm.test.sample")
  @State private var imageURL: URL?
  @State private var answer = ""
  @State private var asking = false
  @State private var askError: LanguageModelError?

  private var folderURL: URL { URL(fileURLWithPath: manager.settings.folder, isDirectory: true) }
  private var hasRecommended: Bool {
    models.contains { $0.name == RecommendedLanguageModel.folderName }
  }

  var body: some View {
    Form {
      folderSection
      memorySection
      testSection
    }
    .formStyle(.grouped)
    .onAppear(perform: refresh)
    .confirmationDialog(
      String(localized: "prefs.llm.download.confirm.title"), isPresented: $confirmingDownload, titleVisibility: .visible
    ) {
      Button("prefs.llm.download.confirm.button", action: startDownload)
    } message: {
      Text(
        String(
          format: String(localized: "prefs.llm.download.confirm.message"), RecommendedLanguageModel.repository,
          ByteCountFormatter.string(fromByteCount: RecommendedLanguageModel.approximateBytes, countStyle: .file),
          manager.settings.folder))
    }
  }

  // MARK: Folder and model

  private var folderSection: some View {
    Section {
      HStack(spacing: DS.controlGap) {
        TextField("prefs.llm.folder", text: $manager.settings.folder)
          .onSubmit(refresh)
        Button("prefs.server.choose", action: chooseFolder)
      }
      if models.isEmpty {
        Text(String(format: String(localized: "prefs.llm.noModels"), manager.settings.folder))
          .foregroundStyle(.secondary)
      } else {
        Picker("prefs.llm.model", selection: $manager.settings.selectedModel) {
          Text("prefs.llm.model.none").tag("")
          ForEach(models) { model in
            Text(verbatim: label(of: model)).tag(model.path)
          }
        }
      }
      downloadRow
    } footer: {
      Text("prefs.llm.folder.note")
        .foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var downloadRow: some View {
    if let downloadProgress {
      HStack(spacing: DS.controlGap) {
        ProgressView(value: downloadProgress)
        Button("prefs.llm.download.cancel") { downloadTask?.cancel() }
      }
    } else if !hasRecommended {
      Button {
        confirmingDownload = true
      } label: {
        Text(
          String(
            format: String(localized: "prefs.llm.download.button"),
            ByteCountFormatter.string(fromByteCount: RecommendedLanguageModel.approximateBytes, countStyle: .file)))
      }
    }
    if let downloadError {
      Text(String(format: String(localized: "prefs.llm.download.error"), downloadError))
        .foregroundStyle(DS.remove)
        .font(.caption)
    }
  }

  private func label(of model: LanguageModelDescriptor) -> String {
    let size = ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file)
    return model.supportsImages
      ? String(format: String(localized: "prefs.llm.model.vision"), model.name, size) : "\(model.name) · \(size)"
  }

  private func refresh() {
    models = manager.availableModels()
    if !manager.settings.selectedModel.isEmpty, !models.contains(where: { $0.path == manager.settings.selectedModel }) {
      manager.settings.selectedModel = ""
    }
    if manager.settings.selectedModel.isEmpty, let first = models.first { manager.settings.selectedModel = first.path }
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK, let url = panel.url {
      manager.settings.folder = url.path
      refresh()
    }
  }

  /// Downloads the recommended model into `<folder>/mlx-community/…` (only after the user
  /// confirmed the dialog that names it, its size and where it goes).
  private func startDownload() {
    downloadError = nil
    downloadProgress = 0
    let destination = folderURL.appendingPathComponent(RecommendedLanguageModel.folderName, isDirectory: true)
    downloadTask = Task {
      do {
        try await HubLanguageModelDownloader().download(
          repository: RecommendedLanguageModel.repository, to: destination,
          progress: { fraction in Task { @MainActor in downloadProgress = fraction } })
      } catch is CancellationError {
      } catch {
        if !Task.isCancelled { downloadError = LanguageModelErrorText.message(error) }
      }
      downloadProgress = nil
      downloadTask = nil
      refresh()
    }
  }

  // MARK: Memory

  private var memorySection: some View {
    Section {
      Toggle("prefs.llm.freeAtRun", isOn: $manager.settings.freeAtRun)
      Toggle("prefs.llm.freeImageModel", isOn: $manager.settings.freeImageModelForLanguageModel)
        .disabled(connection.managed.mode != .managed)
      Stepper(
        value: $manager.settings.idleMinutes, in: LanguageModelSettings.idleRange, step: 5
      ) {
        Text(
          manager.settings.idleMinutes == 0
            ? String(localized: "prefs.llm.idle.never")
            : String(format: String(localized: "prefs.llm.idle"), manager.settings.idleMinutes))
      }
    } header: {
      Text("prefs.llm.memory")
    } footer: {
      VStack(alignment: .leading, spacing: 4) {
        if connection.managed.mode != .managed {
          Text("prefs.llm.freeImageModel.unavailable")
        } else if manager.settings.freeImageModelForLanguageModel {
          Text("prefs.llm.freeImageModel.cost")
        }
      }
      .foregroundStyle(.secondary)
    }
  }

  // MARK: Test

  private var testSection: some View {
    Section {
      TextField("prefs.llm.test.question", text: $question, axis: .vertical)
        .lineLimit(1...4)
      HStack(spacing: DS.controlGap) {
        Button("prefs.llm.test.image", action: chooseImage)
        if let imageURL {
          Text(verbatim: imageURL.lastPathComponent)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Button {
            self.imageURL = nil
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .buttonStyle(.plain)
          .accessibilityLabel(String(localized: "prefs.llm.test.removeImage"))
        }
        Spacer(minLength: DS.controlGap)
        Button("prefs.llm.test.ask", action: ask)
          .buttonStyle(DSPillButtonStyle(prominent: true))
          .disabled(asking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      HStack(spacing: DS.controlGap) {
        if asking { ProgressView().controlSize(.small) }
        Text(verbatim: stateLine)
          .font(.caption)
          .foregroundStyle(askError == nil ? Color.secondary : DS.remove)
      }
      if !answer.isEmpty {
        Text(verbatim: answer)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } header: {
      Text("prefs.llm.test")
    }
  }

  private var stateLine: String {
    if let askError { return LanguageModelErrorText.message(askError) }
    switch manager.state {
    case .unloaded: return String(localized: "prefs.llm.state.unloaded")
    case .loading(let name): return String(format: String(localized: "prefs.llm.state.loading"), name)
    case .ready(let name): return String(format: String(localized: "prefs.llm.state.ready"), name)
    case .failed(let error): return LanguageModelErrorText.message(error)
    }
  }

  private func chooseImage() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    if panel.runModal() == .OK { imageURL = panel.url }
  }

  private func ask() {
    asking = true
    askError = nil
    answer = ""
    Task {
      do {
        answer = try await manager.respond(to: question, images: imageURL.map { [$0] } ?? [])
      } catch {
        askError = error as? LanguageModelError ?? .generationFailed(error.localizedDescription)
      }
      asking = false
    }
  }
}

/// The words for what went wrong with the language model.
enum LanguageModelErrorText {
  static func message(_ error: any Error) -> String {
    guard let error = error as? LanguageModelError else { return error.localizedDescription }
    switch error {
    case .noModelSelected: return String(localized: "llm.error.noModel")
    case .imagesNotSupported: return String(localized: "llm.error.noImages")
    case .notEnoughMemory(let needed, let available):
      return String(
        format: String(localized: "llm.error.memory"), ByteCountFormatter.string(fromByteCount: needed, countStyle: .memory),
        ByteCountFormatter.string(fromByteCount: available, countStyle: .memory))
    case .loadFailed(let detail): return String(format: String(localized: "llm.error.load"), detail)
    case .generationFailed(let detail): return String(format: String(localized: "llm.error.generation"), detail)
    case .downloadFailed(let detail): return detail
    }
  }
}
```

- [ ] **Step 8: Build e test**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with|Missing|Not in|Pass String" | grep -v started`
Expected: `** BUILD SUCCEEDED **`; test HubKit 46, HubCore 168, DTBridge 47, Catalog 6, LLMBridge 4 (inattivi): **271** passati.

- [ ] **Step 9: Commit**

```bash
cd "<repo>" && git add App && git commit -m "feat: scheda LLM nelle Preferenze, memoria condivisa con il modello immagine e collegamento al Run

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verifica dal vivo

Nessun codice nuovo. Serve il server gestito dalla M5 (programma e cartella dei modelli in `/Volumes/LLM-VLM/Models`), il modello 2B già scaricato (`/Volumes/LLM-VLM/MLX/mlx-community/Qwen3-VL-2B-Instruct-4bit`) e il componente Metal Toolchain. Prima si annotano le impostazioni dell'utente (`drawThings.managedServer`, `languageModel.settings`), che alla fine si tolgono se non c'erano; **l'app resta aperta** per le prove dell'utente.

- [ ] **Step 1: Preparare e avviare**

```bash
defaults read com.exiztenz.DTHub drawThings.managedServer 2>&1 | head -1; defaults read com.exiztenz.DTHub languageModel.settings 2>&1 | head -1; open "<repo>/build/Build/Products/Debug/DT Hub.app"
```

- [ ] **Step 2: Checklist (screenshot)**

1. Preferenze › LLM: cartella `/Volumes/LLM-VLM/MLX`, il modello 2B nell'elenco con "1,8 GB · immagini", il pulsante "Scarica il modello consigliato (5,78 GB)…" (il modello 8B non c'è). Il pulsante apre un dialogo che nomina `mlx-community/Qwen3-VL-8B-Instruct-4bit`, la dimensione e la cartella; "Annulla" non scarica nulla.
2. Sezione Memoria: i tre controlli; "Libera il modello immagine…" è grigio con la spiegazione se la modalità del server non è "Avvia gRPCServerCLI".
3. Con il server gestito attivo (pallino verde) e le due opzioni di memoria accese, "Chiedi" con la domanda d'esempio: il server di Draw Things si ferma (nessun processo `gRPCServerCLI` entro un secondo), la riga di stato passa da "Caricamento di …" a "Pronto: …", compare una risposta.
4. Nella finestra principale il pallino è giallo e il suo suggerimento dice che il modello immagine è stato liberato; Run è attivo.
5. Premendo Run: l'LLM torna a "Nessun modello caricato", il server riparte (`pgrep -fl gRPCServerCLI` mostra una riga), la finestra Risultati mostra "Preparazione…" e poi la generazione; "Stop" la ferma.
6. Con "Libera l'LLM quando premo Run" spento, l'LLM resta caricato dopo Run.
7. Una domanda con un'immagine a un modello solo testo mostra l'errore "Questo modello non guarda le immagini…"; con il 2B e un'immagine rossa la risposta nomina il rosso.
8. Uscendo dall'app (⌘Q) non resta nessun server `gRPCServerCLI`.

Punti che servono all'utente (pannelli di scelta file e scaricamento del modello 8B): lasciare **l'app aperta**.

- [ ] **Step 3: Pulizia** (solo se le due impostazioni non c'erano allo Step 1)

```bash
defaults delete com.exiztenz.DTHub drawThings.managedServer; defaults delete com.exiztenz.DTHub languageModel.settings
```

---

## Fine della M6

Esito atteso sul branch `m6-servizio-llm`:
- **271 test verdi** (4 di LLMBridge inattivi senza variabili d'ambiente, provati dal vivo con `xcodebuild test`);
- build Xcode pulita con MLX;
- DT Hub risponde a domande di testo e, con un modello di visione, su immagini, senza lasciare memoria occupata a chi serve dopo.

Poi: revisione indipendente, correzioni, merge, e il piano di M7 (contratto dei plug-in, menu plug-in, card Contributi, pipeline, conflitti, plug-in di prova).

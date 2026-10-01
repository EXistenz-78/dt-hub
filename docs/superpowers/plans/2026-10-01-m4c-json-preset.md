# M4c Editor JSON e preset — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il livello 3 e i preset della spec §6:
- un editor JSON con la configurazione completa di Draw Things (formato "Copy Configuration"), con copia, incolla di un testo completo o parziale, applicazione e validazione;
- preset con nome (parametri, modello, prompt negativo) da salvare, caricare, rinominare, eliminare e importare da un file.

**Architecture:**
- **HubKit** riceve:
  - `JSONValue` e il campo `GenerationParameters.extra`, dove restano le impostazioni di Draw Things senza una card;
  - il contratto `ConfigurationCodec` (esporta, valida, applica un testo al tab);
  - `Preset`.
- **DTBridge** implementa il codec sulla libreria: `JobMapper.configuration(model:parameters:)` costruisce la configurazione (extra comprese), `DrawThingsConfigurationCodec` la esporta e rilegge un testo in parametri.
- **HubCore** riceve `PresetStore` (`presets.json`), `PresetImport` (elenco di `{name, configuration}`), il riempimento delle trigger word e `PresetLoad`.
- **App:** `GenerationController` aggiunge le azioni; una barra in cima al tab ha il menu Preset e il pulsante JSON…; tre fogli (salva, gestisci, editor JSON).

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, DrawThings-Swift 2.2.x.

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 4, 5, 6, 7, 11, 12, 15-M4). M4 è in tre tappe: M4a e M4b fatte, **M4c** (questo piano).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m4c-json-preset` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo `DTBridge` importa DrawThings-Swift; l'app usa il codec attraverso il protocollo `ConfigurationCodec`.
- **Scostamento dalla spec (verificato sul Draw Things dell'utente, 1 ottobre 2026):**
  - la spec §6 prevede "import una tantum da `custom_configs.json`". Quel file **non esiste** in questa versione di Draw Things: le configurazioni dell'utente stanno in un database interno (FlatBuffers dentro SQLite) non leggibile in modo sensato.
  - L'import diventa **"importa preset da file"**: un file JSON con un elenco di `{"name", "configuration", "negative"?}`, scelto con il pannello di apertura. È la forma di `custom_configs.json` e della lista pubblica delle 57 configurazioni ufficiali di Draw Things (`Library/Caches/net/configs.json`, tutte applicate e riesportate senza perdite nel test di prova).
  - I preset personali di Draw Things si portano in DT Hub con "Copy Configuration" incollato nell'editor JSON, o salvandoli come preset.
- **Editor JSON (spec §6, livello 3):**
  - la configurazione completa nel formato di Draw Things (chiavi ordinate, seed −1 = casuale);
  - un testo completo o parziale si **applica** al tab: cambiano solo le chiavi presenti; il testo vuoto o `{}` non cambia nulla;
  - se il testo nomina un modello, il modello viene scelto;
  - un testo non valido (sintassi, tipo, intervallo) non si applica e mostra il motivo (messaggio della libreria, in inglese, sotto un'intestazione localizzata);
  - chiavi che non sono impostazioni di Draw Things (refusi, versioni più recenti) sono ignorate e elencate;
  - le impostazioni senza una card (video, SOL attention, stage 2, controlli, maschere…) restano in `GenerationParameters.extra`, sono **inviate a ogni RUN**, salvate nella sessione, nel PNG e nei preset; un valore uguale al predefinito di Draw Things non è un'impostazione (si toglie da `extra`).
  - Le `extra` non seguono la regola dei "valori nascosti": non dipendono dalla famiglia e si vedono solo qui. Un testo che la libreria non accetta si omette dall'invio senza fermare il RUN.
  - Il pulsante JSON… mostra quante `extra` ci sono.
- **Preset (decisi con l'utente, 1 ottobre 2026):**
  - un preset salva modello, parametri (LoRA, card Avanzate, extra comprese) e prompt negativo, **mai il prompt**;
  - caricarlo cambia i parametri e il modello, e il prompt negativo solo se il preset ne ha uno; il prompt resta;
  - i nomi sono unici senza distinguere maiuscole: salvare con un nome esistente lo sostituisce (il foglio lo avvisa); un nome vuoto non si salva;
  - l'import non sostituisce mai un preset salvato: un nome già usato diventa "Nome (2)", "Nome (3)"…;
  - le voci dell'import senza nome, senza configurazione o con una configurazione non applicabile sono saltate e contate;
  - `presets.json` in `~/Library/Application Support/DT Hub/`, scritto a ogni modifica; un elemento rovinato non toglie gli altri, un file illeggibile significa nessun preset.
- **Trigger word:** il JSON di Draw Things non le contiene; le LoRA nuove per il tab prendono la trigger word dai metadati del server (`fillingTriggers`), quelle già presenti la tengono.
- **Posizione nell'interfaccia (deciso con l'utente):** una riga in cima al tab, sopra la card Prompt: menu Preset, pulsante JSON….
- **Stringhe:**
  - ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo;
  - `String(format: String(localized:), …)` per i valori;
  - i messaggi di DTBridge sono dettagli tecnici in inglese, come quelli della libreria.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Fuori da M4c:** ControlNet e Inpaint (tab dedicato in futuro); modalità del seed; l'import automatico dal database di Draw Things.

## Review Focus

- **Testo JSON con errore di sintassi, tipo sbagliato o fuori intervallo** (`{"steps": "many"}`, `{"width": 10}`): non si applica, il tab resta com'è, il motivo si vede (test `aBadTextIsRejectedWithAReason`, Task 2).
- **Testo parziale:** cambiano solo le sue chiavi (test `aPartialTextChangesOnlyItsKeys`, Task 2).
- **Impostazioni senza card:** restano, partono con il RUN, tornano nell'export e nella sessione (test `settingsWithoutACardAreKeptAsExtra`, `extraSettingsSurviveARoundTripAndOldFilesLoad`, Task 1–2).
- **Export applicato di nuovo:** non riempie `extra` di predefiniti e riproduce gli stessi parametri (test `aCompleteExportAddsNoExtraSettings`, `exportThenApplyReproducesTheParameters`, Task 2).
- **File di preset da importare:** voci rovinate saltate e contate, un file che non è un elenco non dà nulla, nessun preset salvato viene sostituito (test `readsTheValidEntriesAndCountsTheOthers`, `aFileThatIsNotAListGivesNothing`, `importedPresetsNeverReplaceSavedOnes`, Task 3).
- **`presets.json` rovinato:** l'app si apre con i preset leggibili (test `aDamagedPresetDoesNotTakeTheOthers`, `anUnreadableFileMeansNoPresets`, Task 3).

---

### Task 1: Extra, contratto del codec e preset (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Generation/JSONValue.swift`
- Create: `Packages/Sources/HubKit/Generation/ConfigurationCodec.swift`
- Create: `Packages/Sources/HubKit/Generation/Preset.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationParameters.swift` (campo `extra`)
- Test: `Packages/Tests/HubKitTests/GenerationParametersTests.swift` (suite `JSONValueTests`)

**Interfaces:**
- Produces (HubKit, `public`):
  - `enum JSONValue: Equatable, Sendable, Codable { null, bool, int, double, string, array, object }` con `static func text(of: [String: JSONValue]) -> String?`;
  - `GenerationParameters.extra: [String: JSONValue]` (ultimo parametro dell'init, `extra: = [:]`), decodifica tollerante;
  - `struct ConfigurationState: Equatable, Sendable` (`model`, `parameters`);
  - `struct ConfigurationError: Error, Equatable, Sendable` (`message`);
  - `protocol ConfigurationCodec: Sendable` con `exportJSON(_:) -> String`, `validate(_:) -> String?`, `unknownKeys(in:) -> [String]`, `apply(json:to:) throws(ConfigurationError) -> ConfigurationState`;
  - `struct Preset: Equatable, Codable, Sendable, Identifiable` (`id`, `name`, `model`, `negativePrompt`, `parameters`), decodifica tollerante.

- [ ] **Step 1: Creare il branch**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m4c-json-preset
```

- [ ] **Step 2: Scrivere i test che falliscono.** Sostituire `Packages/Tests/HubKitTests/GenerationParametersTests.swift` con:

```swift
import Foundation
import Testing

@testable import HubKit

struct GenerationParametersTests {
  @Test func clampsIntoTheAllowedRanges() {
    let wild = GenerationParameters(
      width: 10, height: 9999, steps: 500, guidanceScale: -1, shift: 20, batchSize: 0, batchCount: 1000)
    let clamped = wild.clamped()
    #expect(clamped.width == 64)
    #expect(clamped.height == 2048)
    #expect(clamped.steps == 150)
    #expect(clamped.guidanceScale == 0)
    #expect(clamped.shift == 10)
    #expect(clamped.batchSize == 1)
    #expect(clamped.batchCount == 100)
  }

  @Test func roundsSizesToTheNearestMultipleOf64() {
    let clamped = GenerationParameters(width: 1000, height: 1343).clamped()
    #expect(clamped.width == 1024)
    #expect(clamped.height == 1344)
  }

  @Test func samplersMatchDrawThingsRawValues() {
    #expect(Sampler.allCases.count == 20)
    #expect(Sampler.dpmpp2mKarras.rawValue == 0)
    #expect(Sampler.tcdTrailing.rawValue == 19)
  }

  @Test func swapsWidthAndHeight() {
    var parameters = GenerationParameters(width: 832, height: 1216)
    parameters.swapDimensions()
    #expect(parameters.width == 1216)
    #expect(parameters.height == 832)
  }

  @Test func cfgZeroInitStepsNeverExceedTheSteps() {
    let clamped = GenerationParameters(steps: 8, cfgZeroStar: true, cfgZeroInitSteps: 20).clamped()
    #expect(clamped.cfgZeroInitSteps == 8)
  }

  @Test func resolutionDependentShiftIsOnByDefault() {
    #expect(GenerationParameters.default.resolutionDependentShift)
    #expect(!GenerationParameters.default.cfgZeroStar)
  }
}

struct LoRASelectionTests {
  @Test func addsALoRAOnceAtFullWeight() {
    var parameters = GenerationParameters.default
    parameters.addLoRA("style.safetensors")
    parameters.loras[0].weight = 0.6
    parameters.addLoRA("style.safetensors")
    #expect(parameters.loras == [LoRASelection(file: "style.safetensors", weight: 0.6)])
  }

  @Test func addsALoRAWithItsSuggestedWeightAndTrigger() {
    var parameters = GenerationParameters.default
    parameters.addLoRA("tarot.safetensors", weight: 0.8, trigger: "vintage tarot style")
    #expect(parameters.loras == [LoRASelection(file: "tarot.safetensors", weight: 0.8, trigger: "vintage tarot style")])
  }

  @Test func triggerWordsGoInFrontOfThePromptInOrder() {
    let job = GenerationJob(
      prompt: "a fox in the snow", model: "m.ckpt",
      parameters: GenerationParameters(loras: [
        LoRASelection(file: "a", trigger: "70sfairytale, "), LoRASelection(file: "b"),
        LoRASelection(file: "c", trigger: " cine1p "),
      ]))
    #expect(job.promptWithTriggers == "70sfairytale, cine1p a fox in the snow")
    #expect(job.prompt == "a fox in the snow")
  }

  @Test func withoutTriggersThePromptIsSentAsItIs() {
    let job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default)
    #expect(job.promptWithTriggers == "a fox")
  }

  @Test func updatesTheLoRAWithThatFileWhereverItIs() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.updateLoRA(LoRASelection(file: "b", weight: 0.3, trigger: "x"))
    #expect(parameters.loras == [LoRASelection(file: "a"), LoRASelection(file: "b", weight: 0.3, trigger: "x")])
  }

  @Test func updatingALoRAAlreadyRemovedChangesNothing() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.removeLoRA("b")
    // A row still editing "b" ends its edit after the removal.
    parameters.updateLoRA(LoRASelection(file: "b", weight: 0.3))
    #expect(parameters.loras == [LoRASelection(file: "a")])
  }

  @Test func thePromptIsTrimmedWhereItJoinsTheTriggers() {
    let job = GenerationJob(
      prompt: "\n  a fox  ", model: "m.ckpt", parameters: GenerationParameters(loras: [LoRASelection(file: "a", trigger: "cine1p")]))
    #expect(job.promptWithTriggers == "cine1p a fox")
    let blank = GenerationJob(prompt: "   ", model: "m.ckpt", parameters: GenerationParameters(loras: [LoRASelection(file: "a", trigger: "cine1p")]))
    #expect(blank.promptWithTriggers == "cine1p")
  }

  @Test func removesALoRA() {
    var parameters = GenerationParameters(loras: [LoRASelection(file: "a"), LoRASelection(file: "b")])
    parameters.removeLoRA("a")
    #expect(parameters.loras.map(\.file) == ["b"])
  }

  @Test func clampsLoRAWeights() {
    let clamped = GenerationParameters(loras: [LoRASelection(file: "a", weight: 9), LoRASelection(file: "b", weight: -3)]).clamped()
    #expect(clamped.loras.map(\.weight) == [2.5, -1.5])
  }

  @Test func loRAModesMatchDrawThingsRawValues() {
    #expect(LoRAMode.all.rawValue == 0)
    #expect(LoRAMode.base.rawValue == 1)
    #expect(LoRAMode.refiner.rawValue == 2)
  }
}

struct LenientDecodingTests {
  @Test func missingFieldsTakeTheirDefaults() throws {
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"width": 768, "steps": 30}"#.utf8))
    var expected = GenerationParameters.default
    expected.width = 768
    expected.steps = 30
    #expect(decoded == expected)
  }

  @Test func unreadableFieldsTakeTheirDefaults() throws {
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"sampler": 99, "height": "tall"}"#.utf8))
    #expect(decoded.sampler == GenerationParameters.default.sampler)
    #expect(decoded.height == GenerationParameters.default.height)
  }

  @Test func parametersSurviveARoundTrip() throws {
    let parameters = GenerationParameters(width: 832, seed: 5, randomSeed: false, loras: [LoRASelection(file: "a", weight: 0.5, mode: .base)])
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(parameters))
    #expect(decoded == parameters)
  }

  @Test func aLoRAWithoutTriggerOrModeLoads() throws {
    let decoded = try JSONDecoder().decode(LoRASelection.self, from: Data(#"{"file": "a", "weight": 0.5}"#.utf8))
    #expect(decoded == LoRASelection(file: "a", weight: 0.5))
  }

  @Test func aJobWithoutANegativePromptLoads() throws {
    let json = #"{"prompt": "fox", "model": "m.ckpt", "parameters": {}}"#
    let job = try JSONDecoder().decode(GenerationJob.self, from: Data(json.utf8))
    #expect(job.negativePrompt == "")
    #expect(job.parameters == .default)
  }
}

struct AdvancedParametersTests {
  @Test func defaultsAreDrawThings() {
    let advanced = AdvancedParameters.default
    #expect(advanced.refinerStart == 0.85)
    #expect(advanced.hiresFixStrength == 0.7)
    #expect(advanced.guidanceEmbed == 3.5)
    #expect(advanced.speedUpWithGuidanceEmbed)
    #expect(advanced.stochasticSamplingGamma == 0.3)
    #expect(advanced.aestheticScore == 6)
    #expect(advanced.negativeAestheticScore == 2.5)
    #expect(advanced.decodingTileWidth == 640)
    #expect(advanced.diffusionTileWidth == 1024)
    #expect(advanced.teaCacheEnd == -1)
    #expect(advanced.compressionQuality == 43.1)
    #expect(GenerationParameters.default.advanced == advanced)
  }

  @Test func clampsIntoTheAllowedRanges() {
    var wild = AdvancedParameters()
    wild.refinerStart = 3
    wild.hiresFixWidth = 700
    wild.hiresFixHeight = -5
    wild.upscalerScaleFactor = 3
    wild.clipSkip = 40
    wild.decodingTileWidth = 700
    wild.teaCacheEnd = -9
    wild.compressionQuality = 400
    let clamped = GenerationParameters(advanced: wild).clamped().advanced
    #expect(clamped.refinerStart == 1)
    #expect(clamped.hiresFixWidth == 704)
    #expect(clamped.hiresFixHeight == 0)
    #expect(clamped.upscalerScaleFactor == 0)
    #expect(clamped.clipSkip == 23)
    #expect(clamped.decodingTileWidth == 704)
    #expect(clamped.teaCacheEnd == -1)
    #expect(clamped.compressionQuality == 100)
  }

  @Test func advancedValuesLoadLeniently() throws {
    let json = #"{"advanced": {"hiresFix": true, "clipSkip": "two", "compressionArtifacts": 9}}"#
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: Data(json.utf8))
    #expect(decoded.advanced.hiresFix)
    #expect(decoded.advanced.clipSkip == 1)
    #expect(decoded.advanced.compressionArtifacts == .none)
    let old = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"steps": 4}"#.utf8))
    #expect(old.advanced == .default)
  }

  @Test func advancedValuesSurviveARoundTrip() throws {
    var advanced = AdvancedParameters()
    advanced.refinerModel = "r.ckpt"
    advanced.separateT5 = true
    advanced.t5Text = "a long description"
    advanced.compressionArtifacts = .jpeg
    let parameters = GenerationParameters(advanced: advanced)
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(parameters))
    #expect(decoded == parameters)
  }

  @Test func conditioningSizesSnapTo64UpTo8192AndZeroStaysAutomatic() {
    #expect(AdvancedParameters.conditioningSize(4096) == 4096)
    #expect(AdvancedParameters.conditioningSize(1000) == 1024)
    #expect(AdvancedParameters.conditioningSize(9000) == 8192)
    #expect(AdvancedParameters.conditioningSize(0) == 0)
    #expect(AdvancedParameters.conditioningSize(20) == 0)
  }

  @Test func cropKeepsTheTypedPixels() {
    #expect(AdvancedParameters.crop(16) == 16)
    #expect(AdvancedParameters.crop(9000) == 8192)
    #expect(AdvancedParameters.crop(-3) == 0)
  }

  @Test func compressionMatchesDrawThingsRawValues() {
    #expect(CompressionArtifacts.allCases.map(\.rawValue) == [0, 1, 2, 3])
  }
}

struct JSONValueTests {
  @Test func readsAndWritesEveryKindOfValue() throws {
    let json = #"{"a": null, "b": true, "c": 3, "d": 0.5, "e": "x", "f": [1, "y"], "g": {"h": 2}}"#
    let object = try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    #expect(object["a"] == .null)
    #expect(object["b"] == .bool(true))
    #expect(object["c"] == .int(3))
    #expect(object["d"] == .double(0.5))
    #expect(object["e"] == .string("x"))
    #expect(object["f"] == .array([.int(1), .string("y")]))
    #expect(object["g"] == .object(["h": .int(2)]))
    let again = try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(object))
    #expect(again == object)
  }

  @Test func integersStayIntegersInTheText() {
    #expect(JSONValue.text(of: ["fps": .int(24), "tau": .double(0.5)]) == #"{"fps":24,"tau":0.5}"#)
    #expect(JSONValue.text(of: [:]) == nil)
  }

  @Test func extraSettingsSurviveARoundTripAndOldFilesLoad() throws {
    let parameters = GenerationParameters(extra: ["fps": .int(24)])
    let decoded = try JSONDecoder().decode(GenerationParameters.self, from: JSONEncoder().encode(parameters))
    #expect(decoded.extra == ["fps": .int(24)])
    let old = try JSONDecoder().decode(GenerationParameters.self, from: Data(#"{"steps": 4}"#.utf8))
    #expect(old.extra.isEmpty)
  }

  @Test func aPresetLoadsLeniently() throws {
    let preset = try JSONDecoder().decode(Preset.self, from: Data(#"{"name": "Fast"}"#.utf8))
    #expect(preset.name == "Fast")
    #expect(preset.model == "" && preset.negativePrompt == "")
    #expect(preset.parameters == .default)
  }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'JSONValue' in scope`.

- [ ] **Step 4: Creare `Packages/Sources/HubKit/Generation/JSONValue.swift`**

```swift
import Foundation

/// Any JSON value, kept as it is: the Draw Things settings DT Hub has no card for (video,
/// SOL attention, stage 2, controls…) travel as these, from the JSON editor to the request.
public enum JSONValue: Equatable, Sendable, Codable {
  case null
  case bool(Bool)
  case int(Int)
  case double(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// A JSON object as text with sorted keys; nil for an empty object.
  public static func text(of object: [String: JSONValue]) -> String? {
    guard !object.isEmpty else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(object)).map { String(decoding: $0, as: UTF8.self) }
  }
}
```

- [ ] **Step 5: Creare `Packages/Sources/HubKit/Generation/ConfigurationCodec.swift`**

```swift
/// The model and parameters of a generation: what the Draw Things configuration JSON holds.
public struct ConfigurationState: Equatable, Sendable {
  public var model: String
  public var parameters: GenerationParameters

  public init(model: String, parameters: GenerationParameters) {
    self.model = model
    self.parameters = parameters
  }
}

/// Why a JSON text could not be applied; the message is the library's, for display.
public struct ConfigurationError: Error, Equatable, Sendable {
  public let message: String

  public init(_ message: String) {
    self.message = message
  }
}

/// Translates between the Draw Things configuration JSON (the "Copy Configuration" format,
/// 97 fields) and DT Hub's parameters (spec §6, level 3). DTBridge implements it; the
/// settings DT Hub has no card for are kept in `GenerationParameters.extra`.
public protocol ConfigurationCodec: Sendable {
  /// The complete configuration as pretty-printed JSON, sorted keys; a random seed is -1.
  func exportJSON(_ state: ConfigurationState) -> String
  /// nil when the text is a valid complete or partial configuration, else what is wrong.
  func validate(_ json: String) -> String?
  /// The top-level keys of `json` that are not Draw Things settings (typos, newer versions):
  /// applying the text ignores them.
  func unknownKeys(in json: String) -> [String]
  /// Applies the keys present in `json` on top of `state`: the others stay as they are.
  func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState
}
```

- [ ] **Step 6: Creare `Packages/Sources/HubKit/Generation/Preset.swift`**

```swift
import Foundation

/// A named recipe (spec §6): the model, the parameters (LoRAs and Advanced cards included)
/// and the negative prompt. Never the prompt itself.
public struct Preset: Equatable, Codable, Sendable, Identifiable {
  public var id: UUID
  public var name: String
  /// Empty when the preset names no model: loading it leaves the model as it is.
  public var model: String
  public var negativePrompt: String
  public var parameters: GenerationParameters

  public init(
    id: UUID = UUID(), name: String, model: String = "", negativePrompt: String = "",
    parameters: GenerationParameters = .default
  ) {
    self.id = id
    self.name = name
    self.model = model
    self.negativePrompt = negativePrompt
    self.parameters = parameters
  }

  /// Lenient, like the other saved formats.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
    name = try container.decode(String.self, forKey: .name)
    model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
  }
}
```

- [ ] **Step 7: Sostituire `Packages/Sources/HubKit/Generation/GenerationParameters.swift` con:**

```swift
/// The base generation parameters of the Generation tab (spec §6, level 1), for T2I.
public struct GenerationParameters: Equatable, Codable, Sendable {
  /// Pixels; Draw Things works in multiples of 64.
  public var width: Int
  public var height: Int
  public var steps: Int
  /// Text guidance (CFG).
  public var guidanceScale: Double
  /// CFG-Zero*: guidance starts after `cfgZeroInitSteps` steps.
  public var cfgZeroStar: Bool
  public var cfgZeroInitSteps: Int
  public var sampler: Sampler
  public var shift: Double
  /// When on, Draw Things computes the shift from the resolution and `shift` is ignored.
  public var resolutionDependentShift: Bool
  /// Used as is when `randomSeed` is off; otherwise a new one is drawn at each RUN.
  public var seed: UInt32
  public var randomSeed: Bool
  /// Images per batch, and batches per RUN.
  public var batchSize: Int
  public var batchCount: Int
  /// The LoRAs of the LoRA card, in order; one entry per file.
  public var loras: [LoRASelection]
  /// The Advanced cards (spec §6, level 2).
  public var advanced: AdvancedParameters
  /// Draw Things settings DT Hub has no card for, from the JSON editor (spec §6, level 3):
  /// kept as they are, sent with every RUN, saved with the session and in the PNG.
  public var extra: [String: JSONValue]

  public init(
    width: Int = 1024, height: Int = 1024, steps: Int = 8, guidanceScale: Double = 1,
    cfgZeroStar: Bool = false, cfgZeroInitSteps: Int = 0,
    sampler: Sampler = .uniPCTrailing, shift: Double = 3, resolutionDependentShift: Bool = true,
    seed: UInt32 = 0, randomSeed: Bool = true, batchSize: Int = 1, batchCount: Int = 1,
    loras: [LoRASelection] = [], advanced: AdvancedParameters = .default,
    extra: [String: JSONValue] = [:]
  ) {
    self.width = width
    self.height = height
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.cfgZeroStar = cfgZeroStar
    self.cfgZeroInitSteps = cfgZeroInitSteps
    self.sampler = sampler
    self.shift = shift
    self.resolutionDependentShift = resolutionDependentShift
    self.seed = seed
    self.randomSeed = randomSeed
    self.batchSize = batchSize
    self.batchCount = batchCount
    self.loras = loras
    self.advanced = advanced
    self.extra = extra
  }

  /// Reads saved parameters leniently: a missing or unreadable field takes its default, so
  /// files written by older or newer versions (session, PNG metadata) still load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let fallback = Self.default
    width = value(.width, fallback.width)
    height = value(.height, fallback.height)
    steps = value(.steps, fallback.steps)
    guidanceScale = value(.guidanceScale, fallback.guidanceScale)
    cfgZeroStar = value(.cfgZeroStar, fallback.cfgZeroStar)
    cfgZeroInitSteps = value(.cfgZeroInitSteps, fallback.cfgZeroInitSteps)
    sampler = value(.sampler, fallback.sampler)
    shift = value(.shift, fallback.shift)
    resolutionDependentShift = value(.resolutionDependentShift, fallback.resolutionDependentShift)
    seed = value(.seed, fallback.seed)
    randomSeed = value(.randomSeed, fallback.randomSeed)
    batchSize = value(.batchSize, fallback.batchSize)
    batchCount = value(.batchCount, fallback.batchCount)
    loras = value(.loras, fallback.loras)
    advanced = value(.advanced, fallback.advanced)
    extra = value(.extra, fallback.extra)
  }

  public static let `default` = GenerationParameters()

  /// Adds a LoRA (full weight unless its metadata suggests one); a file already in the
  /// list is left as it is.
  public mutating func addLoRA(_ file: String, weight: Double = 1, trigger: String = "") {
    guard !loras.contains(where: { $0.file == file }) else { return }
    loras.append(LoRASelection(file: file, weight: weight, trigger: trigger))
  }

  public mutating func removeLoRA(_ file: String) {
    loras.removeAll { $0.file == file }
  }

  /// Replaces the LoRA with the same file, wherever it is now; nothing when it was removed.
  /// The LoRA card's rows write through this, not through an array index: a row that ends
  /// its edit after a removal must not write into another LoRA or past the end.
  public mutating func updateLoRA(_ selection: LoRASelection) {
    guard let index = loras.firstIndex(where: { $0.file == selection.file }) else { return }
    loras[index] = selection
  }

  /// Allowed ranges, used by the cards and by `clamped()`.
  public static let sizeRange = 64...2048
  public static let stepsRange = 1...150
  public static let guidanceRange = 0.0...50.0
  public static let shiftRange = 0.0...10.0
  public static let batchSizeRange = 1...4
  public static let batchCountRange = 1...100

  /// Portrait ↔ landscape. One mutation: `swap(&p.width, &p.height)` on an observed property
  /// is two overlapping accesses to the same struct and crashes at run time.
  public mutating func swapDimensions() {
    (width, height) = (height, width)
  }

  /// Applies an aspect ratio keeping the long side and the orientation (portrait stays portrait).
  public mutating func apply(_ ratio: AspectRatio) {
    let long = max(width, height)
    let short = Self.snap(Double(long) * Double(ratio.height) / Double(ratio.width))
    if height > width {
      (width, height) = (short, Self.snap(Double(long)))
    } else {
      (width, height) = (Self.snap(Double(long)), short)
    }
  }

  /// Sets the width; with a ratio (width ÷ height) the height follows to keep it.
  public mutating func setWidth(_ newWidth: Int, keepingRatio ratio: Double?) {
    width = newWidth
    if let ratio, ratio > 0 { height = Self.snap(Double(newWidth) / ratio) }
  }

  /// Sets the height; with a ratio (width ÷ height) the width follows to keep it.
  public mutating func setHeight(_ newHeight: Int, keepingRatio ratio: Double?) {
    height = newHeight
    if let ratio, ratio > 0 { width = Self.snap(Double(newHeight) * ratio) }
  }

  /// The same parameters forced into the allowed ranges; sizes rounded to the nearest multiple
  /// of 64, as the size fields do when editing ends.
  public func clamped() -> GenerationParameters {
    var copy = self
    copy.width = Self.snap(Double(width))
    copy.height = Self.snap(Double(height))
    copy.steps = min(max(steps, Self.stepsRange.lowerBound), Self.stepsRange.upperBound)
    copy.guidanceScale = min(max(guidanceScale, Self.guidanceRange.lowerBound), Self.guidanceRange.upperBound)
    copy.cfgZeroInitSteps = min(max(cfgZeroInitSteps, 0), copy.steps)
    copy.shift = min(max(shift, Self.shiftRange.lowerBound), Self.shiftRange.upperBound)
    copy.batchSize = min(max(batchSize, Self.batchSizeRange.lowerBound), Self.batchSizeRange.upperBound)
    copy.batchCount = min(max(batchCount, Self.batchCountRange.lowerBound), Self.batchCountRange.upperBound)
    for index in copy.loras.indices {
      let range = LoRASelection.weightRange
      copy.loras[index].weight = min(max(copy.loras[index].weight, range.lowerBound), range.upperBound)
    }
    copy.advanced = advanced.clamped()
    return copy
  }

  /// Nearest multiple of 64 inside `sizeRange`.
  public static func snap(_ size: Double) -> Int {
    let rounded = Int((size / 64).rounded()) * 64
    return min(max(rounded, sizeRange.lowerBound), sizeRange.upperBound)
  }
}
```

- [ ] **Step 8: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: HubKit `44 tests … passed`; HubCore 95, DTBridge 22, Catalog 6 come prima.

- [ ] **Step 9: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: impostazioni extra, contratto del codec JSON e preset nel contratto

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Codec della configurazione di Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift` (`configuration(model:parameters:)`, extra inviate)
- Create: `Packages/Sources/DTBridge/ConfigurationCodec.swift`
- Test: `Packages/Tests/DTBridgeTests/ConfigurationCodecTests.swift`

**Interfaces:**
- Consumes: `ConfigurationCodec`, `ConfigurationState`, `ConfigurationError`, `JSONValue`, `GenerationParameters.extra`, `AdvancedParameters` (Task 1, M4b); dalla libreria `DrawThingsConfiguration` (`toJSON()`, `mergeJSON(_:)`, `validate()`, `validateJSON(_:)`).
- Produces:
  - `JobMapper.configuration(model:parameters:) -> DrawThingsConfiguration` (interno; `request(for:)` lo usa);
  - `public struct DrawThingsConfigurationCodec: ConfigurationCodec` con `init()`; interni `modeledKeys`, `extraKeys`, `knownKeys`, `defaults`, `parameters(from:base:)`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/DTBridgeTests/ConfigurationCodecTests.swift` con:

```swift
import DrawThingsClient
import Foundation
import HubKit
import Testing

@testable import DTBridge

struct ConfigurationCodecTests {
  let codec = DrawThingsConfigurationCodec()
  let state = ConfigurationState(model: "flux_2_klein_9b_f16.ckpt", parameters: GenerationParameters(seed: 42, randomSeed: false))

  func object(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
  }

  @Test func exportsTheCompleteConfiguration() {
    let json = object(codec.exportJSON(state))
    #expect(json["model"] as? String == "flux_2_klein_9b_f16.ckpt")
    #expect(json["steps"] as? Int == 8)
    #expect(json["seed"] as? Int == 42)
    #expect(json.count > 60)
  }

  @Test func aRandomSeedIsExportedAsMinusOne() {
    var random = state
    random.parameters.randomSeed = true
    #expect(object(codec.exportJSON(random))["seed"] as? Int == -1)
  }

  @Test func aPartialTextChangesOnlyItsKeys() throws {
    let result = try codec.apply(json: #"{"steps": 30, "guidanceScale": 4.5, "sampler": 2}"#, to: state)
    var expected = state.parameters
    expected.steps = 30
    expected.guidanceScale = 4.5
    expected.sampler = .ddim
    #expect(result.parameters == expected)
    #expect(result.model == state.model)
  }

  @Test func theModelComesFromTheText() throws {
    let result = try codec.apply(json: #"{"model": "z_image_turbo_1.0_f16.ckpt"}"#, to: state)
    #expect(result.model == "z_image_turbo_1.0_f16.ckpt")
  }

  @Test func aNegativeSeedMeansRandomAndANumberMeansFixed() throws {
    let random = try codec.apply(json: #"{"seed": -1}"#, to: state)
    #expect(random.parameters.randomSeed)
    let fixed = try codec.apply(json: #"{"seed": 7}"#, to: ConfigurationState(model: "m", parameters: GenerationParameters()))
    #expect(!fixed.parameters.randomSeed)
    #expect(fixed.parameters.seed == 7)
  }

  @Test func advancedValuesAreReadBack() throws {
    let json = #"{"hiresFix": true, "hiresFixWidth": 512, "hiresFixHeight": 512, "teaCache": true, "colorCalibration": "lab", "compressionArtifacts": "jpeg", "refinerModel": "r.ckpt", "clipSkip": 2}"#
    let advanced = try codec.apply(json: json, to: state).parameters.advanced
    #expect(advanced.hiresFix && advanced.hiresFixWidth == 512 && advanced.hiresFixHeight == 512)
    #expect(advanced.teaCache)
    #expect(advanced.colorCalibration)
    #expect(advanced.compressionArtifacts == .jpeg)
    #expect(advanced.refinerModel == "r.ckpt")
    #expect(advanced.clipSkip == 2)
  }

  @Test func loRAsKeepTheirTriggerWords() throws {
    var withTrigger = state
    withTrigger.parameters.loras = [LoRASelection(file: "a_lora_f16.ckpt", weight: 1, trigger: "vintage tarot style")]
    let json = #"{"loras": [{"file": "a_lora_f16.ckpt", "weight": 0.6, "mode": "base"}, {"file": "b_lora_f16.ckpt", "weight": 1}]}"#
    let loras = try codec.apply(json: json, to: withTrigger).parameters.loras
    #expect(loras.map(\.file) == ["a_lora_f16.ckpt", "b_lora_f16.ckpt"])
    #expect(loras[0].weight == 0.6 && loras[0].mode == .base && loras[0].trigger == "vintage tarot style")
    #expect(loras[1].trigger == "")
  }

  @Test func settingsWithoutACardAreKeptAsExtra() throws {
    let result = try codec.apply(json: #"{"fps": 24, "solAttentionTau": 0.7, "steps": 20}"#, to: state)
    #expect(result.parameters.extra == ["fps": .int(24), "solAttentionTau": .double(0.7)])
    #expect(result.parameters.steps == 20)
    // They go out with the next request and come back in the export.
    let request = JobMapper.request(for: GenerationJob(prompt: "p", model: "m", parameters: result.parameters)).configuration
    #expect(request.fps == 24)
    #expect(abs(request.solAttentionTau - 0.7) < 0.0001)
    #expect(object(codec.exportJSON(result))["fps"] as? Int == 24)
  }

  @Test func aSettingSetBackToItsDefaultIsNoLongerExtra() throws {
    let set = try codec.apply(json: #"{"fps": 24}"#, to: state)
    let reset = try codec.apply(json: #"{"fps": 5}"#, to: set)
    #expect(reset.parameters.extra.isEmpty)
  }

  @Test func aCompleteExportAddsNoExtraSettings() throws {
    let full = codec.exportJSON(state)
    #expect(try codec.apply(json: full, to: state).parameters.extra.isEmpty)
  }

  @Test func extraSettingsAddUpAcrossApplies() throws {
    let first = try codec.apply(json: #"{"fps": 24}"#, to: state)
    let second = try codec.apply(json: #"{"motionScale": 100}"#, to: first)
    #expect(second.parameters.extra == ["fps": .int(24), "motionScale": .int(100)])
  }

  @Test func anEmptyTextOrAnEmptyObjectChangesNothing() throws {
    #expect(try codec.apply(json: "", to: state) == state)
    #expect(try codec.apply(json: "{}", to: state) == state)
  }

  @Test func aBadTextIsRejectedWithAReason() {
    #expect(codec.validate("not json") != nil)
    #expect(codec.validate("[1, 2]") != nil)
    #expect(codec.validate(#"{"steps": "many"}"#) != nil)
    #expect(codec.validate(#"{"width": 10}"#) != nil)
    #expect(codec.validate(#"{"steps": 8}"#) == nil)
    #expect(codec.validate("  ") == nil)
    #expect(throws: ConfigurationError.self) { try codec.apply(json: "not json", to: state) }
  }

  @Test func unknownKeysAreListedAndIgnored() throws {
    #expect(codec.unknownKeys(in: #"{"steps": 8, "stepz": 3, "futureThing": true}"#) == ["futureThing", "stepz"])
    let result = try codec.apply(json: #"{"stepz": 3}"#, to: state)
    #expect(result == state)
  }

  @Test func exportThenApplyReproducesTheParameters() throws {
    var rich = state
    rich.parameters.width = 832
    rich.parameters.height = 1216
    rich.parameters.guidanceScale = 4.5
    rich.parameters.shift = 2.5
    rich.parameters.cfgZeroStar = true
    rich.parameters.cfgZeroInitSteps = 2
    rich.parameters.sampler = .dpmppSDEKarras
    rich.parameters.batchSize = 2
    rich.parameters.loras = [LoRASelection(file: "a_lora_f16.ckpt", weight: 0.65, mode: .refiner, trigger: "t")]
    rich.parameters.advanced.refinerModel = "r.ckpt"
    rich.parameters.advanced.refinerStart = 0.6
    rich.parameters.advanced.hiresFix = true
    rich.parameters.advanced.hiresFixWidth = 576
    rich.parameters.advanced.hiresFixHeight = 832
    rich.parameters.advanced.guidanceEmbed = 4.5
    rich.parameters.advanced.separateT5 = true
    rich.parameters.advanced.t5Text = "long text"
    rich.parameters.advanced.aestheticScore = 7.5
    rich.parameters.advanced.teaCache = true
    rich.parameters.advanced.teaCacheThreshold = 0.1
    rich.parameters.advanced.compressionArtifacts = .h265
    rich.parameters.advanced.compressionQuality = 50
    rich.parameters.extra = ["fps": .int(12)]
    let json = codec.exportJSON(rich)
    let back = try codec.apply(json: json, to: ConfigurationState(model: "other.ckpt", parameters: GenerationParameters(extra: rich.parameters.extra)))
    #expect(back.model == rich.model)
    // The JSON carries no trigger word: a LoRA new to the tab comes back without one.
    var expected = rich.parameters.clamped()
    expected.loras[0].trigger = ""
    #expect(back.parameters == expected)
    #expect(codec.exportJSON(back) == json)
  }

  @Test func theModeledKeysAreRealKeys() {
    let known = DrawThingsConfigurationCodec.knownKeys
    #expect(DrawThingsConfigurationCodec.modeledKeys.isSubset(of: known))
    #expect(DrawThingsConfigurationCodec.extraKeys.contains("fps"))
    #expect(!DrawThingsConfigurationCodec.extraKeys.contains("steps"))
    #expect(!DrawThingsConfigurationCodec.extraKeys.contains("name"))
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'DrawThingsConfigurationCodec' in scope`.

- [ ] **Step 3: Sostituire `Packages/Sources/DTBridge/JobMapper.swift` con:**

```swift
import DrawThingsClient
import HubKit

/// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
enum JobMapper {
  static func request(for job: GenerationJob) -> GenerationRequest {
    GenerationRequest(
      prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
      configuration: configuration(model: job.model, parameters: job.parameters))
  }

  /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
  /// applied, then the JSON editor's extra settings on top.
  static func configuration(model: String, parameters unclamped: GenerationParameters) -> DrawThingsConfiguration {
    let parameters = unclamped.clamped()
    var configuration = DrawThingsConfiguration(
      width: Int32(parameters.width),
      height: Int32(parameters.height),
      steps: Int32(parameters.steps),
      model: model,
      sampler: SamplerType(rawValue: Int8(parameters.sampler.rawValue)) ?? .unipctrailing,
      guidanceScale: Float(parameters.guidanceScale),
      seed: parameters.seed,
      shift: Float(parameters.shift),
      batchCount: Int32(parameters.batchCount),
      batchSize: Int32(parameters.batchSize),
      cfgZeroStar: parameters.cfgZeroStar,
      cfgZeroInitSteps: Int32(parameters.cfgZeroInitSteps),
      resolutionDependentShift: parameters.resolutionDependentShift)
    // HubKit and the library both have a `LoRAMode`: the library's is qualified.
    configuration.loras = parameters.loras.map {
      LoRAConfig(
        file: $0.file, weight: Float($0.weight),
        mode: DrawThingsClient.LoRAMode(rawValue: Int8($0.mode.rawValue)) ?? .all)
    }
    apply(parameters.advanced, to: &configuration)
    // The extra settings are keys of the configuration JSON the cards do not cover; a text
    // the library cannot take is left out rather than stopping the RUN.
    if let extra = JSONValue.text(of: parameters.extra) { try? configuration.mergeJSON(extra) }
    return configuration
  }

  /// The Advanced cards' values; "" names become nil ("none"), a separate text is sent only
  /// with its switch on.
  static func apply(_ advanced: AdvancedParameters, to configuration: inout DrawThingsConfiguration) {
    func name(_ file: String) -> String? { file.isEmpty ? nil : file }
    configuration.refinerModel = name(advanced.refinerModel)
    configuration.refinerStart = Float(advanced.refinerStart)
    configuration.hiresFix = advanced.hiresFix
    configuration.hiresFixWidth = Int32(advanced.hiresFixWidth)
    configuration.hiresFixHeight = Int32(advanced.hiresFixHeight)
    configuration.hiresFixStrength = Float(advanced.hiresFixStrength)
    configuration.upscaler = name(advanced.upscaler)
    configuration.upscalerScaleFactor = Int32(advanced.upscalerScaleFactor)
    configuration.faceRestoration = name(advanced.faceRestoration)
    configuration.guidanceEmbed = Float(advanced.guidanceEmbed)
    configuration.speedUpWithGuidanceEmbed = advanced.speedUpWithGuidanceEmbed
    configuration.sharpness = Float(advanced.sharpness)
    configuration.stochasticSamplingGamma = Float(advanced.stochasticSamplingGamma)
    configuration.clipSkip = Int32(advanced.clipSkip)
    configuration.t5TextEncoder = advanced.t5TextEncoder
    configuration.separateClipL = advanced.separateClipL
    configuration.clipLText = advanced.separateClipL ? advanced.clipLText : nil
    configuration.separateOpenClipG = advanced.separateOpenClipG
    configuration.openClipGText = advanced.separateOpenClipG ? advanced.openClipGText : nil
    configuration.separateT5 = advanced.separateT5
    configuration.t5Text = advanced.separateT5 ? advanced.t5Text : nil
    configuration.zeroNegativePrompt = advanced.zeroNegativePrompt
    configuration.aestheticScore = Float(advanced.aestheticScore)
    configuration.negativeAestheticScore = Float(advanced.negativeAestheticScore)
    configuration.cropTop = Int32(advanced.cropTop)
    configuration.cropLeft = Int32(advanced.cropLeft)
    configuration.originalImageWidth = Int32(advanced.originalWidth)
    configuration.originalImageHeight = Int32(advanced.originalHeight)
    configuration.targetImageWidth = Int32(advanced.targetWidth)
    configuration.targetImageHeight = Int32(advanced.targetHeight)
    configuration.negativeOriginalImageWidth = Int32(advanced.negativeOriginalWidth)
    configuration.negativeOriginalImageHeight = Int32(advanced.negativeOriginalHeight)
    configuration.tiledDecoding = advanced.tiledDecoding
    configuration.decodingTileWidth = Int32(advanced.decodingTileWidth)
    configuration.decodingTileHeight = Int32(advanced.decodingTileHeight)
    configuration.decodingTileOverlap = Int32(advanced.decodingTileOverlap)
    configuration.tiledDiffusion = advanced.tiledDiffusion
    configuration.diffusionTileWidth = Int32(advanced.diffusionTileWidth)
    configuration.diffusionTileHeight = Int32(advanced.diffusionTileHeight)
    configuration.diffusionTileOverlap = Int32(advanced.diffusionTileOverlap)
    configuration.teaCache = advanced.teaCache
    configuration.teaCacheStart = Int32(advanced.teaCacheStart)
    configuration.teaCacheEnd = Int32(advanced.teaCacheEnd)
    configuration.teaCacheThreshold = Float(advanced.teaCacheThreshold)
    configuration.teaCacheMaxSkipSteps = Int32(advanced.teaCacheMaxSkipSteps)
    configuration.colorCalibration = advanced.colorCalibration ? .lab : .disabled
    configuration.compressionArtifacts = CompressionMethod(rawValue: Int8(advanced.compressionArtifacts.rawValue)) ?? .disabled
    configuration.compressionArtifactsQuality = Float(advanced.compressionQuality)
  }

  /// The update for a library event; nil for events DT Hub does not show (audio, downloads,
  /// single images: the batch's full list arrives with `.completed`).
  static func update(for event: GenerationEvent) throws -> GenerationUpdate? {
    switch event {
    case .progress(let progress):
      switch progress.stage {
      case .sampling(let step), .secondPassSampling(let step):
        return .progress(step: step, totalSteps: progress.totalSteps)
      default:
        break
      }
      return .progress(step: nil, totalSteps: progress.totalSteps)
    case .preview(let image):
      return .preview(image)
    case .completed(let result):
      guard !result.images.isEmpty else { throw BackendError.noImages }
      return .finished(result.images)
    case .image, .audio, .remoteDownload:
      return nil
    }
  }

  /// A library error as DT Hub reports it; cancellation passes through unchanged.
  static func backendError(for error: any Error) -> any Error {
    if error is CancellationError || error is BackendError { return error }
    if case DrawThingsError.connectionFailed(let detail) = error { return BackendError.unreachable(detail) }
    if case DrawThingsError.unauthenticated = error { return BackendError.unauthorized }
    // The library reports a RUN that ends without images (e.g. #131) this way.
    if case DrawThingsError.incompleteResponse(let detail) = error, detail.contains("without returning an image") {
      return BackendError.noImages
    }
    return BackendError.generationFailed(error.localizedDescription)
  }
}
```

- [ ] **Step 4: Creare `Packages/Sources/DTBridge/ConfigurationCodec.swift`**

```swift
import DrawThingsClient
import Foundation
import HubKit

/// The Draw Things configuration JSON (spec §6, level 3) on top of DrawThingsConfiguration:
/// export, validation, and applying a complete or partial text to DT Hub's parameters.
public struct DrawThingsConfigurationCodec: ConfigurationCodec {
  public init() {}

  public func exportJSON(_ state: ConfigurationState) -> String {
    var configuration = JobMapper.configuration(model: state.model, parameters: state.parameters)
    if state.parameters.randomSeed { configuration.seed = nil }
    return (try? configuration.toJSON()) ?? "{}"
  }

  /// The message is the library's (or ours), in English: a technical detail the interface
  /// shows under its own localized headline.
  public func validate(_ json: String) -> String? {
    let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)), object is [String: Any] || trimmed.isEmpty else {
      return trimmed.isEmpty ? nil : "The text must be a JSON object, like {\"steps\": 8}"
    }
    return DrawThingsConfiguration.validateJSON(json).error
  }

  /// The top-level keys of `json` that are not Draw Things settings (typos, newer versions):
  /// they are ignored.
  public func unknownKeys(in json: String) -> [String] {
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
    return object.keys.filter { !Self.knownKeys.contains($0) }.sorted()
  }

  public func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    if let error = validate(json) { throw ConfigurationError(error) }
    var configuration = JobMapper.configuration(model: state.model, parameters: state.parameters)
    configuration.seed = state.parameters.randomSeed ? nil : state.parameters.seed
    do {
      try configuration.mergeJSON(json)
      try configuration.validate()
    } catch {
      throw ConfigurationError(error.localizedDescription)
    }
    var parameters = Self.parameters(from: configuration, base: state.parameters)
    if let overlay = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] {
      for (key, value) in overlay where Self.extraKeys.contains(key) {
        // A value equal to Draw Things' default is no setting at all: a complete export
        // would otherwise fill `extra` with every default.
        if let standard = Self.defaults[key], (standard as AnyObject).isEqual(value) {
          parameters.extra[key] = nil
        } else if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
          let decoded = try? JSONDecoder().decode(JSONValue.self, from: data)
        {
          parameters.extra[key] = decoded
        }
      }
    }
    return ConfigurationState(model: configuration.model, parameters: parameters.clamped())
  }

  // MARK: Keys

  /// The keys DT Hub has a card or field for.
  static let modeledKeys: Set<String> = [
    "width", "height", "steps", "model", "sampler", "guidanceScale", "seed", "shift",
    "resolutionDependentShift", "cfgZeroStar", "cfgZeroInitSteps", "batchCount", "batchSize", "loras",
    "refinerModel", "refinerStart", "hiresFix", "hiresFixWidth", "hiresFixHeight", "hiresFixStrength",
    "upscaler", "upscalerScaleFactor", "faceRestoration", "guidanceEmbed", "speedUpWithGuidanceEmbed",
    "sharpness", "stochasticSamplingGamma", "clipSkip", "t5TextEncoder", "separateClipL", "clipLText",
    "separateOpenClipG", "openClipGText", "separateT5", "t5Text", "zeroNegativePrompt", "aestheticScore",
    "negativeAestheticScore", "cropTop", "cropLeft", "originalImageWidth", "originalImageHeight",
    "targetImageWidth", "targetImageHeight", "negativeOriginalImageWidth", "negativeOriginalImageHeight",
    "tiledDecoding", "decodingTileWidth", "decodingTileHeight", "decodingTileOverlap", "tiledDiffusion",
    "diffusionTileWidth", "diffusionTileHeight", "diffusionTileOverlap", "teaCache", "teaCacheStart",
    "teaCacheEnd", "teaCacheThreshold", "teaCacheMaxSkipSteps", "colorCalibration", "compressionArtifacts",
    "compressionArtifactsQuality",
  ]

  /// Keys that identify the configuration, not a setting.
  static let ignoredKeys: Set<String> = ["id", "name"]

  /// A complete export of the library's default configuration. Built once and never changed
  /// (hence `nonisolated(unsafe)`: `Any` is not `Sendable`).
  nonisolated(unsafe) static let defaults: [String: Any] = {
    let json = (try? DrawThingsConfiguration().toJSON()) ?? "{}"
    return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
  }()

  /// Every key Draw Things writes: the defaults' keys and those written only when set.
  static let knownKeys: Set<String> = Set(defaults.keys).union(["enableInpainting", "name", "id", "t5Text"])

  /// Settings with no card: kept in `GenerationParameters.extra`.
  static var extraKeys: Set<String> { knownKeys.subtracting(modeledKeys).subtracting(ignoredKeys) }

  // MARK: Mapping back

  /// The parameters a configuration describes, with `base` supplying what the JSON does not
  /// carry: the LoRA trigger words, the extra settings.
  static func parameters(from c: DrawThingsConfiguration, base: GenerationParameters) -> GenerationParameters {
    func d(_ value: Float) -> Double { Double("\(value)") ?? Double(value) }
    var p = base
    p.width = Int(c.width)
    p.height = Int(c.height)
    p.steps = Int(c.steps)
    p.guidanceScale = d(c.guidanceScale)
    p.cfgZeroStar = c.cfgZeroStar
    p.cfgZeroInitSteps = Int(c.cfgZeroInitSteps)
    p.sampler = Sampler(rawValue: Int(c.sampler.rawValue)) ?? base.sampler
    p.shift = d(c.shift)
    p.resolutionDependentShift = c.resolutionDependentShift
    p.randomSeed = c.seed == nil
    p.seed = c.seed ?? base.seed
    p.batchSize = Int(c.batchSize)
    p.batchCount = Int(c.batchCount)
    p.loras = c.loras.map { lora in
      LoRASelection(
        file: lora.file, weight: d(lora.weight), mode: HubKit.LoRAMode(rawValue: Int(lora.mode.rawValue)) ?? .all,
        trigger: base.loras.first { $0.file == lora.file }?.trigger ?? "")
    }
    var a = AdvancedParameters()
    a.refinerModel = c.refinerModel ?? ""
    a.refinerStart = d(c.refinerStart)
    a.hiresFix = c.hiresFix
    a.hiresFixWidth = Int(c.hiresFixWidth)
    a.hiresFixHeight = Int(c.hiresFixHeight)
    a.hiresFixStrength = d(c.hiresFixStrength)
    a.upscaler = c.upscaler ?? ""
    a.upscalerScaleFactor = Int(c.upscalerScaleFactor)
    a.faceRestoration = c.faceRestoration ?? ""
    a.guidanceEmbed = d(c.guidanceEmbed)
    a.speedUpWithGuidanceEmbed = c.speedUpWithGuidanceEmbed
    a.sharpness = d(c.sharpness)
    a.stochasticSamplingGamma = d(c.stochasticSamplingGamma)
    a.clipSkip = Int(c.clipSkip)
    a.t5TextEncoder = c.t5TextEncoder
    a.separateClipL = c.separateClipL
    a.clipLText = c.clipLText ?? ""
    a.separateOpenClipG = c.separateOpenClipG
    a.openClipGText = c.openClipGText ?? ""
    a.separateT5 = c.separateT5
    a.t5Text = c.t5Text ?? ""
    a.zeroNegativePrompt = c.zeroNegativePrompt
    a.aestheticScore = d(c.aestheticScore)
    a.negativeAestheticScore = d(c.negativeAestheticScore)
    a.cropTop = Int(c.cropTop)
    a.cropLeft = Int(c.cropLeft)
    a.originalWidth = Int(c.originalImageWidth)
    a.originalHeight = Int(c.originalImageHeight)
    a.targetWidth = Int(c.targetImageWidth)
    a.targetHeight = Int(c.targetImageHeight)
    a.negativeOriginalWidth = Int(c.negativeOriginalImageWidth)
    a.negativeOriginalHeight = Int(c.negativeOriginalImageHeight)
    a.tiledDecoding = c.tiledDecoding
    a.decodingTileWidth = Int(c.decodingTileWidth)
    a.decodingTileHeight = Int(c.decodingTileHeight)
    a.decodingTileOverlap = Int(c.decodingTileOverlap)
    a.tiledDiffusion = c.tiledDiffusion
    a.diffusionTileWidth = Int(c.diffusionTileWidth)
    a.diffusionTileHeight = Int(c.diffusionTileHeight)
    a.diffusionTileOverlap = Int(c.diffusionTileOverlap)
    a.teaCache = c.teaCache
    a.teaCacheStart = Int(c.teaCacheStart)
    a.teaCacheEnd = Int(c.teaCacheEnd)
    a.teaCacheThreshold = d(c.teaCacheThreshold)
    a.teaCacheMaxSkipSteps = Int(c.teaCacheMaxSkipSteps)
    a.colorCalibration = c.colorCalibration != .disabled
    a.compressionArtifacts = CompressionArtifacts(rawValue: Int(c.compressionArtifacts.rawValue)) ?? .none
    a.compressionQuality = d(c.compressionArtifactsQuality)
    p.advanced = a
    return p
  }
}
```

Note:
- `defaults` è `nonisolated(unsafe)`: `[String: Any]` non è `Sendable`, ma si costruisce una volta e non cambia.
- `t5Text` si scrive solo se presente: per questo `knownKeys` lo aggiunge a mano.
- Un valore uguale al predefinito della libreria non entra in `extra` (e ne esce se c'era).

- [ ] **Step 5: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: DTBridge `38 tests … passed`; totale 44 + 95 + 38 + 6 = **183**.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: DTBridge — codec della configurazione JSON di Draw Things e invio delle impostazioni extra

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Preset — archivio, import, caricamento (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Presets/PresetStore.swift`
- Create: `Packages/Sources/HubCore/Presets/PresetImport.swift`
- Test: `Packages/Tests/HubCoreTests/PresetTests.swift`

**Interfaces:**
- Consumes: `Preset`, `ConfigurationCodec`, `ConfigurationState`, `GenerationParameters.clamped()`, `ModelCatalog.lora(forFile:)`, `CatalogLoRA.trigger` (Task 1, M4a).
- Produces (HubCore, `public`):
  - `@MainActor @Observable final class PresetStore` con `init(fileURL:)`, `static var defaultFileURL`, `presets` (per nome), `preset(named:)`, `save(_:) -> Bool`, `delete(_:)`, `rename(_:to:) -> Bool`, `add(imported:)`;
  - `struct PresetImportResult: Equatable, Sendable` (`presets`, `skipped`, `init`);
  - `enum PresetImport { static func read(_: Data, codec:) -> PresetImportResult }`;
  - `GenerationParameters.fillingTriggers(from:) -> GenerationParameters`;
  - `struct PresetLoad: Equatable, Sendable` con `static func of(_:currentNegativePrompt:catalog:) -> PresetLoad` (`parameters`, `negativePrompt`, `model: String?`).

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/PresetTests.swift` con:

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

/// A codec that reads only `model` and `steps`, enough to test what the preset code does with it.
struct FakeCodec: ConfigurationCodec {
  func exportJSON(_ state: ConfigurationState) -> String { "{}" }
  func validate(_ json: String) -> String? { nil }
  func unknownKeys(in json: String) -> [String] { [] }
  func apply(json: String, to state: ConfigurationState) throws(ConfigurationError) -> ConfigurationState {
    guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else {
      throw ConfigurationError("bad")
    }
    if object["broken"] != nil { throw ConfigurationError("broken") }
    var next = state
    if let model = object["model"] as? String { next.model = model }
    if let steps = object["steps"] as? Int { next.parameters.steps = steps }
    return next
  }
}

@MainActor
struct PresetStoreTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PresetStoreTests-\(UUID())", isDirectory: true)
      .appendingPathComponent("presets.json")
  }

  @Test func startsEmptyWithoutAFile() {
    #expect(PresetStore(fileURL: tempFile()).presets.isEmpty)
  }

  @Test func remembersPresetsAcrossLaunchesByName() {
    let file = tempFile()
    let store = PresetStore(fileURL: file)
    store.save(Preset(name: "Zeta", model: "m.ckpt", negativePrompt: "blurry", parameters: GenerationParameters(steps: 20)))
    store.save(Preset(name: "alpha"))
    let again = PresetStore(fileURL: file)
    #expect(again.presets.map(\.name) == ["alpha", "Zeta"])
    #expect(again.preset(named: "zeta")?.parameters.steps == 20)
    #expect(again.preset(named: "ZETA")?.negativePrompt == "blurry")
  }

  @Test func savingUnderAnExistingNameReplacesIt() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "Fast", parameters: GenerationParameters(steps: 4)))
    let id = store.presets[0].id
    store.save(Preset(name: "fast", parameters: GenerationParameters(steps: 8)))
    #expect(store.presets.count == 1)
    #expect(store.presets[0].id == id)
    #expect(store.presets[0].parameters.steps == 8)
  }

  @Test func anEmptyNameIsRefused() {
    let store = PresetStore(fileURL: tempFile())
    #expect(!store.save(Preset(name: "   ")))
    #expect(store.presets.isEmpty)
  }

  @Test func renamesAndDeletes() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "A"))
    store.save(Preset(name: "B"))
    let a = store.preset(named: "A")!.id
    #expect(!store.rename(a, to: "b"))
    #expect(!store.rename(a, to: " "))
    #expect(store.rename(a, to: "C"))
    #expect(store.presets.map(\.name) == ["B", "C"])
    store.delete(a)
    #expect(store.presets.map(\.name) == ["B"])
  }

  @Test func importedPresetsNeverReplaceSavedOnes() {
    let store = PresetStore(fileURL: tempFile())
    store.save(Preset(name: "Qwen Image 2.1", parameters: GenerationParameters(steps: 99)))
    store.add(imported: [Preset(name: "Qwen Image 2.1"), Preset(name: "Qwen Image 2.1"), Preset(name: "Flux")])
    #expect(store.presets.map(\.name) == ["Flux", "Qwen Image 2.1", "Qwen Image 2.1 (2)", "Qwen Image 2.1 (3)"])
    #expect(store.preset(named: "Qwen Image 2.1")?.parameters.steps == 99)
  }

  @Test func aDamagedPresetDoesNotTakeTheOthers() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"[{"name": "Good", "parameters": {"steps": 5}}, {"model": "no name"}, 7]"#.utf8).write(to: file)
    let store = PresetStore(fileURL: file)
    #expect(store.presets.map(\.name) == ["Good"])
    #expect(store.presets[0].parameters.steps == 5)
  }

  @Test func anUnreadableFileMeansNoPresets() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file)
    #expect(PresetStore(fileURL: file).presets.isEmpty)
  }
}

struct PresetImportTests {
  let list = """
    [{"name": "Qwen Image 2.1", "version": "qwen_image_2.1", "negative": "ugly",
      "configuration": {"model": "qwen_image_2.1_q8p.ckpt", "steps": 40}},
     {"name": "No configuration"},
     {"configuration": {"steps": 5}},
     {"name": "Broken", "configuration": {"broken": true}},
     {"name": "Flux", "configuration": {"steps": 8}},
     "not an object"]
    """

  @Test func readsTheValidEntriesAndCountsTheOthers() {
    let result = PresetImport.read(Data(list.utf8), codec: FakeCodec())
    #expect(result.presets.map(\.name) == ["Qwen Image 2.1", "Flux"])
    #expect(result.skipped == 4)
    #expect(result.presets[0].model == "qwen_image_2.1_q8p.ckpt")
    #expect(result.presets[0].negativePrompt == "ugly")
    #expect(result.presets[0].parameters.steps == 40)
    #expect(result.presets[1].model == "")
  }

  @Test func aFileThatIsNotAListGivesNothing() {
    let result = PresetImport.read(Data(#"{"name": "x"}"#.utf8), codec: FakeCodec())
    #expect(result.presets.isEmpty)
    #expect(result.skipped == 1)
    #expect(PresetImport.read(Data("garbage".utf8), codec: FakeCodec()).presets.isEmpty)
  }
}

struct PresetLoadTests {
  let catalog = ModelCatalog(
    models: [], loras: [CatalogLoRA(file: "a.ckpt", name: "A", family: "flux2_9b", trigger: "vintage tarot style")],
    fileCount: 1)

  @Test func fillsTheTriggerWordsFromTheCatalog() {
    let parameters = GenerationParameters(loras: [LoRASelection(file: "a.ckpt"), LoRASelection(file: "b.ckpt", trigger: "mine")])
    let filled = parameters.fillingTriggers(from: catalog)
    #expect(filled.loras.map(\.trigger) == ["vintage tarot style", "mine"])
  }

  @Test func loadingAPresetKeepsTheNegativePromptItDoesNotHave() {
    let withNegative = Preset(name: "a", model: "m.ckpt", negativePrompt: "blurry")
    let without = Preset(name: "b")
    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "blurry")
    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).model == "m.ckpt")
    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "mine")
    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).model == nil)
  }

  @Test func loadedParametersAreClamped() {
    let preset = Preset(name: "wild", parameters: GenerationParameters(steps: 9999))
    #expect(PresetLoad.of(preset, currentNegativePrompt: "", catalog: catalog).parameters.steps == 150)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'PresetStore' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Presets/PresetStore.swift`**

```swift
import Foundation
import HubKit
import Observation

/// The saved presets (spec §6), kept in a JSON file in the app's support folder (spec §11).
/// Names are unique, compared without regard to case.
@MainActor
@Observable
public final class PresetStore {
  /// By name.
  public private(set) var presets: [Preset]
  @ObservationIgnored private let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
    let data = try? Data(contentsOf: fileURL)
    presets = (data.flatMap { try? JSONDecoder().decode([LossyPreset].self, from: $0) } ?? [])
      .compactMap(\.preset)
    presets = Self.sorted(presets)
  }

  /// ~/Library/Application Support/DT Hub/presets.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("presets.json")
  }

  public func preset(named name: String) -> Preset? {
    presets.first { Self.same($0.name, name) }
  }

  /// Saves under `preset.name`, replacing the preset of the same name. An empty name is refused.
  @discardableResult
  public func save(_ preset: Preset) -> Bool {
    var preset = preset
    preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !preset.name.isEmpty else { return false }
    if let index = presets.firstIndex(where: { Self.same($0.name, preset.name) }) {
      preset.id = presets[index].id
      presets[index] = preset
    } else {
      presets.append(preset)
    }
    commit()
    return true
  }

  public func delete(_ id: Preset.ID) {
    presets.removeAll { $0.id == id }
    commit()
  }

  /// False when the new name is empty or taken by another preset.
  @discardableResult
  public func rename(_ id: Preset.ID, to newName: String) -> Bool {
    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }),
      !presets.contains(where: { $0.id != id && Self.same($0.name, name) })
    else { return false }
    presets[index].name = name
    commit()
    return true
  }

  /// Adds imported presets, each under a free name ("Name", "Name (2)", …): nothing the
  /// user saved is replaced.
  public func add(imported: [Preset]) {
    for var preset in imported {
      let base = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
      var name = base
      var number = 2
      while presets.contains(where: { Self.same($0.name, name) }) {
        name = "\(base) (\(number))"
        number += 1
      }
      preset.name = name
      preset.id = UUID()
      presets.append(preset)
    }
    commit()
  }

  private func commit() {
    presets = Self.sorted(presets)
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(presets).write(to: fileURL, options: .atomic)
    } catch {
      // A write failure only loses the memory of the change.
    }
  }

  private static func same(_ a: String, _ b: String) -> Bool {
    a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
  }

  private static func sorted(_ presets: [Preset]) -> [Preset] {
    presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

/// One element of the file, decoded on its own: a damaged preset does not take the others.
private struct LossyPreset: Decodable {
  let preset: Preset?

  init(from decoder: any Decoder) throws {
    preset = try? Preset(from: decoder)
  }
}
```

- [ ] **Step 4: Creare `Packages/Sources/HubCore/Presets/PresetImport.swift`**

```swift
import Foundation
import HubKit

/// What an imported file gave.
public struct PresetImportResult: Equatable, Sendable {
  public var presets: [Preset]
  /// Entries that were not a preset (no name, no configuration, a configuration that does not
  /// apply).
  public var skipped: Int

  public init(presets: [Preset], skipped: Int) {
    self.presets = presets
    self.skipped = skipped
  }
}

/// Reads a file with a list of presets: a JSON array of `{"name", "configuration", "negative"?}`
/// objects, the shape of Draw Things' `custom_configs.json` and of its public list of
/// configurations (spec §6).
public enum PresetImport {
  public static func read(_ data: Data, codec: any ConfigurationCodec) -> PresetImportResult {
    guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
      return PresetImportResult(presets: [], skipped: 1)
    }
    var presets: [Preset] = []
    var skipped = 0
    for entry in entries {
      guard let object = entry as? [String: Any],
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
        let configuration = object["configuration"] as? [String: Any],
        let json = (try? JSONSerialization.data(withJSONObject: configuration)).map({ String(decoding: $0, as: UTF8.self) }),
        let state = try? codec.apply(json: json, to: ConfigurationState(model: "", parameters: .default))
      else {
        skipped += 1
        continue
      }
      presets.append(
        Preset(
          name: name, model: state.model, negativePrompt: object["negative"] as? String ?? "",
          parameters: state.parameters))
    }
    return PresetImportResult(presets: presets, skipped: skipped)
  }
}

extension GenerationParameters {
  /// LoRAs without a trigger word get the one the server's metadata names: the Draw Things
  /// JSON has none.
  public func fillingTriggers(from catalog: ModelCatalog) -> GenerationParameters {
    var copy = self
    for index in copy.loras.indices where copy.loras[index].trigger.isEmpty {
      copy.loras[index].trigger = catalog.lora(forFile: copy.loras[index].file)?.trigger ?? ""
    }
    return copy
  }
}

/// What loading a preset puts on the tab.
public struct PresetLoad: Equatable, Sendable {
  public var parameters: GenerationParameters
  public var negativePrompt: String
  /// nil when the preset names no model: the chosen one stays.
  public var model: String?

  /// The preset's parameters (clamped, triggers filled in), its negative prompt when it has
  /// one, its model when it names one. The prompt is never touched.
  public static func of(_ preset: Preset, currentNegativePrompt: String, catalog: ModelCatalog) -> PresetLoad {
    PresetLoad(
      parameters: preset.parameters.clamped().fillingTriggers(from: catalog),
      negativePrompt: preset.negativePrompt.isEmpty ? currentNegativePrompt : preset.negativePrompt,
      model: preset.model.isEmpty ? nil : preset.model)
  }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with" | grep -v started`
Expected: HubCore `108 tests … passed`; totale 44 + 108 + 38 + 6 = **196**.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: preset — archivio, import da file e caricamento

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Testi di preset ed editor JSON (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (27 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `preset.*`, `json.*`, `sheet.*` usate da `PresetBar`, `PresetSheets`, `JSONEditorSheet` (Task 5); `preset.import.result` (`%lld`, `%lld`), `json.invalid` e `json.unknownKeys` (`%@`) si usano con `String(format:)`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'EOF'
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "json.apply": ("Apply", "Applica"),
    "json.button": ("JSON…", "JSON…"),
    "json.button.help": ("Edit the whole Draw Things configuration as JSON", "Modifica l'intera configurazione di Draw Things come JSON"),
    "json.copy": ("Copy", "Copia"),
    "json.explanation": ("The Draw Things “Copy Configuration” format. Paste a complete or partial text: only the keys in it change. Settings with no card are kept here.", "Il formato “Copy Configuration” di Draw Things. Incolla un testo completo o parziale: cambiano solo le chiavi che contiene. Le impostazioni senza una card restano qui."),
    "json.invalid": ("Not valid: %@", "Non valido: %@"),
    "json.reload": ("Reload from tab", "Ricarica dal tab"),
    "json.reload.help": ("Replace the text with the tab's current configuration", "Sostituisce il testo con la configurazione attuale del tab"),
    "json.title": ("Configuration JSON", "JSON della configurazione"),
    "json.unknownKeys": ("Ignored, not Draw Things settings: %@", "Ignorate, non sono impostazioni di Draw Things: %@"),
    "preset.delete": ("Delete preset", "Elimina preset"),
    "preset.import": ("Import presets from file…", "Importa preset da file…"),
    "preset.import.message": ("Choose a JSON file with a list of presets (name and configuration)", "Scegli un file JSON con un elenco di preset (nome e configurazione)"),
    "preset.import.result": ("%lld presets imported, %lld skipped", "%lld preset importati, %lld saltati"),
    "preset.manage": ("Manage presets…", "Gestisci preset…"),
    "preset.manage.title": ("Presets", "Preset"),
    "preset.menu": ("Presets", "Preset"),
    "preset.none": ("No presets saved", "Nessun preset salvato"),
    "preset.rename.taken": ("This name is already used.", "Questo nome è già usato."),
    "preset.save.button": ("Save", "Salva"),
    "preset.save.contents": ("Saves the model, the settings and the negative prompt, not the prompt.", "Salva il modello, le impostazioni e il prompt negativo, non il prompt."),
    "preset.save.name": ("Name", "Nome"),
    "preset.save.replaces": ("A preset with this name exists: it will be replaced.", "Esiste un preset con questo nome: verrà sostituito."),
    "preset.save.title": ("Save as preset", "Salva come preset"),
    "preset.saveAs": ("Save as preset…", "Salva come preset…"),
    "sheet.cancel": ("Cancel", "Annulla"),
    "sheet.done": ("Done", "Fine"),
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

Expected: `1 file changed, 459 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi di preset ed editor JSON (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Barra Preset, editor JSON e fogli (App)

**Files:**
- Modify: `App/Generation/GenerationController.swift` (preset, codec, azioni)
- Create: `App/Generation/Presets/PresetBar.swift`
- Create: `App/Generation/Presets/PresetSheets.swift`
- Create: `App/Generation/Presets/JSONEditorSheet.swift`
- Modify: `App/MainWindow/GenerationTabView.swift` (barra in cima)

**Interfaces:**
- Consumes: `ConfigurationCodec`/`DrawThingsConfigurationCodec`, `ConfigurationState`, `ConfigurationError` (Task 1–2); `PresetStore`, `PresetImport`, `PresetImportResult`, `PresetLoad`, `fillingTriggers` (Task 3); le chiavi del Task 4; `DSMenuLabel`, `dsMenuPill`, `DSPillButtonStyle`, `DSBackground` (M3).
- Produces: `GenerationController.presets`, `codec`, `configurationState(in:)`, `exportJSON(in:)`, `applyJSON(_:with:)`, `savePreset(named:with:)`, `load(_:with:)`, `importPresets(from:)`; `PresetBar(controller:connection:)`; `SavePresetSheet`, `ManagePresetsSheet`, `JSONEditorSheet`.

- [ ] **Step 1: Sostituire `App/Generation/GenerationController.swift` con:**

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

  @ObservationIgnored private let outputSettings = OutputSettingsStore()
  @ObservationIgnored private let sessionStore: SessionStore
  @ObservationIgnored private var pendingSave: Task<Void, Never>?

  /// Restores the last prompt and parameters (spec §11).
  init(sessionStore: SessionStore = SessionStore(fileURL: SessionStore.defaultFileURL)) {
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
    let monitor = connection.monitor
    return !session.isRunning && monitor.backend != nil
      && RunAvailability.blocker(
        connection: monitor.status, selectedModel: connection.selection.selectedFile, catalog: monitor.catalog) == nil
  }

  /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
  /// drawn for the first batch is shown in the Seed field.
  @discardableResult
  func run(with connection: DrawThingsConnection) -> Bool {
    guard canRun(with: connection), let backend = connection.monitor.backend,
      let model = connection.selection.selectedFile
    else { return false }
    let batches = JobComposer.batches(
      prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
      parameters: parameters, catalog: connection.monitor.catalog)
    if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
    session.start(batches, backend: backend, monitor: connection.monitor)
    return true
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

- [ ] **Step 2: Creare `App/Generation/Presets/PresetBar.swift`**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// The bar at the top of the Generation tab (decided with the user, 1 October 2026): the
/// Preset menu and the JSON editor button.
struct PresetBar: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection
  @State private var saving = false
  @State private var managing = false
  @State private var editingJSON = false
  @State private var importMessage: String?

  var body: some View {
    HStack(spacing: DS.controlGap) {
      Menu {
        if controller.presets.presets.isEmpty {
          Text("preset.none")
        }
        ForEach(controller.presets.presets) { preset in
          Button {
            controller.load(preset, with: connection)
          } label: {
            Text(verbatim: preset.name)
          }
        }
        Divider()
        Button {
          saving = true
        } label: {
          Text("preset.saveAs")
        }
        Button {
          managing = true
        } label: {
          Text("preset.manage")
        }
        .disabled(controller.presets.presets.isEmpty)
        Button {
          importFile()
        } label: {
          Text("preset.import")
        }
      } label: {
        DSMenuLabel(String(localized: "preset.menu"), systemImage: "slider.horizontal.below.rectangle")
      }
      .dsMenuPill()

      Button {
        editingJSON = true
      } label: {
        HStack(spacing: DS.pillIconGap) {
          Image(systemName: "curlybraces")
            .accessibilityHidden(true)
          Text("json.button")
          if !controller.parameters.extra.isEmpty {
            Text(verbatim: "· \(controller.parameters.extra.count)")
              .foregroundStyle(DS.accent)
              .monospacedDigit()
          }
        }
      }
      .buttonStyle(DSPillButtonStyle())
      .help(String(localized: "json.button.help"))

      if let importMessage {
        Text(importMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .sheet(isPresented: $saving) {
      SavePresetSheet(controller: controller, connection: connection)
    }
    .sheet(isPresented: $managing) {
      ManagePresetsSheet(controller: controller)
    }
    .sheet(isPresented: $editingJSON) {
      JSONEditorSheet(controller: controller, connection: connection)
    }
  }

  /// Asks for a file with a list of presets; the result is told in the bar.
  private func importFile() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.message = String(localized: "preset.import.message")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let result = controller.importPresets(from: url)
    importMessage = String(
      format: String(localized: "preset.import.result"), result.presets.count, result.skipped)
  }
}
```

- [ ] **Step 3: Creare `App/Generation/Presets/PresetSheets.swift`**

```swift
import HubCore
import HubKit
import SwiftUI

/// Asks for a name and saves the tab as a preset; an existing name is replaced, and the
/// sheet says so.
struct SavePresetSheet: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""

  private var replaces: Bool {
    controller.presets.preset(named: name.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("preset.save.title")
        .font(.headline)
      TextField(String(localized: "preset.save.name"), text: $name, prompt: Text("preset.save.name"))
        .textFieldStyle(.roundedBorder)
        .onSubmit(save)
      Text("preset.save.contents")
        .font(.caption)
        .foregroundStyle(.secondary)
      if replaces {
        Text("preset.save.replaces")
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.cancel")
        }
        .buttonStyle(DSPillButtonStyle())
        .keyboardShortcut(.cancelAction)
        Button(action: save) {
          Text("preset.save.button")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(20)
    .frame(width: 380)
    .background(DSBackground())
    .tint(DS.accent)
  }

  private func save() {
    if controller.savePreset(named: name, with: connection) { dismiss() }
  }
}

/// The saved presets, each renamed in place or deleted.
struct ManagePresetsSheet: View {
  let controller: GenerationController
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("preset.manage.title")
        .font(.headline)
      if controller.presets.presets.isEmpty {
        Text("preset.none")
          .foregroundStyle(.secondary)
      }
      ScrollView {
        VStack(spacing: DS.controlGap) {
          ForEach(controller.presets.presets) { preset in
            PresetRow(preset: preset, store: controller.presets)
          }
        }
      }
      .frame(minHeight: 120, maxHeight: 360)
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.done")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 440)
    .background(DSBackground())
    .tint(DS.accent)
  }
}

private struct PresetRow: View {
  let preset: Preset
  let store: PresetStore
  @State private var name = ""
  @State private var taken = false

  var body: some View {
    HStack(spacing: DS.controlGap) {
      VStack(alignment: .leading, spacing: 2) {
        TextField(String(localized: "preset.save.name"), text: $name)
          .textFieldStyle(.roundedBorder)
          .onSubmit(rename)
        if taken {
          Text("preset.rename.taken")
            .font(.caption)
            .foregroundStyle(DS.remove)
        } else if !preset.model.isEmpty {
          Text(verbatim: preset.model)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
      Button {
        store.delete(preset.id)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(DS.remove)
      }
      .buttonStyle(.plain)
      .help(String(localized: "preset.delete"))
      .accessibilityLabel(String(localized: "preset.delete"))
    }
    .onAppear { name = preset.name }
  }

  private func rename() {
    taken = !store.rename(preset.id, to: name)
    if taken { name = preset.name }
  }
}
```

- [ ] **Step 4: Creare `App/Generation/Presets/JSONEditorSheet.swift`**

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI

/// The whole Draw Things configuration as JSON (spec §6, level 3): the "Copy Configuration"
/// format, every setting reachable. Paste a complete or partial text and apply it: only the
/// keys in the text change.
struct JSONEditorSheet: View {
  let controller: GenerationController
  let connection: DrawThingsConnection
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var error: String?
  @State private var unknown: [String] = []
  @State private var applyError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: DS.rowGap) {
      Text("json.title")
        .font(.headline)
      Text("json.explanation")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextEditor(text: $text)
        .font(.system(.callout, design: .monospaced))
        .scrollContentBackground(.hidden)
        .padding(8)
        .frame(minWidth: 520, minHeight: 320)
        .background(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
        .accessibilityLabel(String(localized: "json.title"))
      status
      HStack {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
        } label: {
          Text("json.copy")
        }
        .buttonStyle(DSPillButtonStyle())
        Button {
          text = controller.exportJSON(in: connection)
        } label: {
          Text("json.reload")
        }
        .buttonStyle(DSPillButtonStyle())
        .help(String(localized: "json.reload.help"))
        Spacer()
        Button {
          dismiss()
        } label: {
          Text("sheet.cancel")
        }
        .buttonStyle(DSPillButtonStyle())
        .keyboardShortcut(.cancelAction)
        Button(action: apply) {
          Text("json.apply")
        }
        .buttonStyle(DSPillButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(error != nil)
      }
    }
    .padding(20)
    .background(DSBackground())
    .tint(DS.accent)
    .onAppear { text = controller.exportJSON(in: connection) }
    .onChange(of: text) { check() }
  }

  /// What is wrong with the text, or what will be ignored.
  @ViewBuilder private var status: some View {
    if let error {
      Label {
        Text(String(format: String(localized: "json.invalid"), error))
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
      }
      .font(.caption)
      .foregroundStyle(DS.remove)
      .lineLimit(3)
    } else if let applyError {
      Text(String(format: String(localized: "json.invalid"), applyError))
        .font(.caption)
        .foregroundStyle(DS.remove)
    } else if !unknown.isEmpty {
      Text(String(format: String(localized: "json.unknownKeys"), unknown.joined(separator: ", ")))
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func check() {
    applyError = nil
    error = controller.codec.validate(text)
    unknown = error == nil ? controller.codec.unknownKeys(in: text) : []
  }

  private func apply() {
    do {
      try controller.applyJSON(text, with: connection)
      dismiss()
    } catch {
      applyError = error.message
    }
  }
}
```

- [ ] **Step 5: Sostituire `App/MainWindow/GenerationTabView.swift` con:**

```swift
import HubKit
import SwiftUI

/// The built-in Generation tab: the prompt card across the whole width, then the parameter
/// cards two per row, cards in a row as tall as the tallest (spec §7).
struct GenerationTabView: View {
  let controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        PresetBar(controller: controller, connection: connection)
          .padding(.horizontal, DS.panelPadding)
        PromptCard(controller: controller, connection: connection)
        DSCardRow {
          DimensionsCard(controller: controller)
          SeedBatchCard(controller: controller)
        }
        DSCardRow {
          SamplingCard(controller: controller, connection: connection)
          LoRACard(controller: controller, connection: connection)
        }
        AdvancedSection(controller: controller, connection: connection)
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
  }
}
```

- [ ] **Step 6: Build e test**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\\(|Test run with|Missing|Not in|Pass String" | grep -v started`
Expected: `** BUILD SUCCEEDED **`; test HubKit 44, HubCore 108, DTBridge 38, Catalog 6: **196** passati.

- [ ] **Step 7: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: barra Preset, editor JSON e fogli nel tab Generazione

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Verifica dal vivo

Nessun codice nuovo. Si prova l'app contro il server Draw Things (API Server acceso sulla 7859, model browsing attivo). Prima si annotano e si copiano in una cartella temporanea il modello scelto dall'utente, `session.json`, `cards.json` e, se esiste, `presets.json`; alla fine si rimettono (e si toglie `presets.json` se prima non c'era).

- [ ] **Step 1: Preparare e avviare**

```bash
defaults read com.exiztenz.DTHub drawThings.selectedModel; A="$HOME/Library/Application Support/DT Hub"; mkdir -p /tmp/dthub-m4c-backup && cp "$A/session.json" "$A/cards.json" /tmp/dthub-m4c-backup/; ls "$A/presets.json" 2>/dev/null && cp "$A/presets.json" /tmp/dthub-m4c-backup/; defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m4c-check && open "/Users/existenz/Software developement/DT Hub/build/Build/Products/Debug/DT Hub.app"
```

- [ ] **Step 2: Test dal vivo delle impostazioni extra (temporaneo, non si committa)**

Creare `Packages/Tests/DTBridgeTests/ZZExtraLiveTests.swift` che applica `{"maskBlur": 3.5, "fps": 10}` a uno stato Klein 512×512 a 4 step con `DrawThingsConfigurationCodec`, genera con `DrawThingsBackend` e verifica un'immagine 512×512; poi cancellarlo.

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && DTHUB_LIVE_DT=1 swift test --filter ZZExtraLiveTests 2>&1 | grep -E "passed after|failed|error:"`
Expected: passa. Se Draw Things deve ricaricare il modello dal volume esterno può richiedere oltre 10 minuti: si lancia in background.

- [ ] **Step 3: Checklist (screenshot)**

1. In cima al tab, sopra la card Prompt, ci sono il menu "Preset" e il pulsante "JSON…".
2. "JSON…" apre un foglio con la configurazione completa del tab: il modello scelto, `"seed" : -1` con il seed casuale, le LoRA scelte con `file`, `mode`, `weight`.
3. Nel foglio, un testo non valido (es. `{"steps": "many"}`) mostra "Non valido: …" e disattiva "Applica"; `{"stepz": 3}` mostra "Ignorate, non sono impostazioni di Draw Things: stepz".
4. `{"steps": 30, "guidanceScale": 4.5}` applicato: Step e Text guidance nel tab cambiano, il resto no.
5. `{"fps": 12}` applicato: il pulsante JSON… mostra "· 1"; rilanciando l'editor, `"fps" : 12` compare nel testo.
6. "Salva come preset…" con un nome: il menu Preset lo elenca; cambiare i parametri e ricaricarlo li riporta com'erano e il prompt non cambia; salvando di nuovo con lo stesso nome il foglio avvisa che sostituirà.
7. "Gestisci preset…": rinominare con un nome già usato mostra "Questo nome è già usato."; il cestino elimina.
8. "Importa preset da file…" con la lista di Draw Things (`~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json`): compare "57 preset importati, 0 saltati"; caricarne uno sceglie il suo modello, e se il modello non è sul server il RUN resta grigio con il suo messaggio.

Punti che servono all'utente (menu e pannello di apertura non automatizzabili in background): i punti 6–8.

- [ ] **Step 4: Pulizia** (rimettere il modello annotato allo Step 1 al posto di `<modello-annotato>`)

```bash
osascript -e 'quit app "DT Hub"'; A="$HOME/Library/Application Support/DT Hub"; cp /tmp/dthub-m4c-backup/session.json /tmp/dthub-m4c-backup/cards.json "$A/"; if [ -f /tmp/dthub-m4c-backup/presets.json ]; then cp /tmp/dthub-m4c-backup/presets.json "$A/"; else rm -f "$A/presets.json"; fi; defaults delete com.exiztenz.DTHub output.folder; defaults write com.exiztenz.DTHub drawThings.selectedModel <modello-annotato>; rm -rf /tmp/dthub-m4c-check /tmp/dthub-m4c-backup
```

---

## Fine della M4c

Esito atteso sul branch `m4c-json-preset`:
- **196 test verdi**, di cui 3 live eseguiti solo con `DTHUB_LIVE_DT`;
- build Xcode pulita;
- tutta la configurazione di Draw Things raggiungibile da DT Hub (card, card Avanzate, editor JSON), con preset;
- M4 completa: parità con il pannello di Draw Things per il T2I, tranne ControlNet e Inpaint.

Poi: revisione indipendente, correzioni, merge, e il piano di M5 (server gestito con gRPCServerCLI).

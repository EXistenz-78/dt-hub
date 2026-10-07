# M4b Card Avanzate — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il livello 2 della spec §6 per il T2I: otto card Avanzate dietro l'interruttore "Mostra impostazioni avanzate":
- Refiner;
- Hires fix;
- Upscaler e restauro;
- Guidance extra;
- Text encoder;
- Condizionamento SDXL;
- Prestazioni;
- Output.

Ogni campo compare solo se il modello scelto lo usa. I valori modificati che il modello non usa sono segnalati e non vengono inviati.

**Architecture:**
- **HubKit** riceve:
  - `AdvancedParameters` (i ~50 valori delle card, con i predefiniti di Draw Things e la decodifica tollerante), dentro `GenerationParameters.advanced`;
  - `ModelCapabilities` su `CatalogModel`;
  - gli elenchi `upscalers`/`faceRestorers` su `ModelCatalog`.
- **HubCore** riceve:
  - `AdvancedField`/`AdvancedCard`: quando un campo si applica, se è modificato, come si ripristina;
  - `JobComposer`, che toglie dal RUN ciò che il modello non usa o il server non ha e risolve la dimensione automatica dell'Hires fix.
- **DTBridge** legge le capacità dalla specifica del modello, riconosce upscaler e restauro volti dai nomi dei file e invia tutti i valori.
- **L'app** aggiunge `AdvancedSection` (interruttore, conteggio, avviso, righe di card) e `AdvancedCardView`.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, DrawThings-Swift 2.2.x.

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 5, 6, 7, 11, 12, 15-M4). M4 è divisa in tre tappe: M4a (fatta), **M4b** (questo piano), M4c (editor JSON, preset, import `custom_configs.json`).

## Global Constraints

- **Repository e dipendenze:**
  - radice `<repo>` (percorsi tra virgolette);
  - branch `m4b-card-avanzate` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo `DTBridge` importa DrawThings-Swift.
- **Card (decise con l'utente, 1 ottobre 2026):**
  - le otto card elencate nel Goal;
  - Inpaint e ControlNet restano fuori: servono immagini o maschere, e l'utente pensa a un tab dedicato;
  - SOL attention, causal inference, campi video, image guidance, strength, image prior e stage 2 restano all'editor JSON (M4c): non servono al T2I o il loro effetto non è documentato.
- **Interruttore (deciso con l'utente):**
  - "Mostra impostazioni avanzate", spento all'inizio, ricordato in `cards.json` (chiave `advanced`);
  - da spento mostra quanti valori avanzati sono modificati;
  - da acceso mostra le card, due per riga, alte uguali (`DSCardRow`), aperte per impostazione predefinita e ricordate (chiave `advanced.<card>`).
- **Visibilità, dalla specifica del modello e non da una tabella per famiglia** (le specifiche di Draw Things dicono cosa ogni modello supporta):
  - `guidance_embed` → Guidance embed e "Accelera";
  - `tea_cache_coefficients` → TeaCache;
  - encoder presenti tra `text_encoder`, `clip_encoder`, `t5_encoder`, `additional_clip_encoders`: CLIP-L (`clip_vit_l14`), OpenCLIP-G (`open_clip_vit_bigg14`), T5 (`t5_xxl`). Un testo separato si mostra solo se c'è almeno un altro encoder;
  - `t5_encoder` presente → interruttore "Text encoder T5";
  - `text_encoder` CLIP (`clip_vit`/`open_clip`) → CLIP skip;
  - Condizionamento SDXL solo per `sdxl_base_v0.9`, `sdxl_refiner_v0.9`, `ssd_1b`; "Prompt negativo a zero" per queste e `sd3`, `sd3_large`;
  - Gamma del campionamento stocastico solo con i sampler TCD e TCD Trailing;
  - tutti gli altri campi valgono per ogni modello;
  - un modello sconosciuto (catalogo non caricato) mostra tutto.
- **Valori nascosti (spec §6):** un valore modificato che il modello non usa resta conservato ma **non viene inviato**, come in M4a per negativo e CFG-Zero*. Un avviso arancio li elenca con il pulsante "Ripristina".
- **Predefiniti:** quelli della libreria (test `defaultAdvancedValuesMatchTheLibrarysDefaults`).
- **Dimensioni, file e controlli:**
  - Hires fix: dimensioni di partenza 0 = automatiche, cioè la dimensione nativa del modello (`default_scale` × 64, altrimenti 512) limitata all'immagine; se la partenza non è più piccola dell'immagine, l'Hires fix non viene inviato.
  - SDXL: 0 = automatico, come in Draw Things.
  - Refiner, upscaler e restauro volti assenti dal server non vengono inviati.
  - Upscaler e restauro volti si riconoscono dal nome del file:
    - upscaler: `esrgan`, `upscal`, `ultrasharp`, `remacri`, `superscale`, `4x_`, `2x_`;
    - restauro volti: `restoreformer`, `codeformer`, `gfpgan` (ParseNet è un aiutante, non una scelta).
  - Ogni valore numerico si scrive o si cambia con le frecce; le caselle stanno sulla riga del valore che cambiano.
- **Stringhe e nomi:**
  - ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo;
  - `String(format: String(localized:), …)` per i valori;
  - `HubKit.LoRAMode`/`DrawThingsClient.LoRAMode` e `CompressionArtifacts`/`CompressionMethod` sono tipi distinti: in DTBridge si converte per valore grezzo.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- **Modello senza specifica o catalogo non caricato:** tutte le card e tutti i campi visibili (test `anUnknownModelShowsEverything`, Task 2).
- **Sessione salvata da M4a** (senza `advanced`) o con valori avanzati illeggibili: si apre con i predefiniti per ciò che manca (test `advancedValuesLoadLeniently`, Task 1).
- **Refiner o upscaler scelti e poi tolti dal server:** non vengono inviati, nessun errore dal server (test `filesTheServerDoesNotListAreNotSent`, Task 3).
- **Hires fix con dimensioni di partenza non più piccole dell'immagine** (es. 512×512 con SD 1.5): l'Hires fix non parte, invece di un errore o di un'immagine vuota (test `aHiresFixNotSmallerThanTheImageIsDropped`, Task 3).
- **Cambio modello che nasconde un valore modificato** (es. CLIP skip 2, poi FLUX.2 Klein): avviso e valore non inviato (test `hiddenModifiedFieldsAreThoseTheModelDoesNotUse`, `fieldsTheModelDoesNotUseAreNotSent`, Task 2–3).

---

### Task 1: Valori avanzati e capacità del modello (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Generation/AdvancedParameters.swift`
- Create: `Packages/Sources/HubKit/Catalog/ModelCapabilities.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationParameters.swift` (campo `advanced`, `clamped()`, decodifica)
- Modify: `Packages/Sources/HubKit/Catalog/ModelCatalog.swift` (`CatalogModel.capabilities`, `ModelCatalog.upscalers`/`faceRestorers`)
- Test: `Packages/Tests/HubKitTests/GenerationParametersTests.swift` (suite `AdvancedParametersTests`)

**Interfaces:**
- Produces (HubKit, `public`):
  - `enum CompressionArtifacts: Int, CaseIterable, Identifiable, Codable, Sendable { none, h264, h265, jpeg }`;
  - `struct AdvancedParameters: Equatable, Codable, Sendable` con i campi del file, `static let default`, gli intervalli (`unitRange`, `guidanceEmbedRange`, `sharpnessRange`, `clipSkipRange`, `aestheticRange`, `conditioningRange`, `tileRange`, `overlapRange`, `teaCacheStepRange`, `teaCacheEndRange`, `teaCacheSkipRange`, `qualityRange`, `upscalerFactors`) e `func clamped()`;
  - `GenerationParameters.advanced: AdvancedParameters`, ultimo parametro dell'init (`advanced: = .default`);
  - `struct ModelCapabilities: Equatable, Sendable` (`guidanceEmbed`, `teaCache`, `clipL`, `openClipG`, `t5`, `optionalT5`, `clipSkip`, `nativeSize: Int?`, `static let unknown`);
  - `CatalogModel(file:name:family:capabilities: = .unknown)` e `.capabilities`;
  - `ModelCatalog(models:loras:fileCount:upscalers: = [], faceRestorers: = [])` con `.upscalers`, `.faceRestorers`.

- [ ] **Step 1: Creare il branch**

```bash
cd "<repo>" && git switch main && git switch -c m4b-card-avanzate
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

  @Test func compressionMatchesDrawThingsRawValues() {
    #expect(CompressionArtifacts.allCases.map(\.rawValue) == [0, 1, 2, 3])
  }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'AdvancedParameters' in scope`.

- [ ] **Step 4: Creare `Packages/Sources/HubKit/Generation/AdvancedParameters.swift`**

```swift
import Foundation

/// Compression artifacts added to the output (Draw Things `CompressionMethod`, same raw values).
public enum CompressionArtifacts: Int, CaseIterable, Identifiable, Codable, Sendable {
  case none = 0
  case h264 = 1
  case h265 = 2
  case jpeg = 3

  public var id: Int { rawValue }
}

/// The level-2 parameters of the Advanced cards (spec §6), with Draw Things' own defaults.
/// Sizes are in pixels; 0 in a size means "automatic" (the model's native size for the Hires
/// fix start, the image size for the SDXL conditioning), as in Draw Things.
public struct AdvancedParameters: Equatable, Codable, Sendable {
  // Refiner: "" = none.
  public var refinerModel = ""
  public var refinerStart = 0.85
  // Hires fix.
  public var hiresFix = false
  public var hiresFixWidth = 0
  public var hiresFixHeight = 0
  public var hiresFixStrength = 0.7
  // Upscaler and face restoration: "" = none; scale 0 = the upscaler's own factor.
  public var upscaler = ""
  public var upscalerScaleFactor = 0
  public var faceRestoration = ""
  // Extra guidance.
  public var guidanceEmbed = 3.5
  public var speedUpWithGuidanceEmbed = true
  public var sharpness = 0.0
  public var stochasticSamplingGamma = 0.3
  // Text encoders.
  public var clipSkip = 1
  public var t5TextEncoder = true
  public var separateClipL = false
  public var clipLText = ""
  public var separateOpenClipG = false
  public var openClipGText = ""
  public var separateT5 = false
  public var t5Text = ""
  public var zeroNegativePrompt = false
  // SDXL conditioning.
  public var aestheticScore = 6.0
  public var negativeAestheticScore = 2.5
  public var cropTop = 0
  public var cropLeft = 0
  public var originalWidth = 0
  public var originalHeight = 0
  public var targetWidth = 0
  public var targetHeight = 0
  public var negativeOriginalWidth = 0
  public var negativeOriginalHeight = 0
  // Performance.
  public var tiledDecoding = false
  public var decodingTileWidth = 640
  public var decodingTileHeight = 640
  public var decodingTileOverlap = 128
  public var tiledDiffusion = false
  public var diffusionTileWidth = 1024
  public var diffusionTileHeight = 1024
  public var diffusionTileOverlap = 128
  public var teaCache = false
  public var teaCacheStart = 5
  /// -1 = up to the last step.
  public var teaCacheEnd = -1
  public var teaCacheThreshold = 0.06
  public var teaCacheMaxSkipSteps = 3
  // Output.
  public var colorCalibration = false
  public var compressionArtifacts = CompressionArtifacts.none
  public var compressionQuality = 43.1

  public init() {}

  public static let `default` = AdvancedParameters()

  /// Allowed ranges, used by the cards and by `clamped()`.
  public static let unitRange = 0.0...1.0
  public static let guidanceEmbedRange = 0.0...50.0
  public static let sharpnessRange = 0.0...30.0
  public static let clipSkipRange = 1...23
  public static let aestheticRange = 0.0...10.0
  /// SDXL conditioning sizes and crop; 0 = automatic.
  public static let conditioningRange = 0...8192
  public static let tileRange = 64...2048
  public static let overlapRange = 0...1024
  public static let teaCacheStepRange = 0...150
  public static let teaCacheEndRange = -1...150
  public static let teaCacheSkipRange = 1...50
  public static let qualityRange = 0.0...100.0
  /// 0 = the upscaler's own factor.
  public static let upscalerFactors = [0, 2, 4]

  /// The same values forced into the allowed ranges; tile sizes on multiples of 64.
  public func clamped() -> AdvancedParameters {
    func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
      min(max(value, range.lowerBound), range.upperBound)
    }
    func tile(_ value: Int) -> Int { clamp(Int((Double(value) / 64).rounded()) * 64, Self.tileRange) }
    func hiresSize(_ value: Int) -> Int { value <= 0 ? 0 : GenerationParameters.snap(Double(value)) }
    var copy = self
    copy.refinerStart = clamp(refinerStart, Self.unitRange)
    copy.hiresFixWidth = hiresSize(hiresFixWidth)
    copy.hiresFixHeight = hiresSize(hiresFixHeight)
    copy.hiresFixStrength = clamp(hiresFixStrength, Self.unitRange)
    copy.upscalerScaleFactor = Self.upscalerFactors.contains(upscalerScaleFactor) ? upscalerScaleFactor : 0
    copy.guidanceEmbed = clamp(guidanceEmbed, Self.guidanceEmbedRange)
    copy.sharpness = clamp(sharpness, Self.sharpnessRange)
    copy.stochasticSamplingGamma = clamp(stochasticSamplingGamma, Self.unitRange)
    copy.clipSkip = clamp(clipSkip, Self.clipSkipRange)
    copy.aestheticScore = clamp(aestheticScore, Self.aestheticRange)
    copy.negativeAestheticScore = clamp(negativeAestheticScore, Self.aestheticRange)
    for keyPath in [
      \AdvancedParameters.cropTop, \.cropLeft, \.originalWidth, \.originalHeight, \.targetWidth,
      \.targetHeight, \.negativeOriginalWidth, \.negativeOriginalHeight,
    ] {
      copy[keyPath: keyPath] = clamp(copy[keyPath: keyPath], Self.conditioningRange)
    }
    copy.decodingTileWidth = tile(decodingTileWidth)
    copy.decodingTileHeight = tile(decodingTileHeight)
    copy.decodingTileOverlap = clamp(decodingTileOverlap, Self.overlapRange)
    copy.diffusionTileWidth = tile(diffusionTileWidth)
    copy.diffusionTileHeight = tile(diffusionTileHeight)
    copy.diffusionTileOverlap = clamp(diffusionTileOverlap, Self.overlapRange)
    copy.teaCacheStart = clamp(teaCacheStart, Self.teaCacheStepRange)
    copy.teaCacheEnd = clamp(teaCacheEnd, Self.teaCacheEndRange)
    copy.teaCacheThreshold = clamp(teaCacheThreshold, Self.unitRange)
    copy.teaCacheMaxSkipSteps = clamp(teaCacheMaxSkipSteps, Self.teaCacheSkipRange)
    copy.compressionQuality = clamp(compressionQuality, Self.qualityRange)
    return copy
  }

  /// Lenient: a missing or unreadable field takes its default, like `GenerationParameters`.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
      (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
    let d = Self.default
    refinerModel = value(.refinerModel, d.refinerModel)
    refinerStart = value(.refinerStart, d.refinerStart)
    hiresFix = value(.hiresFix, d.hiresFix)
    hiresFixWidth = value(.hiresFixWidth, d.hiresFixWidth)
    hiresFixHeight = value(.hiresFixHeight, d.hiresFixHeight)
    hiresFixStrength = value(.hiresFixStrength, d.hiresFixStrength)
    upscaler = value(.upscaler, d.upscaler)
    upscalerScaleFactor = value(.upscalerScaleFactor, d.upscalerScaleFactor)
    faceRestoration = value(.faceRestoration, d.faceRestoration)
    guidanceEmbed = value(.guidanceEmbed, d.guidanceEmbed)
    speedUpWithGuidanceEmbed = value(.speedUpWithGuidanceEmbed, d.speedUpWithGuidanceEmbed)
    sharpness = value(.sharpness, d.sharpness)
    stochasticSamplingGamma = value(.stochasticSamplingGamma, d.stochasticSamplingGamma)
    clipSkip = value(.clipSkip, d.clipSkip)
    t5TextEncoder = value(.t5TextEncoder, d.t5TextEncoder)
    separateClipL = value(.separateClipL, d.separateClipL)
    clipLText = value(.clipLText, d.clipLText)
    separateOpenClipG = value(.separateOpenClipG, d.separateOpenClipG)
    openClipGText = value(.openClipGText, d.openClipGText)
    separateT5 = value(.separateT5, d.separateT5)
    t5Text = value(.t5Text, d.t5Text)
    zeroNegativePrompt = value(.zeroNegativePrompt, d.zeroNegativePrompt)
    aestheticScore = value(.aestheticScore, d.aestheticScore)
    negativeAestheticScore = value(.negativeAestheticScore, d.negativeAestheticScore)
    cropTop = value(.cropTop, d.cropTop)
    cropLeft = value(.cropLeft, d.cropLeft)
    originalWidth = value(.originalWidth, d.originalWidth)
    originalHeight = value(.originalHeight, d.originalHeight)
    targetWidth = value(.targetWidth, d.targetWidth)
    targetHeight = value(.targetHeight, d.targetHeight)
    negativeOriginalWidth = value(.negativeOriginalWidth, d.negativeOriginalWidth)
    negativeOriginalHeight = value(.negativeOriginalHeight, d.negativeOriginalHeight)
    tiledDecoding = value(.tiledDecoding, d.tiledDecoding)
    decodingTileWidth = value(.decodingTileWidth, d.decodingTileWidth)
    decodingTileHeight = value(.decodingTileHeight, d.decodingTileHeight)
    decodingTileOverlap = value(.decodingTileOverlap, d.decodingTileOverlap)
    tiledDiffusion = value(.tiledDiffusion, d.tiledDiffusion)
    diffusionTileWidth = value(.diffusionTileWidth, d.diffusionTileWidth)
    diffusionTileHeight = value(.diffusionTileHeight, d.diffusionTileHeight)
    diffusionTileOverlap = value(.diffusionTileOverlap, d.diffusionTileOverlap)
    teaCache = value(.teaCache, d.teaCache)
    teaCacheStart = value(.teaCacheStart, d.teaCacheStart)
    teaCacheEnd = value(.teaCacheEnd, d.teaCacheEnd)
    teaCacheThreshold = value(.teaCacheThreshold, d.teaCacheThreshold)
    teaCacheMaxSkipSteps = value(.teaCacheMaxSkipSteps, d.teaCacheMaxSkipSteps)
    colorCalibration = value(.colorCalibration, d.colorCalibration)
    compressionArtifacts = value(.compressionArtifacts, d.compressionArtifacts)
    compressionQuality = value(.compressionQuality, d.compressionQuality)
  }
}
```

- [ ] **Step 5: Creare `Packages/Sources/HubKit/Catalog/ModelCapabilities.swift`**

```swift
/// What a model supports, read from its Draw Things specification (DTBridge). The advanced
/// cards show a field only when the model can use it (spec §6). An unknown model shows all.
public struct ModelCapabilities: Equatable, Sendable {
  /// Guidance embed (FLUX.1 dev, FLUX.2 dev, HiDream, Hunyuan): `guidance_embed`.
  public var guidanceEmbed: Bool
  /// TeaCache: the spec has `tea_cache_coefficients`.
  public var teaCache: Bool
  /// The text encoders it has: CLIP-L, OpenCLIP-G, T5.
  public var clipL: Bool
  public var openClipG: Bool
  public var t5: Bool
  /// T5 is a separate encoder that can be switched off (SD3, HiDream: `t5_encoder`).
  public var optionalT5: Bool
  /// The main text encoder is a CLIP (SD 1.x, 2.x, SDXL, SD3): CLIP skip applies.
  public var clipSkip: Bool
  /// Native size in pixels (`default_scale` × 64); the Hires fix starts here. nil when unknown.
  public var nativeSize: Int?

  public init(
    guidanceEmbed: Bool, teaCache: Bool, clipL: Bool, openClipG: Bool, t5: Bool,
    optionalT5: Bool, clipSkip: Bool, nativeSize: Int?
  ) {
    self.guidanceEmbed = guidanceEmbed
    self.teaCache = teaCache
    self.clipL = clipL
    self.openClipG = openClipG
    self.t5 = t5
    self.optionalT5 = optionalT5
    self.clipSkip = clipSkip
    self.nativeSize = nativeSize
  }

  /// A model without a specification: everything may apply.
  public static let unknown = ModelCapabilities(
    guidanceEmbed: true, teaCache: true, clipL: true, openClipG: true, t5: true,
    optionalT5: true, clipSkip: true, nativeSize: nil)
}
```

- [ ] **Step 6: Sostituire `Packages/Sources/HubKit/Generation/GenerationParameters.swift` con:**

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

  public init(
    width: Int = 1024, height: Int = 1024, steps: Int = 8, guidanceScale: Double = 1,
    cfgZeroStar: Bool = false, cfgZeroInitSteps: Int = 0,
    sampler: Sampler = .uniPCTrailing, shift: Double = 3, resolutionDependentShift: Bool = true,
    seed: UInt32 = 0, randomSeed: Bool = true, batchSize: Int = 1, batchCount: Int = 1,
    loras: [LoRASelection] = [], advanced: AdvancedParameters = .default
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

- [ ] **Step 7: Sostituire `Packages/Sources/HubKit/Catalog/ModelCatalog.swift` con:**

```swift
/// A generative model installed on the Draw Things server.
public struct CatalogModel: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Draw Things model version, e.g. "flux2_9b": the model family key of spec §5.
  public let family: String?
  /// What the model supports, from its specification.
  public let capabilities: ModelCapabilities

  public init(file: String, name: String, family: String?, capabilities: ModelCapabilities = .unknown) {
    self.file = file
    self.name = name
    self.family = family
    self.capabilities = capabilities
  }
}

/// A LoRA installed on the Draw Things server.
public struct CatalogLoRA: Identifiable, Equatable, Sendable {
  public var id: String { file }
  public let file: String
  public let name: String
  /// Model family the LoRA was made for; nil when the server does not say.
  public let family: String?
  /// The trigger word Draw Things keeps for it (its `prefix`); empty when there is none.
  public let trigger: String
  /// The weight suggested by its metadata, when there is one.
  public let defaultWeight: Double?

  public init(file: String, name: String, family: String?, trigger: String = "", defaultWeight: Double? = nil) {
    self.file = file
    self.name = name
    self.family = family
    self.trigger = trigger
    self.defaultWeight = defaultWeight
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
  /// Upscaler and face-restoration files installed on the server, for the Upscaler card.
  public let upscalers: [String]
  public let faceRestorers: [String]

  public init(
    models: [CatalogModel], loras: [CatalogLoRA], fileCount: Int,
    upscalers: [String] = [], faceRestorers: [String] = []
  ) {
    self.models = models
    self.loras = loras
    self.fileCount = fileCount
    self.upscalers = upscalers
    self.faceRestorers = faceRestorers
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

- [ ] **Step 8: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubKit `38 tests … passed`; HubCore 83, DTBridge 18, Catalog 6 come prima.

- [ ] **Step 9: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: valori delle card Avanzate e capacità del modello nel contratto

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Campi avanzati — quando si applicano, modificati, nascosti (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Family/AdvancedField.swift`
- Test: `Packages/Tests/HubCoreTests/AdvancedFieldTests.swift` (suite `AdvancedFieldTests`; la suite `AdvancedCompositionTests` si aggiunge nel Task 3)

**Interfaces:**
- Consumes: `AdvancedParameters`, `ModelCapabilities`, `CatalogModel`, `Sampler` (Task 1, M3).
- Produces (HubCore, `public`):
  - `enum AdvancedCard: String, CaseIterable, Identifiable { refiner, hiresFix, upscale, guidance, textEncoder, sdxl, performance, output }` con `fields`;
  - `enum AdvancedField: String, CaseIterable, Identifiable` (19 casi) con `card`, `isShown(for: CatalogModel?, sampler: Sampler) -> Bool`, `isModified(in:) -> Bool`;
  - `extension AdvancedParameters` con `mutating func reset(_:)`, `var modifiedFields`, `func hiddenModifiedFields(for:sampler:)`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/AdvancedFieldTests.swift` con:

```swift
import HubKit
import Testing

@testable import HubCore

struct AdvancedFieldTests {
  let flux1 = CatalogModel(
    file: "flux_1_dev_q5p.ckpt", name: "FLUX.1 [dev]", family: "flux1",
    capabilities: ModelCapabilities(
      guidanceEmbed: true, teaCache: true, clipL: true, openClipG: false, t5: true,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  let klein = CatalogModel(
    file: "flux_2_klein_9b_f16.ckpt", name: "FLUX.2 [klein] 9B", family: "flux2_9b",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  let sd15 = CatalogModel(
    file: "juggernaut_reborn_q6p_q8p.ckpt", name: "Juggernaut Reborn", family: "v1",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: true, openClipG: false, t5: false,
      optionalT5: false, clipSkip: true, nativeSize: 512))
  let sdxl = CatalogModel(
    file: "sdxl.ckpt", name: "SDXL", family: "sdxl_base_v0.9",
    capabilities: ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: true, openClipG: true, t5: false,
      optionalT5: false, clipSkip: true, nativeSize: 1024))

  func shown(_ model: CatalogModel?, sampler: Sampler = .uniPCTrailing) -> Set<AdvancedField> {
    Set(AdvancedField.allCases.filter { $0.isShown(for: model, sampler: sampler) })
  }

  @Test func fieldsFollowWhatTheModelSupports() {
    #expect(shown(flux1).isSuperset(of: [.guidanceEmbed, .teaCache, .separateClipL, .separateT5]))
    #expect(shown(flux1).isDisjoint(with: [.clipSkip, .separateOpenClipG, .sdxlConditioning, .zeroNegativePrompt]))
    #expect(shown(klein).isDisjoint(with: [.guidanceEmbed, .teaCache, .clipSkip, .separateClipL, .separateT5]))
    #expect(shown(sd15).contains(.clipSkip))
    // One encoder only: no separate text.
    #expect(!shown(sd15).contains(.separateClipL))
    #expect(shown(sdxl).isSuperset(of: [.clipSkip, .separateClipL, .separateOpenClipG, .sdxlConditioning, .zeroNegativePrompt]))
  }

  @Test func refinerHiresUpscalerAndOutputApplyToEveryModel() {
    for model in [flux1, klein, sd15, sdxl] {
      #expect(shown(model).isSuperset(of: [.refiner, .hiresFix, .upscaler, .faceRestoration, .sharpness, .tiledDecoding, .tiledDiffusion, .colorCalibration, .compressionArtifacts]))
    }
  }

  @Test func theSamplingGammaAppliesToTCDSamplersOnly() {
    #expect(shown(klein, sampler: .tcd).contains(.stochasticSamplingGamma))
    #expect(shown(klein, sampler: .tcdTrailing).contains(.stochasticSamplingGamma))
    #expect(!shown(klein).contains(.stochasticSamplingGamma))
  }

  @Test func anUnknownModelShowsEverything() {
    #expect(shown(nil, sampler: .tcd) == Set(AdvancedField.allCases))
  }

  @Test func everyFieldBelongsToACard() {
    #expect(AdvancedCard.allCases.allSatisfy { !$0.fields.isEmpty })
    #expect(AdvancedCard.allCases.flatMap(\.fields).count == AdvancedField.allCases.count)
  }

  @Test func reportsAndResetsModifiedFields() {
    var advanced = AdvancedParameters()
    #expect(advanced.modifiedFields.isEmpty)
    advanced.teaCacheThreshold = 0.1
    advanced.clipSkip = 2
    #expect(advanced.modifiedFields == [.clipSkip, .teaCache])
    advanced.reset(.teaCache)
    #expect(advanced.modifiedFields == [.clipSkip])
  }

  @Test func hiddenModifiedFieldsAreThoseTheModelDoesNotUse() {
    var advanced = AdvancedParameters()
    advanced.clipSkip = 2
    advanced.sharpness = 5
    #expect(advanced.hiddenModifiedFields(for: klein, sampler: .uniPCTrailing) == [.clipSkip])
    #expect(advanced.hiddenModifiedFields(for: sd15, sampler: .uniPCTrailing).isEmpty)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'AdvancedField' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Family/AdvancedField.swift`**

```swift
import HubKit

/// The Advanced cards of the Generation tab (spec §6, level 2), in display order.
public enum AdvancedCard: String, CaseIterable, Identifiable, Sendable {
  case refiner, hiresFix, upscale, guidance, textEncoder, sdxl, performance, output

  public var id: String { rawValue }

  public var fields: [AdvancedField] { AdvancedField.allCases.filter { $0.card == self } }
}

/// One setting of the Advanced cards, with the values that go with it (a switch and its
/// sizes count as one). It knows when it applies, whether it differs from Draw Things'
/// default, and how to go back to it.
public enum AdvancedField: String, CaseIterable, Identifiable, Sendable {
  case refiner
  case hiresFix
  case upscaler
  case faceRestoration
  case guidanceEmbed
  case sharpness
  case stochasticSamplingGamma
  case clipSkip
  case t5TextEncoder
  case separateClipL
  case separateOpenClipG
  case separateT5
  case zeroNegativePrompt
  case sdxlConditioning
  case tiledDecoding
  case tiledDiffusion
  case teaCache
  case colorCalibration
  case compressionArtifacts

  public var id: String { rawValue }

  public var card: AdvancedCard {
    switch self {
    case .refiner: .refiner
    case .hiresFix: .hiresFix
    case .upscaler, .faceRestoration: .upscale
    case .guidanceEmbed, .sharpness, .stochasticSamplingGamma: .guidance
    case .clipSkip, .t5TextEncoder, .separateClipL, .separateOpenClipG, .separateT5, .zeroNegativePrompt: .textEncoder
    case .sdxlConditioning: .sdxl
    case .tiledDecoding, .tiledDiffusion, .teaCache: .performance
    case .colorCalibration, .compressionArtifacts: .output
    }
  }

  /// SDXL-derived versions: Kolors and SSD-1B use them too.
  static let sdxlFamilies: Set<String> = ["sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b"]
  static let sd3Families: Set<String> = ["sd3", "sd3_large"]

  /// Whether the field applies to the chosen model (nil = unknown: everything applies) and,
  /// for the sampling gamma, to the chosen sampler.
  public func isShown(for model: CatalogModel?, sampler: Sampler) -> Bool {
    let capabilities = model?.capabilities ?? .unknown
    let family = model?.family
    switch self {
    case .refiner, .hiresFix, .upscaler, .faceRestoration, .sharpness, .tiledDecoding, .tiledDiffusion,
      .colorCalibration, .compressionArtifacts:
      return true
    case .guidanceEmbed: return capabilities.guidanceEmbed
    case .stochasticSamplingGamma: return sampler == .tcd || sampler == .tcdTrailing
    case .clipSkip: return capabilities.clipSkip
    case .t5TextEncoder: return capabilities.optionalT5
    // A separate text only makes sense next to another encoder.
    case .separateClipL: return capabilities.clipL && (capabilities.openClipG || capabilities.t5)
    case .separateOpenClipG: return capabilities.openClipG && (capabilities.clipL || capabilities.t5)
    case .separateT5: return capabilities.t5 && (capabilities.clipL || capabilities.openClipG)
    case .zeroNegativePrompt:
      guard let family else { return true }
      return Self.sdxlFamilies.contains(family) || Self.sd3Families.contains(family)
    case .sdxlConditioning:
      guard let family else { return true }
      return Self.sdxlFamilies.contains(family)
    case .teaCache: return capabilities.teaCache
    }
  }

  /// True when the field's values differ from Draw Things' defaults.
  public func isModified(in advanced: AdvancedParameters) -> Bool {
    var reset = advanced
    reset.reset(self)
    return reset != advanced
  }
}

extension AdvancedParameters {
  /// Puts the field's values back to Draw Things' defaults.
  public mutating func reset(_ field: AdvancedField) {
    let d = Self.default
    switch field {
    case .refiner:
      refinerModel = d.refinerModel
      refinerStart = d.refinerStart
    case .hiresFix:
      hiresFix = d.hiresFix
      hiresFixWidth = d.hiresFixWidth
      hiresFixHeight = d.hiresFixHeight
      hiresFixStrength = d.hiresFixStrength
    case .upscaler:
      upscaler = d.upscaler
      upscalerScaleFactor = d.upscalerScaleFactor
    case .faceRestoration:
      faceRestoration = d.faceRestoration
    case .guidanceEmbed:
      guidanceEmbed = d.guidanceEmbed
      speedUpWithGuidanceEmbed = d.speedUpWithGuidanceEmbed
    case .sharpness:
      sharpness = d.sharpness
    case .stochasticSamplingGamma:
      stochasticSamplingGamma = d.stochasticSamplingGamma
    case .clipSkip:
      clipSkip = d.clipSkip
    case .t5TextEncoder:
      t5TextEncoder = d.t5TextEncoder
    case .separateClipL:
      separateClipL = d.separateClipL
      clipLText = d.clipLText
    case .separateOpenClipG:
      separateOpenClipG = d.separateOpenClipG
      openClipGText = d.openClipGText
    case .separateT5:
      separateT5 = d.separateT5
      t5Text = d.t5Text
    case .zeroNegativePrompt:
      zeroNegativePrompt = d.zeroNegativePrompt
    case .sdxlConditioning:
      aestheticScore = d.aestheticScore
      negativeAestheticScore = d.negativeAestheticScore
      cropTop = d.cropTop
      cropLeft = d.cropLeft
      originalWidth = d.originalWidth
      originalHeight = d.originalHeight
      targetWidth = d.targetWidth
      targetHeight = d.targetHeight
      negativeOriginalWidth = d.negativeOriginalWidth
      negativeOriginalHeight = d.negativeOriginalHeight
    case .tiledDecoding:
      tiledDecoding = d.tiledDecoding
      decodingTileWidth = d.decodingTileWidth
      decodingTileHeight = d.decodingTileHeight
      decodingTileOverlap = d.decodingTileOverlap
    case .tiledDiffusion:
      tiledDiffusion = d.tiledDiffusion
      diffusionTileWidth = d.diffusionTileWidth
      diffusionTileHeight = d.diffusionTileHeight
      diffusionTileOverlap = d.diffusionTileOverlap
    case .teaCache:
      teaCache = d.teaCache
      teaCacheStart = d.teaCacheStart
      teaCacheEnd = d.teaCacheEnd
      teaCacheThreshold = d.teaCacheThreshold
      teaCacheMaxSkipSteps = d.teaCacheMaxSkipSteps
    case .colorCalibration:
      colorCalibration = d.colorCalibration
    case .compressionArtifacts:
      compressionArtifacts = d.compressionArtifacts
      compressionQuality = d.compressionQuality
    }
  }

  /// Fields changed from the defaults, in card order (for the "Show advanced" switch).
  public var modifiedFields: [AdvancedField] {
    AdvancedField.allCases.filter { $0.isModified(in: self) }
  }

  /// Fields changed from the defaults that the chosen model does not use: kept, not sent
  /// (spec §6: "valori nascosti").
  public func hiddenModifiedFields(for model: CatalogModel?, sampler: Sampler) -> [AdvancedField] {
    modifiedFields.filter { !$0.isShown(for: model, sampler: sampler) }
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubCore `90 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: campi avanzati — visibilità dalle capacità del modello, valori modificati e nascosti

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Il RUN con i valori avanzati (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Generation/JobComposer.swift` (valori avanzati inviati)
- Test: `Packages/Tests/HubCoreTests/AdvancedFieldTests.swift` (aggiungere in fondo la suite `AdvancedCompositionTests`)

**Interfaces:**
- Consumes: `AdvancedField.isShown`, `AdvancedParameters.reset` (Task 2); `ModelCatalog.model(forFile:)`, `.upscalers`, `.faceRestorers`, `CatalogModel.capabilities.nativeSize` (Task 1).
- Produces: `JobComposer.batches(...)` (firma invariata), i cui lavori portano `parameters.advanced` già ripulito; `static func advanced(_:model:catalog:) -> AdvancedParameters` (interno, usato da `batches`).

- [ ] **Step 1: Scrivere i test che falliscono.** Aggiungere in fondo a `Packages/Tests/HubCoreTests/AdvancedFieldTests.swift`:

```swift
struct AdvancedCompositionTests {
  let klein = AdvancedFieldTests().klein
  let sd15 = AdvancedFieldTests().sd15

  func compose(_ parameters: GenerationParameters, model: CatalogModel, catalog extra: ModelCatalog? = nil) -> AdvancedParameters {
    let catalog = extra ?? ModelCatalog(
      models: [klein, sd15], loras: [], fileCount: 4,
      upscalers: ["realesrgan_x4plus_f16.ckpt"], faceRestorers: ["restoreformer_v1.0_f16.ckpt"])
    return JobComposer.batches(
      prompt: "p", negativePrompt: "", model: model.file, family: model.family,
      parameters: parameters, catalog: catalog) { 1 }[0].parameters.advanced
  }

  @Test func fieldsTheModelDoesNotUseAreNotSent() {
    var parameters = GenerationParameters()
    parameters.advanced.clipSkip = 2
    parameters.advanced.sharpness = 4
    #expect(compose(parameters, model: klein).clipSkip == 1)
    #expect(compose(parameters, model: klein).sharpness == 4)
    #expect(compose(parameters, model: sd15).clipSkip == 2)
  }

  @Test func filesTheServerDoesNotListAreNotSent() {
    var parameters = GenerationParameters()
    parameters.advanced.refinerModel = "gone.ckpt"
    parameters.advanced.upscaler = "gone_x4.ckpt"
    parameters.advanced.faceRestoration = "restoreformer_v1.0_f16.ckpt"
    let sent = compose(parameters, model: klein)
    #expect(sent.refinerModel == "")
    #expect(sent.upscaler == "")
    #expect(sent.faceRestoration == "restoreformer_v1.0_f16.ckpt")
  }

  @Test func anAutomaticHiresFixStartsAtTheNativeSize() {
    var parameters = GenerationParameters(width: 1536, height: 1024)
    parameters.advanced.hiresFix = true
    let sent = compose(parameters, model: sd15)
    #expect(sent.hiresFix)
    #expect(sent.hiresFixWidth == 512)
    #expect(sent.hiresFixHeight == 512)
  }

  @Test func aHiresFixNotSmallerThanTheImageIsDropped() {
    var parameters = GenerationParameters(width: 512, height: 512)
    parameters.advanced.hiresFix = true
    #expect(!compose(parameters, model: sd15).hiresFix)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter AdvancedCompositionTests 2>&1 | grep -E "Test run with|Expectation failed" | head -5`
Expected: la suite fallisce: CLIP skip, file assenti e Hires fix passano invariati.

- [ ] **Step 3: Sostituire `Packages/Sources/HubCore/Generation/JobComposer.swift` con:**

```swift
import HubKit

/// Builds the batches of a RUN from what the Generation tab shows (spec §6): fields the
/// model's family does not use are left out, and so are LoRAs that are not usable. Advanced
/// fields the model does not use go back to their defaults; a refiner, upscaler or face
/// restorer the server does not list is left out; a Hires fix without a start size starts
/// from the model's native size, and is dropped when that is not smaller than the image.
public enum JobComposer {
  public static func batches(
    prompt: String, negativePrompt: String, model: String, family: String?,
    parameters: GenerationParameters, catalog: ModelCatalog,
    randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
  ) -> [GenerationJob] {
    let traits = FamilyTraits.of(family)
    var sent = parameters
    sent.loras = parameters.loras.filter { catalog.status(of: $0, family: family) == .usable }
    if !traits.usesShift { sent.cfgZeroStar = false }
    sent.advanced = advanced(parameters, model: catalog.model(forFile: model), catalog: catalog)
    let negative = traits.usesNegativePrompt ? negativePrompt : ""
    return sent.batchesForRun(randomSeed: draw).map {
      GenerationJob(prompt: prompt, negativePrompt: negative, model: model, parameters: $0)
    }
  }

  static func advanced(_ parameters: GenerationParameters, model: CatalogModel?, catalog: ModelCatalog)
    -> AdvancedParameters
  {
    var advanced = parameters.advanced
    for field in AdvancedField.allCases where !field.isShown(for: model, sampler: parameters.sampler) {
      advanced.reset(field)
    }
    if !advanced.refinerModel.isEmpty, catalog.model(forFile: advanced.refinerModel) == nil {
      advanced.reset(.refiner)
    }
    if !advanced.upscaler.isEmpty, !catalog.upscalers.contains(advanced.upscaler) { advanced.reset(.upscaler) }
    if !advanced.faceRestoration.isEmpty, !catalog.faceRestorers.contains(advanced.faceRestoration) {
      advanced.reset(.faceRestoration)
    }
    if advanced.hiresFix {
      let native = model?.capabilities.nativeSize ?? 512
      if advanced.hiresFixWidth == 0 { advanced.hiresFixWidth = min(native, parameters.width) }
      if advanced.hiresFixHeight == 0 { advanced.hiresFixHeight = min(native, parameters.height) }
      if advanced.hiresFixWidth >= parameters.width, advanced.hiresFixHeight >= parameters.height {
        advanced.reset(.hiresFix)
      }
    }
    return advanced
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubCore `94 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: il RUN invia solo i valori avanzati che il modello usa e il server ha

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Capacità dalla specifica, upscaler e invio a Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/CatalogBuilder.swift` (`ModelSpecInfo.capabilities`, `capabilities(_:)`, `isUpscaler`, `isFaceRestorer`)
- Modify: `Packages/Sources/DTBridge/JobMapper.swift` (`apply(_:to:)`)
- Test: `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift`, `Packages/Tests/DTBridgeTests/JobMapperTests.swift`

**Interfaces:**
- Consumes: `AdvancedParameters`, `CompressionArtifacts`, `ModelCapabilities`, `ModelCatalog(…upscalers:faceRestorers:)` (Task 1); dalla libreria i campi di `DrawThingsConfiguration` (`refinerModel`, `hiresFix…`, `upscaler`, `upscalerScaleFactor`, `faceRestoration`, `guidanceEmbed`, `speedUpWithGuidanceEmbed`, `sharpness`, `stochasticSamplingGamma`, `clipSkip`, `t5TextEncoder`, `separateClipL`/`clipLText`, `separateOpenClipG`/`openClipGText`, `separateT5`/`t5Text`, `zeroNegativePrompt`, `aestheticScore`, `negativeAestheticScore`, `cropTop`, `cropLeft`, `originalImage…`, `targetImage…`, `negativeOriginalImage…`, `tiledDecoding`/`decodingTile…`, `tiledDiffusion`/`diffusionTile…`, `teaCache…`, `colorCalibration` (`.disabled`/`.lab`), `compressionArtifacts` (`CompressionMethod`), `compressionArtifactsQuality`).
- Produces: `CatalogBuilder.capabilities(_ spec: [String: Any]) -> ModelCapabilities`, `isUpscaler(_:)`, `isFaceRestorer(_:)`; `JobMapper.apply(_:to:)`.

- [ ] **Step 1: Scrivere i test che falliscono.** Sostituire `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift` con:

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
    [{"file": "sun_direction_lora_f16.ckpt", "name": "Sun direction", "version": "flux2_9b",
      "prefix": "match the sun direction ", "weight": 0.8},
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
        CatalogLoRA(
          file: describedLoRA, name: "Sun direction", family: "flux2_9b",
          trigger: "match the sun direction", defaultWeight: 0.8),
        CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil),
      ])
  }

  @Test func unreadableLoRAMetadataIsNotFatal() {
    let catalog = CatalogBuilder.build(
      files: [klein, bareLoRA], modelSpecs: specs, loraMetadata: Data("not json".utf8))
    #expect(catalog.models.count == 1)
    #expect(catalog.loras == [CatalogLoRA(file: bareLoRA, name: bareLoRA, family: nil)])
  }

  @Test func upscalersAndFaceRestorersComeFromTheFileNames() {
    let catalog = CatalogBuilder.build(
      files: [klein, vae, "realesrgan_x4plus_f16.ckpt", "4x_ultrasharp_f16.ckpt", "restoreformer_v1.0_f16.ckpt", "parsenet_v1.0_f16.ckpt"],
      modelSpecs: specs, loraMetadata: Data())
    #expect(catalog.upscalers == ["4x_ultrasharp_f16.ckpt", "realesrgan_x4plus_f16.ckpt"])
    #expect(catalog.faceRestorers == ["restoreformer_v1.0_f16.ckpt"])
  }

  @Test func capabilitiesComeFromTheSpec() {
    let flux1 = CatalogBuilder.capabilities([
      "guidance_embed": true, "tea_cache_coefficients": [1.0], "clip_encoder": "clip_vit_l14_f16.ckpt",
      "text_encoder": "t5_xxl_encoder_q6p.ckpt", "default_scale": 16,
    ])
    #expect(flux1 == ModelCapabilities(
      guidanceEmbed: true, teaCache: true, clipL: true, openClipG: false, t5: true,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
    let sd3 = CatalogBuilder.capabilities([
      "clip_encoder": "clip_vit_l14_f16.ckpt", "t5_encoder": "t5_xxl_encoder_q6p.ckpt",
      "text_encoder": "open_clip_vit_bigg14_f16.ckpt", "default_scale": 16,
    ])
    #expect(sd3.clipL && sd3.openClipG && sd3.t5 && sd3.optionalT5 && sd3.clipSkip)
    let klein = CatalogBuilder.capabilities(["text_encoder": "qwen_3_8b_q8p.ckpt", "default_scale": 16])
    #expect(klein == ModelCapabilities(
      guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false,
      optionalT5: false, clipSkip: false, nativeSize: 1024))
  }

  @Test func noFilesMeansModelBrowsingIsOff() {
    let catalog = CatalogBuilder.build(files: [], modelSpecs: [:], loraMetadata: Data())
    #expect(catalog.isModelBrowsingDisabled)
  }

  @Test func specInfoFallsBackToTheFileName() {
    let named = CatalogBuilder.specInfo(json: Data(#"{"name": "Z Image", "version": "z_image"}"#.utf8), file: "z.ckpt")
    let unnamed = CatalogBuilder.specInfo(json: Data(#"{"file": "z.ckpt"}"#.utf8), file: "z.ckpt")
    #expect(named.name == "Z Image" && named.family == "z_image")
    #expect(unnamed.name == "z.ckpt" && unnamed.family == nil)
  }
}
```

- [ ] **Step 2: Sostituire `Packages/Tests/DTBridgeTests/JobMapperTests.swift` con:**

```swift
import DrawThingsClient
import HubKit
import Testing

@testable import DTBridge

struct JobMapperTests {
  @Test func mapsEveryBaseParameter() {
    let parameters = GenerationParameters(
      width: 832, height: 1216, steps: 4, guidanceScale: 1.5, cfgZeroStar: true, cfgZeroInitSteps: 2,
      sampler: .ddimTrailing, shift: 2, resolutionDependentShift: false,
      seed: 42, randomSeed: false, batchSize: 2, batchCount: 3)
    let request = JobMapper.request(
      for: GenerationJob(prompt: "a lighthouse", model: "flux_2_klein_9b_f16.ckpt", parameters: parameters))
    let configuration = request.configuration
    #expect(request.prompt == "a lighthouse")
    #expect(configuration.model == "flux_2_klein_9b_f16.ckpt")
    #expect(configuration.width == 832)
    #expect(configuration.height == 1216)
    #expect(configuration.steps == 4)
    #expect(configuration.guidanceScale == 1.5)
    #expect(configuration.sampler == .ddimtrailing)
    #expect(configuration.shift == 2)
    #expect(configuration.seed == 42)
    #expect(configuration.batchSize == 2)
    #expect(configuration.batchCount == 3)
    #expect(configuration.cfgZeroStar)
    #expect(configuration.cfgZeroInitSteps == 2)
    #expect(!configuration.resolutionDependentShift)
  }

  @Test func sendsTheNegativePromptAndTheLoRAs() {
    let parameters = GenerationParameters(loras: [
      LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
    ])
    let request = JobMapper.request(
      for: GenerationJob(prompt: "a fox", negativePrompt: "blurry", model: "m.ckpt", parameters: parameters))
    #expect(request.prompt == "a fox")
    #expect(request.negativePrompt == "blurry")
    #expect(request.configuration.loras == [
      LoRAConfig(file: "style.safetensors", weight: 0.75, mode: .base),
      LoRAConfig(file: "detail.safetensors", weight: 1, mode: .all),
    ])
  }

  @Test func triggerWordsArePutInFrontOfThePrompt() {
    let parameters = GenerationParameters(loras: [LoRASelection(file: "tarot.safetensors", trigger: "vintage tarot style")])
    let request = JobMapper.request(for: GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: parameters))
    #expect(request.prompt == "vintage tarot style a fox")
  }

  @Test func sendsTheAdvancedValues() {
    var advanced = AdvancedParameters()
    advanced.refinerModel = "refiner.ckpt"
    advanced.refinerStart = 0.6
    advanced.hiresFix = true
    advanced.hiresFixWidth = 512
    advanced.hiresFixHeight = 768
    advanced.upscaler = "realesrgan_x4plus_f16.ckpt"
    advanced.upscalerScaleFactor = 2
    advanced.guidanceEmbed = 4.5
    advanced.clipSkip = 2
    advanced.separateT5 = true
    advanced.t5Text = "long text"
    advanced.clipLText = "ignored without its switch"
    advanced.aestheticScore = 7
    advanced.tiledDecoding = true
    advanced.teaCache = true
    advanced.teaCacheThreshold = 0.2
    advanced.colorCalibration = true
    advanced.compressionArtifacts = .jpeg
    advanced.compressionQuality = 60
    let configuration = JobMapper.request(
      for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: GenerationParameters(width: 1024, height: 1024, advanced: advanced))
    ).configuration
    #expect(configuration.refinerModel == "refiner.ckpt")
    #expect(abs(configuration.refinerStart - 0.6) < 0.0001)
    #expect(configuration.hiresFix)
    #expect(configuration.hiresFixWidth == 512)
    #expect(configuration.hiresFixHeight == 768)
    #expect(configuration.upscaler == "realesrgan_x4plus_f16.ckpt")
    #expect(configuration.upscalerScaleFactor == 2)
    #expect(configuration.faceRestoration == nil)
    #expect(configuration.guidanceEmbed == 4.5)
    #expect(configuration.clipSkip == 2)
    #expect(configuration.separateT5)
    #expect(configuration.t5Text == "long text")
    #expect(configuration.clipLText == nil)
    #expect(configuration.aestheticScore == 7)
    #expect(configuration.tiledDecoding)
    #expect(configuration.teaCache)
    #expect(abs(configuration.teaCacheThreshold - 0.2) < 0.0001)
    #expect(configuration.colorCalibration == .lab)
    #expect(configuration.compressionArtifacts == .jpeg)
    #expect(configuration.compressionArtifactsQuality == 60)
  }

  @Test func defaultAdvancedValuesMatchTheLibrarysDefaults() {
    let sent = JobMapper.request(for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)).configuration
    let library = DrawThingsConfiguration()
    #expect(sent.refinerModel == library.refinerModel)
    #expect(sent.refinerStart == library.refinerStart)
    #expect(sent.hiresFix == library.hiresFix)
    #expect(sent.hiresFixStrength == library.hiresFixStrength)
    #expect(sent.upscaler == library.upscaler)
    #expect(sent.guidanceEmbed == library.guidanceEmbed)
    #expect(sent.speedUpWithGuidanceEmbed == library.speedUpWithGuidanceEmbed)
    #expect(sent.sharpness == library.sharpness)
    #expect(sent.stochasticSamplingGamma == library.stochasticSamplingGamma)
    #expect(sent.clipSkip == library.clipSkip)
    #expect(sent.t5TextEncoder == library.t5TextEncoder)
    #expect(sent.aestheticScore == library.aestheticScore)
    #expect(sent.negativeAestheticScore == library.negativeAestheticScore)
    #expect(sent.decodingTileWidth == library.decodingTileWidth)
    #expect(sent.diffusionTileOverlap == library.diffusionTileOverlap)
    #expect(sent.teaCacheStart == library.teaCacheStart)
    #expect(sent.teaCacheEnd == library.teaCacheEnd)
    #expect(sent.teaCacheThreshold == library.teaCacheThreshold)
    #expect(sent.teaCacheMaxSkipSteps == library.teaCacheMaxSkipSteps)
    #expect(sent.colorCalibration == library.colorCalibration)
    #expect(sent.compressionArtifacts == library.compressionArtifacts)
    #expect(sent.compressionArtifactsQuality == library.compressionArtifactsQuality)
  }

  @Test func clampsOutOfRangeValuesBeforeSending() {
    let parameters = GenerationParameters(width: 1000, height: 5000, steps: 0, batchSize: 9)
    let configuration = JobMapper.request(
      for: GenerationJob(prompt: "", model: "m.ckpt", parameters: parameters)
    ).configuration
    #expect(configuration.width == 1024)
    #expect(configuration.height == 2048)
    #expect(configuration.steps == 1)
    #expect(configuration.batchSize == 4)
  }

  @Test func samplingProgressCarriesTheStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .sampling(step: 3), totalSteps: 8)))
    guard case .progress(let step, let total)? = update else { Issue.record("not progress"); return }
    #expect(step == 3)
    #expect(total == 8)
  }

  @Test func otherStagesHaveNoStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .textEncoding, totalSteps: 8)))
    guard case .progress(let step, _)? = update else { Issue.record("not progress"); return }
    #expect(step == nil)
  }

  @Test func secondPassSamplingCarriesTheStep() throws {
    let update = try JobMapper.update(for: .progress(GenerationProgress(stage: .secondPassSampling(step: 2), totalSteps: 8)))
    guard case .progress(let step, _)? = update else { Issue.record("not progress"); return }
    #expect(step == 2)
  }

  @Test func aServerThatFinishesWithoutAnImageMeansNoImages() {
    let error = DrawThingsError.incompleteResponse("the server finished without returning an image; check the server log")
    #expect(JobMapper.backendError(for: error) as? BackendError == .noImages)
    let broken = DrawThingsError.incompleteResponse("the stream ended in the middle of a chunked tensor")
    #expect(JobMapper.backendError(for: broken) as? BackendError != .noImages)
  }

  @Test func libraryErrorsBecomeBackendErrors() {
    #expect(JobMapper.backendError(for: DrawThingsError.connectionFailed("down")) as? BackendError == .unreachable("down"))
    #expect(JobMapper.backendError(for: DrawThingsError.unauthenticated) as? BackendError == .unauthorized)
    #expect(JobMapper.backendError(for: CancellationError()) is CancellationError)
  }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "error:" | head -3`
Expected: `type 'CatalogBuilder' has no member 'capabilities'`.

- [ ] **Step 4: Sostituire `Packages/Sources/DTBridge/CatalogBuilder.swift` con:**

```swift
import Foundation
import HubKit

/// Name, family and capabilities of a model file, read from its Draw Things model specification.
struct ModelSpecInfo: Equatable, Sendable {
  let name: String
  let family: String?
  var capabilities: ModelCapabilities = .unknown
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
        modelSpecs[file].map {
          CatalogModel(file: file, name: $0.name, family: $0.family, capabilities: $0.capabilities)
        }
      }
    let others = files.filter { !loraFiles.contains($0) && modelSpecs[$0] == nil }
    let unlistedLoRAs = files
      .filter { $0.contains("_lora_") && !loraFiles.contains($0) && modelSpecs[$0] == nil }
      .map { CatalogLoRA(file: $0, name: $0, family: nil) }

    return ModelCatalog(
      models: models, loras: loraEntries + unlistedLoRAs, fileCount: files.count,
      upscalers: others.filter(isUpscaler).sorted(), faceRestorers: others.filter(isFaceRestorer).sorted())
  }

  /// Upscalers of Draw Things' zoo (Real-ESRGAN, UltraSharp, Remacri, NMKD…), by file name.
  static func isUpscaler(_ file: String) -> Bool {
    let name = file.lowercased()
    guard !name.contains("_lora_") else { return false }
    return ["esrgan", "upscal", "ultrasharp", "remacri", "superscale", "4x_", "2x_"].contains { name.contains($0) }
  }

  /// Face restorers of Draw Things' zoo (RestoreFormer, CodeFormer, GFPGAN), by file name;
  /// ParseNet is their helper, not a choice.
  static func isFaceRestorer(_ file: String) -> Bool {
    let name = file.lowercased()
    return ["restoreformer", "codeformer", "gfpgan"].contains { name.contains($0) }
  }

  /// The server's LoRA metadata: a JSON array of objects with `file`, `name`, `version`,
  /// `prefix` (the trigger word) and, for some, `weight`.
  /// Unreadable data or entries without `file` are skipped, never fatal.
  static func parseLoRAMetadata(_ data: Data) -> [CatalogLoRA] {
    guard !data.isEmpty,
      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return array.compactMap { entry in
      guard let file = entry["file"] as? String else { return nil }
      return CatalogLoRA(
        file: file, name: entry["name"] as? String ?? file, family: entry["version"] as? String,
        trigger: (entry["prefix"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
        defaultWeight: (entry["weight"] as? NSNumber)?.doubleValue)
    }
  }

  /// Name, family and capabilities from a spec's JSON object; the file name stands in for a
  /// missing name.
  static func specInfo(json: Data, file: String) -> ModelSpecInfo {
    let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    return ModelSpecInfo(
      name: object["name"] as? String ?? file, family: object["version"] as? String,
      capabilities: capabilities(object))
  }

  /// What the spec says the model supports: guidance embed, TeaCache coefficients, its text
  /// encoders (CLIP-L, OpenCLIP-G, T5) and its native size (`default_scale` × 64).
  static func capabilities(_ spec: [String: Any]) -> ModelCapabilities {
    let textEncoder = spec["text_encoder"] as? String ?? ""
    let encoders = [textEncoder, spec["clip_encoder"] as? String ?? "", spec["t5_encoder"] as? String ?? ""]
      + (spec["additional_clip_encoders"] as? [String] ?? [])
    func has(_ fragment: String) -> Bool { encoders.contains { $0.contains(fragment) } }
    return ModelCapabilities(
      guidanceEmbed: spec["guidance_embed"] as? Bool ?? false,
      teaCache: spec["tea_cache_coefficients"] != nil,
      clipL: has("clip_vit_l14"),
      openClipG: has("open_clip_vit_bigg14"),
      t5: has("t5_xxl"),
      optionalT5: spec["t5_encoder"] != nil,
      clipSkip: textEncoder.contains("clip_vit") || textEncoder.contains("open_clip"),
      nativeSize: (spec["default_scale"] as? Int).map { $0 * 64 })
  }
}
```

- [ ] **Step 5: Sostituire `Packages/Sources/DTBridge/JobMapper.swift` con:**

```swift
import DrawThingsClient
import HubKit

/// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
enum JobMapper {
  static func request(for job: GenerationJob) -> GenerationRequest {
    let parameters = job.parameters.clamped()
    var configuration = DrawThingsConfiguration(
      width: Int32(parameters.width),
      height: Int32(parameters.height),
      steps: Int32(parameters.steps),
      model: job.model,
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
    return GenerationRequest(prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt, configuration: configuration)
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

- [ ] **Step 6: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: DTBridge `22 tests … passed`; totale 38 + 94 + 22 + 6 = **160**.

- [ ] **Step 7: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: DTBridge legge le capacità dei modelli, riconosce upscaler e restauro, invia i valori avanzati

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Testi delle card Avanzate (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (56 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `advanced.*` usate da `AdvancedSection` e `AdvancedCardView` (Task 6); `advanced.modifiedCount` (`%lld`) e `advanced.hidden` (`%@` = elenco dei campi) si usano con `String(format:)`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

```bash
cd "<repo>" && python3 - <<'EOF'
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "advanced.autoSizeHint": ("0 = automatic", "0 = automatica"),
    "advanced.card.guidance": ("Extra guidance", "Guidance extra"),
    "advanced.card.hiresFix": ("Hires fix", "Hires fix"),
    "advanced.card.output": ("Output", "Output"),
    "advanced.card.performance": ("Performance", "Prestazioni"),
    "advanced.card.refiner": ("Refiner", "Refiner"),
    "advanced.card.sdxl": ("SDXL conditioning", "Condizionamento SDXL"),
    "advanced.card.textEncoder": ("Text encoder", "Text encoder"),
    "advanced.card.upscale": ("Upscaler and restoration", "Upscaler e restauro"),
    "advanced.compression.none": ("None", "Nessuno"),
    "advanced.compression.quality": ("Quality", "Qualità"),
    "advanced.enabled": ("On", "Attivo"),
    "advanced.field.clipSkip": ("CLIP skip", "CLIP skip"),
    "advanced.field.colorCalibration": ("Color calibration (Lab)", "Calibrazione del colore (Lab)"),
    "advanced.field.compressionArtifacts": ("Compression artifacts", "Artefatti di compressione"),
    "advanced.field.faceRestoration": ("Face restoration", "Restauro volti"),
    "advanced.field.guidanceEmbed": ("Guidance embed", "Guidance embed"),
    "advanced.field.hiresFix": ("Hires fix", "Hires fix"),
    "advanced.field.refiner": ("Refiner", "Refiner"),
    "advanced.field.sdxlConditioning": ("SDXL conditioning", "Condizionamento SDXL"),
    "advanced.field.separateClipL": ("Separate CLIP-L text", "Testo CLIP-L separato"),
    "advanced.field.separateOpenClipG": ("Separate OpenCLIP-G text", "Testo OpenCLIP-G separato"),
    "advanced.field.separateT5": ("Separate T5 text", "Testo T5 separato"),
    "advanced.field.sharpness": ("Sharpness", "Nitidezza"),
    "advanced.field.stochasticSamplingGamma": ("Stochastic sampling gamma", "Gamma del campionamento stocastico"),
    "advanced.field.t5TextEncoder": ("T5 text encoder", "Text encoder T5"),
    "advanced.field.teaCache": ("TeaCache", "TeaCache"),
    "advanced.field.tiledDecoding": ("Tiled decoding", "Decodifica a tile"),
    "advanced.field.tiledDiffusion": ("Tiled diffusion", "Diffusione a tile"),
    "advanced.field.upscaler": ("Upscaler", "Upscaler"),
    "advanced.field.zeroNegativePrompt": ("Zero negative prompt", "Prompt negativo a zero"),
    "advanced.guidance.speedUp": ("Speed up", "Accelera"),
    "advanced.hidden": ("Changed values this model does not use (kept, not sent): %@.", "Valori modificati che questo modello non usa (conservati, non inviati): %@."),
    "advanced.hidden.reset": ("Reset", "Ripristina"),
    "advanced.hiresFix.start": ("Start size", "Dimensioni di partenza"),
    "advanced.hiresFix.strength": ("Strength", "Strength"),
    "advanced.modifiedCount": ("%lld changed", "%lld modificate"),
    "advanced.none": ("None", "Nessuno"),
    "advanced.refiner.model": ("Refiner model", "Modello refiner"),
    "advanced.refiner.start": ("Refiner start", "Inizio refiner"),
    "advanced.sdxl.aesthetic": ("Aesthetic score", "Punteggio estetico"),
    "advanced.sdxl.crop": ("Crop (left × top)", "Ritaglio (sinistra × alto)"),
    "advanced.sdxl.negativeAesthetic": ("Negative aesthetic score", "Punteggio estetico negativo"),
    "advanced.sdxl.negativeOriginal": ("Negative original size", "Dimensioni originali negative"),
    "advanced.sdxl.original": ("Original size", "Dimensioni originali"),
    "advanced.sdxl.target": ("Target size", "Dimensioni di destinazione"),
    "advanced.separateText.placeholder": ("Text for this encoder only", "Testo solo per questo encoder"),
    "advanced.show": ("Show advanced settings", "Mostra impostazioni avanzate"),
    "advanced.teaCache.end": ("End step (−1 = last)", "Step finale (−1 = ultimo)"),
    "advanced.teaCache.maxSkip": ("Max skipped steps", "Step saltati al massimo"),
    "advanced.teaCache.start": ("Start step", "Step iniziale"),
    "advanced.teaCache.threshold": ("Threshold", "Soglia"),
    "advanced.tile.overlap": ("Overlap", "Sovrapposizione"),
    "advanced.tile.size": ("Tile size", "Dimensioni tile"),
    "advanced.upscaler.factor": ("Scale", "Fattore"),
    "advanced.upscaler.factor.auto": ("Upscaler's own", "Dell'upscaler"),
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

Expected: `1 file changed, 952 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "<repo>/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add App/Localizable.xcstrings && git commit -m "feat: testi delle card Avanzate (it, en)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Sezione Avanzate nel tab Generazione (App)

**Files:**
- Create: `App/Generation/Advanced/AdvancedSection.swift`
- Create: `App/Generation/Advanced/AdvancedCardView.swift`
- Modify: `App/Generation/GenerationController.swift` (`selectedModel(in:)`)
- Modify: `App/MainWindow/GenerationTabView.swift` (sezione dopo le card di base)

**Interfaces:**
- Consumes: `AdvancedCard`, `AdvancedField`, `AdvancedParameters.reset/modifiedFields/hiddenModifiedFields` (Task 2); `ModelCatalog.upscalers/faceRestorers`, `CompressionArtifacts` e gli intervalli di `AdvancedParameters` (Task 1); le chiavi del Task 5; `IntField`, `DecimalField`, `CardRow`, `DSCollapsibleCard`, `DSCardRow`, `DSCheckboxToggleStyle`, `DSPillButtonStyle` (M3).
- Produces: `GenerationController.selectedModel(in:) -> CatalogModel?`; `AdvancedSection(controller:connection:)`; `AdvancedCardView(card:controller:connection:)`.

- [ ] **Step 1: In `App/Generation/GenerationController.swift` aggiungere `selectedModel(in:)` e farne usare a `family(in:)`**

Sostituire:

```swift
  /// The family of the chosen model, nil when unknown or while the catalog is not loaded.
  func family(in connection: DrawThingsConnection) -> String? {
    connection.selection.selectedModel(in: connection.monitor.catalog)?.family
  }
```

con:

```swift
  /// The chosen model as the server describes it; nil while the catalog is not loaded.
  func selectedModel(in connection: DrawThingsConnection) -> CatalogModel? {
    connection.selection.selectedModel(in: connection.monitor.catalog)
  }

  /// The family of the chosen model, nil when unknown or while the catalog is not loaded.
  func family(in connection: DrawThingsConnection) -> String? {
    selectedModel(in: connection)?.family
  }
```

- [ ] **Step 2: Creare `App/Generation/Advanced/AdvancedSection.swift`**

```swift
import HubCore
import HubKit
import SwiftUI

/// The Advanced cards behind a switch (decided with the user, 1 October 2026): off, only the
/// switch and how many advanced values are changed; on, the cards that apply to the chosen
/// model, two per row, and a warning for changed values the model does not use (spec §6).
struct AdvancedSection: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var model: CatalogModel? { controller.selectedModel(in: connection) }
  private var advanced: AdvancedParameters { controller.parameters.advanced }
  private var isOn: Binding<Bool> { controller.cards.binding("advanced", default: false) }

  private var visibleCards: [AdvancedCard] {
    AdvancedCard.allCases.filter { card in
      card.fields.contains { $0.isShown(for: model, sampler: controller.parameters.sampler) }
    }
  }

  var body: some View {
    VStack(spacing: DS.groupGap) {
      HStack(spacing: DS.controlGap) {
        Toggle(isOn: isOn) {
          Text("advanced.show")
        }
        .toggleStyle(DSCheckboxToggleStyle())
        let modified = advanced.modifiedFields.count
        if !isOn.wrappedValue, modified > 0 {
          Text(String(format: String(localized: "advanced.modifiedCount"), modified))
            .font(.caption)
            .foregroundStyle(DS.accent)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, DS.panelPadding)

      if isOn.wrappedValue {
        hiddenValuesWarning
        let cards = visibleCards
        ForEach(Array(stride(from: 0, to: cards.count, by: 2)), id: \.self) { index in
          DSCardRow {
            AdvancedCardView(card: cards[index], controller: controller, connection: connection)
            if index + 1 < cards.count {
              AdvancedCardView(card: cards[index + 1], controller: controller, connection: connection)
            } else {
              Color.clear
            }
          }
        }
      }
    }
  }

  /// Changed values the chosen model does not use: kept, not sent, one click to reset.
  @ViewBuilder private var hiddenValuesWarning: some View {
    let hidden = advanced.hiddenModifiedFields(for: model, sampler: controller.parameters.sampler)
    if !hidden.isEmpty {
      HStack(alignment: .firstTextBaseline, spacing: DS.controlGap) {
        Image(systemName: "eye.slash")
          .foregroundStyle(DS.remove)
          .accessibilityHidden(true)
        Text(
          String(
            format: String(localized: "advanced.hidden"),
            hidden.map(\.title).formatted(.list(type: .and))))
          .font(.callout)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: DS.controlGap)
        Button {
          for field in hidden { controller.parameters.advanced.reset(field) }
        } label: {
          Text("advanced.hidden.reset")
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

extension AdvancedField {
  /// The field's name, for the hidden-values warning.
  var title: String {
    switch self {
    case .refiner: String(localized: "advanced.field.refiner")
    case .hiresFix: String(localized: "advanced.field.hiresFix")
    case .upscaler: String(localized: "advanced.field.upscaler")
    case .faceRestoration: String(localized: "advanced.field.faceRestoration")
    case .guidanceEmbed: String(localized: "advanced.field.guidanceEmbed")
    case .sharpness: String(localized: "advanced.field.sharpness")
    case .stochasticSamplingGamma: String(localized: "advanced.field.stochasticSamplingGamma")
    case .clipSkip: String(localized: "advanced.field.clipSkip")
    case .t5TextEncoder: String(localized: "advanced.field.t5TextEncoder")
    case .separateClipL: String(localized: "advanced.field.separateClipL")
    case .separateOpenClipG: String(localized: "advanced.field.separateOpenClipG")
    case .separateT5: String(localized: "advanced.field.separateT5")
    case .zeroNegativePrompt: String(localized: "advanced.field.zeroNegativePrompt")
    case .sdxlConditioning: String(localized: "advanced.field.sdxlConditioning")
    case .tiledDecoding: String(localized: "advanced.field.tiledDecoding")
    case .tiledDiffusion: String(localized: "advanced.field.tiledDiffusion")
    case .teaCache: String(localized: "advanced.field.teaCache")
    case .colorCalibration: String(localized: "advanced.field.colorCalibration")
    case .compressionArtifacts: String(localized: "advanced.field.compressionArtifacts")
    }
  }
}
```

- [ ] **Step 3: Creare `App/Generation/Advanced/AdvancedCardView.swift`**

```swift
import HubCore
import HubKit
import SwiftUI

/// One Advanced card: its title and icon, and the rows of the fields the chosen model uses.
struct AdvancedCardView: View {
  let card: AdvancedCard
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var model: CatalogModel? { controller.selectedModel(in: connection) }
  private var catalog: ModelCatalog { connection.monitor.catalog }
  private var advanced: Binding<AdvancedParameters> { $controller.parameters.advanced }

  private func shows(_ field: AdvancedField) -> Bool {
    field.isShown(for: model, sampler: controller.parameters.sampler)
  }

  var body: some View {
    DSCollapsibleCard(title, systemImage: systemImage, isExpanded: controller.cards.binding("advanced.\(card.rawValue)")) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        switch card {
        case .refiner: refinerRows
        case .hiresFix: hiresFixRows
        case .upscale: upscaleRows
        case .guidance: guidanceRows
        case .textEncoder: textEncoderRows
        case .sdxl: sdxlRows
        case .performance: performanceRows
        case .output: outputRows
        }
      }
    }
  }

  private var title: String {
    switch card {
    case .refiner: String(localized: "advanced.card.refiner")
    case .hiresFix: String(localized: "advanced.card.hiresFix")
    case .upscale: String(localized: "advanced.card.upscale")
    case .guidance: String(localized: "advanced.card.guidance")
    case .textEncoder: String(localized: "advanced.card.textEncoder")
    case .sdxl: String(localized: "advanced.card.sdxl")
    case .performance: String(localized: "advanced.card.performance")
    case .output: String(localized: "advanced.card.output")
    }
  }

  private var systemImage: String {
    switch card {
    case .refiner: "wand.and.stars"
    case .hiresFix: "arrow.up.left.and.arrow.down.right"
    case .upscale: "arrow.up.forward.app"
    case .guidance: "scope"
    case .textEncoder: "character.cursor.ibeam"
    case .sdxl: "square.resize"
    case .performance: "speedometer"
    case .output: "paintpalette"
    }
  }

  // MARK: Refiner

  @ViewBuilder private var refinerRows: some View {
    CardRow(label: String(localized: "advanced.refiner.model")) {
      FilePicker(
        label: String(localized: "advanced.refiner.model"), selection: advanced.refinerModel,
        options: catalog.models.map { ($0.file, $0.name) })
    }
    if !advanced.wrappedValue.refinerModel.isEmpty {
      CardRow(label: String(localized: "advanced.refiner.start")) {
        DecimalField(
          label: String(localized: "advanced.refiner.start"), value: advanced.refinerStart,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Hires fix

  @ViewBuilder private var hiresFixRows: some View {
    CardRow(label: String(localized: "advanced.field.hiresFix")) {
      Toggle(isOn: advanced.hiresFix) { Text("advanced.enabled") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
    if advanced.wrappedValue.hiresFix {
      CardRow(label: String(localized: "advanced.hiresFix.start")) {
        SizePair(width: advanced.hiresFixWidth, height: advanced.hiresFixHeight, range: GenerationParameters.sizeRange.upperBound)
      }
      Text("advanced.autoSizeHint")
        .font(.caption)
        .foregroundStyle(.secondary)
      CardRow(label: String(localized: "advanced.hiresFix.strength")) {
        DecimalField(
          label: String(localized: "advanced.hiresFix.strength"), value: advanced.hiresFixStrength,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Upscaler and face restoration

  @ViewBuilder private var upscaleRows: some View {
    CardRow(label: String(localized: "advanced.field.upscaler")) {
      FilePicker(
        label: String(localized: "advanced.field.upscaler"), selection: advanced.upscaler,
        options: catalog.upscalers.map { ($0, Self.displayName($0)) })
    }
    if !advanced.wrappedValue.upscaler.isEmpty {
      CardRow(label: String(localized: "advanced.upscaler.factor")) {
        Picker(selection: advanced.upscalerScaleFactor) {
          Text("advanced.upscaler.factor.auto").tag(0)
          Text(verbatim: "2×").tag(2)
          Text(verbatim: "4×").tag(4)
        } label: {
          EmptyView()
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(String(localized: "advanced.upscaler.factor"))
      }
    }
    CardRow(label: String(localized: "advanced.field.faceRestoration")) {
      FilePicker(
        label: String(localized: "advanced.field.faceRestoration"), selection: advanced.faceRestoration,
        options: catalog.faceRestorers.map { ($0, Self.displayName($0)) })
    }
  }

  /// "realesrgan_x4plus_f16.ckpt" → "realesrgan_x4plus".
  static func displayName(_ file: String) -> String {
    var name = file
    for suffix in [".ckpt", "_f16", "_q8p", "_q6p"] where name.hasSuffix(suffix) {
      name.removeLast(suffix.count)
    }
    return name
  }

  // MARK: Extra guidance

  @ViewBuilder private var guidanceRows: some View {
    if shows(.guidanceEmbed) {
      CardRow(label: String(localized: "advanced.field.guidanceEmbed")) {
        Toggle(isOn: advanced.speedUpWithGuidanceEmbed) { Text("advanced.guidance.speedUp") }
          .toggleStyle(DSCheckboxToggleStyle())
      } control: {
        DecimalField(
          label: String(localized: "advanced.field.guidanceEmbed"), value: advanced.guidanceEmbed,
          range: AdvancedParameters.guidanceEmbedRange, step: 0.5)
      }
    }
    CardRow(label: String(localized: "advanced.field.sharpness")) {
      DecimalField(
        label: String(localized: "advanced.field.sharpness"), value: advanced.sharpness,
        range: AdvancedParameters.sharpnessRange, step: 0.5)
    }
    if shows(.stochasticSamplingGamma) {
      CardRow(label: String(localized: "advanced.field.stochasticSamplingGamma")) {
        DecimalField(
          label: String(localized: "advanced.field.stochasticSamplingGamma"), value: advanced.stochasticSamplingGamma,
          range: AdvancedParameters.unitRange, step: 0.05, fractionDigits: 2)
      }
    }
  }

  // MARK: Text encoders

  @ViewBuilder private var textEncoderRows: some View {
    if shows(.clipSkip) {
      CardRow(label: String(localized: "advanced.field.clipSkip")) {
        IntField(label: String(localized: "advanced.field.clipSkip"), value: advanced.clipSkip, range: AdvancedParameters.clipSkipRange)
      }
    }
    if shows(.t5TextEncoder) {
      Toggle(isOn: advanced.t5TextEncoder) { Text("advanced.field.t5TextEncoder") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
    if shows(.separateClipL) {
      SeparateText(
        title: String(localized: "advanced.field.separateClipL"), isOn: advanced.separateClipL, text: advanced.clipLText)
    }
    if shows(.separateOpenClipG) {
      SeparateText(
        title: String(localized: "advanced.field.separateOpenClipG"), isOn: advanced.separateOpenClipG,
        text: advanced.openClipGText)
    }
    if shows(.separateT5) {
      SeparateText(title: String(localized: "advanced.field.separateT5"), isOn: advanced.separateT5, text: advanced.t5Text)
    }
    if shows(.zeroNegativePrompt) {
      Toggle(isOn: advanced.zeroNegativePrompt) { Text("advanced.field.zeroNegativePrompt") }
        .toggleStyle(DSCheckboxToggleStyle())
    }
  }

  // MARK: SDXL conditioning

  @ViewBuilder private var sdxlRows: some View {
    CardRow(label: String(localized: "advanced.sdxl.aesthetic")) {
      DecimalField(
        label: String(localized: "advanced.sdxl.aesthetic"), value: advanced.aestheticScore,
        range: AdvancedParameters.aestheticRange, step: 0.5)
    }
    CardRow(label: String(localized: "advanced.sdxl.negativeAesthetic")) {
      DecimalField(
        label: String(localized: "advanced.sdxl.negativeAesthetic"), value: advanced.negativeAestheticScore,
        range: AdvancedParameters.aestheticRange, step: 0.5)
    }
    CardRow(label: String(localized: "advanced.sdxl.crop")) {
      SizePair(width: advanced.cropLeft, height: advanced.cropTop, range: AdvancedParameters.conditioningRange.upperBound)
    }
    CardRow(label: String(localized: "advanced.sdxl.original")) {
      SizePair(width: advanced.originalWidth, height: advanced.originalHeight, range: AdvancedParameters.conditioningRange.upperBound)
    }
    CardRow(label: String(localized: "advanced.sdxl.target")) {
      SizePair(width: advanced.targetWidth, height: advanced.targetHeight, range: AdvancedParameters.conditioningRange.upperBound)
    }
    CardRow(label: String(localized: "advanced.sdxl.negativeOriginal")) {
      SizePair(
        width: advanced.negativeOriginalWidth, height: advanced.negativeOriginalHeight,
        range: AdvancedParameters.conditioningRange.upperBound)
    }
    Text("advanced.autoSizeHint")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  // MARK: Performance

  @ViewBuilder private var performanceRows: some View {
    Toggle(isOn: advanced.tiledDecoding) { Text("advanced.field.tiledDecoding") }
      .toggleStyle(DSCheckboxToggleStyle())
    if advanced.wrappedValue.tiledDecoding {
      TileRows(width: advanced.decodingTileWidth, height: advanced.decodingTileHeight, overlap: advanced.decodingTileOverlap)
    }
    Toggle(isOn: advanced.tiledDiffusion) { Text("advanced.field.tiledDiffusion") }
      .toggleStyle(DSCheckboxToggleStyle())
    if advanced.wrappedValue.tiledDiffusion {
      TileRows(width: advanced.diffusionTileWidth, height: advanced.diffusionTileHeight, overlap: advanced.diffusionTileOverlap)
    }
    if shows(.teaCache) {
      Toggle(isOn: advanced.teaCache) { Text("advanced.field.teaCache") }
        .toggleStyle(DSCheckboxToggleStyle())
      if advanced.wrappedValue.teaCache {
        CardRow(label: String(localized: "advanced.teaCache.start")) {
          IntField(label: String(localized: "advanced.teaCache.start"), value: advanced.teaCacheStart, range: AdvancedParameters.teaCacheStepRange)
        }
        CardRow(label: String(localized: "advanced.teaCache.end")) {
          IntField(label: String(localized: "advanced.teaCache.end"), value: advanced.teaCacheEnd, range: AdvancedParameters.teaCacheEndRange)
        }
        CardRow(label: String(localized: "advanced.teaCache.threshold")) {
          DecimalField(
            label: String(localized: "advanced.teaCache.threshold"), value: advanced.teaCacheThreshold,
            range: AdvancedParameters.unitRange, step: 0.01, fractionDigits: 2)
        }
        CardRow(label: String(localized: "advanced.teaCache.maxSkip")) {
          IntField(label: String(localized: "advanced.teaCache.maxSkip"), value: advanced.teaCacheMaxSkipSteps, range: AdvancedParameters.teaCacheSkipRange)
        }
      }
    }
  }

  // MARK: Output

  @ViewBuilder private var outputRows: some View {
    Toggle(isOn: advanced.colorCalibration) { Text("advanced.field.colorCalibration") }
      .toggleStyle(DSCheckboxToggleStyle())
    CardRow(label: String(localized: "advanced.field.compressionArtifacts")) {
      Picker(selection: advanced.compressionArtifacts) {
        Text("advanced.compression.none").tag(CompressionArtifacts.none)
        Text(verbatim: "H.264").tag(CompressionArtifacts.h264)
        Text(verbatim: "H.265").tag(CompressionArtifacts.h265)
        Text(verbatim: "JPEG").tag(CompressionArtifacts.jpeg)
      } label: {
        EmptyView()
      }
      .labelsHidden()
      .fixedSize()
      .accessibilityLabel(String(localized: "advanced.field.compressionArtifacts"))
    }
    if advanced.wrappedValue.compressionArtifacts != .none {
      CardRow(label: String(localized: "advanced.compression.quality")) {
        DecimalField(
          label: String(localized: "advanced.compression.quality"), value: advanced.compressionQuality,
          range: AdvancedParameters.qualityRange, step: 1)
      }
    }
  }
}

/// A file chooser with "None" first; a chosen file the server no longer lists stays shown.
private struct FilePicker: View {
  let label: String
  @Binding var selection: String
  let options: [(file: String, name: String)]

  var body: some View {
    Picker(selection: $selection) {
      Text("advanced.none").tag("")
      ForEach(options, id: \.file) { option in
        Text(verbatim: option.name).tag(option.file)
      }
      if !selection.isEmpty, !options.contains(where: { $0.file == selection }) {
        Text(verbatim: selection).tag(selection)
      }
    } label: {
      EmptyView()
    }
    .labelsHidden()
    .fixedSize()
    .accessibilityLabel(label)
  }
}

/// Width × height in multiples of 64; 0 = automatic.
private struct SizePair: View {
  @Binding var width: Int
  @Binding var height: Int
  let range: Int

  var body: some View {
    HStack(spacing: 4) {
      IntField(
        label: String(localized: "card.dimensions.width"), value: $width, range: 0...range, step: 64,
        commit: { $0 == 0 ? 0 : GenerationParameters.snap(Double($0)) })
      Text(verbatim: "×").foregroundStyle(.secondary)
      IntField(
        label: String(localized: "card.dimensions.height"), value: $height, range: 0...range, step: 64,
        commit: { $0 == 0 ? 0 : GenerationParameters.snap(Double($0)) })
    }
  }
}

/// Tile width × height and overlap, for tiled decoding and diffusion.
private struct TileRows: View {
  @Binding var width: Int
  @Binding var height: Int
  @Binding var overlap: Int

  var body: some View {
    CardRow(label: String(localized: "advanced.tile.size")) {
      HStack(spacing: 4) {
        IntField(
          label: String(localized: "card.dimensions.width"), value: $width, range: AdvancedParameters.tileRange, step: 64,
          commit: { GenerationParameters.snap(Double($0)) })
        Text(verbatim: "×").foregroundStyle(.secondary)
        IntField(
          label: String(localized: "card.dimensions.height"), value: $height, range: AdvancedParameters.tileRange, step: 64,
          commit: { GenerationParameters.snap(Double($0)) })
      }
    }
    CardRow(label: String(localized: "advanced.tile.overlap")) {
      IntField(label: String(localized: "advanced.tile.overlap"), value: $overlap, range: AdvancedParameters.overlapRange, step: 64)
    }
  }
}

/// A checkbox for a separate encoder text and, when on, its text box.
private struct SeparateText: View {
  let title: String
  @Binding var isOn: Bool
  @Binding var text: String

  var body: some View {
    Toggle(isOn: $isOn) { Text(title) }
      .toggleStyle(DSCheckboxToggleStyle())
    if isOn {
      TextField(title, text: $text, prompt: Text("advanced.separateText.placeholder"), axis: .vertical)
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .lineLimit(2...5)
    }
  }
}
```

- [ ] **Step 4: Sostituire `App/MainWindow/GenerationTabView.swift` con:**

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

- [ ] **Step 5: Build e test**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in|Pass String"`
Expected: `** BUILD SUCCEEDED **`; test HubKit 38, HubCore 94, DTBridge 22, Catalog 6: **160** passati.

- [ ] **Step 6: Commit**

```bash
cd "<repo>" && git add App && git commit -m "feat: card Avanzate dietro l'interruttore, con avviso dei valori non usati

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verifica dal vivo

Nessun codice nuovo. Si prova l'app contro il server Draw Things (API Server acceso sulla 7859, model browsing attivo), salvando in una cartella temporanea.

Prima di iniziare si annotano e si copiano in una cartella temporanea:
- il modello scelto dall'utente;
- `session.json`;
- `cards.json`.

Alla fine si rimettono.

- [ ] **Step 1: Preparare e avviare**

```bash
defaults read com.exiztenz.DTHub drawThings.selectedModel; A="$HOME/Library/Application Support/DT Hub"; mkdir -p /tmp/dthub-m4b-backup && cp "$A/session.json" "$A/cards.json" /tmp/dthub-m4b-backup/; defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m4b-check && defaults write com.exiztenz.DTHub drawThings.selectedModel flux_1_dev_q5p.ckpt && open "<repo>/build/Build/Products/Debug/DT Hub.app"
```

- [ ] **Step 2: Checklist (screenshot)**

1. Sotto le card di base c'è "Mostra impostazioni avanzate", spento. Acceso:
   - le card compaiono due per riga, alte uguali;
   - con FLUX.1 [dev] si vedono Guidance embed con "Accelera", "Testo CLIP-L separato", "Testo T5 separato" e TeaCache;
   - non si vedono CLIP skip né Condizionamento SDXL.
2. Con Juggernaut Reborn (`v1`), scelto dalle Preferenze o dal menu modello:
   - compare CLIP skip;
   - spariscono Guidance embed, TeaCache e i testi separati.
3. CLIP skip a 2, poi FLUX.2 Klein:
   - compare l'avviso arancio "Valori modificati che questo modello non usa… CLIP skip";
   - "Ripristina" lo toglie.
4. Con l'interruttore spento, il conteggio "N modificate" segue i valori cambiati.
5. Con Juggernaut, 1024×1024, Hires fix attivo e dimensioni di partenza 0 (automatiche), RUN:
   - l'immagine è 1024×1024;
   - nel PNG, `exiftool -UserComment` mostra `advanced.hiresFix: true`;
   - DT non segnala errori.
6. Upscaler `realesrgan_x4plus` con fattore 2× su 512×512: l'immagine salvata è 1024×1024.

Punti che servono all'utente (interazione non automatizzabile in background): i menu Picker (refiner, upscaler, compressione) e i campi di testo separati.

- [ ] **Step 3: Pulizia** (rimettere il modello annotato allo Step 1 al posto di `<modello-annotato>`)

```bash
osascript -e 'quit app "DT Hub"'; A="$HOME/Library/Application Support/DT Hub"; cp /tmp/dthub-m4b-backup/session.json /tmp/dthub-m4b-backup/cards.json "$A/"; defaults delete com.exiztenz.DTHub output.folder; defaults write com.exiztenz.DTHub drawThings.selectedModel <modello-annotato>; rm -rf /tmp/dthub-m4b-check /tmp/dthub-m4b-backup
```

---

## Fine della M4b

Esito atteso sul branch `m4b-card-avanzate`:
- **160 test verdi**, di cui 3 live eseguiti solo con `DTHUB_LIVE_DT`;
- build Xcode pulita;
- livello 2 della spec §6 completo per il T2I, con Inpaint e ControlNet rimandati a un tab dedicato.

Poi: revisione indipendente, correzioni, merge, e il piano di M4c (editor JSON, preset, import di `custom_configs.json`).

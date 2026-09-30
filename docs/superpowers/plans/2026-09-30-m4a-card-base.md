# M4a Card di base complete — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il livello 1 della spec §6 è completo:
- prompt negativo dentro la card Prompt;
- card LoRA (più LoRA, con peso, modalità e trigger word, filtrate per famiglia);
- campi mostrati secondo la famiglia del modello;
- all'avvio si ritrovano l'ultimo prompt e gli ultimi parametri.

**Architecture:**
- **HubKit** riceve `LoRASelection`/`LoRAMode`. `GenerationParameters.loras` e `GenerationJob.negativePrompt` si aggiungono con una decodifica tollerante, così i file salvati da versioni diverse si caricano sempre. `CatalogLoRA` guadagna la trigger word e il peso suggerito. `GenerationJob.promptWithTriggers` compone ciò che riceve Draw Things.
- **HubCore** riceve tre pezzi:
  - la tabella famiglia → campi (`FamilyTraits`, chiave `version` di DT);
  - la compatibilità delle LoRA con il catalogo;
  - `JobComposer`, che dal contenuto del tab costruisce i batch, togliendo ciò che la famiglia non usa e le LoRA non utilizzabili.
- **HubCore** riceve anche `SessionStore`, che scrive `session.json`.
- **DTBridge** legge dai metadati del server la trigger word (`prefix`) e il peso suggerito (`weight`), e manda a Draw Things il negativo, le LoRA e il prompt con le trigger word davanti.
- **App:** il controller salva la sessione 0,5 s dopo l'ultima modifica e all'uscita. La card Prompt mostra il negativo, Campionamento nasconde Shift e CFG-Zero* dove non servono, e la nuova card LoRA occupa il posto libero accanto a Campionamento.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, DrawThings-Swift 2.2.x.

**Spec:** `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (sezioni 5, 6, 7, 11, 12, 15-M4). M4 è divisa in tre tappe (decisione dell'utente, 30 settembre 2026):
- **M4a** (questo piano): negativo, LoRA, visibilità per famiglia, ripristino sessione;
- **M4b:** card Avanzate e avviso "valori nascosti attivi";
- **M4c:** editor JSON, preset, import di `custom_configs.json`.

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi sempre tra virgolette);
  - branch `m4a-card-base` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo `DTBridge` importa DrawThings-Swift (spec §4).
- **La famiglia è la chiave di tutto (spec §5).**
  - Si usa il campo `version` del modello (es. `flux2_9b`). Verificato sul server: modelli e LoRA usano le stesse stringhe; 3 LoRA su 103 non hanno famiglia.
  - Una famiglia sconosciuta o assente (catalogo non ancora caricato) mostra tutti i campi.
- **Visibilità (spec §6), tabella in HubCore:**
  - Shift, "In base alla risoluzione" e CFG-Zero* solo per i modelli flow-matching. Sono nascosti per `v1`, `v2`, `sdxl_base_v0.9`, `sdxl_refiner_v0.9`, `ssd_1b`, `pixart`, `kandinsky2.1`, `wurstchen_v3.0_stage_c`, `wurstchen_v3.0_stage_b`, `svd_i2v`.
  - Prompt negativo nascosto per `seedvr2_3b`, `seedvr2_7b`, `svd_i2v`.
  - Un campo nascosto non viene inviato: negativo vuoto, CFG-Zero* spento.
- **Prompt negativo (deciso con l'utente, 30 settembre 2026):**
  - sta dentro la card Prompt, sotto il prompt, in tinta arancio (`DS.remove`);
  - con Text guidance ≤ 1 e negativo non vuoto, una nota dice che il negativo agisce solo sopra 1 (a CFG 1 il termine incondizionato si annulla).
- **LoRA (spec §6):**
  - più LoRA, ciascuna una sola volta, con peso −1,5…2,5 (passo 0,05, due decimali) e modalità Tutto/Base/Refiner (valori di Draw Things 0/1/2);
  - il menu "Aggiungi LoRA" offre prima quelle della famiglia del modello, poi quelle di famiglia sconosciuta; con famiglia del modello sconosciuta, tutte;
  - una LoRA di un'altra famiglia o sparita dal server resta nella card con il motivo in arancio e non viene inviata;
  - aggiungendo una LoRA si usa il peso suggerito dai metadati (`weight`, presente su poche), altrimenti 1.
- **Trigger word (deciso con l'utente, 30 settembre 2026):**
  - ogni LoRA ha un proprio campo "Trigger", precompilato con il `prefix` di Draw Things (44 LoRA su 100 sul server dell'utente) e modificabile;
  - la trigger word **non entra nel testo del prompt**: l'LLM che riscriverà i prompt (M6, PM2) non deve poterla alterare;
  - al RUN, le trigger word delle LoRA inviate, nell'ordine della card e senza spazi ai bordi, vanno davanti al prompt, separate da spazi (`promptWithTriggers`); una LoRA non inviata non aggiunge la sua;
  - il PNG ("Description") registra il prompt inviato, trigger word comprese; il lavoro in JSON conserva prompt e trigger separati, così "Riprendi parametri" non le duplica.
- **Ripristino (spec §11):**
  - prompt, negativo, parametri (LoRA comprese) e "Blocca proporzioni" in `~/Library/Application Support/DT Hub/session.json`;
  - scrittura 0,5 s dopo l'ultima modifica e all'uscita dall'app;
  - un file assente, illeggibile o parziale non impedisce l'avvio (vale ciò che si legge, il resto torna ai predefiniti);
  - i valori ripristinati passano da `clamped()`.
- **Riprendi parametri:** rimette anche il negativo e le LoRA effettivamente inviate con quel batch.
- **Stringhe:** ogni testo visibile va in `App/Localizable.xcstrings` (en + it). Nessuna interpolazione nei letterali localizzati: si usa `String(format: String(localized:), …)`. Ai componenti del design system si passa `String(localized:)`. Il catalogo si modifica senza riformattarlo (JSON con indentazione 2 e senza newline finale, come lo scrive Xcode).
- **Nomi e commit:**
  - `HubKit.LoRAMode` e `DrawThingsClient.LoRAMode` hanno lo stesso nome; in DTBridge si usa `DrawThingsClient.LoRAMode`.
  - Indentazione a 2 spazi.
  - Ogni commit termina con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Test dal vivo:** solo con `DTHUB_LIVE_DT=localhost:7859` (API Server dell'app Draw Things acceso, model browsing attivo).
- **Fuori da M4a:** card Avanzate, avviso "valori nascosti attivi" (M4b); editor JSON, preset, import (M4c); Strength (arriva con i plug-in I2I); modalità del seed (rimandata a quando servirà: decisione dell'utente, 30 settembre 2026).

## Review Focus

- **Si cambia modello verso un'altra famiglia con LoRA scelte:** le LoRA restano visibili con "Fatta per …: non usata" e non partono con il RUN (test `statusSaysWhyALoRAIsNotSent`, `sendsOnlyTheUsableLoRAs`, Task 2–3).
- **`session.json` rovinato, parziale o scritto da un'altra versione:** l'app si apre con ciò che riesce a leggere e i predefiniti per il resto (test `anUnreadableFileMeansNoSession`, `aPartialFileKeepsWhatItHas`, `missingFieldsTakeTheirDefaults`, `unreadableFieldsTakeTheirDefaults`, Task 1 e 5).
- **Un PNG salvato da M3, senza negativo né LoRA, letto in futuro:** il lavoro si carica (test `aJobWithoutANegativePromptLoads`, Task 1).
- **All'avvio DT non è ancora collegato (catalogo vuoto):**
  - tutti i campi visibili (test `anUnknownFamilyShowsEverything`, Task 2);
  - le LoRA ripristinate risultano "Non presente sul server" finché il catalogo non arriva (test `statusSaysWhyALoRAIsNotSent`);
  - il RUN resta bloccato da `RunAvailability`.
- **LoRA con trigger word:**
  - le trigger word finiscono davanti al prompt solo per le LoRA inviate, senza doppi spazi, anche con prefissi che finiscono con virgola o spazio (test `triggerWordsGoInFrontOfThePromptInOrder`, `triggerWordsArePutInFrontOfThePrompt`, `sendsOnlyTheUsableLoRAs`);
  - il PNG le registra (test `theDescriptionIsThePromptSentWithItsTriggerWords`);
  - una sessione o un PNG senza il campo si carica (test `aLoRAWithoutTriggerOrModeLoads`).
- **Negativo scritto, poi si passa a una famiglia che non lo usa:** il testo resta conservato ma non viene inviato (test `keepsTheNegativePromptWhereTheFamilyUsesIt`, Task 3). Allo stesso modo CFG-Zero* acceso su un modello senza shift non viene inviato (test `turnsCFGZeroOffWhereTheFamilyHasNoShift`).

---

### Task 1: LoRA e prompt negativo nel contratto (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Generation/LoRASelection.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationParameters.swift` (campo `loras`, `addLoRA`/`removeLoRA`, pesi in `clamped()`, decodifica tollerante)
- Modify: `Packages/Sources/HubKit/Generation/GenerationJob.swift` (campo `negativePrompt`, `promptWithTriggers`, decodifica tollerante)
- Modify: `Packages/Sources/HubKit/Catalog/ModelCatalog.swift` (`CatalogLoRA.trigger`, `CatalogLoRA.defaultWeight`)
- Test: `Packages/Tests/HubKitTests/GenerationParametersTests.swift` (suite `LoRASelectionTests`, `LenientDecodingTests`)

**Interfaces:**
- Consumes: `GenerationParameters` di M3 (campi, `default`, `clamped()`).
- Produces (HubKit, `public`):
  - `enum LoRAMode: Int, CaseIterable, Identifiable, Codable, Sendable { case all = 0, base = 1, refiner = 2 }`;
  - `struct LoRASelection: Equatable, Codable, Sendable, Identifiable` con `file: String`, `weight: Double`, `mode: LoRAMode`, `trigger: String`, `static let weightRange = -1.5...2.5`, `init(file:weight: = 1, mode: = .all, trigger: = "")`, decodifica tollerante;
  - `GenerationParameters.loras: [LoRASelection]` (predefinito `[]`, ultimo parametro dell'init), `mutating func addLoRA(_ file: String, weight: Double = 1, trigger: String = "")`, `mutating func removeLoRA(_ file: String)`, decodifica tollerante;
  - `GenerationJob.negativePrompt: String`, `init(prompt:negativePrompt: = "", model:parameters:)`, `var promptWithTriggers: String`;
  - `CatalogLoRA.trigger: String`, `CatalogLoRA.defaultWeight: Double?`, `init(file:name:family:trigger: = "", defaultWeight: = nil)`.

- [ ] **Step 1: Creare il branch**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m4a-card-base
```

Expected: `Switched to a new branch 'm4a-card-base'`

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
```

- [ ] **Step 3: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -5`
Expected: errori di compilazione `cannot find 'LoRASelection' in scope` / `extra argument 'loras'`.

- [ ] **Step 4: Creare `Packages/Sources/HubKit/Generation/LoRASelection.swift`**

```swift
/// How a LoRA applies when a refiner runs (Draw Things `LoRAMode`, same raw values).
public enum LoRAMode: Int, CaseIterable, Identifiable, Codable, Sendable {
  case all = 0
  case base = 1
  case refiner = 2

  public var id: Int { rawValue }
}

/// A LoRA chosen in the LoRA card: file, weight and mode (spec §6, level 1).
public struct LoRASelection: Equatable, Codable, Sendable, Identifiable {
  public var id: String { file }
  public var file: String
  /// 1 = full strength; Draw Things accepts −1,5…2,5.
  public var weight: Double
  public var mode: LoRAMode
  /// Words that call the LoRA up. Kept apart from the prompt, so rewriting the prompt (for
  /// example with the LLM) never touches them; put in front of the prompt at RUN.
  public var trigger: String

  public static let weightRange = -1.5...2.5

  public init(file: String, weight: Double = 1, mode: LoRAMode = .all, trigger: String = "") {
    self.file = file
    self.weight = weight
    self.mode = mode
    self.trigger = trigger
  }

  /// Lenient: a missing weight, mode or trigger takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    file = try container.decode(String.self, forKey: .file)
    weight = (try? container.decodeIfPresent(Double.self, forKey: .weight)) ?? 1
    mode = (try? container.decodeIfPresent(LoRAMode.self, forKey: .mode)) ?? .all
    trigger = (try? container.decodeIfPresent(String.self, forKey: .trigger)) ?? ""
  }
}
```

- [ ] **Step 5: Sostituire `Packages/Sources/HubKit/Generation/GenerationParameters.swift` con:**

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

  public init(
    width: Int = 1024, height: Int = 1024, steps: Int = 8, guidanceScale: Double = 1,
    cfgZeroStar: Bool = false, cfgZeroInitSteps: Int = 0,
    sampler: Sampler = .uniPCTrailing, shift: Double = 3, resolutionDependentShift: Bool = true,
    seed: UInt32 = 0, randomSeed: Bool = true, batchSize: Int = 1, batchCount: Int = 1,
    loras: [LoRASelection] = []
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
    return copy
  }

  /// Nearest multiple of 64 inside `sizeRange`.
  public static func snap(_ size: Double) -> Int {
    let rounded = Int((size / 64).rounded()) * 64
    return min(max(rounded, sizeRange.lowerBound), sizeRange.upperBound)
  }
}
```

- [ ] **Step 6: Sostituire `Packages/Sources/HubKit/Generation/GenerationJob.swift` con:**

```swift
import Foundation
import CoreGraphics

/// One RUN, as sent to the backend: everything is resolved (the seed included).
public struct GenerationJob: Equatable, Codable, Sendable {
  public let prompt: String
  /// Empty when the family does not use it (spec §6).
  public let negativePrompt: String
  public let model: String
  public let parameters: GenerationParameters

  public init(prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.model = model
    self.parameters = parameters
  }

  /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
  /// prompt, separated by spaces.
  public var promptWithTriggers: String {
    let triggers = parameters.loras.map { $0.trigger.trimmingCharacters(in: .whitespacesAndNewlines) }
    return (triggers + [prompt]).filter { !$0.isEmpty }.joined(separator: " ")
  }

  /// Lenient, like `GenerationParameters`: jobs saved before the negative prompt existed load.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = try container.decode(String.self, forKey: .prompt)
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    model = try container.decode(String.self, forKey: .model)
    parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
  }
}

/// What a running generation reports, in order; `.finished` is always last.
public enum GenerationUpdate: Sendable {
  /// Sampling step `step` of `totalSteps`; nil step while encoding or decoding.
  case progress(step: Int?, totalSteps: Int)
  /// A preview of the image being sampled.
  case preview(CGImage)
  /// All the final images of the RUN.
  case finished([CGImage])
}
```

- [ ] **Step 6b: Sostituire `Packages/Sources/HubKit/Catalog/ModelCatalog.swift` con:**

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

- [ ] **Step 7: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubKit `30 tests … passed`; HubCore, DTBridge e Catalog passano come prima (67, 16, 6).

- [ ] **Step 8: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: LoRA con trigger word e prompt negativo nel contratto, decodifica tollerante

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Tabella famiglia → campi e compatibilità delle LoRA (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Family/FamilyTraits.swift`
- Create: `Packages/Sources/HubCore/Family/LoRACompatibility.swift`
- Test: `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift` (suite `FamilyTraitsTests`, `LoRACompatibilityTests`; la suite `JobComposerTests` dello stesso file si aggiunge nel Task 3)

**Interfaces:**
- Consumes: `ModelCatalog`, `CatalogLoRA` (HubKit, M2); `LoRASelection` (Task 1).
- Produces (HubCore, `public`):
  - `struct FamilyTraits: Equatable, Sendable` con `usesShift: Bool`, `usesNegativePrompt: Bool`, `static let all`, `static func of(_ family: String?) -> FamilyTraits`;
  - `enum LoRAStatus: Equatable, Sendable { case usable, otherFamily(String), notOnServer }`;
  - `extension ModelCatalog` con `func loras(for family: String?) -> [CatalogLoRA]`, `func lora(forFile: String) -> CatalogLoRA?`, `func status(of: LoRASelection, family: String?) -> LoRAStatus`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift` con:

```swift
import HubKit
import Testing

@testable import HubCore

struct FamilyTraitsTests {
  @Test(arguments: ["flux2_9b", "flux1", "qwen_image", "qwen_image_2.1", "z_image", "krea_2", "ideogram_4", "ernie_image", "sd3"])
  func flowMatchingFamiliesUseShift(family: String) {
    #expect(FamilyTraits.of(family).usesShift)
  }

  @Test(arguments: ["v1", "v2", "sdxl_base_v0.9", "ssd_1b", "kandinsky2.1", "wurstchen_v3.0_stage_c"])
  func otherDiffusionFamiliesDoNot(family: String) {
    #expect(!FamilyTraits.of(family).usesShift)
  }

  @Test func upscalersTakeNoNegativePrompt() {
    #expect(!FamilyTraits.of("seedvr2_7b").usesNegativePrompt)
    #expect(FamilyTraits.of("sdxl_base_v0.9").usesNegativePrompt)
    #expect(FamilyTraits.of("flux2_9b").usesNegativePrompt)
  }

  @Test func anUnknownFamilyShowsEverything() {
    #expect(FamilyTraits.of(nil) == .all)
    #expect(FamilyTraits.of("some_future_model") == .all)
  }
}

struct LoRACompatibilityTests {
  let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "b.safetensors", name: "Beta", family: "flux2_9b"),
      CatalogLoRA(file: "a.safetensors", name: "Alpha", family: "flux2_9b"),
      CatalogLoRA(file: "q.safetensors", name: "Qwen style", family: "qwen_image"),
      CatalogLoRA(file: "u.safetensors", name: "Unknown", family: nil),
    ],
    fileCount: 4)

  @Test func offersTheFamilyThenTheUnknownOnes() {
    #expect(catalog.loras(for: "flux2_9b").map(\.name) == ["Alpha", "Beta", "Unknown"])
  }

  @Test func offersEverythingForAnUnknownModelFamily() {
    #expect(catalog.loras(for: nil).count == 4)
  }

  @Test func statusSaysWhyALoRAIsNotSent() {
    #expect(catalog.status(of: LoRASelection(file: "a.safetensors"), family: "flux2_9b") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "u.safetensors"), family: "flux2_9b") == .usable)
    #expect(catalog.status(of: LoRASelection(file: "q.safetensors"), family: "flux2_9b") == .otherFamily("qwen_image"))
    #expect(catalog.status(of: LoRASelection(file: "gone.safetensors"), family: "flux2_9b") == .notOnServer)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'FamilyTraits' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Family/FamilyTraits.swift`**

```swift
import HubKit

/// Which base fields make sense for a model family (spec §6: "una tabella famiglia → campi
/// pertinenti vive in HubCore"). The key is Draw Things' model `version`, e.g. "flux2_9b".
/// An unknown or missing family shows everything: hiding a field the model uses is worse
/// than showing one it ignores.
public struct FamilyTraits: Equatable, Sendable {
  /// Flow-matching models: Shift, "resolution-based" shift and CFG-Zero* apply.
  public let usesShift: Bool
  /// The model reads a negative prompt (it acts only with text guidance above 1).
  public let usesNegativePrompt: Bool

  public init(usesShift: Bool, usesNegativePrompt: Bool) {
    self.usesShift = usesShift
    self.usesNegativePrompt = usesNegativePrompt
  }

  public static let all = FamilyTraits(usesShift: true, usesNegativePrompt: true)

  /// Diffusion models without flow matching: SD 1.x/2.x, SDXL (Kolors, SSD-1B, PixArt use
  /// its version), Kandinsky, Würstchen, SVD.
  static let withoutShift: Set<String> = [
    "v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "pixart",
    "kandinsky2.1", "wurstchen_v3.0_stage_c", "wurstchen_v3.0_stage_b", "svd_i2v",
  ]

  /// Models that take no text to avoid: upscalers (SeedVR2) and image-to-video (SVD).
  static let withoutNegativePrompt: Set<String> = ["seedvr2_3b", "seedvr2_7b", "svd_i2v"]

  public static func of(_ family: String?) -> FamilyTraits {
    guard let family else { return .all }
    return FamilyTraits(
      usesShift: !withoutShift.contains(family),
      usesNegativePrompt: !withoutNegativePrompt.contains(family))
  }
}
```

- [ ] **Step 4: Creare `Packages/Sources/HubCore/Family/LoRACompatibility.swift`**

```swift
import HubKit

/// Whether a chosen LoRA is sent with the next RUN.
public enum LoRAStatus: Equatable, Sendable {
  case usable
  /// Made for another family (named): kept in the card, not sent.
  case otherFamily(String)
  /// The server does not list it (any more): kept in the card, not sent.
  case notOnServer
}

extension ModelCatalog {
  /// The LoRAs to offer for a model family: that family's, then those whose family the server
  /// does not know; each group by name. With an unknown model family, every LoRA.
  public func loras(for family: String?) -> [CatalogLoRA] {
    let byName: (CatalogLoRA, CatalogLoRA) -> Bool = {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
    guard let family else { return loras.sorted(by: byName) }
    return loras.filter { $0.family == family }.sorted(by: byName)
      + loras.filter { $0.family == nil }.sorted(by: byName)
  }

  public func lora(forFile file: String) -> CatalogLoRA? {
    loras.first { $0.file == file }
  }

  public func status(of selection: LoRASelection, family: String?) -> LoRAStatus {
    guard let lora = lora(forFile: selection.file) else { return .notOnServer }
    if let loraFamily = lora.family, let family, loraFamily != family { return .otherFamily(loraFamily) }
    return .usable
  }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubCore `74 tests … passed`; le altre suite invariate.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: tabella famiglia → campi e compatibilità delle LoRA

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Composizione del RUN (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Generation/JobComposer.swift`
- Modify: `Packages/Sources/HubCore/Output/ImageStore.swift` (il campo PNG "Description" registra `job.promptWithTriggers`)
- Test: `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift` (aggiungere la suite `JobComposerTests` in fondo)
- Test: `Packages/Tests/HubCoreTests/PNGImageStoreTests.swift` (test `theDescriptionIsThePromptSentWithItsTriggerWords`)

**Interfaces:**
- Consumes: `FamilyTraits.of`, `ModelCatalog.status(of:family:)` (Task 2); `GenerationParameters.batchesForRun(randomSeed:)` (M3); `GenerationJob.init(prompt:negativePrompt:model:parameters:)` (Task 1).
- Produces (HubCore, `public`): `enum JobComposer` con `static func batches(prompt: String, negativePrompt: String, model: String, family: String?, parameters: GenerationParameters, catalog: ModelCatalog, randomSeed draw: () -> UInt32 = …) -> [GenerationJob]`.

- [ ] **Step 1: Scrivere i test che falliscono.** Aggiungere in fondo a `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift`:

```swift
struct JobComposerTests {
  let catalog = ModelCatalog(
    models: [],
    loras: [
      CatalogLoRA(file: "a.safetensors", name: "Alpha", family: "flux2_9b"),
      CatalogLoRA(file: "q.safetensors", name: "Qwen style", family: "qwen_image"),
    ],
    fileCount: 2)

  func compose(family: String?, _ parameters: GenerationParameters) -> [GenerationJob] {
    JobComposer.batches(
      prompt: "fox", negativePrompt: "blurry", model: "m.ckpt", family: family,
      parameters: parameters, catalog: catalog) { 7 }
  }

  @Test func sendsOnlyTheUsableLoRAs() {
    let parameters = GenerationParameters(loras: [
      LoRASelection(file: "a.safetensors", weight: 0.8), LoRASelection(file: "q.safetensors"),
      LoRASelection(file: "gone.safetensors"),
    ])
    let jobs = compose(family: "flux2_9b", parameters)
    #expect(jobs[0].parameters.loras == [LoRASelection(file: "a.safetensors", weight: 0.8)])
  }

  @Test func keepsTheNegativePromptWhereTheFamilyUsesIt() {
    #expect(compose(family: "sdxl_base_v0.9", .default)[0].negativePrompt == "blurry")
    #expect(compose(family: "seedvr2_7b", .default)[0].negativePrompt == "")
  }

  @Test func turnsCFGZeroOffWhereTheFamilyHasNoShift() {
    let parameters = GenerationParameters(cfgZeroStar: true)
    #expect(!compose(family: "v1", parameters)[0].parameters.cfgZeroStar)
    #expect(compose(family: "flux2_9b", parameters)[0].parameters.cfgZeroStar)
  }

  @Test func splitsIntoBatchesWithTheirSeeds() {
    let jobs = compose(family: "flux2_9b", GenerationParameters(seed: 3, randomSeed: false, batchCount: 2))
    #expect(jobs.map(\.parameters.seed) == [3, 4])
    #expect(jobs.allSatisfy { $0.prompt == "fox" && $0.model == "m.ckpt" })
  }
}
```

- [ ] **Step 1b: Test del PNG.** Sostituire `Packages/Tests/HubCoreTests/PNGImageStoreTests.swift` con:

```swift
import ImageIO
import Foundation
import HubKit
import Testing

@testable import HubCore

struct PNGImageStoreTests {
  let job = GenerationJob(
    prompt: "a lighthouse at dusk", model: "flux_2_klein_9b_f16.ckpt",
    parameters: GenerationParameters(seed: 1234, randomSeed: false))
  let date = Date(timeIntervalSince1970: 1_790_000_000)

  func tempFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PNGImageStoreTests-\(UUID())", isDirectory: true)
  }

  @Test func savesAPNGWithTheJobInside() throws {
    let store = PNGImageStore(folder: tempFolder())
    let url = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(url.pathExtension == "png")
    #expect(url.lastPathComponent.hasSuffix("-1234.png"))
    #expect(PNGImageStore.job(in: url) == job)
  }

  @Test func theDescriptionIsThePromptSentWithItsTriggerWords() throws {
    let triggered = GenerationJob(
      prompt: "a fox", model: "m.ckpt",
      parameters: GenerationParameters(seed: 5, randomSeed: false, loras: [LoRASelection(file: "t", trigger: "vintage tarot style")]))
    let url = try PNGImageStore(folder: tempFolder()).save(testImage(), job: triggered, index: 0, date: date)
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
    #expect(png?[kCGImagePropertyPNGDescription] as? String == "vintage tarot style a fox")
    #expect(PNGImageStore.job(in: url) == triggered)
  }

  @Test func namesEachImageOfABatchAndNeverOverwrites() throws {
    let store = PNGImageStore(folder: tempFolder())
    let first = try store.save(testImage(), job: job, index: 0, date: date)
    let second = try store.save(testImage(), job: job, index: 1, date: date)
    let again = try store.save(testImage(), job: job, index: 0, date: date)
    #expect(second.lastPathComponent.hasSuffix("-1234-2.png"))
    #expect(Set([first, second, again]).count == 3)
  }

  @Test func reportsAFolderItCannotCreate() {
    let store = PNGImageStore(folder: URL(fileURLWithPath: "/System/DT Hub test"))
    #expect(throws: ImageStoreError.self) { try store.save(testImage(), job: job, index: 0, date: date) }
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'JobComposer' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Generation/JobComposer.swift`**

```swift
import HubKit

/// Builds the batches of a RUN from what the Generation tab shows (spec §6): fields the
/// model's family does not use are left out, and so are LoRAs that are not usable.
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
    let negative = traits.usesNegativePrompt ? negativePrompt : ""
    return sent.batchesForRun(randomSeed: draw).map {
      GenerationJob(prompt: prompt, negativePrompt: negative, model: model, parameters: $0)
    }
  }
}
```

- [ ] **Step 3b: In `Packages/Sources/HubCore/Output/ImageStore.swift` registrare il prompt inviato**

Sostituire `kCGImagePropertyPNGDescription: job.prompt,` con `kCGImagePropertyPNGDescription: job.promptWithTriggers,`.

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubCore `79 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: JobComposer — il RUN senza campi e LoRA che la famiglia non usa; PNG con le trigger word

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Trigger word dal server; negativo, LoRA e trigger verso Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift` (`request(for:)`)
- Modify: `Packages/Sources/DTBridge/CatalogBuilder.swift` (`parseLoRAMetadata` legge `prefix` e `weight`)
- Test: `Packages/Tests/DTBridgeTests/JobMapperTests.swift` (test `sendsTheNegativePromptAndTheLoRAs`, `triggerWordsArePutInFrontOfThePrompt`)
- Test: `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift` (`loRAsComeFromMetadataPlusUndescribedLoRAFiles` con trigger e peso)

**Interfaces:**
- Consumes: `GenerationJob.negativePrompt`, `GenerationParameters.loras`, `LoRASelection`, `HubKit.LoRAMode` (Task 1); dalla libreria `GenerationRequest(prompt:negativePrompt:configuration:)`, `DrawThingsConfiguration.loras: [LoRAConfig]`, `LoRAConfig(file:weight:mode:)`, `DrawThingsClient.LoRAMode`.
- Produces: `JobMapper.request(for:)` che imposta `prompt` = `job.promptWithTriggers`, `negativePrompt` e `configuration.loras`; `CatalogBuilder.parseLoRAMetadata` che riempie `trigger` (senza spazi ai bordi) e `defaultWeight`.

- [ ] **Step 1: Scrivere il test che fallisce.** Sostituire `Packages/Tests/DTBridgeTests/JobMapperTests.swift` con:

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

- [ ] **Step 1b: Sostituire `Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift` con:**

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

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: falliscono `sendsTheNegativePromptAndTheLoRAs()`, `triggerWordsArePutInFrontOfThePrompt()` e `loRAsComeFromMetadataPlusUndescribedLoRAFiles()`.

- [ ] **Step 3: Sostituire `Packages/Sources/DTBridge/JobMapper.swift` con:**

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
    return GenerationRequest(prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt, configuration: configuration)
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

Nota: l'argomento `loras:` dell'init di `DrawThingsConfiguration` va prima di `shift:`, e `LoRAMode` esiste sia in HubKit sia nella libreria. Per questo le LoRA si assegnano dopo l'init, con il nome qualificato.

- [ ] **Step 3b: Sostituire `Packages/Sources/DTBridge/CatalogBuilder.swift` con:**

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

  /// Name and family from a spec's JSON object; the file name stands in for a missing name.
  static func specInfo(json: Data, file: String) -> ModelSpecInfo {
    let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
    return ModelSpecInfo(name: object["name"] as? String ?? file, family: object["version"] as? String)
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: DTBridge `18 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: DTBridge legge le trigger word e invia negativo, LoRA e trigger

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Sessione salvata e ripristinata (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Session/SessionStore.swift`
- Test: `Packages/Tests/HubCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `GenerationParameters` con decodifica tollerante (Task 1).
- Produces (HubCore, `public`):
  - `struct SessionSnapshot: Equatable, Codable, Sendable` con `prompt`, `negativePrompt`, `parameters`, `lockRatio` e `init(prompt: = "", negativePrompt: = "", parameters: = .default, lockRatio: = false)`;
  - `struct SessionStore: Sendable` con `init(fileURL:)`, `static var defaultFileURL`, `func load() -> SessionSnapshot?`, `func save(_:) throws`.

- [ ] **Step 1: Scrivere i test che falliscono.** Creare `Packages/Tests/HubCoreTests/SessionStoreTests.swift` con:

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

struct SessionStoreTests {
  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("SessionStoreTests-\(UUID())", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  @Test func noFileMeansNoSession() {
    #expect(SessionStore(fileURL: tempFile()).load() == nil)
  }

  @Test func restoresWhatWasSaved() throws {
    let store = SessionStore(fileURL: tempFile())
    let snapshot = SessionSnapshot(
      prompt: "a fox", negativePrompt: "blurry",
      parameters: GenerationParameters(width: 832, steps: 20, loras: [LoRASelection(file: "a", weight: 0.7)]),
      lockRatio: true)
    try store.save(snapshot)
    #expect(store.load() == snapshot)
  }

  @Test func anUnreadableFileMeansNoSession() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("garbage".utf8).write(to: file)
    #expect(SessionStore(fileURL: file).load() == nil)
  }

  @Test func aPartialFileKeepsWhatItHas() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"prompt": "a fox", "parameters": {"steps": 20}}"#.utf8).write(to: file)
    let snapshot = try #require(SessionStore(fileURL: file).load())
    #expect(snapshot.prompt == "a fox")
    #expect(snapshot.negativePrompt == "")
    #expect(snapshot.parameters.steps == 20)
    #expect(snapshot.parameters.width == GenerationParameters.default.width)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter SessionStoreTests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'SessionStore' in scope`.

- [ ] **Step 3: Creare `Packages/Sources/HubCore/Session/SessionStore.swift`**

```swift
import Foundation
import HubKit

/// What the Generation tab shows, restored at the next launch (spec §11).
public struct SessionSnapshot: Equatable, Codable, Sendable {
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters
  public var lockRatio: Bool

  public init(prompt: String = "", negativePrompt: String = "", parameters: GenerationParameters = .default, lockRatio: Bool = false) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
    self.lockRatio = lockRatio
  }

  /// Lenient: a missing field takes its default (parameters decode leniently too).
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
    negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
    parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
    lockRatio = (try? container.decodeIfPresent(Bool.self, forKey: .lockRatio)) ?? false
  }
}

/// Reads and writes the session as JSON in the app's support folder (spec §11).
public struct SessionStore: Sendable {
  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// ~/Library/Application Support/DT Hub/session.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("session.json")
  }

  /// nil when there is no session yet or the file cannot be read: the tab starts from defaults.
  public func load() -> SessionSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder().decode(SessionSnapshot.self, from: data)
  }

  public func save(_ snapshot: SessionSnapshot) throws {
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with"`
Expected: HubCore `83 tests … passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: SessionStore — ultimo prompt e parametri in session.json

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Testi della M4a (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (18 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente: ogni chiave tradotta in en e it)

**Interfaces:**
- Produces: le chiavi `card.prompt.negative`, `card.prompt.negative.placeholder`, `card.prompt.negative.noEffect`, `card.lora`, `card.lora.add`, `card.lora.none`, `card.lora.noneAvailable`, `card.lora.unknownFamily`, `card.lora.weight`, `card.lora.mode`, `card.lora.mode.all`, `card.lora.mode.base`, `card.lora.mode.refiner`, `card.lora.remove`, `card.lora.otherFamily` (con `%@` = famiglia), `card.lora.notOnServer`, `card.lora.trigger`, `card.lora.trigger.placeholder`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'EOF'
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "card.prompt.negative": ("Negative prompt", "Prompt negativo"),
    "card.prompt.negative.placeholder": ("What to avoid… (negative prompt)", "Cosa evitare… (prompt negativo)"),
    "card.prompt.negative.noEffect": ("The negative prompt only acts with text guidance above 1.", "Il prompt negativo agisce solo con Text guidance maggiore di 1."),
    "card.lora": ("LoRA", "LoRA"),
    "card.lora.add": ("Add LoRA", "Aggiungi LoRA"),
    "card.lora.none": ("No LoRA", "Nessuna LoRA"),
    "card.lora.noneAvailable": ("No LoRA for this model", "Nessuna LoRA per questo modello"),
    "card.lora.unknownFamily": ("Unknown family", "Famiglia sconosciuta"),
    "card.lora.weight": ("Weight", "Peso"),
    "card.lora.mode": ("Mode", "Modalità"),
    "card.lora.mode.all": ("All", "Tutto"),
    "card.lora.mode.base": ("Base", "Base"),
    "card.lora.mode.refiner": ("Refiner", "Refiner"),
    "card.lora.remove": ("Remove LoRA", "Rimuovi LoRA"),
    "card.lora.otherFamily": ("Made for %@: not used", "Fatta per %@: non usata"),
    "card.lora.notOnServer": ("Not on the server: not used", "Non presente sul server: non usata"),
    "card.lora.trigger": ("Trigger", "Trigger"),
    "card.lora.trigger.placeholder": ("No trigger word", "Nessuna trigger word"),
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

Expected: `1 file changed, 306 insertions(+)` e nessuna riga tolta. Se compaiono righe tolte, il file è stato riformattato: annullare con `git checkout App/Localizable.xcstrings` e controllare indentazione e newline finale.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi del prompt negativo e della card LoRA con trigger word (it, en)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Tab Generazione — negativo, LoRA, visibilità, ripristino (App)

**Files:**
- Modify: `App/Generation/GenerationController.swift` (negativo, sessione, `family(in:)`, `traits(in:)`, RUN tramite `JobComposer`, "Riprendi parametri" con il negativo)
- Modify: `App/Generation/Cards/PromptCard.swift` (negativo arancio sotto il prompt, nota CFG ≤ 1)
- Modify: `App/Generation/Cards/SamplingCard.swift` (Shift, "In base alla risoluzione" e CFG-Zero* solo se `usesShift`)
- Create: `App/Generation/Cards/LoRACard.swift`
- Modify: `App/MainWindow/GenerationTabView.swift` (riceve `connection`; seconda riga Campionamento | LoRA)
- Modify: `App/MainWindow/MainWindowView.swift` (passa `connection`)
- Modify: `App/DTHubApp.swift` (salva la sessione all'uscita)

**Interfaces:**
- Consumes: `FamilyTraits`, `ModelCatalog.loras(for:)`, `lora(forFile:)`, `status(of:family:)`, `LoRAStatus` (Task 2); `JobComposer.batches` (Task 3); `SessionStore`, `SessionSnapshot` (Task 5); `LoRASelection`, `LoRAMode`, `GenerationParameters.addLoRA/removeLoRA` (Task 1); le chiavi del Task 6; `DecimalField`, `CardRow`, `DSMenuLabel`, `dsMenuPill()`, `DSCollapsibleCard`, `DSCardRow` (M3).
- Produces: `GenerationController.negativePrompt`, `family(in:)`, `traits(in:)`, `saveSessionNow()`, `init(sessionStore:)`; `LoRACard`; `GenerationTabView(controller:connection:)`.

- [ ] **Step 1: Sostituire `App/Generation/GenerationController.swift` con:**

```swift
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

  /// The family of the chosen model, nil when unknown or while the catalog is not loaded.
  func family(in connection: DrawThingsConnection) -> String? {
    connection.selection.selectedModel(in: connection.monitor.catalog)?.family
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

Nota: dentro `init` gli osservatori `didSet` non partono. Per questo `lockedRatio` si imposta a mano, e l'eventuale salvataggio pianificato viene annullato.

- [ ] **Step 2: Sostituire `App/Generation/Cards/PromptCard.swift` con:**

```swift
import HubKit
import SwiftUI

/// The big prompt card, always first (spec §7). Below the prompt, the negative prompt in the
/// orange tint, only for families that use it (spec §6).
struct PromptCard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.prompt"), systemImage: "text.cursor",
      isExpanded: controller.cards.binding("prompt")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        PromptEditor(
          text: $controller.prompt, placeholder: String(localized: "card.prompt.placeholder"),
          accessibilityLabel: String(localized: "card.prompt"), tint: DS.accent, minHeight: 140)
        if controller.traits(in: connection).usesNegativePrompt {
          PromptEditor(
            text: $controller.negativePrompt, placeholder: String(localized: "card.prompt.negative.placeholder"),
            accessibilityLabel: String(localized: "card.prompt.negative"), tint: DS.remove, minHeight: 60)
          if !controller.negativePrompt.isEmpty, controller.parameters.guidanceScale <= 1 {
            Text("card.prompt.negative.noEffect")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

/// A text editor with a placeholder in the given tint and a faint tinted background.
private struct PromptEditor: View {
  @Binding var text: String
  let placeholder: String
  let accessibilityLabel: String
  let tint: Color
  let minHeight: CGFloat

  var body: some View {
    TextEditor(text: $text)
      .font(.body)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.never)
      .padding(8)
      .frame(minHeight: minHeight)
      .background(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(tint == DS.accent ? Color.primary.opacity(0.06) : tint.opacity(0.08))
      )
      .overlay(
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .strokeBorder(tint == DS.accent ? Color.clear : tint.opacity(0.35), lineWidth: 1)
      )
      .overlay(alignment: .topLeading) {
        if text.isEmpty {
          Text(placeholder)
            .foregroundStyle(tint.opacity(0.75))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .allowsHitTesting(false)
        }
      }
      .accessibilityLabel(accessibilityLabel)
  }
}
```

- [ ] **Step 3: Sostituire `App/Generation/Cards/SamplingCard.swift` con:**

```swift
import HubKit
import SwiftUI

/// Steps, text guidance with CFG-Zero*, sampler, shift with resolution-dependent shift (spec §6).
/// Shift, "resolution-based" and CFG-Zero* show only for flow-matching families (`FamilyTraits`).
struct SamplingCard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.sampling"), systemImage: "dial.medium",
      isExpanded: controller.cards.binding("sampling")
    ) {
      let usesShift = controller.traits(in: connection).usesShift
      VStack(spacing: DS.rowGap) {
        CardRow(label: String(localized: "card.sampling.steps")) {
          IntField(
            label: String(localized: "card.sampling.steps"), value: $controller.parameters.steps,
            range: GenerationParameters.stepsRange)
        }

        CardRow(label: String(localized: "card.sampling.guidance")) {
          if usesShift {
            Toggle(isOn: $controller.parameters.cfgZeroStar) {
              Text("card.sampling.cfgZero")
            }
            .toggleStyle(DSCheckboxToggleStyle())
          }
        } control: {
          DecimalField(
            label: String(localized: "card.sampling.guidance"), value: $controller.parameters.guidanceScale,
            range: GenerationParameters.guidanceRange, step: 0.5)
        }
        if usesShift, controller.parameters.cfgZeroStar {
          CardRow(label: String(localized: "card.sampling.cfgZeroInitSteps")) {
            IntField(
              label: String(localized: "card.sampling.cfgZeroInitSteps"),
              value: $controller.parameters.cfgZeroInitSteps,
              range: 0...controller.parameters.steps)
          }
        }

        CardRow(label: String(localized: "card.sampling.sampler")) {
          Picker(selection: $controller.parameters.sampler) {
            ForEach(Sampler.allCases) { sampler in
              Text(verbatim: sampler.displayName).tag(sampler)
            }
          } label: {
            EmptyView()
          }
          .labelsHidden()
          .fixedSize()
          .accessibilityLabel(String(localized: "card.sampling.sampler"))
        }

        if usesShift {
          CardRow(label: String(localized: "card.sampling.shift")) {
            Toggle(isOn: $controller.parameters.resolutionDependentShift) {
              Text("card.sampling.resolutionShift")
            }
            .toggleStyle(DSCheckboxToggleStyle())
          } control: {
            DecimalField(
              label: String(localized: "card.sampling.shift"), value: $controller.parameters.shift,
              range: GenerationParameters.shiftRange, step: 0.1, fractionDigits: 2)
              .disabled(controller.parameters.resolutionDependentShift)
          }
        }
      }
    }
  }
}
```

- [ ] **Step 4: Creare `App/Generation/Cards/LoRACard.swift`**

```swift
import HubCore
import HubKit
import SwiftUI

/// The LoRAs of the next RUN, each with weight, mode and trigger word (spec §6). The menu offers the LoRAs
/// of the chosen model's family and those of unknown family; a LoRA that no longer fits
/// (other family, gone from the server) stays in the list with the reason and is not sent.
/// Trigger words stay in their own field, prefilled from Draw Things; at RUN those of the
/// LoRAs sent go in front of the prompt (`GenerationJob.promptWithTriggers`).
struct LoRACard: View {
  @Bindable var controller: GenerationController
  let connection: DrawThingsConnection

  private var catalog: ModelCatalog { connection.monitor.catalog }
  private var family: String? { controller.family(in: connection) }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "card.lora"), systemImage: "square.stack.3d.up",
      isExpanded: controller.cards.binding("lora")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if controller.parameters.loras.isEmpty {
          Text("card.lora.none")
            .foregroundStyle(.secondary)
        }
        ForEach($controller.parameters.loras) { $selection in
          LoRARow(
            selection: $selection,
            name: catalog.lora(forFile: selection.file)?.name ?? selection.file,
            status: catalog.status(of: selection, family: family),
            remove: { controller.parameters.removeLoRA(selection.file) })
        }
        addMenu
      }
    }
  }

  private var addMenu: some View {
    let offered = catalog.loras(for: family)
    let chosen = Set(controller.parameters.loras.map(\.file))
    return Menu {
      if offered.isEmpty {
        Text("card.lora.noneAvailable")
      }
      let known = offered.filter { $0.family != nil }
      let unknown = offered.filter { $0.family == nil }
      if !known.isEmpty {
        Section {
          ForEach(known) { lora in addButton(lora, disabled: chosen.contains(lora.file)) }
        } header: {
          Text(verbatim: family ?? "")
        }
      }
      if !unknown.isEmpty {
        Section {
          ForEach(unknown) { lora in addButton(lora, disabled: chosen.contains(lora.file)) }
        } header: {
          Text("card.lora.unknownFamily")
        }
      }
    } label: {
      DSMenuLabel(String(localized: "card.lora.add"), systemImage: "plus")
    }
    .dsMenuPill()
  }

  private func addButton(_ lora: CatalogLoRA, disabled: Bool) -> some View {
    Button {
      controller.parameters.addLoRA(lora.file, weight: lora.defaultWeight ?? 1, trigger: lora.trigger)
    } label: {
      Text(verbatim: lora.name)
    }
    .disabled(disabled)
  }
}

/// One chosen LoRA: name and remove on the first line, mode and weight on the second, the
/// trigger word on the third, the reason in orange when it is not sent.
private struct LoRARow: View {
  @Binding var selection: LoRASelection
  let name: String
  let status: LoRAStatus
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: DS.controlGap) {
        Text(verbatim: name)
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundStyle(status == .usable ? .primary : .secondary)
        Spacer(minLength: DS.controlGap)
        Button(action: remove) {
          Image(systemName: "minus.circle.fill")
            .foregroundStyle(DS.remove)
        }
        .buttonStyle(.plain)
        .help(String(localized: "card.lora.remove"))
        .accessibilityLabel(String(localized: "card.lora.remove"))
      }
      HStack(spacing: DS.controlGap) {
        Picker(selection: $selection.mode) {
          ForEach(LoRAMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        } label: {
          EmptyView()
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(String(localized: "card.lora.mode"))
        Spacer(minLength: DS.controlGap)
        DecimalField(
          label: String(localized: "card.lora.weight"), value: $selection.weight,
          range: LoRASelection.weightRange, step: 0.05, fractionDigits: 2)
      }
      HStack(spacing: DS.controlGap) {
        Text("card.lora.trigger")
          .foregroundStyle(.secondary)
          .lineLimit(1)
        TextField(String(localized: "card.lora.trigger"), text: $selection.trigger, prompt: Text("card.lora.trigger.placeholder"))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
      }
      if let reason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    }
    .padding(.vertical, 2)
  }

  private var reason: String? {
    switch status {
    case .usable: nil
    case .otherFamily(let family): String(format: String(localized: "card.lora.otherFamily"), family)
    case .notOnServer: String(localized: "card.lora.notOnServer")
    }
  }
}

extension LoRAMode {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .all: "card.lora.mode.all"
    case .base: "card.lora.mode.base"
    case .refiner: "card.lora.mode.refiner"
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
        PromptCard(controller: controller, connection: connection)
        DSCardRow {
          DimensionsCard(controller: controller)
          SeedBatchCard(controller: controller)
        }
        DSCardRow {
          SamplingCard(controller: controller, connection: connection)
          LoRACard(controller: controller, connection: connection)
        }
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
  }
}
```

- [ ] **Step 6: In `App/MainWindow/MainWindowView.swift` passare la connessione al tab**

Sostituire `GenerationTabView(controller: generation)` con `GenerationTabView(controller: generation, connection: connection)`.

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

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in|Pass String"`
Expected: `** BUILD SUCCEEDED **`; test HubKit 30, HubCore 83, DTBridge 18, Catalog 6: **137** passati.

- [ ] **Step 9: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: prompt negativo, card LoRA con trigger word, campi per famiglia e ripristino della sessione

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Verifica dal vivo

Nessun codice nuovo. Si prova l'app vera contro il server Draw Things: API Server acceso sulla 7859, model browsing attivo, installati Flux 2 Klein, Juggernaut Reborn (`v1`) e LoRA `flux2_9b`. Per non toccare la cartella Immagini si salva in una cartella temporanea. Prima si annota il modello scelto dall'utente, per rimetterlo alla fine.

- [ ] **Step 1: Preparare e avviare**

```bash
defaults read com.exiztenz.DTHub drawThings.selectedModel; defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m4a-check && defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt && open "/Users/existenz/Software developement/DT Hub/build/Build/Products/Debug/DT Hub.app"
```

- [ ] **Step 2: Checklist (screenshot)**

1. Con Flux 2 Klein:
   - sotto il prompt c'è il negativo arancio "Cosa evitare… (prompt negativo)";
   - la seconda riga è Campionamento | LoRA, alte uguali;
   - Campionamento mostra Shift, "In base alla risoluzione" e CFG-Zero*.
2. Scrivere un negativo con Text guidance 1: compare la nota "agisce solo con Text guidance maggiore di 1".
3. "Aggiungi LoRA":
   - il menu mostra prima le LoRA `flux2_9b`, poi "Famiglia sconosciuta";
   - aggiungere una LoRA con trigger word (es. "F2 realistic"): compare la riga con nome, modalità, peso 1,00, il campo Trigger precompilato ("realistic") e il pulsante per toglierla;
   - il testo del prompt non cambia;
   - peso a 0,60; RUN a 512×512;
   - nel PNG, `exiftool -Description` mostra "realistic <prompt>" e `exiftool -UserComment` mostra `loras` con peso 0.6, `trigger` e `negativePrompt`, con il `prompt` senza trigger.
4. Scegliere Juggernaut Reborn (`v1`):
   - Shift e CFG-Zero* spariscono, il negativo resta;
   - la LoRA scelta mostra in arancio "Fatta per flux2_9b: non usata".
5. Tornare a Flux 2 Klein, chiudere l'app con ⌘Q e riaprirla: prompt, negativo, LoRA, dimensioni e "Blocca proporzioni" sono quelli di prima.
6. "Riprendi parametri" sull'immagine: tornano anche il negativo e la LoRA con peso 0,60 e la sua trigger word, che non compare nel testo del prompt.

Punti che servono all'utente (interazione non automatizzabile in background): scrittura diretta del peso e della trigger word; menu Modalità.

- [ ] **Step 3: Pulizia** (rimettere il modello annotato allo Step 1 al posto di `<modello-annotato>`)

```bash
osascript -e 'quit app "DT Hub"'; defaults delete com.exiztenz.DTHub output.folder; defaults write com.exiztenz.DTHub drawThings.selectedModel <modello-annotato>; rm -rf /tmp/dthub-m4a-check
```

---

## Fine della M4a

Esito atteso sul branch `m4a-card-base`:
- **137 test verdi**, di cui 3 live eseguiti solo con `DTHUB_LIVE_DT`;
- build Xcode pulita;
- livello 1 della spec §6 completo tranne la modalità del seed e Strength.

Poi: revisione indipendente, correzioni, merge in `main`, e il piano di M4b (card Avanzate e avviso "valori nascosti attivi").

# M8b Contributi dei plug-in — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un plug-in attivo può mandare all'app **valori per i campi, LoRA, immagini per il Moodboard, un'immagine di partenza e una pipeline**, e può fare una domanda al modello linguistico. I campi che un plug-in ha riempito sono in teal al 30%; se l'utente li cambia compare il valore del plug-in tra parentesi; due plug-in sullo stesso campo si risolvono con un pop-up; la pipeline sta sul pulsante Run («Run · N passaggi»). **Un plug-in contribuisce e il Run lo esegue.** In più, il plug-in di esempio passa alla versione 1.2 e manda tutto questo (con una variante B per provare i conflitti).

**Architecture:**
- **HubKit** riceve i tipi del contratto: i campi che un plug-in può riempire (`ContributionField`, `FieldValue`, `GenerationFields`, `FieldOverlay`) e il messaggio `contribute` letto in modo permissivo (`PluginContribution`, `PluginPipeline`, `PipelineStep`, `PluginImageRef`).
- **HubCore** riceve `ContributionStore` (chi ha riempito cosa, conflitti, pipeline; parla con la scheda tramite il protocollo `ContributionTarget`, quindi si prova con una scheda finta) e `PipelineInputs` (gli ingressi di un passaggio). `PluginRegistry` instrada `contribute` e `llm` (la ricezione diventa asincrona) e toglie i segni di un plug-in quando si spegne.
- **L'app**: `GenerationController` è il bersaglio dei contributi ed esegue la pipeline; le card mostrano teal e parentesi; il pop-up dei conflitti; il pulsante Run.
- **PluginKit**: `contribute` e `askLanguageModel` per gli autori, il plug-in di esempio 1.2 con la variante B, lo script che li costruisce.

**Tech Stack:** Swift 6, SwiftUI/AppKit, macOS 26, Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-03-plugin-design.md` (§7 e §11).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m8b-plugin` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift, solo LLMBridge importa MLX; **`PluginKit/` non dipende da nulla dell'app**.
- **Il contratto resta la versione 1**: `contribute` e `llm` sono aggiunte; un tipo sconosciuto → `{"type":"unsupported"}`. Solo un plug-in **attivo** può mandarli, gli altri ricevono `{"type":"error","text":…}`.
- **Un campo è sempre modificabile**, nessun blocco, nessun «importato da» (spec §7). Teal = `DS.accent` al 30%. Prompt e negativo: teal, **mai** parentesi.
- **Il segno di un campo** (`FieldMark`) tiene il valore **già limitato** come lo limitano le card (`GenerationParameters.clamped()`); è `isOverridden` quando il campo non contiene più quel valore, e torna in teal se l'utente riscrive lo stesso valore.
- **Conflitto** = un **altro** plug-in manda un valore **diverso** da quello segnato su un campo (anche se l'utente nel frattempo lo ha cambiato), o un'altra immagine di partenza, o un'altra pipeline. Valori uguali: nessun pop-up, il segno passa al nuovo plug-in. LoRA e Moodboard si sommano, senza pop-up. Esc lascia tutto com'è. Chi manda di nuovo la stessa cosa sostituisce la propria domanda in attesa.
- **Moodboard:** lo stesso plug-in che rimanda le immagini sostituisce quelle che aveva mandato e che ci sono ancora. **LoRA:** lo stesso file già presente prende peso, modo e trigger nuovi.
- **Pipeline:** ogni passaggio è `fields` sopra i campi del tab; `loras` e `moodboard` del passaggio **sostituiscono** quelli del tab per quel passaggio (`[]` = nessuno), se assenti restano quelli del tab; `startImage` o l'output del passaggio precedente (`useOutputAsStart`) sostituiscono l'immagine di partenza, inquadrata sul canvas del passaggio e **senza la maschera del tab**. La pipeline resta sul pulsante finché non la si toglie o il plug-in si spegne. Ogni passaggio è una generazione normale (le sue immagini vanno nella striscia dei Risultati); un passaggio che fallisce, o Stop, fermano la pipeline; il campo Seed non si aggiorna. Per tutta la pipeline `isPreparing` resta vero.
- **Non si contribuiscono:** il modello, le card Avanzate, la forza, la maschera (backlog).
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; mai una stringa vuota come titolo.
- **Più plug-in nello stesso processo:** ogni plug-in dà alla propria copia di `DTHubPluginKit` un nome di modulo suo con `moduleAliases` (altrimenti «Class … is implemented in both»).
- **La logica sta in HubKit/HubCore (testata); le viste si verificano con la compilazione e con la prova del Task 7.**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi (o riscritti per intero, dove il testo lo dice) si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **L'app di prova** condivide le preferenze (`UserDefaults`) con quella dell'utente anche con `CFFIXED_USER_HOME`: i file (immagini, plug-in, sessione) sono a parte, il modello scelto e la scheda aperta no. Se si cambia il modello per la prova, **rimetterlo a mano alla fine** (Task 7).
- **Fuori da M8b:** modello, card Avanzate, forza e maschera contribuiti; segni salvati tra un avvio e l'altro; i plug-in veri (Prompt Master, Sphere Light, Qwen).

## Review Focus

- **Un contributo sbagliato non rompe nulla:** chiavi sconosciute, tipi sbagliati, numeri fuori limite, un file che non si legge, un messaggio che non è un oggetto JSON, un plug-in non attivo (test `unknownKeysAndValuesOfTheWrongKindAreLeftOut`, `appliedValuesAreLimitedLikeTheCards`, `aMessageThatIsNotAnObjectOrCarriesNothingIsRecognised`, `aPictureThatCannotBeReadIsReportedAndTheRestGoesIn`, `aPluginThatIsNotActiveContributesNothing`, Task 1, 2, 4).
- **Il segno dice la verità:** teal solo se il campo contiene il valore del plug-in; parentesi dopo una modifica a mano; spegnere un plug-in toglie segni e pipeline e lascia i valori (test `changingTheFieldByHandLosesTheTealAndKeepsThePluginsValue`, `typingThePluginsValueBackBringsTheTealBack`, `turningAPluginOffTakesItsMarksAndPipelineButKeepsTheValues`, Task 2).
- **I conflitti non bloccano mai:** il campo in conflitto resta com'è finché l'utente non sceglie; Esc lascia tutto (test `anotherPluginOnAMarkedFieldIsAConflictAndTheFieldWaits`, `escapeLeavesTheFieldsAsTheyAre`, Task 2).
- **La pipeline non lascia l'app bloccata:** un passaggio che fallisce, Stop, un'immagine del passaggio che non si legge, un modello che non usa il Moodboard (test `aModelThatDoesNotReadTheMoodboardGetsNone`, Task 3; **l'esecuzione della pipeline in `GenerationController.runPipeline` non ha test automatici**: il revisore la legga con attenzione e la provi la prova dal vivo del Task 7).
- **Reentrancy:** `ContributionStore.receive` scrive nei campi, e la scheda chiama `reconcile()` a ogni modifica mentre `receive` è ancora in corso (nessun test diretto: il revisore controlli che il segno nuovo non si perda).
- **Più plug-in nello stesso processo** (`moduleAliases`): provato dal vivo nel Task 7; il test del Task 6 carica i due bundle insieme.

---

### Task 1: I tipi del contratto di M8b (HubKit)

**Files:**
- Create: `Packages/Sources/HubKit/Plugin/ContributionFields.swift`, `Packages/Sources/HubKit/Plugin/PluginContribution.swift`
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift`
- Test: `Packages/Tests/HubKitTests/ContributionContractTests.swift` (nuovo)

**Interfaces:**
- Produces (HubKit, `public`):
  - `enum ContributionField: String, CaseIterable, Codable, Hashable, Sendable`: `prompt, negativePrompt, width, height, steps, guidanceScale, cfgZeroStar, cfgZeroInitSteps, sampler, shift, resolutionDependentShift, seed, randomSeed, batchSize, batchCount` (il valore grezzo è la chiave di `fields`);
  - `enum FieldValue: Equatable, Sendable`: `text(String)`, `int(Int)`, `double(Double)`, `bool(Bool)`;
  - `struct GenerationFields: Equatable, Sendable` (`prompt`, `negativePrompt`, `parameters`; `value(of:) -> FieldValue`; `set(_:for:)`: un valore del tipo sbagliato è ignorato; il campionatore è il suo numero);
  - `struct FieldOverlay: Equatable, Sendable` (`values`, `init(_:)`, `init(json: [String: JSONValue])` che lascia fuori chiavi sconosciute e valori del tipo sbagliato; `sampler` anche per nome; `fields` nell'ordine del tab; `isEmpty`; `applied(to:) -> GenerationFields` che poi limita con `clamped()`);
  - `struct PluginImageRef: Equatable, Sendable` (`name`, `path`; il nome manca = il nome del file);
  - `struct PipelineStep: Equatable, Sendable` (`title`, `fields: FieldOverlay`, `loras: [LoRASelection]?`, `moodboard: [PluginImageRef]?`, `startImage: PluginImageRef?`, `useOutputAsStart`; `fields(over: GenerationFields) -> GenerationFields`: le modifiche sopra i campi del tab, e le LoRA del passaggio al posto di quelle del tab se ci sono);
  - `struct PluginPipeline: Equatable, Sendable` (`name`, `steps`);
  - `struct PluginContribution: Equatable, Sendable` (`fields`, `loras`, `moodboard`, `startImage`, `pipeline`; `init?(message: Data)`: nil se non è un oggetto JSON; `isEmpty`; una pipeline senza passaggi leggibili non c'è);
  - `PluginMessageType.contribute`, `.llm`, `.error` e `PluginMessageType.failure(_ text: String) -> Data` (`{"type":"error","text":…}`).
- Consumes: `GenerationParameters`, `Sampler`, `JSONValue`, `LoRASelection`, `PluginMessageType` (esistenti).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m8b-plugin
```

```swift
import Foundation
import Testing

@testable import HubKit

struct ContributionContractTests {
  private func overlay(_ json: String) -> FieldOverlay {
    let value = try! JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    guard case .object(let object) = value else { fatalError("not an object") }
    return FieldOverlay(json: object)
  }

  @Test func fieldsAreReadByKeyAndKind() {
    let read = overlay(
      #"{"prompt":"a cat","negativePrompt":"blur","steps":4,"guidanceScale":1,"shift":3,"sampler":16,"cfgZeroStar":true,"seed":7,"randomSeed":false,"width":1024.0}"#
    )
    #expect(read.values[.prompt] == .text("a cat"))
    #expect(read.values[.steps] == .int(4))
    #expect(read.values[.guidanceScale] == .double(1))
    #expect(read.values[.sampler] == .int(16))
    #expect(read.values[.cfgZeroStar] == .bool(true))
    #expect(read.values[.randomSeed] == .bool(false))
    #expect(read.values[.width] == .int(1024))
  }

  @Test func theSamplerCanBeNamedByItsDisplayName() {
    #expect(overlay(#"{"sampler":"ddim trailing"}"#).values[.sampler] == .int(Sampler.ddimTrailing.rawValue))
    #expect(overlay(#"{"sampler":"not a sampler"}"#).isEmpty)
    #expect(overlay(#"{"sampler":99}"#).isEmpty)
  }

  @Test func unknownKeysAndValuesOfTheWrongKindAreLeftOut() {
    let read = overlay(#"{"model":"flux.ckpt","steps":"four","prompt":3,"cfgZeroStar":1,"width":1000.5,"shift":null}"#)
    #expect(read.isEmpty)
  }

  @Test func appliedValuesAreLimitedLikeTheCards() {
    let fields = overlay(#"{"width":1000,"steps":999,"guidanceScale":-4,"batchSize":9,"prompt":"x"}"#)
      .applied(to: GenerationFields())
    #expect(fields.parameters.width == 1024)
    #expect(fields.parameters.steps == GenerationParameters.stepsRange.upperBound)
    #expect(fields.parameters.guidanceScale == 0)
    #expect(fields.parameters.batchSize == GenerationParameters.batchSizeRange.upperBound)
    #expect(fields.prompt == "x")
  }

  @Test func valueOfAndSetAgreeForEveryField() {
    var fields = GenerationFields()
    for field in ContributionField.allCases {
      let value = fields.value(of: field)
      fields.set(value, for: field)
      #expect(fields.value(of: field) == value)
    }
  }

  @Test func aContributionIsReadWithItsParts() throws {
    let message = Data(
      """
      {"type":"contribute","fields":{"steps":4},"loras":[{"file":"sun.ckpt","weight":0.6,"mode":"all"},{"weight":1}],
       "moodboard":[{"path":"/tmp/a.png","name":"Sphere"},{"path":"/tmp/b.png"},{"name":"no path"}],
       "startImage":{"path":"/tmp/s.png"},
       "pipeline":{"name":"Match","steps":[
         {"title":"Overcast","fields":{"steps":4},"loras":[]},
         {"fields":{"guidanceScale":1},"moodboard":[{"path":"/tmp/a.png"}],"useOutputAsStart":true},
         "junk"]}}
      """.utf8)
    let contribution = try #require(PluginContribution(message: message))
    #expect(contribution.fields.values[.steps] == .int(4))
    #expect(contribution.loras.map(\.file) == ["sun.ckpt"])
    #expect(contribution.loras.first?.weight == 0.6)
    #expect(contribution.moodboard == [PluginImageRef(name: "Sphere", path: "/tmp/a.png"), PluginImageRef(name: "b.png", path: "/tmp/b.png")])
    #expect(contribution.startImage == PluginImageRef(name: "s.png", path: "/tmp/s.png"))
    let pipeline = try #require(contribution.pipeline)
    #expect(pipeline.name == "Match")
    #expect(pipeline.steps.count == 2)
    #expect(pipeline.steps[0].title == "Overcast")
    #expect(pipeline.steps[0].loras == [])
    #expect(pipeline.steps[0].useOutputAsStart == false)
    #expect(pipeline.steps[1].loras == nil)
    #expect(pipeline.steps[1].moodboard?.count == 1)
    #expect(pipeline.steps[1].useOutputAsStart)
  }

  @Test func aMessageThatIsNotAnObjectOrCarriesNothingIsRecognised() {
    #expect(PluginContribution(message: Data("[1]".utf8)) == nil)
    #expect(PluginContribution(message: Data("nope".utf8)) == nil)
    #expect(PluginContribution(message: Data(#"{"type":"contribute"}"#.utf8))?.isEmpty == true)
    #expect(PluginContribution(message: Data(#"{"pipeline":{"steps":[]}}"#.utf8))?.pipeline == nil)
  }

  @Test func theFailureAnswerNamesTheProblem() {
    let data = PluginMessageType.failure("no way")
    #expect(PluginMessageType.of(data) == PluginMessageType.error)
    #expect(String(decoding: data, as: UTF8.self).contains("no way"))
  }
}

struct PipelineStepTests {
  @Test func aPassPutsItsChangesOnTheTabsFields() {
    var base = GenerationFields(prompt: "tab prompt")
    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
    base.parameters.steps = 20
    let step = PipelineStep(fields: FieldOverlay([.steps: .int(4), .prompt: .text("pass prompt")]))
    let result = step.fields(over: base)
    #expect(result.parameters.steps == 4)
    #expect(result.prompt == "pass prompt")
    #expect(result.parameters.loras.map(\.file) == ["tab.ckpt"])
  }

  @Test func aPassWithLoRAsReplacesTheListAndAnEmptyListClearsIt() {
    var base = GenerationFields()
    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
    #expect(PipelineStep(loras: [LoRASelection(file: "sun.ckpt", weight: 0.6)]).fields(over: base).parameters.loras.map(\.file) == ["sun.ckpt"])
    #expect(PipelineStep(loras: []).fields(over: base).parameters.loras.isEmpty)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter ContributionContractTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'FieldOverlay' in scope`.

- [ ] **Step 3: Implementare**

```swift
import Foundation

/// A field of the Generation tab a plug-in can fill (plug-in design §7). The raw value is the key in the
/// `fields` object of the `contribute` message.
public enum ContributionField: String, CaseIterable, Codable, Hashable, Sendable {
  case prompt, negativePrompt
  case width, height, steps, guidanceScale, cfgZeroStar, cfgZeroInitSteps, sampler, shift, resolutionDependentShift
  case seed, randomSeed, batchSize, batchCount
}

/// What a field holds, as a plug-in sends it. The sampler is its raw value.
public enum FieldValue: Equatable, Sendable {
  case text(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
}

/// The prompt, the negative prompt and the base parameters: everything `ContributionField` names.
public struct GenerationFields: Equatable, Sendable {
  public var prompt: String
  public var negativePrompt: String
  public var parameters: GenerationParameters

  public init(prompt: String = "", negativePrompt: String = "", parameters: GenerationParameters = .default) {
    self.prompt = prompt
    self.negativePrompt = negativePrompt
    self.parameters = parameters
  }

  public func value(of field: ContributionField) -> FieldValue {
    switch field {
    case .prompt: .text(prompt)
    case .negativePrompt: .text(negativePrompt)
    case .width: .int(parameters.width)
    case .height: .int(parameters.height)
    case .steps: .int(parameters.steps)
    case .guidanceScale: .double(parameters.guidanceScale)
    case .cfgZeroStar: .bool(parameters.cfgZeroStar)
    case .cfgZeroInitSteps: .int(parameters.cfgZeroInitSteps)
    case .sampler: .int(parameters.sampler.rawValue)
    case .shift: .double(parameters.shift)
    case .resolutionDependentShift: .bool(parameters.resolutionDependentShift)
    case .seed: .int(Int(parameters.seed))
    case .randomSeed: .bool(parameters.randomSeed)
    case .batchSize: .int(parameters.batchSize)
    case .batchCount: .int(parameters.batchCount)
    }
  }

  /// Puts a value in a field; a value of the wrong kind is ignored. Numbers are not limited here:
  /// `FieldOverlay.applied(to:)` limits them all at once.
  public mutating func set(_ value: FieldValue, for field: ContributionField) {
    switch (field, value) {
    case (.prompt, .text(let text)): prompt = text
    case (.negativePrompt, .text(let text)): negativePrompt = text
    case (.width, .int(let number)): parameters.width = number
    case (.height, .int(let number)): parameters.height = number
    case (.steps, .int(let number)): parameters.steps = number
    case (.guidanceScale, .double(let number)): parameters.guidanceScale = number
    case (.cfgZeroStar, .bool(let flag)): parameters.cfgZeroStar = flag
    case (.cfgZeroInitSteps, .int(let number)): parameters.cfgZeroInitSteps = number
    case (.sampler, .int(let number)): if let sampler = Sampler(rawValue: number) { parameters.sampler = sampler }
    case (.shift, .double(let number)): parameters.shift = number
    case (.resolutionDependentShift, .bool(let flag)): parameters.resolutionDependentShift = flag
    case (.seed, .int(let number)): parameters.seed = UInt32(clamping: max(number, 0))
    case (.randomSeed, .bool(let flag)): parameters.randomSeed = flag
    case (.batchSize, .int(let number)): parameters.batchSize = number
    case (.batchCount, .int(let number)): parameters.batchCount = number
    default: break
    }
  }
}

/// Values for some fields, read from the JSON a plug-in sends. A key that is not a field, or a value of
/// the wrong kind, is left out: a plug-in cannot break the app with a bad message.
public struct FieldOverlay: Equatable, Sendable {
  public private(set) var values: [ContributionField: FieldValue]

  public init(_ values: [ContributionField: FieldValue] = [:]) { self.values = values }

  public init(json: [String: JSONValue]) {
    var values: [ContributionField: FieldValue] = [:]
    for (key, raw) in json {
      guard let field = ContributionField(rawValue: key), let value = Self.value(raw, for: field) else { continue }
      values[field] = value
    }
    self.values = values
  }

  public var isEmpty: Bool { values.isEmpty }

  /// The fields, in the order of the Generation tab.
  public var fields: [ContributionField] { ContributionField.allCases.filter { values[$0] != nil } }

  /// The fields with these values, limited to what the tab accepts (sizes in multiples of 64, ranges).
  public func applied(to fields: GenerationFields) -> GenerationFields {
    var result = fields
    for (field, value) in values { result.set(value, for: field) }
    result.parameters = result.parameters.clamped()
    return result
  }

  private static func value(_ raw: JSONValue, for field: ContributionField) -> FieldValue? {
    switch field {
    case .prompt, .negativePrompt:
      if case .string(let text) = raw { return .text(text) }
    case .width, .height, .steps, .cfgZeroInitSteps, .seed, .batchSize, .batchCount:
      if let number = integer(raw) { return .int(number) }
    case .guidanceScale, .shift:
      switch raw {
      case .double(let number) where number.isFinite: return .double(number)
      case .int(let number): return .double(Double(number))
      default: break
      }
    case .cfgZeroStar, .resolutionDependentShift, .randomSeed:
      if case .bool(let flag) = raw { return .bool(flag) }
    case .sampler:
      if let number = integer(raw), Sampler(rawValue: number) != nil { return .int(number) }
      if case .string(let name) = raw,
        let sampler = Sampler.allCases.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame })
      {
        return .int(sampler.rawValue)
      }
    }
    return nil
  }

  private static func integer(_ raw: JSONValue) -> Int? {
    switch raw {
    case .int(let number): return number
    case .double(let number) where number.isFinite && number == number.rounded() && abs(number) < 1e12:
      return Int(number)
    default: return nil
    }
  }
}
```

```swift
import Foundation

/// An image a plug-in hands over: a file in the folder the app gave it (`PluginContext.tempFolder`).
public struct PluginImageRef: Equatable, Sendable {
  public var name: String
  public var path: String

  public init(name: String, path: String) {
    self.name = name
    self.path = path
  }

  init?(_ value: JSONValue?) {
    guard case .object(let object)? = value, case .string(let path)? = object["path"], !path.isEmpty else { return nil }
    let fallback = URL(fileURLWithPath: path).lastPathComponent
    if case .string(let name)? = object["name"], !name.isEmpty {
      self.init(name: name, path: path)
    } else {
      self.init(name: fallback, path: path)
    }
  }
}

/// One pass of a pipeline: changes to the configuration, the inputs, and whether the picture the previous
/// pass made becomes the start image (plug-in design §7).
public struct PipelineStep: Equatable, Sendable {
  public var title: String
  public var fields: FieldOverlay
  /// The LoRAs of this pass; nil keeps the ones on the tab.
  public var loras: [LoRASelection]?
  /// The Moodboard of this pass; nil keeps the one on the tab.
  public var moodboard: [PluginImageRef]?
  public var startImage: PluginImageRef?
  public var useOutputAsStart: Bool

  public init(
    title: String = "", fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection]? = nil,
    moodboard: [PluginImageRef]? = nil, startImage: PluginImageRef? = nil, useOutputAsStart: Bool = false
  ) {
    self.title = title
    self.fields = fields
    self.loras = loras
    self.moodboard = moodboard
    self.startImage = startImage
    self.useOutputAsStart = useOutputAsStart
  }

  init(_ object: [String: JSONValue]) {
    var title = ""
    if case .string(let text)? = object["title"] { title = text }
    var fields = FieldOverlay()
    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
    var useOutput = false
    if case .bool(let flag)? = object["useOutputAsStart"] { useOutput = flag }
    self.init(
      title: title, fields: fields, loras: PluginContribution.loras(object["loras"]),
      moodboard: PluginContribution.images(object["moodboard"]), startImage: PluginImageRef(object["startImage"]),
      useOutputAsStart: useOutput)
  }
}

extension PipelineStep {
  /// What this pass runs with: the tab's fields with the pass's changes on top, and its own LoRAs when it
  /// has some (an empty list means no LoRA at all).
  public func fields(over base: GenerationFields) -> GenerationFields {
    var result = fields.applied(to: base)
    if let loras { result.parameters.loras = loras }
    return result
  }
}

/// A list of passes that RUN executes one after the other.
public struct PluginPipeline: Equatable, Sendable {
  public var name: String
  public var steps: [PipelineStep]

  public init(name: String = "", steps: [PipelineStep]) {
    self.name = name
    self.steps = steps
  }
}

/// The `contribute` message (plug-in → app): values for fields, LoRAs and Moodboard pictures to add, a
/// start image, a pipeline. Every part is optional; what cannot be read is left out.
public struct PluginContribution: Equatable, Sendable {
  public var fields: FieldOverlay
  public var loras: [LoRASelection]
  public var moodboard: [PluginImageRef]
  public var startImage: PluginImageRef?
  public var pipeline: PluginPipeline?

  public init(
    fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection] = [], moodboard: [PluginImageRef] = [],
    startImage: PluginImageRef? = nil, pipeline: PluginPipeline? = nil
  ) {
    self.fields = fields
    self.loras = loras
    self.moodboard = moodboard
    self.startImage = startImage
    self.pipeline = pipeline
  }

  /// Nil when the data is not a JSON object.
  public init?(message: Data) {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: message), case .object(let object) = root else {
      return nil
    }
    var fields = FieldOverlay()
    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
    var pipeline: PluginPipeline?
    if case .object(let body)? = object["pipeline"], case .array(let list)? = body["steps"] {
      let steps = list.compactMap { value -> PipelineStep? in
        guard case .object(let step) = value else { return nil }
        return PipelineStep(step)
      }
      var name = ""
      if case .string(let text)? = body["name"] { name = text }
      if !steps.isEmpty { pipeline = PluginPipeline(name: name, steps: steps) }
    }
    self.init(
      fields: fields, loras: Self.loras(object["loras"]) ?? [], moodboard: Self.images(object["moodboard"]) ?? [],
      startImage: PluginImageRef(object["startImage"]), pipeline: pipeline)
  }

  /// True when the message carries nothing the app can use.
  public var isEmpty: Bool {
    fields.isEmpty && loras.isEmpty && moodboard.isEmpty && startImage == nil && pipeline == nil
  }

  static func loras(_ value: JSONValue?) -> [LoRASelection]? {
    guard case .array(let list)? = value else { return nil }
    return list.compactMap { item in
      guard let data = try? JSONEncoder().encode(item) else { return nil }
      return try? JSONDecoder().decode(LoRASelection.self, from: data)
    }
  }

  static func images(_ value: JSONValue?) -> [PluginImageRef]? {
    guard case .array(let list)? = value else { return nil }
    return list.compactMap { PluginImageRef($0) }
  }
}
```

```diff
diff --git a/Packages/Sources/HubKit/Plugin/PluginMessages.swift b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
index 806bd03..af9dc35 100644
--- a/Packages/Sources/HubKit/Plugin/PluginMessages.swift
+++ b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
@@ -7,6 +7,12 @@ public enum PluginMessageType {
   public static let activate = "activate"
   public static let deactivate = "deactivate"
   public static let notice = "notice"
+  /// Plug-in → app: values, LoRAs, pictures, a pipeline (`PluginContribution`).
+  public static let contribute = "contribute"
+  /// Plug-in → app: a question for the language model; the answer is `{"type":"llm","text":…}`.
+  public static let llm = "llm"
+  /// The answer to a message the app could not use: `{"type":"error","text":…}`.
+  public static let error = "error"
   public static let unsupported = "unsupported"
   public static let ok = "ok"
 
@@ -15,6 +21,11 @@ public enum PluginMessageType {
     (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["type"] as? String
   }
 
+  /// `{"type":"error","text":text}` as data.
+  public static func failure(_ text: String) -> Data {
+    (try? JSONSerialization.data(withJSONObject: ["type": error, "text": text])) ?? bare(error)
+  }
+
   /// `{"type": type}` as data.
   public static func bare(_ type: String) -> Data {
     Data(#"{"type":"\#(type)"}"#.utf8)
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `92 tests … passed` (10 nuovi); gli altri invariati.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: i tipi del contratto di M8b (campi contribuibili, messaggio contribute, pipeline)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Lo store dei contributi (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/ContributionStore.swift`
- Test: `Packages/Tests/HubCoreTests/ContributionStoreTests.swift` (nuovo; definisce `FakeContributionTarget`, usato anche dal Task 4)

**Interfaces:**
- Consumes: i tipi del Task 1.
- Produces (HubCore, `public`):
  - `struct FieldMark: Equatable, Sendable` (`pluginID`, `value: FieldValue` già limitato, `isOverridden`);
  - `struct PipelineContribution: Equatable, Sendable` (`pluginID`, `pipeline: PluginPipeline`);
  - `struct ContributionConflict: Identifiable, Equatable, Sendable` (`id`, `subject: .field(ContributionField) | .startImage | .pipeline`, `current` e `proposed: Side(pluginID, content: .value(FieldValue) | .image(String) | .passes(Int))`);
  - `@MainActor protocol ContributionTarget: AnyObject`: `var fields: GenerationFields { get set }`, `loraFiles: Set<String>`, `addLoRA(_:)` (aggiunge o aggiorna lo stesso file), `moodboardIDs: Set<UUID>`, `startImageID: UUID?`, `addMoodboardImage(_:from:) throws -> UUID`, `removeMoodboardImage(_:)`, `setStartImage(_:from:) throws -> UUID`;
  - `@MainActor @Observable final class ContributionStore`: `marks: [ContributionField: FieldMark]`, `loraPlugins: [String: String]` (file → plug-in), `moodboardPlugins: [UUID: String]`, `startImage: (pluginID, id, name)?`, `pipeline: PipelineContribution?`, `conflicts: [ContributionConflict]`, `weak var target`; `receive(_ contribution: PluginContribution, from pluginID: String) -> [String]` (i motivi di ciò che non si è potuto usare; senza `target` un motivo solo); `choose(_ conflictID: UUID, proposed: Bool)`; `dismissConflicts()`; `reconcile()` (aggiorna `isOverridden` e dimentica LoRA, immagini e immagine di partenza che non ci sono più); `forget(_ pluginID: String)` (segni, LoRA, immagini, immagine di partenza, pipeline e conflitti di quel plug-in; i valori restano); `removePipeline()`.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
final class FakeContributionTarget: ContributionTarget {
  var fields = GenerationFields()
  private(set) var loras: [LoRASelection] = []
  private(set) var moodboard: [UUID: String] = [:]
  private(set) var startImageName: String?
  private(set) var startID: UUID?
  var failImages = false

  var loraFiles: Set<String> { Set(loras.map(\.file)) }
  var moodboardIDs: Set<UUID> { Set(moodboard.keys) }
  var startImageID: UUID? { startID }

  func addLoRA(_ lora: LoRASelection) {
    if let index = loras.firstIndex(where: { $0.file == lora.file }) { loras[index] = lora } else { loras.append(lora) }
  }

  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    struct Failure: Error {}
    if failImages { throw Failure() }
    let id = UUID()
    moodboard[id] = image.name
    return id
  }

  func removeMoodboardImage(_ id: UUID) { moodboard[id] = nil }

  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
    let id = UUID()
    startID = id
    startImageName = image.name
    return id
  }

  func userRemovesStartImage() { startID = nil }
  func userRemovesLoRA(_ file: String) { loras.removeAll { $0.file == file } }
}

@MainActor
struct ContributionStoreTests {
  let target = FakeContributionTarget()
  let store = ContributionStore()

  init() { store.target = target }

  private func contribution(_ fields: [ContributionField: FieldValue] = [:], loras: [LoRASelection] = [], moodboard: [String] = [], start: String? = nil, pipeline: PluginPipeline? = nil) -> PluginContribution {
    PluginContribution(
      fields: FieldOverlay(fields), loras: loras, moodboard: moodboard.map { PluginImageRef(name: $0, path: "/tmp/\($0)") },
      startImage: start.map { PluginImageRef(name: $0, path: "/tmp/\($0)") }, pipeline: pipeline)
  }

  private func pipeline(_ passes: Int) -> PluginPipeline {
    PluginPipeline(name: "p", steps: Array(repeating: PipelineStep(), count: passes))
  }

  @Test func aValueGoesInTheFieldAndTheFieldIsMarkedForThePlugin() {
    store.receive(contribution([.steps: .int(24), .prompt: .text("a cat")]), from: "a")
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.prompt == "a cat")
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(24), isOverridden: false))
    #expect(store.marks[.prompt]?.pluginID == "a")
  }

  @Test func theMarkedValueIsTheLimitedOne() {
    store.receive(contribution([.width: .int(1000)]), from: "a")
    #expect(target.fields.parameters.width == 1024)
    #expect(store.marks[.width]?.value == .int(1024))
  }

  @Test func changingTheFieldByHandLosesTheTealAndKeepsThePluginsValue() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(24), isOverridden: true))
  }

  @Test func typingThePluginsValueBackBringsTheTealBack() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    target.fields.parameters.steps = 24
    store.reconcile()
    #expect(store.marks[.steps]?.isOverridden == false)
  }

  @Test func theSamePluginSendingAgainStartsOverEvenAboveAManualChange() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    store.receive(contribution([.steps: .int(12)]), from: "a")
    #expect(target.fields.parameters.steps == 12)
    #expect(store.marks[.steps] == FieldMark(pluginID: "a", value: .int(12), isOverridden: false))
    #expect(store.conflicts.isEmpty)
  }

  @Test func aValuePluginsSetOverAManualOneNeverMakesAConflict() {
    target.fields.parameters.steps = 30
    store.receive(contribution([.steps: .int(24)]), from: "a")
    #expect(target.fields.parameters.steps == 24)
    #expect(store.conflicts.isEmpty)
  }

  @Test func anotherPluginOnAMarkedFieldIsAConflictAndTheFieldWaits() {
    store.receive(contribution([.steps: .int(24), .shift: .double(3)]), from: "a")
    store.receive(contribution([.steps: .int(8), .shift: .double(3), .guidanceScale: .double(2)]), from: "b")
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.parameters.guidanceScale == 2)
    #expect(store.conflicts.count == 1)
    let conflict = store.conflicts[0]
    #expect(conflict.subject == .field(.steps))
    #expect(conflict.current == .init(pluginID: "a", content: .value(.int(24))))
    #expect(conflict.proposed == .init(pluginID: "b", content: .value(.int(8))))
  }

  @Test func theConflictAlsoCountsWhenTheFirstValueWasOverriddenByHand() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    target.fields.parameters.steps = 30
    store.reconcile()
    store.receive(contribution([.steps: .int(8)]), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(target.fields.parameters.steps == 30)
  }

  @Test func choosingTheNewPluginPutsItsValueInWithTheTeal() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(target.fields.parameters.steps == 8)
    #expect(store.marks[.steps] == FieldMark(pluginID: "b", value: .int(8), isOverridden: false))
    #expect(store.conflicts.isEmpty)
  }

  @Test func choosingTheCurrentPluginLeavesEverythingAsItIs() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.choose(store.conflicts[0].id, proposed: false)
    #expect(target.fields.parameters.steps == 24)
    #expect(store.marks[.steps]?.pluginID == "a")
    #expect(store.conflicts.isEmpty)
  }

  @Test func escapeLeavesTheFieldsAsTheyAre() {
    store.receive(contribution([.steps: .int(24), .shift: .double(1)]), from: "a")
    store.receive(contribution([.steps: .int(8), .shift: .double(2)]), from: "b")
    #expect(store.conflicts.count == 2)
    store.dismissConflicts()
    #expect(store.conflicts.isEmpty)
    #expect(target.fields.parameters.steps == 24)
    #expect(target.fields.parameters.shift == 1)
  }

  @Test func theSamePluginAskingAgainReplacesItsEarlierQuestion() {
    store.receive(contribution([.steps: .int(24)]), from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    store.receive(contribution([.steps: .int(6)]), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(store.conflicts[0].proposed.content == .value(.int(6)))
  }

  @Test func lorasFromDifferentPluginsAddUpWithoutAConflict() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.5)]), from: "a")
    store.receive(contribution(loras: [LoRASelection(file: "y.ckpt")]), from: "b")
    #expect(target.loraFiles == ["x.ckpt", "y.ckpt"])
    #expect(store.loraPlugins == ["x.ckpt": "a", "y.ckpt": "b"])
    #expect(store.conflicts.isEmpty)
  }

  @Test func aLoRAAlreadyThereTakesTheLastPluginsWeight() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.5)]), from: "a")
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt", weight: 0.9)]), from: "b")
    #expect(target.loras.map(\.weight) == [0.9])
    #expect(store.loraPlugins["x.ckpt"] == "b")
  }

  @Test func aLoRATheUserRemovedIsForgotten() {
    store.receive(contribution(loras: [LoRASelection(file: "x.ckpt")]), from: "a")
    target.userRemovesLoRA("x.ckpt")
    store.reconcile()
    #expect(store.loraPlugins.isEmpty)
  }

  @Test func moodboardPicturesFromDifferentPluginsAddUp() {
    store.receive(contribution(moodboard: ["a.png"]), from: "a")
    store.receive(contribution(moodboard: ["b.png"]), from: "b")
    #expect(Set(target.moodboard.values) == ["a.png", "b.png"])
    #expect(Set(store.moodboardPlugins.values) == ["a", "b"])
    #expect(store.conflicts.isEmpty)
  }

  @Test func aPluginSendingItsPicturesAgainReplacesTheOnesItSentBefore() {
    store.receive(contribution(moodboard: ["a.png"]), from: "a")
    store.receive(contribution(moodboard: ["b.png"]), from: "b")
    store.receive(contribution(moodboard: ["a2.png"]), from: "a")
    #expect(Set(target.moodboard.values) == ["a2.png", "b.png"])
  }

  @Test func aPictureThatCannotBeReadIsReportedAndTheRestGoesIn() {
    target.failImages = true
    let problems = store.receive(contribution([.steps: .int(5)], moodboard: ["a.png"]), from: "a")
    #expect(problems.count == 1)
    #expect(target.fields.parameters.steps == 5)
    #expect(store.moodboardPlugins.isEmpty)
  }

  @Test func theStartImageFromTwoPluginsIsAConflict() {
    store.receive(contribution(start: "one.png"), from: "a")
    store.receive(contribution(start: "two.png"), from: "b")
    #expect(target.startImageName == "one.png")
    #expect(store.conflicts.map(\.subject) == [.startImage])
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(target.startImageName == "two.png")
    #expect(store.startImage?.pluginID == "b")
  }

  @Test func aStartImageTheUserReplacedIsNoLongerThePluginsAndMakesNoConflict() {
    store.receive(contribution(start: "one.png"), from: "a")
    target.userRemovesStartImage()
    store.reconcile()
    #expect(store.startImage == nil)
    store.receive(contribution(start: "two.png"), from: "b")
    #expect(store.conflicts.isEmpty)
    #expect(target.startImageName == "two.png")
  }

  @Test func aPipelineFromTwoPluginsIsAConflictAndOneFromTheSamePluginReplaces() {
    store.receive(contribution(pipeline: pipeline(2)), from: "a")
    store.receive(contribution(pipeline: pipeline(3)), from: "a")
    #expect(store.pipeline?.pipeline.steps.count == 3)
    #expect(store.conflicts.isEmpty)
    store.receive(contribution(pipeline: pipeline(1)), from: "b")
    #expect(store.conflicts.count == 1)
    #expect(store.conflicts[0].current.content == .passes(3))
    #expect(store.conflicts[0].proposed.content == .passes(1))
    store.choose(store.conflicts[0].id, proposed: true)
    #expect(store.pipeline?.pluginID == "b")
  }

  @Test func theUserCanTakeThePipelineAway() {
    store.receive(contribution(pipeline: pipeline(2)), from: "a")
    store.removePipeline()
    #expect(store.pipeline == nil)
  }

  @Test func turningAPluginOffTakesItsMarksAndPipelineButKeepsTheValues() {
    store.receive(
      contribution([.steps: .int(24)], loras: [LoRASelection(file: "x.ckpt")], moodboard: ["a.png"], start: "s.png", pipeline: pipeline(2)),
      from: "a")
    store.receive(contribution([.steps: .int(8)]), from: "b")
    #expect(store.conflicts.count == 1)
    store.forget("a")
    #expect(store.marks.isEmpty)
    #expect(store.loraPlugins.isEmpty)
    #expect(store.moodboardPlugins.isEmpty)
    #expect(store.startImage == nil)
    #expect(store.pipeline == nil)
    #expect(store.conflicts.isEmpty)
    #expect(target.fields.parameters.steps == 24)
    #expect(target.loraFiles == ["x.ckpt"])
    #expect(target.moodboard.count == 1)
  }

  @Test func withoutATargetNothingIsTaken() {
    let lonely = ContributionStore()
    #expect(!lonely.receive(contribution([.steps: .int(5)]), from: "a").isEmpty)
    #expect(lonely.marks.isEmpty)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter ContributionStoreTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find type 'ContributionTarget' in scope`.

- [ ] **Step 3: Implementare**

```swift
import Foundation
import HubKit
import Observation

/// A field a plug-in filled: teal while the field still holds the plug-in's value; once the user changes it
/// the teal goes and the plug-in's value stays for reference (plug-in design §7).
public struct FieldMark: Equatable, Sendable {
  public let pluginID: String
  /// What the plug-in sent, already limited as the card limits it.
  public let value: FieldValue
  public var isOverridden: Bool
}

/// The pipeline a plug-in proposed, shown on the Run button.
public struct PipelineContribution: Equatable, Sendable {
  public let pluginID: String
  public let pipeline: PluginPipeline
}

/// Two plug-ins want the same thing: the user picks one in a pop-up (the only conflict there is).
public struct ContributionConflict: Identifiable, Equatable, Sendable {
  public enum Subject: Equatable, Sendable {
    case field(ContributionField)
    case startImage
    case pipeline
  }

  public enum Content: Equatable, Sendable {
    case value(FieldValue)
    /// The name of a picture.
    case image(String)
    /// The number of passes of a pipeline.
    case passes(Int)
  }

  public struct Side: Equatable, Sendable {
    public let pluginID: String
    public let content: Content
  }

  public let id = UUID()
  public let subject: Subject
  /// What the tab has now, from another plug-in.
  public let current: Side
  /// What the plug-in that is writing now wants.
  public let proposed: Side
  let payload: Payload

  enum Payload: Equatable, Sendable {
    case field(ContributionField, FieldValue)
    case startImage(PluginImageRef)
    case pipeline(PluginPipeline)
  }
}

/// What the store needs from the tab: the fields, the LoRA list, the Control tab's pictures.
@MainActor
public protocol ContributionTarget: AnyObject {
  var fields: GenerationFields { get set }
  var loraFiles: Set<String> { get }
  /// Adds the LoRA, or gives the one with the same file the new weight, mode and trigger.
  func addLoRA(_ lora: LoRASelection)
  var moodboardIDs: Set<UUID> { get }
  var startImageID: UUID? { get }
  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID
  func removeMoodboardImage(_ id: UUID)
  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID
}

/// Remembers what each plug-in contributed, so the tab can show it (teal, the value in brackets) and so a
/// second plug-in writing the same field can be told apart (plug-in design §7). Plug-ins never block
/// anything: a field is always editable, and RUN sends what the fields hold.
@MainActor
@Observable
public final class ContributionStore {
  public private(set) var marks: [ContributionField: FieldMark] = [:]
  /// LoRA file → the plug-in that added it.
  public private(set) var loraPlugins: [String: String] = [:]
  /// Moodboard picture → the plug-in that added it.
  public private(set) var moodboardPlugins: [UUID: String] = [:]
  public private(set) var startImage: (pluginID: String, id: UUID, name: String)?
  public private(set) var pipeline: PipelineContribution?
  /// Waiting for the user, in order; the pop-up lists them all.
  public private(set) var conflicts: [ContributionConflict] = []

  @ObservationIgnored public weak var target: (any ContributionTarget)?

  public init() {}

  /// Takes a contribution. Fields, LoRAs and Moodboard pictures that do not clash go in at once; what clashes
  /// with another plug-in's becomes a conflict. Returns the reasons for what could not be used.
  @discardableResult
  public func receive(_ contribution: PluginContribution, from pluginID: String) -> [String] {
    guard let target else { return ["The app is not ready."] }
    var problems: [String] = []

    var accepted: [ContributionField: FieldValue] = [:]
    for field in contribution.fields.fields {
      guard let value = contribution.fields.values[field] else { continue }
      let limited = Self.limited(value, for: field, in: target.fields)
      if let mark = marks[field], mark.pluginID != pluginID, mark.value != limited {
        addConflict(
          subject: .field(field), current: .init(pluginID: mark.pluginID, content: .value(mark.value)),
          proposed: .init(pluginID: pluginID, content: .value(limited)), payload: .field(field, value))
      } else {
        accepted[field] = value
      }
    }
    if !accepted.isEmpty {
      let applied = FieldOverlay(accepted).applied(to: target.fields)
      target.fields = applied
      for field in accepted.keys {
        marks[field] = FieldMark(pluginID: pluginID, value: applied.value(of: field), isOverridden: false)
      }
    }

    for lora in contribution.loras {
      target.addLoRA(lora)
      loraPlugins[lora.file] = pluginID
    }

    if !contribution.moodboard.isEmpty {
      // A plug-in that sends its pictures again replaces the ones it sent before.
      for (id, owner) in moodboardPlugins where owner == pluginID {
        target.removeMoodboardImage(id)
        moodboardPlugins[id] = nil
      }
      for image in contribution.moodboard {
        do {
          moodboardPlugins[try target.addMoodboardImage(image, from: pluginID)] = pluginID
        } catch {
          problems.append("\(image.name): \(error)")
        }
      }
    }

    if let image = contribution.startImage {
      if let held = startImage, held.pluginID != pluginID, target.startImageID == held.id {
        addConflict(
          subject: .startImage, current: .init(pluginID: held.pluginID, content: .image(held.name)),
          proposed: .init(pluginID: pluginID, content: .image(image.name)), payload: .startImage(image))
      } else {
        do {
          startImage = (pluginID, try target.setStartImage(image, from: pluginID), image.name)
        } catch {
          problems.append("\(image.name): \(error)")
        }
      }
    }

    if let proposed = contribution.pipeline {
      if let held = pipeline, held.pluginID != pluginID {
        addConflict(
          subject: .pipeline, current: .init(pluginID: held.pluginID, content: .passes(held.pipeline.steps.count)),
          proposed: .init(pluginID: pluginID, content: .passes(proposed.steps.count)), payload: .pipeline(proposed))
      } else {
        pipeline = PipelineContribution(pluginID: pluginID, pipeline: proposed)
      }
    }
    return problems
  }

  /// The user's pick in the pop-up: the plug-in that was writing (`proposed`) or the one already there.
  public func choose(_ conflictID: UUID, proposed: Bool) {
    guard let index = conflicts.firstIndex(where: { $0.id == conflictID }) else { return }
    let conflict = conflicts.remove(at: index)
    guard proposed, let target else { return }
    let owner = conflict.proposed.pluginID
    switch conflict.payload {
    case .field(let field, let value):
      let applied = FieldOverlay([field: value]).applied(to: target.fields)
      target.fields = applied
      marks[field] = FieldMark(pluginID: owner, value: applied.value(of: field), isOverridden: false)
    case .startImage(let image):
      if let id = try? target.setStartImage(image, from: owner) { startImage = (owner, id, image.name) }
    case .pipeline(let plan):
      pipeline = PipelineContribution(pluginID: owner, pipeline: plan)
    }
  }

  /// Esc: the fields stay as they are.
  public func dismissConflicts() { conflicts = [] }

  /// The tab's fields or pictures changed: a field that no longer holds the plug-in's value loses its teal,
  /// and a LoRA, Moodboard picture or start image that is gone is forgotten.
  public func reconcile() {
    guard let target else { return }
    let fields = target.fields
    for (field, mark) in marks {
      let overridden = fields.value(of: field) != mark.value
      if overridden != mark.isOverridden { marks[field]?.isOverridden = overridden }
    }
    let files = target.loraFiles
    if loraPlugins.keys.contains(where: { !files.contains($0) }) { loraPlugins = loraPlugins.filter { files.contains($0.key) } }
    let ids = target.moodboardIDs
    if moodboardPlugins.keys.contains(where: { !ids.contains($0) }) {
      moodboardPlugins = moodboardPlugins.filter { ids.contains($0.key) }
    }
    if let held = startImage, target.startImageID != held.id { startImage = nil }
  }

  /// The plug-in was turned off: its teal, its brackets and its pipeline go; the values stay as they are.
  public func forget(_ pluginID: String) {
    marks = marks.filter { $0.value.pluginID != pluginID }
    loraPlugins = loraPlugins.filter { $0.value != pluginID }
    moodboardPlugins = moodboardPlugins.filter { $0.value != pluginID }
    if startImage?.pluginID == pluginID { startImage = nil }
    if pipeline?.pluginID == pluginID { pipeline = nil }
    conflicts.removeAll { $0.current.pluginID == pluginID || $0.proposed.pluginID == pluginID }
  }

  /// "Take away the pipeline" in the Run button's menu.
  public func removePipeline() { pipeline = nil }

  private func addConflict(
    subject: ContributionConflict.Subject, current: ContributionConflict.Side, proposed: ContributionConflict.Side,
    payload: ContributionConflict.Payload
  ) {
    // The same plug-in asking again for the same thing replaces its earlier question.
    conflicts.removeAll { $0.subject == subject && $0.proposed.pluginID == proposed.pluginID }
    conflicts.append(ContributionConflict(subject: subject, current: current, proposed: proposed, payload: payload))
  }

  private static func limited(_ value: FieldValue, for field: ContributionField, in fields: GenerationFields) -> FieldValue {
    FieldOverlay([field: value]).applied(to: fields).value(of: field)
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `422 tests … passed` (24 nuovi).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: lo store dei contributi (segni sui campi, conflitti, LoRA, Moodboard, immagine di partenza, pipeline)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Gli ingressi di un passaggio della pipeline (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Plugins/PipelineInputs.swift`
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift`
- Test: `Packages/Tests/HubCoreTests/PipelineInputsTests.swift` (nuovo)

**Interfaces:**
- Consumes: `PipelineStep`, `PluginImageRef` (Task 1); `GenerationInputs`, `GenerationHint`, `InputComposer.frame`, `PNGImageStore.image(at:maxPixel:)`, `ControlStore.pngData(of:)` (esistenti).
- Produces (HubCore, `public`):
  - `enum PipelineInputs`: `inputs(for step: PipelineStep, base: GenerationInputs, previousOutput: CGImage?, canvasWidth: Int, canvasHeight: Int, usesMoodboard: Bool) -> GenerationInputs`: se il passaggio prende l'output precedente (e c'è) o nomina una `startImage`, l'immagine di partenza è quella, inquadrata sul canvas, e la maschera sparisce; se ha un `moodboard`, sostituisce le immagini del tab (a 1024 pixel sul lato lungo; quelle che non si leggono sono lasciate fuori; nessuna se il modello non usa il Moodboard);
  - `enum PluginImages`: `image(_ ref: PluginImageRef, maxPixel: Int) -> CGImage?`, `hint(_ ref: PluginImageRef) -> GenerationHint?`;
  - `ControlStore.setImage(data:name:source:)` e `addMoodboardImage(data:name:source:)` restituiscono l'`UUID` dell'immagine messa (`@discardableResult`).

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import ImageIO
import HubKit
import Testing
import UniformTypeIdentifiers

@testable import HubCore

struct PipelineInputsTests {
  let folder: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipeline-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()

  func solid(_ red: Double, _ green: Double, _ blue: Double, side: Int = 64) -> CGImage {
    let context = CGContext(
      data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    return context.makeImage()!
  }

  func write(_ image: CGImage, as name: String) -> PluginImageRef {
    let url = folder.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    return PluginImageRef(name: name, path: url.path)
  }

  func pixel(_ image: CGImage) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
    return bytes.map(Int.init)
  }

  func base() -> GenerationInputs {
    GenerationInputs(
      image: solid(0, 1, 0), hints: [GenerationHint(imageData: Data([1]))], mask: solid(1, 1, 1), enableInpainting: true)
  }

  func run(_ step: PipelineStep, previous: CGImage? = nil, usesMoodboard: Bool = true) -> GenerationInputs {
    PipelineInputs.inputs(
      for: step, base: base(), previousOutput: previous, canvasWidth: 128, canvasHeight: 64, usesMoodboard: usesMoodboard)
  }

  @Test func aPassThatAsksForNothingKeepsTheTabsInputs() {
    let result = run(PipelineStep())
    #expect(result.image?.width == 64)
    #expect(result.mask != nil)
    #expect(result.hints.count == 1 && result.enableInpainting)
  }

  @Test func thePreviousOutputBecomesTheStartImageFramedToTheCanvasWithoutTheMask() throws {
    let result = run(PipelineStep(useOutputAsStart: true), previous: solid(1, 0, 0))
    let image = try #require(result.image)
    #expect(image.width == 128 && image.height == 64)
    #expect(pixel(image)[0] > 250)
    #expect(result.mask == nil)
  }

  @Test func withoutAPreviousOutputTheTabsImageStays() {
    let result = run(PipelineStep(useOutputAsStart: true), previous: nil)
    #expect(result.image?.width == 64 && result.mask != nil)
  }

  @Test func aPassCanNameItsOwnStartImage() throws {
    let blue = write(solid(0, 0, 1), as: "blue.png")
    let result = run(PipelineStep(startImage: blue), previous: solid(1, 0, 0))
    #expect(try #require(result.image).width == 128)
    #expect(pixel(try #require(result.image))[2] > 250)
    #expect(result.mask == nil)
  }

  @Test func thePassMoodboardReplacesTheTabsAndAnUnreadablePictureIsLeftOut() {
    let sphere = write(solid(0.5, 0.5, 0.5), as: "sphere.png")
    let result = run(PipelineStep(moodboard: [sphere, PluginImageRef(name: "gone", path: folder.appendingPathComponent("gone.png").path)]))
    #expect(result.hints.count == 1)
    #expect(result.hints.first?.imageData != Data([1]))
    #expect(run(PipelineStep(moodboard: [])).hints.isEmpty)
  }

  @Test func aModelThatDoesNotReadTheMoodboardGetsNone() {
    let sphere = write(solid(0.5, 0.5, 0.5), as: "sphere.png")
    #expect(run(PipelineStep(moodboard: [sphere]), usesMoodboard: false).hints.isEmpty)
  }

  @Test func aMoodboardPictureIsReducedToTheLongSideOf1024() throws {
    let big = write(solid(0.2, 0.2, 0.2, side: 2000), as: "big.png")
    let hint = try #require(PluginImages.hint(big))
    let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(max(image.width, image.height) == 1024)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter PipelineInputsTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'PipelineInputs' in scope`.

- [ ] **Step 3: Implementare**

```swift
import CoreGraphics
import Foundation
import HubKit

/// The inputs of one pass of a plug-in's pipeline (plug-in design §7): the tab's own inputs, with the start
/// image and the Moodboard the pass asks for put in their place.
public enum PipelineInputs {
  /// Longest side of a Moodboard picture when it is sent (as for the Moodboard of the Control tab).
  static let hintPixels = 1024

  /// `base` is what the tab would send (framed to the pass's canvas). A pass that takes the previous
  /// output, or names its own start image, replaces the start image: framed to the canvas, with no mask (the
  /// mask belongs to the tab's picture). A pass with a Moodboard replaces the Moodboard; a picture that
  /// cannot be read is left out. `usesMoodboard` is false for models that do not read it.
  public static func inputs(
    for step: PipelineStep, base: GenerationInputs, previousOutput: CGImage?, canvasWidth: Int, canvasHeight: Int,
    usesMoodboard: Bool
  ) -> GenerationInputs {
    var result = base
    let replacement: CGImage? =
      step.useOutputAsStart && previousOutput != nil
      ? previousOutput : step.startImage.flatMap { PluginImages.image($0, maxPixel: 4096) }
    if let replacement,
      let framed = InputComposer.frame(replacement, toWidth: canvasWidth, height: canvasHeight, framing: Framing())
    {
      result.image = framed
      result.mask = nil
    }
    if let refs = step.moodboard {
      result.hints = usesMoodboard ? refs.compactMap { PluginImages.hint($0) } : []
    }
    return result
  }
}

/// Pictures a plug-in leaves in its folder.
public enum PluginImages {
  /// The picture at the path, no larger than `maxPixel` on its long side; nil when it cannot be read.
  public static func image(_ ref: PluginImageRef, maxPixel: Int) -> CGImage? {
    PNGImageStore.image(at: URL(fileURLWithPath: ref.path), maxPixel: maxPixel)
  }

  /// A Moodboard picture of a RUN (PNG, long side at most 1024); nil when it cannot be read.
  public static func hint(_ ref: PluginImageRef) -> GenerationHint? {
    guard let image = image(ref, maxPixel: PipelineInputs.hintPixels), let data = ControlStore.pngData(of: image) else {
      return nil
    }
    return GenerationHint(imageData: data, weight: 1)
  }
}
```

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index a40a932..b288b44 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -97,7 +97,8 @@ public final class ControlStore {
 
   /// Takes a picture from its bytes: copies it, describes it, and makes it the start image
   /// (the one there was, if any, can be brought back with `undo`). The framing starts centered.
-  public func setImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
+  @discardableResult
+  public func setImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) -> UUID {
     let image = try reference(from: data, name: name, source: source)
     var next = inputs
     next.image = image
@@ -107,6 +108,7 @@ public final class ControlStore {
     let replaced = inputs.image
     commit(next)
     notice = replaced.map { .replaced(name: $0.name) }
+    return image.id
   }
 
   /// A picture that only exists in memory (a result that could not be saved): stored as PNG.
@@ -228,11 +230,13 @@ public final class ControlStore {
   // MARK: Moodboard
 
   /// Adds a picture to the Moodboard (on, at the end).
-  public func addMoodboardImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
+  @discardableResult
+  public func addMoodboardImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) -> UUID {
     let image = try reference(from: data, name: name, source: source)
     var next = inputs
     next.moodboard.append(MoodboardEntry(image: image))
     commit(next)
+    return image.id
   }
 
   public func addMoodboardImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `429 tests … passed` (7 nuovi).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: gli ingressi di un passaggio della pipeline; gli id delle immagini messe nel Control

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Il registro instrada `contribute` e `llm`

**Files:**
- Modify: `Packages/Sources/HubCore/Plugins/PluginHosting.swift`, `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `Packages/Sources/PluginHost/BundlePluginLoader.swift`, `Packages/Tests/HubCoreTests/PluginRegistryTests.swift`
- Test: `Packages/Tests/HubCoreTests/PluginRoutingTests.swift` (nuovo)

**Interfaces:**
- Consumes: `ContributionStore`, `FakeContributionTarget` (Task 2); `PluginContribution`, `PluginMessageType.failure` (Task 1).
- Produces:
  - `PluginHosting.receive(_:from:) async -> Data` (era sincrona: la domanda al modello linguistico può tardare); `BundlePluginHost.dthubSend` aspetta la risposta prima di rispondere al plug-in;
  - `PluginRegistry.contributions: ContributionStore` (`let`), `askLanguageModel: (@MainActor (String, [URL]) async throws -> String)?`;
  - `contribute` da un plug-in non attivo → `error`; da uno attivo → `{"type":"ok","conflicts":n}` (più `problems`); `llm` con `prompt` (e `images`) → `{"type":"llm","text":…}`, senza prompt, senza modello, non attivo o con un errore → `error`;
  - `setActive(_, false)` chiama `contributions.forget(_)`.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginRoutingTests {
  let root = PluginFixture.folder()
  let target = FakeContributionTarget()

  func started(_ ids: [String] = ["a"]) throws -> (PluginRegistry, FakeLoader) {
    for id in ids { try PluginFixture.bundle(in: root, id: id, name: id.uppercased()) }
    let settingsFile = root.deletingLastPathComponent().appendingPathComponent("routing-\(root.lastPathComponent).json")
    let settings = PluginSettingsStore(fileURL: settingsFile)
    settings.save(Set(ids))
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.contributions.target = target
    registry.start()
    return (registry, loader)
  }

  private func send(_ json: String, from id: String = "a", through loader: FakeLoader) async throws -> [String: Any] {
    let reply = await (try #require(loader.host)).receive(Data(json.utf8), from: id)
    return try #require(try JSONSerialization.jsonObject(with: reply) as? [String: Any])
  }

  @Test func aContributionFromAnActivePluginReachesTheTab() async throws {
    let (registry, loader) = try started()
    let reply = try await send(#"{"type":"contribute","fields":{"steps":4},"loras":[{"file":"x.ckpt"}]}"#, through: loader)
    #expect(reply["type"] as? String == "ok")
    #expect(reply["conflicts"] as? Int == 0)
    #expect(target.fields.parameters.steps == 4)
    #expect(registry.contributions.marks[.steps]?.pluginID == "a")
    #expect(target.loraFiles == ["x.ckpt"])
  }

  @Test func aPluginThatIsNotActiveContributesNothing() async throws {
    let (registry, loader) = try started()
    registry.setActive("a", false)
    let reply = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, through: loader)
    #expect(reply["type"] as? String == "error")
    #expect(target.fields.parameters.steps != 4)
  }

  @Test func anEmptyContributionIsFineAndChangesNothing() async throws {
    let (registry, loader) = try started()
    let reply = try await send(#"{"type":"contribute","fields":{"model":"x.ckpt","steps":"four"}}"#, through: loader)
    #expect(reply["type"] as? String == "ok")
    #expect(registry.contributions.marks.isEmpty)
    #expect(target.fields == GenerationFields())
  }

  @Test func theAnswerCountsTheConflictsAndNamesWhatCouldNotBeRead() async throws {
    let (_, loader) = try started(["a", "b"])
    _ = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, from: "a", through: loader)
    target.failImages = true
    let reply = try await send(#"{"type":"contribute","fields":{"steps":9},"moodboard":[{"path":"/tmp/x.png"}]}"#, from: "b", through: loader)
    #expect(reply["conflicts"] as? Int == 1)
    #expect((reply["problems"] as? [String])?.count == 1)
  }

  @Test func turningAPluginOffFromTheHeaderTakesItsMarks() async throws {
    let (registry, loader) = try started()
    _ = try await send(#"{"type":"contribute","fields":{"steps":4}}"#, through: loader)
    registry.setActive("a", false)
    #expect(registry.contributions.marks.isEmpty)
    #expect(target.fields.parameters.steps == 4)
  }

  @Test func aQuestionForTheLanguageModelIsAnswered() async throws {
    let (registry, loader) = try started()
    var asked: (String, [URL])?
    registry.askLanguageModel = { prompt, images in
      asked = (prompt, images)
      return "Sunny."
    }
    let reply = try await send(#"{"type":"llm","prompt":"weather?","images":["/tmp/a.png"]}"#, through: loader)
    #expect(reply["type"] as? String == "llm")
    #expect(reply["text"] as? String == "Sunny.")
    #expect(asked?.0 == "weather?")
    #expect(asked?.1 == [URL(fileURLWithPath: "/tmp/a.png")])
  }

  @Test func aQuestionThatCannotBeAnsweredGetsAnError() async throws {
    let (registry, loader) = try started()
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
    registry.askLanguageModel = { _, _ in throw LanguageModelError.noModelSelected }
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
    #expect(try await send(#"{"type":"llm"}"#, through: loader)["type"] as? String == "error")
    registry.setActive("a", false)
    registry.askLanguageModel = { _, _ in "never" }
    #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
  }
}
```

I test esistenti del registro che chiamano `receive` diventano `async` (`await`): lo fa la modifica di `PluginRegistryTests` del Step 3.

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter PluginRoutingTests 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'PluginRegistry' has no member 'contributions'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PluginHosting.swift b/Packages/Sources/HubCore/Plugins/PluginHosting.swift
index 864e503..f9b16a4 100644
--- a/Packages/Sources/HubCore/Plugins/PluginHosting.swift
+++ b/Packages/Sources/HubCore/Plugins/PluginHosting.swift
@@ -14,8 +14,8 @@ public protocol LoadedPlugin: AnyObject {
 /// What a plug-in calls into: the app side of the message channel.
 @MainActor
 public protocol PluginHosting: AnyObject {
-  /// Plug-in → app; the answer goes back to the plug-in.
-  func receive(_ message: Data, from pluginID: String) -> Data
+  /// Plug-in → app; the answer goes back to the plug-in. Async: a question for the language model takes a while.
+  func receive(_ message: Data, from pluginID: String) async -> Data
 }
 
 /// Loads the code of a plug-in bundle (the app's implementation uses `Bundle`; the tests a fake).
```

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
index 68d6e5e..c3fda7f 100644
--- a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
+++ b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
@@ -60,6 +60,11 @@ public final class PluginRegistry: PluginHosting {
   public private(set) var family: String?
   public private(set) var model: String?
 
+  /// What the active plug-ins contributed (teal fields, conflicts, the pipeline); the app sets its `target`.
+  public let contributions = ContributionStore()
+  /// Answers a plug-in's question to the language model (`llm` message); nil = no language model.
+  @ObservationIgnored public var askLanguageModel: (@MainActor (_ prompt: String, _ images: [URL]) async throws -> String)?
+
   @ObservationIgnored private let folder: PluginFolder
   @ObservationIgnored private let settings: PluginSettingsStore
   @ObservationIgnored private let loader: any PluginLoading
@@ -217,6 +222,7 @@ public final class PluginRegistry: PluginHosting {
       entries[index].isActive != isActive
     else { return }
     entries[index].isActive = isActive
+    if !isActive { contributions.forget(identifier) }
     send(PluginMessageType.bare(isActive ? PluginMessageType.activate : PluginMessageType.deactivate), to: identifier)
     if isActive { sendContext(to: identifier) }
   }
@@ -271,8 +277,12 @@ public final class PluginRegistry: PluginHosting {
 
   // MARK: PluginHosting
 
-  public func receive(_ message: Data, from pluginID: String) -> Data {
+  public func receive(_ message: Data, from pluginID: String) async -> Data {
     switch PluginMessageType.of(message) {
+    case PluginMessageType.contribute:
+      return contribute(message, from: pluginID)
+    case PluginMessageType.llm:
+      return await askModel(message, from: pluginID)
     case PluginMessageType.notice:
       if let notice = try? JSONDecoder().decode(PluginNotice.self, from: message) {
         let name = entries.first { $0.id == pluginID }?.name ?? pluginID
@@ -286,4 +296,37 @@ public final class PluginRegistry: PluginHosting {
       return PluginMessageType.bare(PluginMessageType.unsupported)
     }
   }
+
+  private func isActive(_ pluginID: String) -> Bool {
+    entries.first { $0.id == pluginID }?.isActive ?? false
+  }
+
+  /// Only a plug-in that is on for this job contributes; the answer says how it went.
+  private func contribute(_ message: Data, from pluginID: String) -> Data {
+    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
+    guard let contribution = PluginContribution(message: message) else {
+      return PluginMessageType.failure("The message is not a JSON object.")
+    }
+    let problems = contributions.receive(contribution, from: pluginID)
+    var answer: [String: Any] = ["type": PluginMessageType.ok, "conflicts": contributions.conflicts.count]
+    if !problems.isEmpty { answer["problems"] = problems }
+    return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
+  }
+
+  /// `{"type":"llm","prompt":…,"images":[paths]}` → `{"type":"llm","text":…}`.
+  private func askModel(_ message: Data, from pluginID: String) async -> Data {
+    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
+    guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
+      let prompt = object["prompt"] as? String, !prompt.isEmpty
+    else { return PluginMessageType.failure("The message has no prompt.") }
+    guard let ask = askLanguageModel else { return PluginMessageType.failure("There is no language model.") }
+    let images = (object["images"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
+    do {
+      let text = try await ask(prompt, images)
+      return (try? JSONSerialization.data(withJSONObject: ["type": PluginMessageType.llm, "text": text]))
+        ?? PluginMessageType.failure("The answer could not be sent.")
+    } catch {
+      return PluginMessageType.failure(String(describing: error))
+    }
+  }
 }
```

```diff
diff --git a/Packages/Sources/PluginHost/BundlePluginLoader.swift b/Packages/Sources/PluginHost/BundlePluginLoader.swift
index 8fe4376..4b86f4a 100644
--- a/Packages/Sources/PluginHost/BundlePluginLoader.swift
+++ b/Packages/Sources/PluginHost/BundlePluginLoader.swift
@@ -81,7 +81,7 @@ final class PluginHostObject: NSObject, @unchecked Sendable {
     nonisolated(unsafe) let reply = reply
     Task { @MainActor [weak self] in
       guard let self, let host = self.host else { return reply(PluginMessageType.bare(PluginMessageType.unsupported)) }
-      reply(host.receive(message, from: self.pluginID))
+      reply(await host.receive(message, from: self.pluginID))
     }
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PluginRegistryTests.swift b/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
index db567f4..6efcf38 100644
--- a/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
+++ b/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
@@ -252,19 +252,19 @@ struct PluginRegistryTests {
     #expect(registry.needsRestart, "a loaded plug-in removed is still running until then")
   }
 
-  @Test func theNoticesOfAPluginAreKeptNewestFirstEvenAfterTheBannerIsClosed() throws {
+  @Test func theNoticesOfAPluginAreKeptNewestFirstEvenAfterTheBannerIsClosed() async throws {
     try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
     let loader = FakeLoader()
     let registry = registry(loader: loader, enabled: ["a"])
     registry.start()
     let host = try #require(loader.host)
-    _ = host.receive(Data(#"{"type":"notice","text":"one"}"#.utf8), from: "a")
-    _ = host.receive(Data(#"{"type":"notice","text":"two"}"#.utf8), from: "a")
+    _ = await host.receive(Data(#"{"type":"notice","text":"one"}"#.utf8), from: "a")
+    _ = await host.receive(Data(#"{"type":"notice","text":"two"}"#.utf8), from: "a")
     #expect(registry.lastNotice(of: "a")?.text == "two")
     registry.dismissNotice()
     #expect(registry.latestNotice == nil && registry.lastNotice(of: "a")?.text == "two")
     #expect(registry.lastNotice(of: "zzz") == nil)
-    for index in 0..<30 { _ = host.receive(Data(#"{"type":"notice","text":"n\#(index)"}"#.utf8), from: "a") }
+    for index in 0..<30 { _ = await host.receive(Data(#"{"type":"notice","text":"n\#(index)"}"#.utf8), from: "a") }
     #expect(registry.notices.count == 20 && registry.notices.first?.text == "n29")
   }
 
@@ -287,18 +287,18 @@ struct PluginRegistryTests {
     #expect(registry.entries.first?.isActive == true)
   }
 
-  @Test func aNoticeFromAPluginIsShownWithItsName() throws {
+  @Test func aNoticeFromAPluginIsShownWithItsName() async throws {
     try PluginFixture.bundle(in: root, id: "a", name: "Alpha")
     let loader = FakeLoader()
     let registry = registry(loader: loader, enabled: ["a"])
     registry.start()
-    let reply = try #require(loader.host).receive(Data(#"{"type":"notice","text":"Ready","isError":true}"#.utf8), from: "a")
+    let reply = await (try #require(loader.host)).receive(Data(#"{"type":"notice","text":"Ready","isError":true}"#.utf8), from: "a")
     #expect(PluginMessageType.of(reply) == PluginMessageType.ok)
     #expect(registry.latestNotice?.pluginName == "Alpha" && registry.latestNotice?.text == "Ready")
     #expect(registry.latestNotice?.isError == true)
     registry.dismissNotice()
     #expect(registry.latestNotice == nil)
-    let unknown = try #require(loader.host).receive(Data(#"{"type":"fly"}"#.utf8), from: "a")
+    let unknown = await (try #require(loader.host)).receive(Data(#"{"type":"fly"}"#.utf8), from: "a")
     #expect(PluginMessageType.of(unknown) == PluginMessageType.unsupported)
   }
 }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `436 tests … passed` (7 nuovi); PluginHost 5.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: il registro instrada contribute e llm; spegnere un plug-in toglie i suoi segni

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: L'app — teal, parentesi, pop-up, Run con i passaggi, pipeline

**Files:**
- Create: `App/Plugins/ContributionText.swift`, `App/Plugins/ContributionViews.swift`
- Modify: `App/Generation/GenerationController.swift`, `App/Generation/Cards/CardBinding.swift`, `App/Generation/Cards/PromptCard.swift`, `App/Generation/Cards/SamplingCard.swift`, `App/Generation/Cards/DimensionsCard.swift`, `App/Generation/Cards/SeedBatchCard.swift`, `App/Generation/Cards/LoRACard.swift`, `App/Control/ControlText.swift`, `App/Control/ImageCard.swift`, `App/Control/MoodboardCard.swift`, `App/MainWindow/HeaderBar.swift`, `App/MainWindow/MainWindowView.swift`, `App/Results/ResultsView.swift`, `App/DTHubApp.swift`, `App/Localizable.xcstrings`
- Test: nessuno nuovo — `LocalizationCatalogTests` (esistente) controlla il catalogo; le viste e `runPipeline` si verificano con la compilazione e col Task 7.

**Interfaces:**
- Consumes: `ContributionStore`, `ContributionTarget`, `PipelineInputs`, `PluginRegistry.contributions`, `askLanguageModel` (Task 2–4); `GenerationFields`, `PipelineStep.fields(over:)` (Task 1).
- Produces:
  - `GenerationController`: conforme a `ContributionTarget` (`fields` get/set, che tiene il blocco delle proporzioni; `loraFiles`, `addLoRA`, `moodboardIDs`, `startImageID`, `addMoodboardImage`, `removeMoodboardImage`, `setStartImage`); `attach(_ store: ContributionStore)`; `contributions`; `pipelinePass: (index, count)?`; ogni modifica di `prompt`, `negativePrompt` e `parameters` chiama `contributions?.reconcile()`; `run(with:)` esegue i passaggi della pipeline se c'è (`runPipeline`: per ogni passaggio i campi `pass.fields(over: fields)`, gli ingressi del tab resi per il canvas del passaggio, poi `PipelineInputs.inputs`, un `JobComposer.batches`, `session.start` e l'attesa; l'output del passaggio — il file originale se c'è — è `previousOutput` del successivo; un errore o Stop ferma tutto);
  - `CardRow(label:fields:accessory:control:)`: la riga prende il teal se uno dei `fields` è segnato e non cambiato, e mostra `(valore)` se è cambiato; le card Prompt (editor), LoRA, Campionamento, Dimensioni e Seed e batch passano i loro campi; la tessera del Moodboard e la scheda Immagine hanno il teal e «da <plug-in>» con il nome del plug-in;
  - `ContributionConflictSheet` (il pop-up, nella finestra principale: Esc o «Lascia com'è» = `dismissConflicts()`); il pulsante Run diventa «Run · N passaggi» (tooltip: plug-in e passaggi), con «Togli la pipeline» nel menu contestuale; durante la pipeline il pulsante Stop e la finestra Risultati mostrano «Passaggio i/n»;
  - `DTHubApp`: `generation.attach(plugins.contributions)` e `plugins.askLanguageModel` verso `languageModel.respond`.

- [ ] **Step 1: Stringhe**

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "contribution.on": ("on", "acceso"),
    "contribution.off": ("off", "spento"),
    "contribution.startImage": ("Start image", "Immagine di partenza"),
    "contribution.pipeline": ("Pipeline", "Pipeline"),
    "contribution.passes": ("%lld passes", "%lld passaggi"),
    "contribution.pass": ("Pass %lld", "Passaggio %lld"),
    "contribution.conflict.title": ("Two plug-ins want the same thing", "Due plug-in vogliono la stessa cosa"),
    "contribution.conflict.hint": ("Pick the one to keep. Esc leaves everything as it is.", "Scegli quale tenere. Esc lascia tutto com'\u00e8."),
    "contribution.conflict.dismiss": ("Leave as is", "Lascia com'\u00e8"),
    "header.run.pipeline": ("Run \u00b7 %lld passes", "Run \u00b7 %lld passaggi"),
    "header.run.removePipeline": ("Remove the pipeline", "Togli la pipeline"),
    "header.stop.pass": ("Pass %lld/%lld", "Passaggio %lld/%lld"),
}
for key, (en, it) in new.items():
    assert key not in d['strings'], key
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
```

Salvare lo script come `/tmp/m8b_keys.py` e lanciarlo dalla radice: `cd "/Users/existenz/Software developement/DT Hub" && python3 /tmp/m8b_keys.py`. Controllare con `git diff --stat App/Localizable.xcstrings | tail -1`.

Expected: solo righe aggiunte (`204 insertions(+)`), nessuna cancellata.

- [ ] **Step 2: Il bersaglio dei contributi e la pipeline**

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 25561a2..a7ba84e 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -11,14 +11,23 @@ import Observation
 @Observable
 final class GenerationController {
   var prompt = "" {
-    didSet { scheduleSessionSave() }
+    didSet {
+      scheduleSessionSave()
+      contributions?.reconcile()
+    }
   }
   /// Sent only when the model's family uses it (`JobComposer`).
   var negativePrompt = "" {
-    didSet { scheduleSessionSave() }
+    didSet {
+      scheduleSessionSave()
+      contributions?.reconcile()
+    }
   }
   var parameters = GenerationParameters.default {
-    didSet { scheduleSessionSave() }
+    didSet {
+      scheduleSessionSave()
+      contributions?.reconcile()
+    }
   }
   /// When on, width and height move together to keep `lockedRatio`.
   var lockRatio = false {
@@ -39,8 +48,12 @@ final class GenerationController {
   /// The Control tab's images (tab Control spec): the start image goes with every RUN.
   @ObservationIgnored let control: ControlStore
   /// True between pressing RUN and the generation starting: the language model is being freed
-  /// and a parked server brought back.
+  /// and a parked server brought back. Also true all through a pipeline, between its passes.
   private(set) var isPreparing = false
+  /// The pass of a plug-in's pipeline that is running (1-based), nil outside one.
+  private(set) var pipelinePass: (index: Int, count: Int)?
+  /// What the plug-ins contributed (teal fields, conflicts, the pipeline); set by `attach`.
+  @ObservationIgnored private(set) var contributions: ContributionStore?
 
   @ObservationIgnored private let outputSettings = OutputSettingsStore()
   @ObservationIgnored private let sessionStore: SessionStore
@@ -162,16 +175,22 @@ final class GenerationController {
   }
 
   /// Starts a RUN, split into its batches (`batchesForRun`). With a random seed, the seed
-  /// drawn for the first batch is shown in the Seed field.
+  /// drawn for the first batch is shown in the Seed field. When a plug-in proposed a pipeline, the RUN is
+  /// its passes, one after the other.
   @discardableResult
   func run(with connection: DrawThingsConnection) -> Bool {
     guard canRun(with: connection) else { return false }
     isPreparing = true
+    let passes = contributions?.pipeline?.pipeline.steps
     preparation = Task {
       // Memory first: the language model leaves, a server parked for it comes back.
       await languageModel.prepareForRun()
       await connection.ensureServerForRun()
-      let inputs = await renderInputs(in: connection)
+      if let passes {
+        await runPipeline(passes, with: connection)
+        return
+      }
+      let inputs = await renderInputs(in: connection, parameters: parameters)
       isPreparing = false
       preparation = nil
       guard !Task.isCancelled, let inputs else { return }
@@ -180,6 +199,44 @@ final class GenerationController {
     return true
   }
 
+  /// The passes of a pipeline, one after the other (plug-in design §7). Each pass runs the tab's fields with
+  /// its own changes on top; the picture a pass makes can be the next one's start image. A failed or stopped
+  /// pass ends the pipeline; the pictures already made stay in the strip.
+  private func runPipeline(_ passes: [PipelineStep], with connection: DrawThingsConnection) async {
+    defer {
+      isPreparing = false
+      pipelinePass = nil
+      preparation = nil
+    }
+    var previous: CGImage?
+    for (index, pass) in passes.enumerated() {
+      guard !Task.isCancelled else { return }
+      pipelinePass = (index + 1, passes.count)
+      let used = pass.fields(over: fields)
+      guard let base = await renderInputs(in: connection, parameters: used.parameters) else { return }
+      guard !Task.isCancelled, let backend = connection.monitor.backend, let model = connection.selection.selectedFile,
+        RunAvailability.blocker(
+          connection: connection.monitor.status, selectedModel: model, catalog: connection.monitor.catalog) == nil
+      else { return }
+      let inputs = PipelineInputs.inputs(
+        for: pass, base: base, previousOutput: previous, canvasWidth: used.parameters.width,
+        canvasHeight: used.parameters.height, usesMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard)
+      let hasTabImage = inputs.image != nil && inputs.image === base.image
+      let batches = JobComposer.batches(
+        prompt: used.prompt, negativePrompt: used.negativePrompt, model: model, family: family(in: connection),
+        parameters: used.parameters, catalog: connection.monitor.catalog,
+        imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(
+          editModel: isEditModel(in: connection),
+          hasMargins: hasTabImage && control.hasMargins(canvasWidth: used.parameters.width, canvasHeight: used.parameters.height)),
+        moodboardCount: inputs.hints.count, maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
+      session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
+      await session.waitUntilFinished()
+      if case .failed = session.phase { return }
+      guard !Task.isCancelled, let made = session.results.first else { return }
+      previous = made.fileURL.flatMap { PNGImageStore.image(at: $0, maxPixel: 4096) } ?? made.image
+    }
+  }
+
   /// Stop (button and ⌘.): ends the preparation that is under way, or the generation.
   func stop() {
     preparation?.cancel()
@@ -208,11 +265,12 @@ final class GenerationController {
 
   /// The Control tab's images framed to the canvas, decoded away from the main actor. A failure
   /// is shown as the RUN's failure, and nothing starts.
-  private func renderInputs(in connection: DrawThingsConnection) async -> GenerationInputs? {
+  private func renderInputs(in connection: DrawThingsConnection, parameters: GenerationParameters) async -> GenerationInputs? {
     // The Moodboard goes only to a model that uses it (the old families would need an adapter).
     let pending = control.pendingInputs(
       canvasWidth: parameters.width, canvasHeight: parameters.height,
-      includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard, marginFill: marginFill)
+      includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard,
+      marginFill: control.inputs.marginFill ?? MarginFill.automatic(loras: parameters.loras))
     do {
       var inputs = try await Task.detached { try pending.render() }.value
       inputs.enableInpainting = selectedModel(in: connection)?.capabilities.needsInpaintControl ?? false
@@ -229,6 +287,12 @@ final class GenerationController {
     control.inputs.marginFill ?? MarginFill.automatic(loras: parameters.loras)
   }
 
+  /// The plug-ins' contributions land here; the fields leaving their value are told to the store.
+  func attach(_ store: ContributionStore) {
+    contributions = store
+    store.target = self
+  }
+
   /// True when the chosen model is an Edit model (the canvas image is the one to modify).
   func isEditModel(in connection: DrawThingsConnection) -> Bool {
     selectedModel(in: connection)?.capabilities.isEditModel ?? false
@@ -299,3 +363,54 @@ struct CurrentFolderImageStore: ImageStore {
     try PNGImageStore(folder: OutputSettingsStore().folder()).save(image, job: job, index: index, date: date)
   }
 }
+
+// MARK: Plug-in contributions
+
+extension GenerationController: ContributionTarget {
+  /// The prompt, the negative prompt and the parameters, as one value. A change keeps a ratio lock on
+  /// the new size.
+  var fields: GenerationFields {
+    get { GenerationFields(prompt: prompt, negativePrompt: negativePrompt, parameters: parameters) }
+    set {
+      if prompt != newValue.prompt { prompt = newValue.prompt }
+      if negativePrompt != newValue.negativePrompt { negativePrompt = newValue.negativePrompt }
+      if parameters != newValue.parameters {
+        parameters = newValue.parameters
+        if lockRatio { lockedRatio = currentRatio }
+      }
+    }
+  }
+
+  var loraFiles: Set<String> { Set(parameters.loras.map(\.file)) }
+
+  func addLoRA(_ lora: LoRASelection) {
+    if parameters.loras.contains(where: { $0.file == lora.file }) {
+      parameters.updateLoRA(lora)
+    } else {
+      parameters.loras.append(lora)
+    }
+  }
+
+  var moodboardIDs: Set<UUID> { Set(control.inputs.moodboard.map(\.id)) }
+  var startImageID: UUID? { control.inputs.image?.id }
+
+  func addMoodboardImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
+    let data = try Self.read(image)
+    return try control.addMoodboardImage(data: data, name: image.name, source: .plugin(id: pluginID))
+  }
+
+  func removeMoodboardImage(_ id: UUID) { control.removeMoodboardImage(id: id) }
+
+  func setStartImage(_ image: PluginImageRef, from pluginID: String) throws -> UUID {
+    let data = try Self.read(image)
+    return try control.setImage(data: data, name: image.name, source: .plugin(id: pluginID))
+  }
+
+  private static func read(_ image: PluginImageRef) throws -> Data {
+    do {
+      return try Data(contentsOf: URL(fileURLWithPath: image.path))
+    } catch {
+      throw ControlError.unreadable(image.name)
+    }
+  }
+}
```

- [ ] **Step 3: Le viste nuove**

```swift
import HubCore
import HubKit
import SwiftUI

/// The words for what plug-ins contribute: field names, values, the pop-up of a conflict.
enum ContributionText {
  /// The name the field has in its card.
  static func name(_ field: ContributionField) -> String {
    switch field {
    case .prompt: String(localized: "card.prompt")
    case .negativePrompt: String(localized: "card.prompt.negative")
    case .width: String(localized: "card.dimensions.width")
    case .height: String(localized: "card.dimensions.height")
    case .steps: String(localized: "card.sampling.steps")
    case .guidanceScale: String(localized: "card.sampling.guidance")
    case .cfgZeroStar: String(localized: "card.sampling.cfgZero")
    case .cfgZeroInitSteps: String(localized: "card.sampling.cfgZeroInitSteps")
    case .sampler: String(localized: "card.sampling.sampler")
    case .shift: String(localized: "card.sampling.shift")
    case .resolutionDependentShift: String(localized: "card.sampling.resolutionShift")
    case .seed: String(localized: "card.seed.value")
    case .randomSeed: String(localized: "card.seed.random")
    case .batchSize: String(localized: "card.batch.size")
    case .batchCount: String(localized: "card.batch.count")
    }
  }

  /// A value as the field shows it.
  static func value(_ value: FieldValue, for field: ContributionField) -> String {
    switch value {
    case .text(let text): text
    case .int(let number): field == .sampler ? (Sampler(rawValue: number)?.displayName ?? "\(number)") : String(number)
    case .double(let number): number.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    case .bool(let flag): String(localized: flag ? "contribution.on" : "contribution.off")
    }
  }

  static func subject(_ subject: ContributionConflict.Subject) -> String {
    switch subject {
    case .field(let field): name(field)
    case .startImage: String(localized: "contribution.startImage")
    case .pipeline: String(localized: "contribution.pipeline")
    }
  }

  /// "Alpha · 24": the plug-in and what it wants, the text of a button of the pop-up.
  static func choice(_ side: ContributionConflict.Side, subject: ContributionConflict.Subject, plugins: PluginRegistry) -> String {
    let plugin = plugins.entries.first { $0.id == side.pluginID }?.name ?? side.pluginID
    let content: String =
      switch side.content {
      case .value(let value):
        if case .field(let field) = subject { Self.value(value, for: field) } else { "" }
      case .image(let name): name
      case .passes(let count): passes(count)
      }
    return "\(plugin) · \(content)"
  }

  static func passes(_ count: Int) -> String { String(format: String(localized: "contribution.passes"), count) }

  /// "Run · 2 passes".
  static func runTitle(passes count: Int) -> String {
    String(format: String(localized: "header.run.pipeline"), count)
  }

  /// The tooltip of the Run button with a pipeline: who proposed it and the passes.
  static func pipelineHelp(_ contribution: PipelineContribution, plugins: PluginRegistry) -> String {
    let plugin = plugins.entries.first { $0.id == contribution.pluginID }?.name ?? contribution.pluginID
    let list = contribution.pipeline.steps.enumerated().map { index, step in
      "\(index + 1). " + (step.title.isEmpty ? String(format: String(localized: "contribution.pass"), index + 1) : step.title)
    }
    return ([plugin + (contribution.pipeline.name.isEmpty ? "" : " · " + contribution.pipeline.name)] + list).joined(separator: "\n")
  }
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// Teal at 30% behind what a plug-in filled and the user has not changed (plug-in design §7).
extension View {
  /// Highlights the row when one of `fields` holds a plug-in's value that has not been changed.
  func contributed(_ fields: [ContributionField], in store: ContributionStore?) -> some View {
    modifier(ContributedBackground(active: fields.contains { store?.marks[$0]?.isOverridden == false }))
  }

  /// Highlights the view (a LoRA, a picture) when `isContributed`.
  func contributed(_ isContributed: Bool) -> some View {
    modifier(ContributedBackground(active: isContributed))
  }
}

private struct ContributedBackground: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    content.background {
      if active {
        RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
          .fill(DS.accent.opacity(0.3))
          .padding(.horizontal, -6)
          .padding(.vertical, -3)
      }
    }
  }
}

/// The plug-in's value kept in brackets beside the user's own: `30 (24)`.
struct ContributedReference: View {
  let field: ContributionField
  let store: ContributionStore?

  var body: some View {
    if let mark = store?.marks[field], mark.isOverridden {
      Text(verbatim: "(\(ContributionText.value(mark.value, for: field)))")
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }
  }
}

/// The pop-up when two plug-ins want the same field: one button per plug-in and value. Esc leaves the
/// fields as they are.
struct ContributionConflictSheet: View {
  let plugins: PluginRegistry

  private var store: ContributionStore { plugins.contributions }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.panelPadding) {
      Text("contribution.conflict.title").font(.headline)
      Text("contribution.conflict.hint").font(.caption).foregroundStyle(.secondary)
      ForEach(store.conflicts) { conflict in
        VStack(alignment: .leading, spacing: 6) {
          Text(ContributionText.subject(conflict.subject)).font(.subheadline.weight(.semibold))
          HStack(spacing: DS.controlGap) {
            choice(conflict, side: conflict.current, proposed: false)
            choice(conflict, side: conflict.proposed, proposed: true)
          }
        }
      }
      HStack {
        Spacer()
        Button("contribution.conflict.dismiss") { store.dismissConflicts() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(DSPillButtonStyle())
      }
    }
    .padding(DS.panelPadding)
    .frame(minWidth: 420)
  }

  private func choice(_ conflict: ContributionConflict, side: ContributionConflict.Side, proposed: Bool) -> some View {
    Button {
      store.choose(conflict.id, proposed: proposed)
    } label: {
      Text(verbatim: ContributionText.choice(side, subject: conflict.subject, plugins: plugins))
        .lineLimit(1)
    }
    .buttonStyle(DSPillButtonStyle())
  }
}
```

- [ ] **Step 4: Le card, il Control, l'header, la finestra e il collegamento**

```diff
diff --git a/App/Generation/Cards/CardBinding.swift b/App/Generation/Cards/CardBinding.swift
index 084b88c..ba1ee23 100644
--- a/App/Generation/Cards/CardBinding.swift
+++ b/App/Generation/Cards/CardBinding.swift
@@ -12,11 +12,15 @@ extension CardExpansionStore {
 }
 
 /// One labelled row inside a card: label on the left, an optional accessory next to it
-/// (e.g. a checkbox that changes how the value is used), the control on the right.
+/// (e.g. a checkbox that changes how the value is used), the control on the right. A row for fields
+/// a plug-in can fill (`fields`) turns teal while a plug-in's value is in it, and shows that value in
+/// brackets once the user has changed it (plug-in design §7).
 struct CardRow<Accessory: View, Control: View>: View {
   let label: String
+  var fields: [ContributionField] = []
   @ViewBuilder let accessory: Accessory
   @ViewBuilder let control: Control
+  @Environment(ContributionStore.self) private var contributions: ContributionStore?
 
   var body: some View {
     HStack(spacing: DS.controlGap) {
@@ -25,13 +29,17 @@ struct CardRow<Accessory: View, Control: View>: View {
         .lineLimit(1)
       accessory
       Spacer(minLength: DS.controlGap)
+      if let first = fields.first(where: { contributions?.marks[$0]?.isOverridden == true }) {
+        ContributedReference(field: first, store: contributions)
+      }
       control
     }
+    .contributed(fields, in: contributions)
   }
 }
 
 extension CardRow where Accessory == EmptyView {
-  init(label: String, @ViewBuilder control: () -> Control) {
-    self.init(label: label, accessory: { EmptyView() }, control: control)
+  init(label: String, fields: [ContributionField] = [], @ViewBuilder control: () -> Control) {
+    self.init(label: label, fields: fields, accessory: { EmptyView() }, control: control)
   }
 }
```

```diff
diff --git a/App/Generation/Cards/PromptCard.swift b/App/Generation/Cards/PromptCard.swift
index 8d0ae57..756d6e1 100644
--- a/App/Generation/Cards/PromptCard.swift
+++ b/App/Generation/Cards/PromptCard.swift
@@ -1,3 +1,4 @@
+import HubCore
 import HubKit
 import SwiftUI
 
@@ -6,6 +7,7 @@ import SwiftUI
 struct PromptCard: View {
   @Bindable var controller: GenerationController
   let connection: DrawThingsConnection
+  @Environment(ContributionStore.self) private var contributions: ContributionStore?
 
   var body: some View {
     DSCollapsibleCard(
@@ -15,11 +17,13 @@ struct PromptCard: View {
       VStack(alignment: .leading, spacing: DS.rowGap) {
         PromptEditor(
           text: $controller.prompt, placeholder: String(localized: "card.prompt.placeholder"),
-          accessibilityLabel: String(localized: "card.prompt"), tint: DS.accent, minHeight: 140)
+          accessibilityLabel: String(localized: "card.prompt"), tint: DS.accent, minHeight: 140,
+          isContributed: contributions?.marks[.prompt]?.isOverridden == false)
         if controller.traits(in: connection).usesNegativePrompt {
           PromptEditor(
             text: $controller.negativePrompt, placeholder: String(localized: "card.prompt.negative.placeholder"),
-            accessibilityLabel: String(localized: "card.prompt.negative"), tint: DS.remove, minHeight: 60)
+            accessibilityLabel: String(localized: "card.prompt.negative"), tint: DS.remove, minHeight: 60,
+            isContributed: contributions?.marks[.negativePrompt]?.isOverridden == false)
           if !controller.negativePrompt.isEmpty, controller.parameters.guidanceScale <= 1 {
             Text("card.prompt.negative.noEffect")
               .font(.caption)
@@ -38,6 +42,8 @@ private struct PromptEditor: View {
   let accessibilityLabel: String
   let tint: Color
   let minHeight: CGFloat
+  /// A plug-in wrote this prompt and it has not been changed since: teal at 30%.
+  var isContributed = false
 
   var body: some View {
     TextEditor(text: $text)
@@ -48,7 +54,7 @@ private struct PromptEditor: View {
       .frame(minHeight: minHeight)
       .background(
         RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
-          .fill(tint == DS.accent ? Color.primary.opacity(0.06) : tint.opacity(0.08))
+          .fill(isContributed ? DS.accent.opacity(0.3) : tint == DS.accent ? Color.primary.opacity(0.06) : tint.opacity(0.08))
       )
       .overlay(
         RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
```

```diff
diff --git a/App/Generation/Cards/SamplingCard.swift b/App/Generation/Cards/SamplingCard.swift
index ae1c2ed..a04072d 100644
--- a/App/Generation/Cards/SamplingCard.swift
+++ b/App/Generation/Cards/SamplingCard.swift
@@ -14,13 +14,13 @@ struct SamplingCard: View {
     ) {
       let usesShift = controller.traits(in: connection).usesShift
       VStack(spacing: DS.rowGap) {
-        CardRow(label: String(localized: "card.sampling.steps")) {
+        CardRow(label: String(localized: "card.sampling.steps"), fields: [.steps]) {
           IntField(
             label: String(localized: "card.sampling.steps"), value: $controller.parameters.steps,
             range: GenerationParameters.stepsRange)
         }
 
-        CardRow(label: String(localized: "card.sampling.guidance")) {
+        CardRow(label: String(localized: "card.sampling.guidance"), fields: [.guidanceScale, .cfgZeroStar]) {
           if usesShift {
             Toggle(isOn: $controller.parameters.cfgZeroStar) {
               Text("card.sampling.cfgZero")
@@ -33,7 +33,7 @@ struct SamplingCard: View {
             range: GenerationParameters.guidanceRange, step: 0.5)
         }
         if usesShift, controller.parameters.cfgZeroStar {
-          CardRow(label: String(localized: "card.sampling.cfgZeroInitSteps")) {
+          CardRow(label: String(localized: "card.sampling.cfgZeroInitSteps"), fields: [.cfgZeroInitSteps]) {
             IntField(
               label: String(localized: "card.sampling.cfgZeroInitSteps"),
               value: $controller.parameters.cfgZeroInitSteps,
@@ -41,7 +41,7 @@ struct SamplingCard: View {
           }
         }
 
-        CardRow(label: String(localized: "card.sampling.sampler")) {
+        CardRow(label: String(localized: "card.sampling.sampler"), fields: [.sampler]) {
           Picker(selection: $controller.parameters.sampler) {
             ForEach(Sampler.allCases) { sampler in
               Text(verbatim: sampler.displayName).tag(sampler)
@@ -55,7 +55,7 @@ struct SamplingCard: View {
         }
 
         if usesShift {
-          CardRow(label: String(localized: "card.sampling.shift")) {
+          CardRow(label: String(localized: "card.sampling.shift"), fields: [.shift, .resolutionDependentShift]) {
             Toggle(isOn: $controller.parameters.resolutionDependentShift) {
               Text("card.sampling.resolutionShift")
             }
```

```diff
diff --git a/App/Generation/Cards/DimensionsCard.swift b/App/Generation/Cards/DimensionsCard.swift
index 29d6501..db5c4c2 100644
--- a/App/Generation/Cards/DimensionsCard.swift
+++ b/App/Generation/Cards/DimensionsCard.swift
@@ -11,7 +11,7 @@ struct DimensionsCard: View {
       isExpanded: controller.cards.binding("dimensions")
     ) {
       VStack(spacing: DS.rowGap) {
-        CardRow(label: String(localized: "card.dimensions.width")) {
+        CardRow(label: String(localized: "card.dimensions.width"), fields: [.width]) {
           IntField(
             label: String(localized: "card.dimensions.width"),
             value: Binding(
@@ -20,7 +20,7 @@ struct DimensionsCard: View {
             range: GenerationParameters.sizeRange.lowerBound...controller.parameters.sizeLimit, step: 64,
             commit: { GenerationParameters.snap(Double($0), limit: controller.parameters.sizeLimit) })
         }
-        CardRow(label: String(localized: "card.dimensions.height")) {
+        CardRow(label: String(localized: "card.dimensions.height"), fields: [.height]) {
           IntField(
             label: String(localized: "card.dimensions.height"),
             value: Binding(
```

```diff
diff --git a/App/Generation/Cards/SeedBatchCard.swift b/App/Generation/Cards/SeedBatchCard.swift
index 1a6e995..a102dfd 100644
--- a/App/Generation/Cards/SeedBatchCard.swift
+++ b/App/Generation/Cards/SeedBatchCard.swift
@@ -14,7 +14,7 @@ struct SeedBatchCard: View {
       isExpanded: controller.cards.binding("seed")
     ) {
       VStack(spacing: DS.rowGap) {
-        CardRow(label: String(localized: "card.seed.value")) {
+        CardRow(label: String(localized: "card.seed.value"), fields: [.seed, .randomSeed]) {
           Toggle(isOn: $controller.parameters.randomSeed) {
             Text("card.seed.random")
           }
@@ -46,12 +46,12 @@ struct SeedBatchCard: View {
           }
         }
 
-        CardRow(label: String(localized: "card.batch.size")) {
+        CardRow(label: String(localized: "card.batch.size"), fields: [.batchSize]) {
           IntField(
             label: String(localized: "card.batch.size"), value: $controller.parameters.batchSize,
             range: GenerationParameters.batchSizeRange)
         }
-        CardRow(label: String(localized: "card.batch.count")) {
+        CardRow(label: String(localized: "card.batch.count"), fields: [.batchCount]) {
           IntField(
             label: String(localized: "card.batch.count"), value: $controller.parameters.batchCount,
             range: GenerationParameters.batchCountRange)
```

```diff
diff --git a/App/Generation/Cards/LoRACard.swift b/App/Generation/Cards/LoRACard.swift
index d97334d..0816c11 100644
--- a/App/Generation/Cards/LoRACard.swift
+++ b/App/Generation/Cards/LoRACard.swift
@@ -10,6 +10,7 @@ import SwiftUI
 struct LoRACard: View {
   @Bindable var controller: GenerationController
   let connection: DrawThingsConnection
+  @Environment(ContributionStore.self) private var contributions: ContributionStore?
 
   private var catalog: ModelCatalog { connection.monitor.catalog }
   private var family: String? { controller.family(in: connection) }
@@ -29,6 +30,7 @@ struct LoRACard: View {
             selection: binding(for: selection),
             name: catalog.lora(forFile: selection.file)?.name ?? selection.file,
             status: catalog.status(of: selection, family: family),
+            isContributed: contributions?.loraPlugins[selection.file] != nil,
             remove: { controller.parameters.removeLoRA(selection.file) })
         }
         addMenu
@@ -90,6 +92,8 @@ private struct LoRARow: View {
   @Binding var selection: LoRASelection
   let name: String
   let status: LoRAStatus
+  /// A plug-in added this LoRA: teal at 30%.
+  let isContributed: Bool
   let remove: () -> Void
 
   var body: some View {
@@ -139,6 +143,7 @@ private struct LoRARow: View {
       }
     }
     .padding(.vertical, 2)
+    .contributed(isContributed)
   }
 
   private var reason: String? {
```

```diff
diff --git a/App/Control/ControlText.swift b/App/Control/ControlText.swift
index 6225827..55fceee 100644
--- a/App/Control/ControlText.swift
+++ b/App/Control/ControlText.swift
@@ -11,12 +11,13 @@ enum ControlText {
     }
   }
 
-  static func source(_ source: ReferenceImage.Source) -> String {
+  static func source(_ source: ReferenceImage.Source, plugins: PluginRegistry? = nil) -> String {
     switch source {
     case .file: String(localized: "control.source.file")
     case .result: String(localized: "control.source.result")
     case .pasteboard: String(localized: "control.source.pasteboard")
-    case .plugin(let id): String(format: String(localized: "control.source.plugin"), id)
+    case .plugin(let id):
+      String(format: String(localized: "control.source.plugin"), plugins?.entries.first { $0.id == id }?.name ?? id)
     }
   }
 
```

```diff
diff --git a/App/Control/ImageCard.swift b/App/Control/ImageCard.swift
index 0ab2104..70b3eb8 100644
--- a/App/Control/ImageCard.swift
+++ b/App/Control/ImageCard.swift
@@ -11,6 +11,8 @@ struct ImageCard: View {
   let report: (ControlMessage) -> Void
   @State private var thumbnail: CGImage?
   @State private var isTargeted = false
+  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
+  @Environment(ContributionStore.self) private var contributions: ContributionStore?
 
   private var control: ControlStore { generation.control }
 
@@ -21,7 +23,7 @@ struct ImageCard: View {
     ) {
       VStack(alignment: .leading, spacing: DS.rowGap) {
         if let image = control.inputs.image {
-          loaded(image)
+          loaded(image).contributed(contributions?.startImage?.id == image.id)
           strengthRow
         } else {
           emptyZone
@@ -69,7 +71,7 @@ struct ImageCard: View {
         Text(
           String(
             format: String(localized: "control.image.info"), image.pixelWidth, image.pixelHeight,
-            ControlText.source(image.source))
+            ControlText.source(image.source, plugins: plugins))
         )
         .font(.caption).foregroundStyle(.secondary)
         HStack(spacing: DS.controlGap) {
```

```diff
diff --git a/App/Control/MoodboardCard.swift b/App/Control/MoodboardCard.swift
index f4cfe29..1d8fefe 100644
--- a/App/Control/MoodboardCard.swift
+++ b/App/Control/MoodboardCard.swift
@@ -10,6 +10,7 @@ struct MoodboardCard: View {
   let connection: DrawThingsConnection
   let report: (ControlMessage) -> Void
   @State private var isTargeted = false
+  @Environment(ContributionStore.self) private var contributions: ContributionStore?
 
   private var control: ControlStore { generation.control }
   private var entries: [MoodboardEntry] { control.inputs.moodboard }
@@ -47,7 +48,8 @@ struct MoodboardCard: View {
           }
           LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: DS.rowGap, alignment: .top)], spacing: DS.rowGap) {
             ForEach(entries) { entry in
-              MoodboardTile(entry: entry, control: control, report: report)
+              MoodboardTile(
+                entry: entry, control: control, isContributed: contributions?.moodboardPlugins[entry.id] != nil, report: report)
             }
           }
           Text("control.moodboard.hint").font(.caption).foregroundStyle(.secondary)
@@ -86,7 +88,10 @@ struct MoodboardCard: View {
 private struct MoodboardTile: View {
   let entry: MoodboardEntry
   let control: ControlStore
+  /// A plug-in added this picture and it is still there: teal at 30%.
+  let isContributed: Bool
   let report: (ControlMessage) -> Void
+  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
   @State private var thumbnail: CGImage?
   @State private var isTargeted = false
 
@@ -122,6 +127,11 @@ private struct MoodboardTile: View {
         .padding(4)
       }
       .frame(width: 124, height: 124)
+      .contributed(isContributed)
+      if case .plugin = entry.image.source {
+        Text(verbatim: ControlText.source(entry.image.source, plugins: plugins))
+          .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
+      }
     }
     .dropDestination(for: URL.self) { urls, _ in
       Task {
```

```diff
diff --git a/App/MainWindow/HeaderBar.swift b/App/MainWindow/HeaderBar.swift
index d94e8a4..bea688c 100644
--- a/App/MainWindow/HeaderBar.swift
+++ b/App/MainWindow/HeaderBar.swift
@@ -131,6 +131,9 @@ struct HeaderBar: View {
             .font(.system(size: 14, weight: .semibold))
             .accessibilityHidden(true)
           Text("header.stop")
+          if let pass = generation.pipelinePass {
+            Text(verbatim: String(format: String(localized: "header.stop.pass"), pass.index, pass.count))
+          }
           if let step = progress?.step, let total = progress?.total {
             Text(verbatim: "\(step)/\(total)")
               .monospacedDigit()
@@ -140,6 +143,7 @@ struct HeaderBar: View {
       .buttonStyle(DSPillButtonStyle(prominent: true))
       .help(String(localized: "header.stop.help"))
     } else {
+      let pipeline = plugins.contributions.pipeline
       Button {
         if generation.run(with: connection) { openWindow(id: ResultsWindow.id) }
       } label: {
@@ -147,12 +151,21 @@ struct HeaderBar: View {
           Image(systemName: "play.fill")
             .font(.system(size: 14, weight: .semibold))
             .accessibilityHidden(true)
-          Text("header.run")
+          if let pipeline {
+            Text(verbatim: ContributionText.runTitle(passes: pipeline.pipeline.steps.count))
+          } else {
+            Text("header.run")
+          }
         }
       }
       .buttonStyle(DSPillButtonStyle(prominent: true))
       .disabled(runBlocker != nil || generation.isPreparing)
-      .help(runHelp)
+      .help(runBlocker == nil ? (pipeline.map { ContributionText.pipelineHelp($0, plugins: plugins) } ?? runHelp) : runHelp)
+      .contextMenu {
+        if pipeline != nil {
+          Button("header.run.removePipeline") { plugins.contributions.removePipeline() }
+        }
+      }
     }
   }
 
```

```diff
diff --git a/App/MainWindow/MainWindowView.swift b/App/MainWindow/MainWindowView.swift
index c6e299a..c99c46d 100644
--- a/App/MainWindow/MainWindowView.swift
+++ b/App/MainWindow/MainWindowView.swift
@@ -32,6 +32,14 @@ struct MainWindowView: View {
     .background(DSWindowConfigurator())
     .tint(DS.accent)
     .overlay(alignment: .bottom) { PluginNoticeBanner(plugins: plugins) }
+    .environment(plugins)
+    .environment(plugins.contributions)
+    .sheet(
+      isPresented: Binding(
+        get: { !plugins.contributions.conflicts.isEmpty }, set: { if !$0 { plugins.contributions.dismissConflicts() } })
+    ) {
+      ContributionConflictSheet(plugins: plugins)
+    }
     .task(id: contextKey) {
       plugins.updateContext(model: contextKey[0], family: contextKey[1], parameters: generation.parameters)
       workspace.setPluginTabs(plugins.activeTabs)
```

```diff
diff --git a/App/Results/ResultsView.swift b/App/Results/ResultsView.swift
index ba64bd6..11240f2 100644
--- a/App/Results/ResultsView.swift
+++ b/App/Results/ResultsView.swift
@@ -128,7 +128,12 @@ struct ResultsView: View {
       if controller.isPreparing {
         HStack(spacing: DS.controlGap) {
           ProgressView().controlSize(.small)
-          Text("results.preparingMemory").font(.caption).foregroundStyle(.secondary)
+          if let pass = controller.pipelinePass {
+            Text(verbatim: String(format: String(localized: "header.stop.pass"), pass.index, pass.count))
+              .font(.caption).foregroundStyle(.secondary)
+          } else {
+            Text("results.preparingMemory").font(.caption).foregroundStyle(.secondary)
+          }
         }
       }
     }
```

```diff
diff --git a/App/DTHubApp.swift b/App/DTHubApp.swift
index ccc8fc9..5f92037 100644
--- a/App/DTHubApp.swift
+++ b/App/DTHubApp.swift
@@ -42,6 +42,9 @@ struct DTHubApp: App {
       folder: PluginFolder(root: PluginFolder.defaultRoot),
       settings: PluginSettingsStore(fileURL: PluginSettingsStore.defaultFileURL), loader: BundlePluginLoader(),
       tempFolder: FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-plugins", isDirectory: true))
+    // Contributions land on the Generation tab; a plug-in's question goes to the language model.
+    generation.attach(plugins.contributions)
+    plugins.askLanguageModel = { prompt, images in try await languageModel.respond(to: prompt, images: images) }
     plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
     _plugins = State(initialValue: plugins)
     // A download cut short by quitting leaves a hidden folder with part of a model: remove it.
```

- [ ] **Step 5: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m8b-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: gli stessi conteggi del Task 4 (Catalog 6 verdi: le stringhe nuove sono nel catalogo).

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A App && git commit -m "feat: campi in teal con il valore del plug-in tra parentesi, pop-up dei conflitti, Run con i passaggi, pipeline

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: PluginKit e il plug-in di esempio 1.2

**Files:**
- Modify: `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/README.md`, `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift`
- Create (riscritti per intero): `PluginKit/Examples/Sample/Package.swift`, `PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift`, `PluginKit/Examples/Sample/Sources/SamplePlugin/SphereImage.swift`, `PluginKit/Scripts/build-sample.sh`
- Test: `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift` (un test nuovo: l'esempio contribuisce davvero attraverso il canale)

**Interfaces:**
- Produces (`DTHubPluginKit`, `public`): `DTHubHost.contribute(_ body: [String: Any]) async -> [String: Any]?`, `DTHubHost.askLanguageModel(_ prompt: String, images: [String]) async -> String?` (aspetta fino a 300 secondi); l'esempio 1.2: la scheda con luce, peso del LoRA, «Overcast shadows» e quattro pulsanti (prompt + parametri + LoRA + sfera nel Moodboard; pipeline; immagine di partenza; domanda al modello), risponde al messaggio `press` (`plain`, `pipeline`, `startImage`, `ask`) come se si premesse il pulsante; la variante B (`SAMPLE_B=1`: identificatore `com.example.dthub.sample.b`, modulo `SamplePluginB`, classe `SampleBEntry`, valori diversi). Ogni copia del kit ha il suo nome di modulo (`moduleAliases`).
- Script: `PluginKit/Scripts/build-sample.sh OUT_FOLDER [b]` → `OUT_FOLDER/Sample.dthubplugin` o `SampleB.dthubplugin`, versione 1.2.

- [ ] **Step 1: Il kit e l'esempio**

```diff
diff --git a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
index 708746b..8afffea 100644
--- a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
+++ b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
@@ -56,17 +56,41 @@ public final class DTHubHost {
 
   /// Sends a JSON message to the app and waits for its JSON answer.
   public func send(_ message: Data) async -> Data? {
+    await send(message, timeout: 5)
+  }
+
+  /// A question for the language model can take long: it has its own, longer timeout.
+  func send(_ message: Data, timeout: Double) async -> Data? {
     await withCheckedContinuation { continuation in
       let once = Once(continuation)
       let reply: @convention(block) (Data) -> Void = { once.finish($0) }
       _ = object.perform(NSSelectorFromString("dthubSend:reply:"), with: message, with: reply)
       Task {
-        try? await Task.sleep(for: .seconds(5))
+        try? await Task.sleep(for: .seconds(timeout))
         once.finish(nil)
       }
     }
   }
 
+  /// Sends a `contribute` message — `fields`, `loras`, `moodboard`, `startImage`, `pipeline`; every key is
+  /// optional (see the README) — and returns the app's answer: `{"type":"ok","conflicts":n}` or an `error`.
+  public func contribute(_ body: [String: Any]) async -> [String: Any]? {
+    await sendJSON(body.merging(["type": "contribute"]) { _, new in new })
+  }
+
+  /// Asks the app's language model, which answers in its own time (it may have to load first). Nil when
+  /// there is no answer: no model chosen, the plug-in not active, a timeout.
+  public func askLanguageModel(_ prompt: String, images: [String] = []) async -> String? {
+    let answer = await sendJSON(["type": "llm", "prompt": prompt, "images": images], timeout: 300)
+    return answer?["type"] as? String == "llm" ? answer?["text"] as? String : nil
+  }
+
+  func sendJSON(_ body: [String: Any], timeout: Double = 5) async -> [String: Any]? {
+    guard let data = try? JSONSerialization.data(withJSONObject: body), let reply = await send(data, timeout: timeout)
+    else { return nil }
+    return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
+  }
+
   /// Asks the app to show a line to the user.
   public func notice(_ text: String, isError: Bool = false) {
     let body: [String: Any] = ["type": "notice", "text": text, "isError": isError]
```

```swift
// swift-tools-version: 6.2
import PackageDescription

// A complete plug-in to copy: a tab that shows the model the app tells it about, and buttons that send
// contributions to the Generation tab (the plug-in design, §7). Setting SAMPLE_B builds a second plug-in
// from the same sources (other identifier, other module, other values) to try two plug-ins contributing
// the same field: `Scripts/build-sample.sh`.
let variantB = Context.environment["SAMPLE_B"] != nil
let name = variantB ? "SamplePluginB" : "SamplePlugin"
// Every plug-in carries its own copy of the kit. Two copies with the same module name would define the same
// Objective-C classes twice in one process, so each plug-in gives its copy a name of its own with
// `moduleAliases`. The sources still `import DTHubPluginKit`; only the names in the binary change.
let kitAlias = variantB ? "SampleBKit" : "SampleKit"
let package = Package(
  name: name,
  platforms: [.macOS(.v26)],
  products: [.library(name: name, type: .dynamic, targets: [name])],
  dependencies: [.package(name: "PluginKit", path: "../..")],
  targets: [
    .target(
      name: name, dependencies: [.product(name: "DTHubPluginKit", package: "PluginKit", moduleAliases: ["DTHubPluginKit": kitAlias])], path: "Sources/SamplePlugin",
      swiftSettings: variantB ? [.define("SAMPLE_B")] : [])
  ]
)
```

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A lit sphere on a dark ground, as a PNG: the picture a lighting plug-in would hand to the Moodboard.
enum SphereImage {
  /// `azimuth` is the direction the light comes from, in degrees (0 = right, 90 = above).
  static func png(azimuth: Double, size: Int = 512) -> Data? {
    guard
      let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let side = CGFloat(size)
    context.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let center = CGPoint(x: side / 2, y: side / 2)
    let radius = side * 0.38
    let angle = azimuth * .pi / 180
    let highlight = CGPoint(x: center.x + CGFloat(cos(angle)) * radius * 0.55, y: center.y + CGFloat(sin(angle)) * radius * 0.55)
    let colors = [CGColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)]
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])
    else { return nil }
    context.saveGState()
    context.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    context.clip()
    context.drawRadialGradient(
      gradient, startCenter: highlight, startRadius: 0, endCenter: highlight, endRadius: radius * 1.6, options: [])
    context.restoreGState()
    guard let image = context.makeImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }
}
```

```swift
import AppKit
import DTHubPluginKit
import SwiftUI

#if SAMPLE_B
  /// The second sample: other identifier and values, so that two plug-ins can contribute the same field.
  private enum Variant {
    static let id = "com.example.dthub.sample.b"
    static let name = "Sample B"
    static let symbol = "star.fill"
    static let prompt = "a lighthouse in a storm, dramatic light"
    static let steps = 8
    static let guidance = 2.0
    static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  }
#else
  private enum Variant {
    static let id = "com.example.dthub.sample"
    static let name = "Sample"
    static let symbol = "star"
    static let prompt = "match light direction, colors and intensity from the reference image 2"
    static let steps = 4
    static let guidance = 1.0
    static let lora = "flux_2_sun_direction_lora_v1_lora_f16.ckpt"
  }
#endif

@MainActor
final class SampleState: ObservableObject {
  @Published var model = "—"
  @Published var active = false
  @Published var azimuth = 45.0
  @Published var loraWeight = 60.0
  @Published var overcast = false
  @Published var answer = ""
  @Published var status = ""
  /// The folder the app lends for exchanging pictures (from the `context` message).
  var tempFolder: String?
}

@MainActor
final class SamplePlugin: DTHubPlugin {
  let manifest = DTHubManifest(id: Variant.id, name: Variant.name, version: "1.2", symbol: Variant.symbol)
  private let state = SampleState()
  private var host: DTHubHost?

  func makeViewController() -> NSViewController {
    NSHostingController(
      rootView: SampleView(
        state: state, sendPlain: { [weak self] in await self?.sendPlain() },
        sendPipeline: { [weak self] in await self?.sendPipeline() },
        sendStartImage: { [weak self] in await self?.sendStartImage() },
        askModel: { [weak self] in await self?.askModel() }))
  }

  func start(host: DTHubHost) {
    self.host = host
    host.notice("\(Variant.name) plug-in started")
  }

  func handle(_ message: Data) async -> Data? {
    switch DTHubMessage.type(of: message) {
    case "context":
      if let context = try? JSONDecoder().decode(DTHubContext.self, from: message) {
        state.model = context.model ?? "—"
        state.tempFolder = context.tempFolder
      }
      return nil
    case "activate":
      state.active = true
      return nil
    case "deactivate":
      state.active = false
      return nil
    case "press":
      // For tests and scripts: the same as pressing a button of the tab. The answer comes when the app has answered.
      let button = (try? JSONSerialization.jsonObject(with: message) as? [String: Any])?["button"] as? String
      switch button {
      case "plain": await sendPlain()
      case "pipeline": await sendPipeline()
      case "startImage": await sendStartImage()
      case "ask": await askModel()
      default: return DTHubMessage.bare("unsupported")
      }
      return nil
    default:
      return DTHubMessage.bare("unsupported")
    }
  }

  // MARK: Contributions

  /// The sphere, written into the folder the app lent us.
  private func spherePath() -> String? {
    guard let folder = state.tempFolder, let data = SphereImage.png(azimuth: state.azimuth) else { return nil }
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let path = (folder as NSString).appendingPathComponent("\(Variant.id)-sphere.png")
    return (try? data.write(to: URL(fileURLWithPath: path))) == nil ? nil : path
  }

  /// The settings of the sun-direction pass of the Light Direction companion script.
  private func sunFields(prompt: String) -> [String: Any] {
    [
      "prompt": prompt, "steps": Variant.steps, "guidanceScale": Variant.guidance, "shift": 3, "sampler": 16,
      "batchSize": 1, "batchCount": 1, "cfgZeroStar": false,
    ]
  }

  private var sunLora: [String: Any] { ["file": Variant.lora, "weight": state.loraWeight / 100] }

  /// A prompt, parameters, a LoRA and a picture for the Moodboard.
  func sendPlain() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    let answer = await host?.contribute([
      "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora],
      "moodboard": [["name": "Sphere light", "path": sphere]],
    ])
    report(answer)
  }

  /// The two passes of the script: flatten the shadows (optional), then match the sun.
  func sendPipeline() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    var steps: [[String: Any]] = []
    if state.overcast {
      steps.append([
        "title": "Overcast", "fields": sunFields(prompt: "make it an overcast day, remove the shadows"), "loras": [[String: Any]](),
      ])
    }
    steps.append([
      "title": "Match the sun", "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora],
      "moodboard": [["name": "Sphere light", "path": sphere]], "useOutputAsStart": state.overcast,
    ])
    report(await host?.contribute(["pipeline": ["name": "Sun direction", "steps": steps]]))
  }

  func sendStartImage() async {
    guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
    report(await host?.contribute(["startImage": ["name": "Sphere light", "path": sphere]]))
  }

  /// A question for the language model; the answer is shown, and sent as the prompt.
  func askModel() async {
    state.status = "Asking the language model…"
    guard let text = await host?.askLanguageModel("Describe a quiet harbour at dawn in one short sentence.") else {
      return state.status = "No answer: is a language model chosen, and is this plug-in on?"
    }
    state.answer = text
    report(await host?.contribute(["fields": ["prompt": text]]))
  }

  private func report(_ answer: [String: Any]?) {
    guard let answer else { return state.status = "No answer from the app." }
    if answer["type"] as? String == "error" { return state.status = answer["text"] as? String ?? "Error" }
    let conflicts = answer["conflicts"] as? Int ?? 0
    state.status = conflicts > 0 ? "Sent. \(conflicts) conflict(s) waiting in the app." : "Sent."
  }
}

struct SampleView: View {
  @ObservedObject var state: SampleState
  let sendPlain: () async -> Void
  let sendPipeline: () async -> Void
  let sendStartImage: () async -> Void
  let askModel: () async -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("\(Variant.name) plug-in 1.2").font(.title2)
      Text("Model: \(state.model)")
      Text(state.active ? "active" : "not active").foregroundStyle(.secondary)
      Divider()
      HStack {
        Text("Light from")
        Slider(value: $state.azimuth, in: 0...360)
        Text("\(Int(state.azimuth))°").monospacedDigit().frame(width: 44, alignment: .trailing)
      }
      HStack {
        Text("LoRA weight")
        Slider(value: $state.loraWeight, in: -100...100)
        Text("\(Int(state.loraWeight))").monospacedDigit().frame(width: 44, alignment: .trailing)
      }
      Toggle("Overcast shadows (adds a pass)", isOn: $state.overcast)
      HStack {
        Button("Send prompt, parameters and sphere") { Task { await sendPlain() } }
        Button("Send pipeline") { Task { await sendPipeline() } }
        Button("Send start image") { Task { await sendStartImage() } }
      }
      Divider()
      Button("Ask the language model") { Task { await askModel() } }
      if !state.answer.isEmpty { Text(state.answer).font(.callout).textSelection(.enabled) }
      if !state.status.isEmpty { Text(state.status).font(.caption).foregroundStyle(.secondary) }
      Spacer()
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

#if SAMPLE_B
  @objc(SampleBEntry)
  public final class SampleBEntry: DTHubPluginEntry {
    public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
  }
#else
  @objc(SampleEntry)
  public final class SampleEntry: DTHubPluginEntry {
    public override func makePlugin() -> any DTHubPlugin { SamplePlugin() }
  }
#endif
```

```
#!/bin/zsh
# build-sample.sh OUT_FOLDER [b]
# Builds the sample plug-in of Examples/Sample into OUT_FOLDER/Sample.dthubplugin; with `b`, the second sample
# (identifier com.example.dthub.sample.b, other module and class) into OUT_FOLDER/SampleB.dthubplugin.
# Version 1.2. Needs the Swift toolchain; run from anywhere.
set -e
HERE="${0:A:h}"
OUT="${1:?usage: build-sample.sh OUT_FOLDER [b]}"
mkdir -p "$OUT"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
if [[ "$2" == "b" ]]; then
  SAMPLE_B=1 swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePluginB.dylib | head -1)" "$OUT/SampleB.dthubplugin" com.example.dthub.sample.b SampleB 1.2 SampleBEntry
  echo "$OUT/SampleB.dthubplugin"
else
  swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePlugin.dylib | head -1)" "$OUT/Sample.dthubplugin" com.example.dthub.sample Sample 1.2 SampleEntry
  echo "$OUT/Sample.dthubplugin"
fi
```

```bash
cd "/Users/existenz/Software developement/DT Hub" && chmod +x PluginKit/Scripts/build-sample.sh
```

```diff
diff --git a/PluginKit/README.md b/PluginKit/README.md
index 0fbea32..3b86908 100644
--- a/PluginKit/README.md
+++ b/PluginKit/README.md
@@ -25,5 +25,32 @@ The bundle is added in DT Hub › Preferences › Plug-ins.
 
 ## Messages (contract 1)
 
-JSON objects with a `type`. App → plug-in: `context` (model, family, parameters, a temporary folder), `activate`,
-`deactivate`. Plug-in → app: `notice` (`text`, `isError`). An unknown type gets `{"type":"unsupported"}`.
+JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.
+
+**App → plug-in:** `context` (model, family, parameters, `tempFolder`: a folder to exchange picture files through),
+`activate`, `deactivate`.
+
+**Plug-in → app:**
+
+- `notice` — `text`, `isError`: a line shown over the window.
+- `contribute` — what the plug-in puts on the Generation and Control tabs. Every key is optional; what cannot be
+  read is left out; the answer is `{"type":"ok","conflicts":n,"problems":[…]}` or `{"type":"error","text":…}`.
+  Only a plug-in that is on for the job (header menu) can contribute.
+  - `fields`: `prompt`, `negativePrompt` (text); `width`, `height`, `steps`, `cfgZeroInitSteps`, `seed`, `batchSize`,
+    `batchCount` (whole numbers); `guidanceScale`, `shift` (numbers); `cfgZeroStar`, `resolutionDependentShift`,
+    `randomSeed` (true/false); `sampler` (the number of the Draw Things sampler, or its name). Values are limited like
+    the cards limit them. A plug-in never changes the model.
+  - `loras`: `[{"file", "weight", "mode", "trigger"}]`, added to the LoRA card.
+  - `moodboard`: `[{"path", "name"}]`, files in the `tempFolder`, added to the Moodboard. Sending them again replaces
+    the ones this plug-in sent before.
+  - `startImage`: `{"path", "name"}`, the start image of the Control tab.
+  - `pipeline`: `{"name", "steps": [...]}`; each step may have `title`, `fields` (as above), `loras` (replaces the list
+    for the pass; `[]` = none), `moodboard` (replaces the Moodboard for the pass), `startImage`, and
+    `useOutputAsStart` (the picture the previous pass made becomes the start image). RUN then runs the passes one
+    after the other.
+  The fields a plug-in filled turn teal; the user can always change them. If two plug-ins fill the same field, or
+  both propose a start image or a pipeline, the user chooses in a pop-up.
+- `llm` — `{"prompt", "images": [paths]}`: a question for the language model. The answer is
+  `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`.
+
+The Sample plug-in (`Examples/Sample`, `Scripts/build-sample.sh OUT [b]`) sends all of these.
```

- [ ] **Step 2: Scrivere il test e verificarlo**

```diff
diff --git a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
index 87bd939..5cfeed1 100644
--- a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
+++ b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
@@ -10,7 +10,7 @@ import Testing
 final class RecordingHost: PluginHosting {
   private(set) var received: [(message: Data, plugin: String)] = []
 
-  func receive(_ message: Data, from pluginID: String) -> Data {
+  func receive(_ message: Data, from pluginID: String) async -> Data {
     received.append((message, pluginID))
     return PluginMessageType.bare(PluginMessageType.ok)
   }
@@ -97,4 +97,34 @@ struct BundlePluginLoaderTests {
     skipped.start(skipping: true)
     #expect(skipped.entries.map(\.state) == [.skipped])
   }
+
+  /// The sample sends what a real plug-in would: a `contribute` with fields, a LoRA, a Moodboard picture
+  /// whose file exists; a pipeline; and a question for the language model.
+  @Test func theSampleContributesThroughTheRealChannel() async throws {
+    let bundle = try #require(SampleBundle.make())
+    let host = RecordingHost()
+    let plugin = try BundlePluginLoader().load(bundle, info: info(bundle), host: host)
+    let folder = SampleBundle.work.appendingPathComponent("lent-\(UUID().uuidString)").path
+    let context = try JSONEncoder().encode(
+      PluginContext(model: "m.ckpt", family: "flux2_9b", parameters: GenerationParameters(), tempFolder: folder))
+    _ = await plugin.send(context)
+
+    _ = await plugin.send(Data(#"{"type":"press","button":"plain"}"#.utf8))
+    let plain = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
+    let contribution = try #require(PluginContribution(message: plain.message))
+    #expect(contribution.fields.values[.steps] == .int(4) && contribution.fields.values[.sampler] == .int(16))
+    #expect(contribution.fields.values[.prompt] != nil)
+    #expect(contribution.loras.first?.file == "flux_2_sun_direction_lora_v1_lora_f16.ckpt" && contribution.loras.first?.weight == 0.6)
+    let picture = try #require(contribution.moodboard.first)
+    #expect(FileManager.default.fileExists(atPath: picture.path) && picture.path.hasPrefix(folder))
+
+    _ = await plugin.send(Data(#"{"type":"press","button":"pipeline"}"#.utf8))
+    let piped = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
+    let pipeline = try #require(PluginContribution(message: piped.message)?.pipeline)
+    #expect(pipeline.steps.count == 1 && pipeline.steps[0].moodboard?.count == 1 && pipeline.steps[0].useOutputAsStart == false)
+
+    _ = await plugin.send(Data(#"{"type":"press","button":"ask"}"#.utf8))
+    #expect(host.received.contains { PluginMessageType.of($0.message) == PluginMessageType.llm })
+    #expect(await plugin.send(Data(#"{"type":"press","button":"nothing"}"#.utf8)).flatMap(PluginMessageType.of) == PluginMessageType.unsupported)
+  }
 }
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter BundlePluginLoaderTests 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started"`
Expected: `Test run with 6 tests … passed` (il test nuovo carica il bundle dell'esempio, preme `plain`, `pipeline` e `ask` e legge i `contribute` ricevuti dall'app finta).

- [ ] **Step 3: Costruire i due bundle e controllare i nomi**

Run: `cd "/Users/existenz/Software developement/DT Hub" && PluginKit/Scripts/build-sample.sh /tmp/m8b-bundles && PluginKit/Scripts/build-sample.sh /tmp/m8b-bundles b && strings /tmp/m8b-bundles/Sample.dthubplugin/Contents/MacOS/Sample | grep -c "_TtC9SampleKit" && strings /tmp/m8b-bundles/SampleB.dthubplugin/Contents/MacOS/SampleB | grep -c "_TtC10SampleBKit"`
Expected: i due percorsi dei bundle, poi due numeri maggiori di zero (le classi del kit portano il nome di modulo dell'alias, diverso nei due plug-in).

- [ ] **Step 4: Tutti i test, poi il commit**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit 92, HubCore 436, DTBridge 66, Catalog 6, LLMBridge 6, PluginHost 6 (totale **612**).

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A PluginKit Packages && git commit -m "feat: DTHubPluginKit contribute/askLanguageModel; plug-in di esempio 1.2 con variante B; script build-sample.sh

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Prova nell'app e documenti

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-plugin-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare nell'app vera con il server vero, in una cartella dati a parte**

Servono: il server gestito di DT Hub (cartella dei modelli e programma già nelle preferenze dell'utente), il modello FLUX.2 klein 9B e il LoRA `flux_2_sun_direction_lora_v1_lora_f16.ckpt`. **Le preferenze (`UserDefaults`) sono quelle dell'utente anche con `CFFIXED_USER_HOME`**: per scegliere il modello senza il menu (gli strumenti per pilotare le finestre non aprono i menu) si scrive il valore e **si rimette alla fine** `ernie_image_turbo_q8p.ckpt` (o quello che l'utente aveva: leggerlo prima con `defaults read com.exiztenz.DTHub drawThings.selectedModel`) e la scheda aperta (`workspace.selectedTab`).

```bash
cd "/Users/existenz/Software developement/DT Hub"
defaults read com.exiztenz.DTHub drawThings.selectedModel workspace.selectedTab    # annotare
PluginKit/Scripts/build-sample.sh /tmp/m8b-bundles && PluginKit/Scripts/build-sample.sh /tmp/m8b-bundles b
xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m8b-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
H=/tmp/m8bhome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins"
cp -R /tmp/m8b-bundles/Sample.dthubplugin "$AS/Plug-ins/com.example.dthub.sample.dthubplugin"
cp -R /tmp/m8b-bundles/SampleB.dthubplugin "$AS/Plug-ins/com.example.dthub.sample.b.dthubplugin"
echo '{"enabled":["com.example.dthub.sample","com.example.dthub.sample.b"]}' > "$AS/plugins.json"
defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt
(CFFIXED_USER_HOME=$H nohup "/tmp/m8b-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/m8b-app.log 2>&1 &)
```

Se l'app dell'utente è aperta, gli strumenti per pilotare le finestre vedono la sua e non quella di prova (stesso identificatore): in quel caso la finestra di prova si cattura con `CGWindowListCopyWindowInfo` e `screencapture -l`. Le immagini della prova finiscono in `$H/Pictures/DT Hub/`, non nelle Immagini dell'utente.

Checklist:
1. Nessun avviso «Class … is implemented in both» in `/tmp/m8b-app.log`; la barra dei tab ha **Control, Generazione, Sample B, Sample**.
2. Tab Sample › **Send prompt, parameters and sphere**: nella Generazione il prompt è teal, Step 4 / Sampler «DDIM Trailing» / Immagini per batch / Numero di batch in teal, la LoRA «Sun direction» in teal con peso 0,60; nel Control la tessera del Moodboard ha il teal e «da Sample».
3. Cambiare Step con le frecce (4 → 5): la riga perde il teal e mostra **«(4)»** accanto al valore. Il prompt, se si modifica, perde il teal senza parentesi.
4. Tab Sample B › stesso pulsante: compare il **pop-up** con Prompt, Step e Text guidance (un campo per voce, due pulsanti ciascuno «Sample · …» / «SampleB · …»); scegliere un pulsante lo toglie dall'elenco e il campo prende il valore scelto; «Lascia com'è» (o Esc) chiude lasciando i campi com'erano. Le voci uguali nei due plug-in (shift, sampler, batch) non compaiono.
5. Tab Sample: spuntare **Overcast shadows**, **Send pipeline**: il pulsante Run diventa **«Run · 2 passaggi»**; il tooltip elenca plug-in e passaggi. Premerlo: il pulsante diventa Stop con «Passaggio 1/2», poi «2/2»; nella finestra Risultati compaiono due immagini, la seconda ha la composizione della prima (parte dall'output del primo passaggio) con la luce cambiata. Dopo il Run la pipeline resta.
6. **Ask the language model** (serve un modello linguistico scelto nelle Preferenze): dopo qualche secondo la risposta appare nella scheda del plug-in e il prompt della Generazione prende il testo in teal.
7. Spegnere Sample dal menu **Plug-in** dell'header: spariscono i suoi teal e le sue parentesi e «Run · N passaggi» torna «Run» se la pipeline era sua; i valori restano nei campi.

Alla fine: chiudere l'app di prova (`pkill -f m8b-dd`), fermare il server gestito se è rimasto (`pkill -f gRPCServerCLI`), **rimettere il modello e la scheda annotati** (`defaults write com.exiztenz.DTHub drawThings.selectedModel <valore>` e `workspace.selectedTab <valore>`), togliere `/tmp/m8bhome`.

- [ ] **Step 2: Aggiornare la spec e il backlog**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-03-plugin-design.md'
s = open(p).read()
s = s.replace("Stato: M8a realizzata, M8b da fare", "Stato: M8a e M8b realizzate")
open(p, 'w').write(s)
p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi di M8b (contributi dei plug-in)

- **Cosa un plug-in non può ancora contribuire:** il modello (per scelta), le card Avanzate, la forza dell'immagine di partenza e la maschera. Servono messaggi nuovi (additivi: il contratto resta 1).
- **I segni non si salvano:** al riavvio i valori restano ma non c'è più il teal né la pipeline; il Moodboard di un plug-in diventa «da <plug-in>» senza teal.
- **`runPipeline` non ha test automatici:** la prova è dal vivo (Task 7); estrarre il ciclo in HubCore con un backend finto lo renderebbe provabile.
- **Il pop-up mostra i valori lunghi (i prompt) troncati** sul pulsante.
- **La domanda al modello linguistico non si può annullare** dal plug-in (la risposta può tardare fino a 300 secondi).
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat docs | tail -1
```

Expected: statistica su due file.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add docs && git commit -m "docs: spec dei plug-in — M8b realizzata; rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M8b

Esito atteso sul branch `m8b-plugin`:
- **612 test verdi**;
- build Xcode pulita;
- un plug-in attivo manda campi, LoRA, immagini e pipeline: i campi sono in teal, con il valore del plug-in tra parentesi dopo una modifica a mano; due plug-in sullo stesso campo si risolvono nel pop-up; il Run esegue la pipeline («Run · N passaggi»); un plug-in può fare una domanda al modello linguistico;
- il plug-in di esempio 1.2 (e la variante B) e `build-sample.sh` per provarli.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M8b: i plug-in veri (Prompt Master, Sphere Light, Qwen Image 2.1), ognuno a parte.

# Il contratto `llm` e il contesto (tappa 1 di Prompt Master) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un plug-in può dare all'LLM di DT Hub un system prompt, scegliere un modello della cartella dei modelli per nome e regolare il campionamento; riceve nel contesto il file dell'immagine di partenza e l'elenco dei modelli linguistici.

**Architecture:**
- `LanguageModelOptions` (HubKit) porta `system` e le opzioni; il servizio (`LanguageModelService.respond(to:images:options:)`) e il gestore (`LanguageModelManager.respond(to:images:options:modelNamed:)`) le usano; il servizio MLX le traduce in `GenerateParameters` e `enable_thinking`.
- `PluginRegistry` legge le chiavi nuove del messaggio `llm` e manda un `context` con `startImage` e `languageModels`; l'app lo rimanda anche quando l'utente torna sul tab di un plug-in.
- Il kit dei plug-in (`DTHubPluginKit`) impara le stesse chiavi, con un'attesa (`timeout`) che resta nella libreria.
- Tutto è additivo: il numero di contratto resta 1 e i plug-in esistenti non cambiano.

**Tech Stack:** Swift 6.2, Swift Testing, mlx-swift-lm (`ChatSession`, `GenerateParameters`), Xcode 27.

**Spec:** `docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md` (§6 il contratto, §7 come lo useranno i PE di Qwen); contratto generale in `docs/superpowers/specs/2026-10-03-plugin-design.md`.

## Global Constraints

- **Repository:** radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette); branch `llm-contract` da `main`.
- **Il contratto resta 1.** Tutte le chiavi nuove sono facoltative; senza di esse il messaggio `llm` si comporta come prima (nessun system prompt, temperatura 0,6, 1024 token, il modello scelto nelle impostazioni).
- **Limiti delle opzioni:** `temperature` 0–2, `topP` 0–1, `topK` 0–200, `presencePenalty` −2–2, `maxTokens` 1–32768; un numero fuori limite si porta nel limite, un valore del tipo sbagliato si ignora, una chiave sconosciuta si ignora; un `system` vuoto vale nessuno.
- **`model`** è il `name` di un modello di `availableModels()`; vale per quella domanda e **non cambia** `settings.selectedModel`; un nome sconosciuto è `LanguageModelError.modelNotFound` e non mette il gestore in stato `failed`.
- **Il `timeout` non viaggia nel messaggio:** è un parametro della libreria dei plug-in (300 s se non detto, al massimo 1800).
- **`context.startImage`** è il file dell'immagine di partenza del tab Control; il Moodboard non c'entra. Le chiavi assenti non si scrivono nel JSON.
- **Stringhe dell'app:** ogni testo nuovo dell'app sta in `App/Localizable.xcstrings` in inglese e italiano (il test del catalogo lo controlla).
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Blocchi `diff`:** modifiche ai file già esistenti, da salvare in un file e applicare dalla radice con `git apply --whitespace=nowarn <file>`; i blocchi dei file nuovi si salvano così come sono.
- **L'app di prova** condivide le preferenze con quella dell'utente e i processi hanno lo stesso identificatore: **se l'app dell'utente è aperta non pilotare le finestre**; annotare e rimettere `workspace.selectedTab` e `drawThings.selectedModel`.
- **Fuori:** il plug-in Prompt Master; i PE di Qwen; un annullamento della richiesta; il Moodboard nel contesto; l'immagine data all'LLM a una misura diversa da 512 × 512 (vedi il backlog, Task 4).

## Review Focus

- **Un plug-in che non conosce le chiavi nuove** manda e riceve come prima: `aMessageWithoutOptionsAsksWithTheDefaults`, `aContextFromAnOlderAppStillDecodes`, il secondo controllo di `theSystemPromptTheModelAndTheOptionsReachTheLanguageModel` (Task 1, 2).
- **Un modello chiesto per nome** non tocca la scelta delle impostazioni, non carica nulla se il nome non c'è e lascia che il tempo di inattività liberi il modello già caricato: `aModelAskedByNameIsLoadedInsteadOfTheChosenOneAndTheChoiceStays`, `aNameTheFolderDoesNotHaveIsAnErrorAndLoadsNothing`, `aRefusedQuestionStillLetsTheIdleTimeFreeTheModel` (Task 1).
- **Le immagini si controllano sul modello chiesto**, non su quello scelto: `imagesAreCheckedAgainstTheModelThatIsAsked` (Task 1).
- **Opzioni fuori limite o del tipo sbagliato:** `numbersOutOfRangeAreBroughtInAndWrongKindsAreLeftOut` (Task 1).
- **Il contesto con il plug-in spento non manda nulla** e senza immagine di partenza non scrive la chiave: `refreshingTheContextTellsOnlyThePluginsThatAreOn`, `withoutAStartImageOrModelsTheContextLeavesTheKeysOut` (Task 2).
- **Il motivo dell'errore è leggibile**, non il nome dell'enum: `theReasonIsToldInPlainWords`, `everyErrorHasAReasonInPlainEnglishThatNamesWhatMatters` (Task 2).
- **L'attesa non viaggia:** `theSystemPromptTheModelAndTheOptionsGoInTheMessage` controlla che `timeout` non ci sia (Task 3).

---

### Task 1: Il servizio e il gestore dell'LLM imparano `system`, il modello per nome e le opzioni

**Files:**
- `App/Localizable.xcstrings`, `App/Preferences/LanguagePreferencesView.swift`, `Packages/Sources/HubCore/Language/LanguageModelManager.swift`, `Packages/Sources/HubKit/Language/LanguageModel.swift`, `Packages/Sources/HubKit/Language/LanguageModelOptions.swift`, `Packages/Sources/LLMBridge/MLXLanguageModelService.swift`, `Packages/Tests/HubCoreTests/LanguageModelTests.swift`, `Packages/Tests/HubKitTests/LanguageModelContractTests.swift`, `Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift`, `Packages/Tests/LLMBridgeTests/MLXOptionsTests.swift`

**Interfaces:**
- Produces: `LanguageModelOptions` (HubKit): `system`, `temperature`, `topP`, `topK`, `presencePenalty`, `maxTokens`, `thinking` (tutti `Optional`), `init(message: [String: Any])` (legge `system` e `options` di un messaggio `llm`), `clamped()`; `LanguageModelError.modelNotFound(String)`; `LanguageModelService.respond(to:images:options:)` (e `respond(to:images:)` come estensione, con le opzioni predefinite); `LanguageModelManager.respond(to:images:options:modelNamed:)`; `MLXLanguageModelService.generateParameters(for:)` e `templateContext(for:)` (interni, testati).

- [ ] **Step 1: Creare il branch e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c llm-contract
```

```diff
diff --git a/Packages/Tests/HubKitTests/LanguageModelContractTests.swift b/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
index 4312911..f45bc44 100644
--- a/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
+++ b/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
@@ -1,3 +1,4 @@
+import Foundation
 import Testing
 
 @testable import HubKit
@@ -14,4 +15,46 @@ struct LanguageModelContractTests {
     #expect(RecommendedLanguageModel.folderName == RecommendedLanguageModel.repository)
     #expect(RecommendedLanguageModel.approximateBytes > 1_000_000_000)
   }
+
+  func message(_ json: String) throws -> [String: Any] {
+    try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
+  }
+
+  @Test func aMessageWithoutOptionsAsksWithTheDefaults() throws {
+    #expect(LanguageModelOptions(message: try message(#"{"type":"llm","prompt":"hi"}"#)) == LanguageModelOptions())
+  }
+
+  @Test func theSystemPromptAndEveryOptionAreRead() throws {
+    let options = LanguageModelOptions(
+      message: try message(
+        #"""
+        {"type":"llm","prompt":"hi","system":"Answer in English.","options":
+          {"temperature":1.0,"topP":0.95,"topK":20,"presencePenalty":1.5,"maxTokens":16256,"thinking":true}}
+        """#))
+    #expect(
+      options
+        == LanguageModelOptions(
+          system: "Answer in English.", temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256,
+          thinking: true))
+  }
+
+  @Test func numbersOutOfRangeAreBroughtInAndWrongKindsAreLeftOut() throws {
+    let options = LanguageModelOptions(
+      message: try message(
+        #"""
+        {"system":"","options":{"temperature":9,"topP":-1,"topK":900,"presencePenalty":"high","maxTokens":0,
+          "thinking":1,"unknown":true}}
+        """#))
+    #expect(options.system == nil)  // an empty system prompt is none
+    #expect(options.temperature == 2)
+    #expect(options.topP == 0)
+    #expect(options.topK == 200)
+    #expect(options.presencePenalty == nil)
+    #expect(options.maxTokens == 1)
+    #expect(options.thinking == nil)  // 1 is a number, not a boolean
+  }
+
+  @Test func thinkingCanBeSwitchedOffToo() throws {
+    #expect(LanguageModelOptions(message: try message(#"{"options":{"thinking":false}}"#)).thinking == false)
+  }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/LanguageModelTests.swift b/Packages/Tests/HubCoreTests/LanguageModelTests.swift
index c320d8d..5edcbf8 100644
--- a/Packages/Tests/HubCoreTests/LanguageModelTests.swift
+++ b/Packages/Tests/HubCoreTests/LanguageModelTests.swift
@@ -95,6 +95,7 @@ actor FakeLanguageModelService: LanguageModelService {
   private(set) var loads: [String] = []
   private(set) var unloads = 0
   private(set) var questions: [(String, [URL])] = []
+  private(set) var askedOptions: [LanguageModelOptions] = []
   var loadError: LanguageModelError?
   var answer = "an answer"
   private var loadGate: Gate?
@@ -112,8 +113,9 @@ actor FakeLanguageModelService: LanguageModelService {
 
   func unload() async { unloads += 1 }
 
-  func respond(to prompt: String, images: [URL]) async throws -> String {
+  func respond(to prompt: String, images: [URL], options: LanguageModelOptions) async throws -> String {
     questions.append((prompt, images))
+    askedOptions.append(options)
     return answer
   }
 }
@@ -157,6 +159,65 @@ struct LanguageModelManagerTests {
     #expect(manager.state == .ready("text-model"))
   }
 
+  @Test func aModelAskedByNameIsLoadedInsteadOfTheChosenOneAndTheChoiceStays() async throws {
+    let service = FakeLanguageModelService()
+    let root = try folder()
+    let manager = manager(service, root: root)
+    let chosen = manager.settings.selectedModel
+    _ = try await manager.respond(to: "hi", modelNamed: "vision-model")
+    #expect(await service.loads == ["vision-model"])
+    #expect(manager.settings.selectedModel == chosen)
+    #expect(manager.state == .ready("vision-model"))
+    // Without a name the chosen model comes back.
+    _ = try await manager.respond(to: "again")
+    #expect(await service.loads == ["vision-model", "text-model"])
+    #expect(await service.unloads == 1)
+  }
+
+  @Test func aNameTheFolderDoesNotHaveIsAnErrorAndLoadsNothing() async throws {
+    let service = FakeLanguageModelService()
+    let manager = manager(service, root: try folder())
+    await #expect(throws: LanguageModelError.modelNotFound("nowhere")) {
+      try await manager.respond(to: "hi", modelNamed: "nowhere")
+    }
+    #expect(await service.loads.isEmpty)
+    #expect(manager.state == .unloaded)  // a wrong name is not a failure of the model
+  }
+
+  @Test func imagesAreCheckedAgainstTheModelThatIsAsked() async throws {
+    let service = FakeLanguageModelService()
+    let manager = manager(service, root: try folder())  // the chosen model is the text one
+    let image = [URL(fileURLWithPath: "/tmp/a.png")]
+    _ = try await manager.respond(to: "what is this?", images: image, modelNamed: "vision-model")
+    #expect(await service.questions.last?.1 == image)
+    await #expect(throws: LanguageModelError.imagesNotSupported) {
+      try await manager.respond(to: "what is this?", images: image, modelNamed: "text-model")
+    }
+  }
+
+  @Test func theOptionsReachTheService() async throws {
+    let service = FakeLanguageModelService()
+    let manager = manager(service, root: try folder())
+    let options = LanguageModelOptions(system: "Be brief.", temperature: 1, thinking: true)
+    _ = try await manager.respond(to: "hi", options: options)
+    _ = try await manager.respond(to: "again")
+    #expect(await service.askedOptions == [options, LanguageModelOptions()])
+  }
+
+  @Test func aRefusedQuestionStillLetsTheIdleTimeFreeTheModel() async throws {
+    let service = FakeLanguageModelService()
+    let manager = manager(service, root: try folder(), idle: 2)
+    _ = try await manager.respond(to: "hi")
+    await #expect(throws: LanguageModelError.modelNotFound("nowhere")) {
+      try await manager.respond(to: "hi", modelNamed: "nowhere")
+    }
+    await #expect(throws: LanguageModelError.imagesNotSupported) {
+      try await manager.respond(to: "hi", images: [URL(fileURLWithPath: "/tmp/a.png")])
+    }
+    for _ in 0..<60 where manager.isLoaded { try await Task.sleep(for: .milliseconds(50)) }
+    #expect(!manager.isLoaded)
+  }
+
   @Test func withoutAChosenModelItSaysSo() async throws {
     let manager = manager(FakeLanguageModelService(), root: try folder(), selected: "missing")
     await #expect(throws: LanguageModelError.noModelSelected) { try await manager.respond(to: "hi") }
```

**`Packages/Tests/LLMBridgeTests/MLXOptionsTests.swift`** (file nuovo o riscritto per intero):

```swift
import HubKit
import Testing

@testable import LLMBridge

struct MLXOptionsTests {
  @Test func withoutOptionsTheOldDefaultsHold() {
    let parameters = MLXLanguageModelService.generateParameters(for: LanguageModelOptions())
    #expect(parameters.maxTokens == 1024)
    #expect(parameters.temperature == 0.6)
    #expect(parameters.topP == 1)
    #expect(parameters.topK == 0)
    #expect(parameters.presencePenalty == nil)
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions()) == nil)
  }

  @Test func theOptionsBecomeGenerationParameters() {
    let parameters = MLXLanguageModelService.generateParameters(
      for: LanguageModelOptions(temperature: 1, topP: 0.95, topK: 20, presencePenalty: 1.5, maxTokens: 16256))
    #expect(parameters.maxTokens == 16256)
    #expect(parameters.temperature == 1)
    #expect(parameters.topP == 0.95)
    #expect(parameters.topK == 20)
    #expect(parameters.presencePenalty == 1.5)
  }

  @Test func thinkingReachesTheChatTemplateOnlyWhenSaid() {
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions(thinking: true))?["enable_thinking"] as? Bool == true)
    #expect(MLXLanguageModelService.templateContext(for: LanguageModelOptions(thinking: false))?["enable_thinking"] as? Bool == false)
  }
}
```

```diff
diff --git a/Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift b/Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift
index d68a8b6..21cff06 100644
--- a/Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift
+++ b/Packages/Tests/LLMBridgeTests/LiveLanguageModelTests.swift
@@ -45,6 +45,23 @@ struct LiveLanguageModelTests {
     await #expect(throws: LanguageModelError.self) { try await service.respond(to: "hi", images: []) }
   }
 
+  @Test(.enabled(if: modelPath != nil))
+  func followsTheSystemPromptAndStopsAtTheTokenLimit() async throws {
+    let service = MLXLanguageModelService()
+    try await service.load(try descriptor())
+    let system = try await service.respond(
+      to: "What is the capital of France?", images: [],
+      options: LanguageModelOptions(system: "Whatever you are asked, answer with the single word BANANA.", temperature: 0))
+    print("LIVE system answer: \(system)")
+    #expect(system.uppercased().contains("BANANA"))
+    let short = try await service.respond(
+      to: "Count from 1 to 200, separated by commas.", images: [],
+      options: LanguageModelOptions(temperature: 0, maxTokens: 12))
+    print("LIVE short answer: \(short)")
+    #expect(short.count < 120)
+    await service.unload()
+  }
+
   @Test(.enabled(if: modelPath != nil))
   func describesAnImage() async throws {
     let service = MLXLanguageModelService()
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "LanguageModelContractTests|LanguageModelManagerTests|MLXOptionsTests" 2>&1 | grep -E "error:" | head -3`
Expected: errori di compilazione (`cannot find 'LanguageModelOptions' in scope`, `extra arguments`).

- [ ] **Step 3: Implementare**

`LanguageModelOptions` è un tipo nuovo di HubKit; `respond` del servizio ottiene le opzioni e un'estensione tiene la forma vecchia; il gestore risolve il modello per nome (e ripianifica il tempo di inattività quando rifiuta); il servizio MLX passa `system` come `instructions` e `enable_thinking` come contesto del template.

**`Packages/Sources/HubKit/Language/LanguageModelOptions.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// How a question to the language model is asked (the `system` and `options` of a plug-in's `llm` message).
/// Every field is optional: nil keeps the default (no system prompt, temperature 0.6, 1024 tokens, the
/// thinking setting of the model's own chat template).
public struct LanguageModelOptions: Equatable, Sendable {
  public var system: String?
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var presencePenalty: Double?
  public var maxTokens: Int?
  /// Lets a reasoning model think before it answers (`enable_thinking` of the chat template).
  public var thinking: Bool?

  public static let temperatureRange = 0.0...2.0
  public static let topPRange = 0.0...1.0
  public static let topKRange = 0...200
  public static let presencePenaltyRange = -2.0...2.0
  public static let maxTokensRange = 1...32768

  public init(
    system: String? = nil, temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil,
    presencePenalty: Double? = nil, maxTokens: Int? = nil, thinking: Bool? = nil
  ) {
    self.system = system
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.presencePenalty = presencePenalty
    self.maxTokens = maxTokens
    self.thinking = thinking
  }

  /// Reads a plug-in's message: `system` (a string) and `options` (an object with `temperature`, `topP`,
  /// `topK`, `presencePenalty`, `maxTokens`, `thinking`). A number out of range is brought into range, a
  /// value of the wrong kind is left out, an unknown key is ignored.
  public init(message: [String: Any]) {
    let options = message["options"] as? [String: Any] ?? [:]
    func number(_ key: String) -> Double? { (options[key] as? NSNumber)?.doubleValue }
    func flag(_ key: String) -> Bool? { (options[key] as? NSNumber).flatMap { Self.isBoolean($0) ? $0.boolValue : nil } }
    let system = (message["system"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    self.init(
      system: system, temperature: number("temperature"), topP: number("topP"),
      topK: number("topK").map { Int($0.rounded()) }, presencePenalty: number("presencePenalty"),
      maxTokens: number("maxTokens").map { Int($0.rounded()) }, thinking: flag("thinking"))
    self = clamped()
  }

  /// The numbers forced into their ranges.
  public func clamped() -> LanguageModelOptions {
    var copy = self
    copy.temperature = temperature.map { min(max($0, Self.temperatureRange.lowerBound), Self.temperatureRange.upperBound) }
    copy.topP = topP.map { min(max($0, Self.topPRange.lowerBound), Self.topPRange.upperBound) }
    copy.topK = topK.map { min(max($0, Self.topKRange.lowerBound), Self.topKRange.upperBound) }
    copy.presencePenalty = presencePenalty.map {
      min(max($0, Self.presencePenaltyRange.lowerBound), Self.presencePenaltyRange.upperBound)
    }
    copy.maxTokens = maxTokens.map { min(max($0, Self.maxTokensRange.lowerBound), Self.maxTokensRange.upperBound) }
    return copy
  }

  private static func isBoolean(_ number: NSNumber) -> Bool { CFGetTypeID(number) == CFBooleanGetTypeID() }
}
```

```diff
diff --git a/Packages/Sources/HubKit/Language/LanguageModel.swift b/Packages/Sources/HubKit/Language/LanguageModel.swift
index 1ab270a..6470508 100644
--- a/Packages/Sources/HubKit/Language/LanguageModel.swift
+++ b/Packages/Sources/HubKit/Language/LanguageModel.swift
@@ -28,6 +28,8 @@ public enum LanguageModelError: Error, Equatable, Sendable {
   /// The model does not fit in the memory that is free now.
   case notEnoughMemory(neededBytes: Int64, availableBytes: Int64)
   case imagesNotSupported
+  /// A plug-in asked for a model by name and the models folder has none with that name.
+  case modelNotFound(String)
   /// The model was freed while it was loading, because RUN needed the memory.
   case interrupted
   case loadFailed(String)
@@ -42,8 +44,15 @@ public protocol LanguageModelService: Sendable {
   func load(_ model: LanguageModelDescriptor) async throws
   /// Frees the memory of the loaded model; does nothing when none is loaded.
   func unload() async
-  /// One question, with images for a vision model. The model must be loaded.
-  func respond(to prompt: String, images: [URL]) async throws -> String
+  /// One question, with images for a vision model and the options of `LanguageModelOptions`. The model must be loaded.
+  func respond(to prompt: String, images: [URL], options: LanguageModelOptions) async throws -> String
+}
+
+extension LanguageModelService {
+  /// A question with the default options.
+  public func respond(to prompt: String, images: [URL]) async throws -> String {
+    try await respond(to: prompt, images: images, options: LanguageModelOptions())
+  }
 }
 
 /// Downloads a model from Hugging Face into a folder, only when the user asked (spec §9).
```

```diff
diff --git a/Packages/Sources/HubCore/Language/LanguageModelManager.swift b/Packages/Sources/HubCore/Language/LanguageModelManager.swift
index a1e7b0d..03c3c6d 100644
--- a/Packages/Sources/HubCore/Language/LanguageModelManager.swift
+++ b/Packages/Sources/HubCore/Language/LanguageModelManager.swift
@@ -72,18 +72,35 @@ public final class LanguageModelManager {
   }
 
   /// Asks the model: loads it first when needed (after the memory check), then frees it after
-  /// the idle time.
-  public func respond(to prompt: String, images: [URL] = []) async throws(LanguageModelError) -> String {
+  /// the idle time. `modelNamed` asks a model of the folder by name instead of the one chosen in
+  /// the settings (a plug-in's wish): the choice in the settings stays as it is.
+  public func respond(
+    to prompt: String, images: [URL] = [], options: LanguageModelOptions = LanguageModelOptions(),
+    modelNamed name: String? = nil
+  ) async throws(LanguageModelError) -> String {
     activity += 1
     idleTask?.cancel()
-    guard let model = selectedModel() else {
-      state = .failed(.noModelSelected)
-      throw .noModelSelected
+    let model: LanguageModelDescriptor
+    if let name {
+      guard let named = availableModels().first(where: { $0.name == name }) else {
+        scheduleIdleUnload()
+        throw .modelNotFound(name)
+      }
+      model = named
+    } else {
+      guard let chosen = selectedModel() else {
+        state = .failed(.noModelSelected)
+        throw .noModelSelected
+      }
+      model = chosen
+    }
+    if !images.isEmpty, !model.supportsImages {
+      scheduleIdleUnload()
+      throw .imagesNotSupported
     }
-    if !images.isEmpty, !model.supportsImages { throw .imagesNotSupported }
     try await ensureLoaded(model)
     do {
-      let answer = try await service.respond(to: prompt, images: images)
+      let answer = try await service.respond(to: prompt, images: images, options: options)
       scheduleIdleUnload()
       return answer
     } catch let error as LanguageModelError {
```

```diff
diff --git a/Packages/Sources/LLMBridge/MLXLanguageModelService.swift b/Packages/Sources/LLMBridge/MLXLanguageModelService.swift
index 3f64131..b4ba785 100644
--- a/Packages/Sources/LLMBridge/MLXLanguageModelService.swift
+++ b/Packages/Sources/LLMBridge/MLXLanguageModelService.swift
@@ -33,10 +33,12 @@ public actor MLXLanguageModelService: LanguageModelService {
     MLX.Memory.clearCache()
   }
 
-  public func respond(to prompt: String, images: [URL]) async throws -> String {
+  public func respond(to prompt: String, images: [URL], options: LanguageModelOptions) async throws -> String {
     guard let container else { throw LanguageModelError.loadFailed("No model is loaded.") }
     // A new session per question: DT Hub asks single questions, with no conversation to keep.
-    let session = ChatSession(container, generateParameters: GenerateParameters(maxTokens: 1024, temperature: 0.6))
+    let session = ChatSession(
+      container, instructions: options.system, generateParameters: Self.generateParameters(for: options),
+      additionalContext: Self.templateContext(for: options))
     do {
       return try await session.respond(
         to: prompt, role: .user, images: images.map { UserInput.Image.url($0) }, videos: [], audios: [])
@@ -44,4 +46,16 @@ public actor MLXLanguageModelService: LanguageModelService {
       throw LanguageModelError.generationFailed(error.localizedDescription)
     }
   }
+
+  /// The defaults are the ones DT Hub always had: temperature 0.6, 1024 tokens.
+  static func generateParameters(for options: LanguageModelOptions) -> GenerateParameters {
+    GenerateParameters(
+      maxTokens: options.maxTokens ?? 1024, temperature: Float(options.temperature ?? 0.6),
+      topP: Float(options.topP ?? 1), topK: options.topK ?? 0, presencePenalty: options.presencePenalty.map { Float($0) })
+  }
+
+  /// What the chat template is told: `enable_thinking`, only when the plug-in said something.
+  static func templateContext(for options: LanguageModelOptions) -> [String: any Sendable]? {
+    options.thinking.map { ["enable_thinking": $0] }
+  }
 }
```

```diff
diff --git a/App/Preferences/LanguagePreferencesView.swift b/App/Preferences/LanguagePreferencesView.swift
index df45005..6b43867 100644
--- a/App/Preferences/LanguagePreferencesView.swift
+++ b/App/Preferences/LanguagePreferencesView.swift
@@ -245,6 +245,7 @@ enum LanguageModelErrorText {
     case .noModelSelected: return String(localized: "llm.error.noModel")
     case .imagesNotSupported: return String(localized: "llm.error.noImages")
     case .interrupted: return String(localized: "llm.error.interrupted")
+    case .modelNotFound(let name): return String(format: String(localized: "llm.error.modelNotFound"), name)
     case .notEnoughMemory(let needed, let available):
       return String(
         format: String(localized: "llm.error.memory"), ByteCountFormatter.string(fromByteCount: needed, countStyle: .memory),
```

```diff
diff --git a/App/Localizable.xcstrings b/App/Localizable.xcstrings
index 8910006..856dcde 100644
--- a/App/Localizable.xcstrings
+++ b/App/Localizable.xcstrings
@@ -3707,6 +3707,23 @@
         }
       }
     },
+    "llm.error.modelNotFound": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "The language model “%@” is not in the models folder."
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Il modello linguistico «%@» non è nella cartella dei modelli."
+          }
+        }
+      }
+    },
     "llm.error.noImages": {
       "extractionState": "manual",
       "localizations": {
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:|✘ Test [a-zA-Z]+\(" | grep -v started`
Expected: HubKit `106 tests`, HubCore `469 tests`, LLMBridge `10 tests` (uno è il test dal vivo, saltato senza modello), gli altri invariati (DTBridge 66, Catalog 6, PluginHost 6), nessuna riga `✘`.

Run (se la cartella del modello c'è): `cd "/Users/existenz/Software developement/DT Hub/Packages" && TEST_RUNNER_DTHUB_LIVE_LLM=/Volumes/LLM-VLM/MLX/mlx-community/Qwen3-VL-2B-Instruct-4bit xcodebuild test -scheme DTHubPackages-Package -destination 'platform=macOS' -derivedDataPath ../build/pkg -only-testing:LLMBridgeTests 2>&1 | grep -E "LIVE (system|short)|Test run with|TEST (SUCCEEDED|FAILED)"`
Expected: `LIVE system answer: BANANA`, `LIVE short answer: 1, 2, 3, 4,`, `Test run with 10 tests in 4 suites passed`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Packages App && git commit -m "feat: llm con system, modello per nome e opzioni (HubKit, HubCore, LLMBridge)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Il registro dei plug-in legge le chiavi nuove; il contesto porta l'immagine di partenza e i modelli

**Files:**
- `App/DTHubApp.swift`, `App/MainWindow/MainWindowView.swift`, `Packages/Sources/HubCore/Control/ControlStore.swift`, `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `Packages/Sources/HubKit/Language/LanguageModelError+Plain.swift`, `Packages/Sources/HubKit/Plugin/PluginMessages.swift`, `Packages/Tests/HubCoreTests/ControlStoreTests.swift`, `Packages/Tests/HubCoreTests/PluginRegistryTests.swift`, `Packages/Tests/HubCoreTests/PluginRoutingTests.swift`, `Packages/Tests/HubKitTests/LanguageModelContractTests.swift`, `Packages/Tests/HubKitTests/PluginContractTests.swift`

**Interfaces:**
- Consumes: `LanguageModelOptions(message:)` e `LanguageModelManager.respond(to:images:options:modelNamed:)` (Task 1).
- Produces: `PluginLanguageModel {name, path, supportsImages}` e `PluginContext.startImage: String?`, `PluginContext.languageModels: [PluginLanguageModel]?` (HubKit); `ControlStore.startImageURL: URL?`; `LanguageModelError.plainText` (HubKit: il motivo in inglese semplice, che il registro manda al plug-in al posto del nome dell'enum); `PluginRegistry.askLanguageModel: (prompt, images, options, modelName) async throws -> String`, `PluginRegistry.startImagePath`, `PluginRegistry.languageModels` (closure, lette a ogni invio del contesto), `PluginRegistry.refreshContext()`; nell'app il contesto si rimanda al cambio dell'immagine di partenza e quando si torna su un tab.

- [ ] **Step 1: Scrivere i test**

```diff
diff --git a/Packages/Tests/HubKitTests/PluginContractTests.swift b/Packages/Tests/HubKitTests/PluginContractTests.swift
index f251427..2fb62b1 100644
--- a/Packages/Tests/HubKitTests/PluginContractTests.swift
+++ b/Packages/Tests/HubKitTests/PluginContractTests.swift
@@ -55,4 +55,30 @@ struct PluginContractTests {
     let back = try JSONDecoder().decode(PluginContext.self, from: data)
     #expect(back == context)
   }
+
+  @Test func theContextCarriesTheStartImageAndTheLanguageModels() throws {
+    let context = PluginContext(
+      model: "m.ckpt", family: "qwen_image_2.1", parameters: GenerationParameters(), tempFolder: "/tmp/x",
+      startImage: "/tmp/start.png",
+      languageModels: [PluginLanguageModel(name: "a/b", path: "/m/a/b", supportsImages: true)])
+    let data = try JSONEncoder().encode(context)
+    #expect(try JSONDecoder().decode(PluginContext.self, from: data) == context)
+    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
+    #expect(object["startImage"] as? String == "/tmp/start.png")
+    #expect((object["languageModels"] as? [[String: Any]])?.first?["name"] as? String == "a/b")
+  }
+
+  @Test func withoutAStartImageOrModelsTheContextLeavesTheKeysOut() throws {
+    let context = PluginContext(model: nil, family: nil, parameters: GenerationParameters(), tempFolder: "/tmp/x")
+    let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? [String: Any])
+    #expect(object["startImage"] == nil)
+    #expect(object["languageModels"] == nil)
+  }
+
+  @Test func aContextFromAnOlderAppStillDecodes() throws {
+    let old = try JSONEncoder().encode(
+      PluginContext(model: "m.ckpt", family: nil, parameters: GenerationParameters(), tempFolder: "/tmp/x"))
+    let back = try JSONDecoder().decode(PluginContext.self, from: old)
+    #expect(back.startImage == nil && back.languageModels == nil)
+  }
 }
```

```diff
diff --git a/Packages/Tests/HubKitTests/LanguageModelContractTests.swift b/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
index f45bc44..91392e6 100644
--- a/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
+++ b/Packages/Tests/HubKitTests/LanguageModelContractTests.swift
@@ -57,4 +57,16 @@ struct LanguageModelContractTests {
   @Test func thinkingCanBeSwitchedOffToo() throws {
     #expect(LanguageModelOptions(message: try message(#"{"options":{"thinking":false}}"#)).thinking == false)
   }
+
+  @Test func everyErrorHasAReasonInPlainEnglishThatNamesWhatMatters() {
+    #expect(LanguageModelError.modelNotFound("mlx/pe").plainText.contains("mlx/pe"))
+    #expect(LanguageModelError.loadFailed("bad weights").plainText.contains("bad weights"))
+    #expect(LanguageModelError.generationFailed("out of tokens").plainText.contains("out of tokens"))
+    #expect(LanguageModelError.downloadFailed("offline").plainText == "offline")
+    let all: [LanguageModelError] = [
+      .noModelSelected, .notEnoughMemory(neededBytes: 5_000_000_000, availableBytes: 1_000_000_000), .imagesNotSupported,
+      .interrupted,
+    ]
+    #expect(all.allSatisfy { !$0.plainText.isEmpty && !$0.plainText.contains("noModel") })
+  }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PluginRoutingTests.swift b/Packages/Tests/HubCoreTests/PluginRoutingTests.swift
index 9d0dff2..5c950ac 100644
--- a/Packages/Tests/HubCoreTests/PluginRoutingTests.swift
+++ b/Packages/Tests/HubCoreTests/PluginRoutingTests.swift
@@ -72,7 +72,7 @@ struct PluginRoutingTests {
   @Test func aQuestionForTheLanguageModelIsAnswered() async throws {
     let (registry, loader) = try started()
     var asked: (String, [URL])?
-    registry.askLanguageModel = { prompt, images in
+    registry.askLanguageModel = { prompt, images, _, _ in
       asked = (prompt, images)
       return "Sunny."
     }
@@ -83,14 +83,47 @@ struct PluginRoutingTests {
     #expect(asked?.1 == [URL(fileURLWithPath: "/tmp/a.png")])
   }
 
+  @Test func theSystemPromptTheModelAndTheOptionsReachTheLanguageModel() async throws {
+    let (registry, loader) = try started()
+    var asked: (LanguageModelOptions, String?)?
+    registry.askLanguageModel = { _, _, options, name in
+      asked = (options, name)
+      return "ok"
+    }
+    _ = try await send(
+      #"{"type":"llm","prompt":"p","system":"Be brief.","model":"mlx/pe","options":{"temperature":1,"thinking":true}}"#,
+      through: loader)
+    #expect(asked?.0 == LanguageModelOptions(system: "Be brief.", temperature: 1, thinking: true))
+    #expect(asked?.1 == "mlx/pe")
+    // Without the new keys the question is asked as it always was.
+    _ = try await send(#"{"type":"llm","prompt":"p"}"#, through: loader)
+    #expect(asked?.0 == LanguageModelOptions())
+    #expect(asked?.1 == nil)
+  }
+
+  @Test func theReasonIsToldInPlainWords() async throws {
+    let (registry, loader) = try started()
+    registry.askLanguageModel = { _, _, _, _ in throw LanguageModelError.noModelSelected }
+    let reply = try await send(#"{"type":"llm","prompt":"p"}"#, through: loader)
+    #expect(reply["text"] as? String == "No language model is chosen.")
+  }
+
+  @Test func aModelThatIsNotThereIsAnError() async throws {
+    let (registry, loader) = try started()
+    registry.askLanguageModel = { _, _, _, name in throw LanguageModelError.modelNotFound(name ?? "") }
+    let reply = try await send(#"{"type":"llm","prompt":"p","model":"nowhere"}"#, through: loader)
+    #expect(reply["type"] as? String == "error")
+    #expect((reply["text"] as? String)?.contains("nowhere") == true)
+  }
+
   @Test func aQuestionThatCannotBeAnsweredGetsAnError() async throws {
     let (registry, loader) = try started()
     #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
-    registry.askLanguageModel = { _, _ in throw LanguageModelError.noModelSelected }
+    registry.askLanguageModel = { _, _, _, _ in throw LanguageModelError.noModelSelected }
     #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
     #expect(try await send(#"{"type":"llm"}"#, through: loader)["type"] as? String == "error")
     registry.setActive("a", false)
-    registry.askLanguageModel = { _, _ in "never" }
+    registry.askLanguageModel = { _, _, _, _ in "never" }
     #expect(try await send(#"{"type":"llm","prompt":"hi"}"#, through: loader)["type"] as? String == "error")
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PluginRegistryTests.swift b/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
index 6efcf38..bd2407b 100644
--- a/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
+++ b/Packages/Tests/HubCoreTests/PluginRegistryTests.swift
@@ -127,6 +127,47 @@ struct PluginRegistryTests {
     #expect(Array(plugin.sentTypes.suffix(2)) == [PluginMessageType.activate, PluginMessageType.context])
   }
 
+  @Test func theContextTellsAboutTheStartImageAndTheLanguageModels() async throws {
+    try PluginFixture.bundle(in: root, id: "a", name: "A")
+    let loader = FakeLoader()
+    let registry = registry(loader: loader, enabled: ["a"])
+    var startImage: String? = "/tmp/start.png"
+    var models = [PluginLanguageModel(name: "a/pe", path: "/m/a/pe", supportsImages: true)]
+    registry.startImagePath = { startImage }
+    registry.languageModels = { models }
+    registry.start()
+    registry.updateContext(model: "m.ckpt", family: "qwen_image_2.1", parameters: GenerationParameters())
+    await settle()
+    let plugin = try #require(loader.plugins["a"])
+    func lastContext() throws -> PluginContext {
+      let data = try #require(plugin.sent.last { PluginMessageType.of($0) == PluginMessageType.context })
+      return try JSONDecoder().decode(PluginContext.self, from: data)
+    }
+    #expect(try lastContext().startImage == "/tmp/start.png")
+    #expect(try lastContext().languageModels == models)
+    // The start image goes and a model arrives: nothing is sent until the app says so, then it is.
+    startImage = nil
+    models.append(PluginLanguageModel(name: "b", path: "/m/b", supportsImages: false))
+    #expect(try lastContext().startImage == "/tmp/start.png")
+    registry.refreshContext()
+    await settle()
+    #expect(try lastContext().startImage == nil)
+    #expect(try lastContext().languageModels?.count == 2)
+  }
+
+  @Test func refreshingTheContextTellsOnlyThePluginsThatAreOn() async throws {
+    try PluginFixture.bundle(in: root, id: "a", name: "A")
+    let loader = FakeLoader()
+    let registry = registry(loader: loader, enabled: ["a"])
+    registry.start()
+    registry.setActive("a", false)
+    await settle()
+    let before = try #require(loader.plugins["a"]).sent.count
+    registry.refreshContext()
+    await settle()
+    #expect(try #require(loader.plugins["a"]).sent.count == before)
+  }
+
   @Test func aPluginForOtherFamiliesHasNoTabWhileAnotherModelIsChosen() throws {
     try PluginFixture.bundle(in: root, id: "a", name: "A")
     let loader = FakeLoader()
```

```diff
diff --git a/Packages/Tests/HubCoreTests/ControlStoreTests.swift b/Packages/Tests/HubCoreTests/ControlStoreTests.swift
index b3743ab..e748f95 100644
--- a/Packages/Tests/HubCoreTests/ControlStoreTests.swift
+++ b/Packages/Tests/HubCoreTests/ControlStoreTests.swift
@@ -51,6 +51,18 @@ struct ControlStoreTests {
     #expect(image.fileName.hasSuffix(".png"))
   }
 
+  @Test func theStartImageHasAFileAndNothingElseDoes() throws {
+    let root = folder()
+    let store = store(in: root)
+    #expect(store.startImageURL == nil)
+    try store.setImage(data: pictureData(width: 30, height: 20), name: "cat.png", source: .pasteboard)
+    let url = try #require(store.startImageURL)
+    #expect(url.deletingLastPathComponent().lastPathComponent == "Control")
+    #expect(FileManager.default.fileExists(atPath: url.path))
+    store.removeImage()
+    #expect(store.startImageURL == nil)
+  }
+
   @Test func theSizeFollowsTheExifOrientation() throws {
     let store = store(in: folder())
     try store.setImage(data: pictureData(width: 300, height: 200, type: .jpeg, orientation: 6), name: "p.jpg", source: .pasteboard)
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "PluginContractTests|PluginRoutingTests|PluginRegistryTests|ControlStoreTests" 2>&1 | grep -E "error:" | head -3`
Expected: errori di compilazione (`extra arguments 'startImage'`, `value of type 'PluginRegistry' has no member 'startImagePath'`, `has no member 'startImageURL'`).

- [ ] **Step 3: Implementare**

`PluginContext` ottiene i due campi facoltativi (assenti dal JSON quando sono `nil`); `ControlStore.startImageURL` dà il file dell'immagine di partenza; il registro legge `system`, `model` e `options` dal messaggio `llm`, le passa alla closure e risponde a un errore dell'LLM con `plainText`; l'app collega la closure al gestore, il percorso all'immagine di partenza e l'elenco ai modelli della cartella, e rimanda il contesto quando cambia l'immagine di partenza o si sceglie un tab.

**`Packages/Sources/HubKit/Language/LanguageModelError+Plain.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

extension LanguageModelError {
  /// The reason in plain English, for a plug-in to show (the app's own windows use the localized catalog).
  public var plainText: String {
    switch self {
    case .noModelSelected:
      return "No language model is chosen."
    case .notEnoughMemory(let needed, let available):
      return "The language model needs about \(ByteCountFormatter.string(fromByteCount: needed, countStyle: .memory)) "
        + "and only \(ByteCountFormatter.string(fromByteCount: available, countStyle: .memory)) is free."
    case .imagesNotSupported:
      return "The language model cannot read images."
    case .modelNotFound(let name):
      return "The language model “\(name)” is not in the models folder."
    case .interrupted:
      return "The language model was stopped to free the memory for an image."
    case .loadFailed(let detail):
      return "The language model could not be loaded: \(detail)"
    case .generationFailed(let detail):
      return "The language model could not answer: \(detail)"
    case .downloadFailed(let detail):
      return detail
    }
  }
}
```

```diff
diff --git a/Packages/Sources/HubKit/Plugin/PluginMessages.swift b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
index 223f6ff..ab0696e 100644
--- a/Packages/Sources/HubKit/Plugin/PluginMessages.swift
+++ b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
@@ -34,7 +34,24 @@ public enum PluginMessageType {
   }
 }
 
-/// App → plug-in: where the app stands (sent when the plug-in is activated and when the model changes).
+/// A language model of the models folder, as a plug-in is told about it (`PluginContext.languageModels`).
+public struct PluginLanguageModel: Codable, Equatable, Sendable {
+  /// The name `llm`'s `model` asks for (the path below the models folder).
+  public var name: String
+  /// Its folder, to read files that come with the model.
+  public var path: String
+  /// True for a vision-language model: it can be given images.
+  public var supportsImages: Bool
+
+  public init(name: String, path: String, supportsImages: Bool) {
+    self.name = name
+    self.path = path
+    self.supportsImages = supportsImages
+  }
+}
+
+/// App → plug-in: where the app stands (sent when the plug-in is activated, when the model, its parameters or the
+/// start image change, and when the user comes back to a tab).
 public struct PluginContext: Codable, Equatable, Sendable {
   public var type = PluginMessageType.context
   public var model: String?
@@ -42,12 +59,21 @@ public struct PluginContext: Codable, Equatable, Sendable {
   public var parameters: GenerationParameters
   /// A folder the plug-in can exchange image files through.
   public var tempFolder: String
+  /// The start image of the Control tab: the path of its file. Absent when there is none. The Moodboard is not part of it.
+  public var startImage: String?
+  /// The language models of the models folder. Absent when the app has none to list.
+  public var languageModels: [PluginLanguageModel]?
 
-  public init(model: String?, family: String?, parameters: GenerationParameters, tempFolder: String) {
+  public init(
+    model: String?, family: String?, parameters: GenerationParameters, tempFolder: String, startImage: String? = nil,
+    languageModels: [PluginLanguageModel]? = nil
+  ) {
     self.model = model
     self.family = family
     self.parameters = parameters
     self.tempFolder = tempFolder
+    self.startImage = startImage
+    self.languageModels = languageModels
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index b288b44..fc86bc7 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -36,6 +36,9 @@ public enum ControlWarning: Hashable, Sendable {
 public final class ControlStore {
   public private(set) var inputs: ControlInputs
   public private(set) var notice: ControlNotice?
+
+  /// The file of the start image: what a plug-in is told, and what a language model reads.
+  public var startImageURL: URL? { inputs.image.map { storage.url(for: $0.fileName) } }
   /// Changes with every step of the history, so `canUndo` and `canRedo` can be observed (the
   /// stacks themselves are not).
   private var historyVersion = 0
```

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
index ec3bcfb..2313b9e 100644
--- a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
+++ b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
@@ -64,8 +64,14 @@ public final class PluginRegistry: PluginHosting {
   public let contributions = ContributionStore()
   /// The Preset menu's store, where the presets a plug-in brings go; set by the app.
   @ObservationIgnored public var presetStore: PresetStore?
-  /// Answers a plug-in's question to the language model (`llm` message); nil = no language model.
-  @ObservationIgnored public var askLanguageModel: (@MainActor (_ prompt: String, _ images: [URL]) async throws -> String)?
+  /// Answers a plug-in's question to the language model (`llm` message); nil = no language model. `modelName` is the
+  /// model of the models folder the plug-in asks for; nil = the one chosen in the settings.
+  @ObservationIgnored public var askLanguageModel:
+    (@MainActor (_ prompt: String, _ images: [URL], _ options: LanguageModelOptions, _ modelName: String?) async throws -> String)?
+  /// The path of the Control tab's start image, when there is one; read whenever a context is sent.
+  @ObservationIgnored public var startImagePath: (@MainActor () -> String?)?
+  /// The language models of the models folder; read whenever a context is sent.
+  @ObservationIgnored public var languageModels: (@MainActor () -> [PluginLanguageModel])?
 
   @ObservationIgnored private let folder: PluginFolder
   @ObservationIgnored private let settings: PluginSettingsStore
@@ -263,9 +269,16 @@ public final class PluginRegistry: PluginHosting {
 
   @ObservationIgnored private var latestParameters = GenerationParameters()
 
+  /// Tells the active plug-ins where the app stands again, for what changed without the model or its parameters
+  /// changing (a model added to the models folder, a start image): the app calls it when a plug-in's tab is shown.
+  public func refreshContext() {
+    for entry in entries where entry.state == .loaded && entry.isActive { sendContext(to: entry.id) }
+  }
+
   private func sendContext(to identifier: String) {
     let context = PluginContext(
-      model: model, family: family, parameters: latestParameters, tempFolder: tempFolder.path)
+      model: model, family: family, parameters: latestParameters, tempFolder: tempFolder.path,
+      startImage: startImagePath?(), languageModels: languageModels?())
     guard let data = try? JSONEncoder().encode(context) else { return }
     send(data, to: identifier)
   }
@@ -337,7 +350,7 @@ public final class PluginRegistry: PluginHosting {
     return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
   }
 
-  /// `{"type":"llm","prompt":…,"images":[paths]}` → `{"type":"llm","text":…}`.
+  /// `{"type":"llm","prompt":…,"images":[paths],"system":…,"model":name,"options":{…}}` → `{"type":"llm","text":…}`.
   private func askModel(_ message: Data, from pluginID: String) async -> Data {
     guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
     guard let object = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
@@ -345,10 +358,14 @@ public final class PluginRegistry: PluginHosting {
     else { return PluginMessageType.failure("The message has no prompt.") }
     guard let ask = askLanguageModel else { return PluginMessageType.failure("There is no language model.") }
     let images = (object["images"] as? [String] ?? []).map { URL(fileURLWithPath: $0) }
+    let options = LanguageModelOptions(message: object)
+    let modelName = (object["model"] as? String).flatMap { $0.isEmpty ? nil : $0 }
     do {
-      let text = try await ask(prompt, images)
+      let text = try await ask(prompt, images, options, modelName)
       return (try? JSONSerialization.data(withJSONObject: ["type": PluginMessageType.llm, "text": text]))
         ?? PluginMessageType.failure("The answer could not be sent.")
+    } catch let error as LanguageModelError {
+      return PluginMessageType.failure(error.plainText)
     } catch {
       return PluginMessageType.failure(String(describing: error))
     }
```

```diff
diff --git a/App/DTHubApp.swift b/App/DTHubApp.swift
index f840956..f09466c 100644
--- a/App/DTHubApp.swift
+++ b/App/DTHubApp.swift
@@ -45,7 +45,15 @@ struct DTHubApp: App {
     // Contributions land on the Generation tab; a plug-in's question goes to the language model.
     generation.attach(plugins.contributions)
     plugins.presetStore = generation.presets
-    plugins.askLanguageModel = { prompt, images in try await languageModel.respond(to: prompt, images: images) }
+    plugins.askLanguageModel = { prompt, images, options, name in
+      try await languageModel.respond(to: prompt, images: images, options: options, modelNamed: name)
+    }
+    plugins.startImagePath = { control.startImageURL?.path }
+    plugins.languageModels = {
+      languageModel.availableModels().map {
+        PluginLanguageModel(name: $0.name, path: $0.path, supportsImages: $0.supportsImages)
+      }
+    }
     plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
     _plugins = State(initialValue: plugins)
     // A download cut short by quitting leaves a hidden folder with part of a model: remove it.
```

```diff
diff --git a/App/MainWindow/MainWindowView.swift b/App/MainWindow/MainWindowView.swift
index 53e8aab..4b55fa7 100644
--- a/App/MainWindow/MainWindowView.swift
+++ b/App/MainWindow/MainWindowView.swift
@@ -13,7 +13,7 @@ struct MainWindowView: View {
   /// What the plug-ins are told about: the model and its family.
   private var contextKey: [String?] {
     let model = connection.selection.selectedModel(in: connection.monitor.catalog)
-    return [model?.file, model?.family]
+    return [model?.file, model?.family, generation.control.inputs.image?.id.uuidString]
   }
 
   var body: some View {
@@ -45,6 +45,8 @@ struct MainWindowView: View {
       workspace.setPluginTabs(plugins.activeTabs)
     }
     .onChange(of: plugins.activeTabs) { workspace.setPluginTabs(plugins.activeTabs) }
+    // A model added to the models folder meanwhile: the plug-in hears about it when its tab is shown.
+    .onChange(of: workspace.selectedTabID) { plugins.refreshContext() }
   }
 
   @ViewBuilder private var tabContent: some View {
```

- [ ] **Step 4: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:|✘ Test [a-zA-Z]+\(" | grep -v started`
Expected: HubKit `110 tests`, HubCore `475 tests`, LLMBridge `10`, DTBridge 66, Catalog 6, PluginHost 6, nessuna riga `✘`.

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/p-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Packages App && git commit -m "feat: il contesto dei plug-in porta l'immagine di partenza e i modelli linguistici; llm arriva al modello

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Il kit dei plug-in e i documenti

**Files:**
- `PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift`, `PluginKit/README.md`, `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`, `PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift`, `docs/superpowers/specs/2026-10-03-plugin-design.md`, `docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md`

**Interfaces:**
- Consumes: il formato del messaggio `llm` e del `context` (Task 1 e 2).
- Produces: `DTHubLanguageModel`, `DTHubContext.startImage` e `.languageModels`, `DTHubLLMOptions` (con `timeout`), `DTHubLLMAnswer` (`.text`, `.failure`), `DTHubHost.askLanguageModel(_:images:system:model:options:)` (il testo o `nil`) e `askLanguageModelAnswer(_:images:system:model:options:)` (con il motivo), `DTHubHost.llmMessage(...)` (interno, testato).

- [ ] **Step 1: Scrivere i test**

```diff
diff --git a/PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift b/PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift
index bcdd13d..5076daf 100644
--- a/PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift
+++ b/PluginKit/Tests/DTHubPluginKitTests/DTHubPluginKitTests.swift
@@ -1,3 +1,4 @@
+import Foundation
 import Testing
 
 @testable import DTHubPluginKit
@@ -11,4 +12,46 @@ struct DTHubPluginKitTests {
   @Test func aBareMessageIsAnObjectWithItsType() {
     #expect(DTHubMessage.type(of: DTHubMessage.bare("ok")) == "ok")
   }
+
+  @Test func aQuestionWithoutTheNewKeysIsTheOldMessage() throws {
+    let message = DTHubHost.llmMessage(prompt: "hi", images: [], system: nil, model: nil, options: DTHubLLMOptions())
+    #expect(Set(message.keys) == ["type", "prompt", "images"])
+    #expect(DTHubHost.llmMessage(prompt: "hi", images: [], system: "", model: "", options: DTHubLLMOptions()).count == 3)
+  }
+
+  @Test func theSystemPromptTheModelAndTheOptionsGoInTheMessage() throws {
+    let options = DTHubLLMOptions(temperature: 1, topK: 20, maxTokens: 100, thinking: false, timeout: 900)
+    let message = DTHubHost.llmMessage(
+      prompt: "hi", images: ["/a.png"], system: "Be brief.", model: "mlx/pe", options: options)
+    #expect(message["system"] as? String == "Be brief.")
+    #expect(message["model"] as? String == "mlx/pe")
+    let sent = try #require(message["options"] as? [String: Any])
+    #expect(sent["temperature"] as? Double == 1)
+    #expect(sent["topK"] as? Int == 20)
+    #expect(sent["maxTokens"] as? Int == 100)
+    #expect(sent["thinking"] as? Bool == false)
+    #expect(sent["timeout"] == nil)  // the wait is this library's business
+    #expect(sent["topP"] == nil)
+  }
+
+  @Test func theWaitIsFiveMinutesUnlessAskedAndNeverMoreThanHalfAnHour() {
+    #expect(DTHubLLMOptions().effectiveTimeout == 300)
+    #expect(DTHubLLMOptions(timeout: 900).effectiveTimeout == 900)
+    #expect(DTHubLLMOptions(timeout: 99_999).effectiveTimeout == 1800)
+    #expect(DTHubLLMOptions(timeout: 0).effectiveTimeout == 1)
+  }
+
+  @Test func theContextReadsTheStartImageAndTheModelsWhenTheyAreThereAndNotWhenTheyAreNot() throws {
+    let full = try JSONDecoder().decode(
+      DTHubContext.self,
+      from: Data(
+        #"""
+        {"type":"context","tempFolder":"/t","startImage":"/s.png",
+         "languageModels":[{"name":"a/b","path":"/m/a/b","supportsImages":true}]}
+        """#.utf8))
+    #expect(full.startImage == "/s.png")
+    #expect(full.languageModels == [DTHubLanguageModel(name: "a/b", path: "/m/a/b", supportsImages: true)])
+    let old = try JSONDecoder().decode(DTHubContext.self, from: Data(#"{"type":"context","tempFolder":"/t"}"#.utf8))
+    #expect(old.startImage == nil && old.languageModels == nil)
+  }
 }
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/PluginKit" && swift test 2>&1 | grep -E "error:" | head -2`
Expected: un errore di compilazione (`type 'DTHubHost' has no member 'llmMessage'`).

- [ ] **Step 3: Implementare**

`llmMessage` è `nonisolated static` (il tipo è `@MainActor`) e lascia fuori le chiavi non impostate e il `timeout`. `askLanguageModel` resta compatibile (la forma vecchia compila) e si appoggia su `askLanguageModelAnswer`. Il Sample usa `system` e le opzioni.

```diff
diff --git a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
index 5ca3ec5..ce26c3c 100644
--- a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
+++ b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
@@ -39,12 +39,77 @@ public enum DTHubMessage {
   public static func bare(_ type: String) -> Data { Data(#"{"type":"\#(type)"}"#.utf8) }
 }
 
+/// A language model of the app's models folder (an entry of `DTHubContext.languageModels`).
+public struct DTHubLanguageModel: Decodable, Equatable, Sendable {
+  /// The name `askLanguageModel(model:)` asks for.
+  public var name: String
+  /// Its folder, to read files that come with the model.
+  public var path: String
+  /// True for a vision-language model: it can be given images.
+  public var supportsImages: Bool
+}
+
 /// App → plug-in: where the app stands (message type `context`).
 public struct DTHubContext: Decodable, Sendable {
   public var model: String?
   public var family: String?
   /// A folder to exchange image files through.
   public var tempFolder: String
+  /// The path of the start image of the Control tab; nil when there is none. The Moodboard does not count.
+  public var startImage: String?
+  /// The language models of the app's models folder; nil when the app does not say.
+  public var languageModels: [DTHubLanguageModel]?
+}
+
+/// How a question to the language model is asked. Every field is optional: nil keeps the app's default.
+public struct DTHubLLMOptions: Equatable, Sendable {
+  public var temperature: Double?
+  public var topP: Double?
+  public var topK: Int?
+  public var presencePenalty: Double?
+  public var maxTokens: Int?
+  /// Lets a reasoning model think before it answers.
+  public var thinking: Bool?
+  /// How long to wait for the answer, in seconds. Only this library uses it (the app never sees it): 300 when
+  /// nil, at most 1800.
+  public var timeout: Double?
+
+  public static let defaultTimeout = 300.0
+  public static let maxTimeout = 1800.0
+
+  public init(
+    temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil, presencePenalty: Double? = nil,
+    maxTokens: Int? = nil, thinking: Bool? = nil, timeout: Double? = nil
+  ) {
+    self.temperature = temperature
+    self.topP = topP
+    self.topK = topK
+    self.presencePenalty = presencePenalty
+    self.maxTokens = maxTokens
+    self.thinking = thinking
+    self.timeout = timeout
+  }
+
+  var effectiveTimeout: Double { min(max(timeout ?? Self.defaultTimeout, 1), Self.maxTimeout) }
+
+  /// The `options` object of the `llm` message: only what is set, and not the timeout.
+  var json: [String: Any] {
+    var object: [String: Any] = [:]
+    if let temperature { object["temperature"] = temperature }
+    if let topP { object["topP"] = topP }
+    if let topK { object["topK"] = topK }
+    if let presencePenalty { object["presencePenalty"] = presencePenalty }
+    if let maxTokens { object["maxTokens"] = maxTokens }
+    if let thinking { object["thinking"] = thinking }
+    return object
+  }
+}
+
+/// What the language model answered, or why not.
+public enum DTHubLLMAnswer: Equatable, Sendable {
+  case text(String)
+  /// The app's reason (no model chosen, not enough memory, the model is not in the folder…) or "No answer."
+  case failure(String)
 }
 
 /// The app side of the channel, given to the plug-in at start.
@@ -86,10 +151,41 @@ public final class DTHubHost {
   }
 
   /// Asks the app's language model, which answers in its own time (it may have to load first). Nil when
-  /// there is no answer: no model chosen, the plug-in not active, a timeout.
-  public func askLanguageModel(_ prompt: String, images: [String] = []) async -> String? {
-    let answer = await sendJSON(["type": "llm", "prompt": prompt, "images": images], timeout: 300)
-    return answer?["type"] as? String == "llm" ? answer?["text"] as? String : nil
+  /// there is no answer: no model chosen, the plug-in not active, a timeout. `system` is the system prompt;
+  /// `model` the name of a model of `DTHubContext.languageModels` to use instead of the one the user chose.
+  public func askLanguageModel(
+    _ prompt: String, images: [String] = [], system: String? = nil, model: String? = nil,
+    options: DTHubLLMOptions = DTHubLLMOptions()
+  ) async -> String? {
+    if case .text(let text) = await askLanguageModelAnswer(
+      prompt, images: images, system: system, model: model, options: options)
+    {
+      return text
+    }
+    return nil
+  }
+
+  /// Like `askLanguageModel`, with the app's reason when there is no answer.
+  public func askLanguageModelAnswer(
+    _ prompt: String, images: [String] = [], system: String? = nil, model: String? = nil,
+    options: DTHubLLMOptions = DTHubLLMOptions()
+  ) async -> DTHubLLMAnswer {
+    let message = Self.llmMessage(prompt: prompt, images: images, system: system, model: model, options: options)
+    guard let answer = await sendJSON(message, timeout: options.effectiveTimeout) else { return .failure("No answer.") }
+    if answer["type"] as? String == "llm", let text = answer["text"] as? String { return .text(text) }
+    return .failure(answer["text"] as? String ?? "No answer.")
+  }
+
+  /// The `llm` message: the keys that are not set are left out, so the app asks as it always did.
+  nonisolated static func llmMessage(
+    prompt: String, images: [String], system: String?, model: String?, options: DTHubLLMOptions
+  ) -> [String: Any] {
+    var message: [String: Any] = ["type": "llm", "prompt": prompt, "images": images]
+    if let system, !system.isEmpty { message["system"] = system }
+    if let model, !model.isEmpty { message["model"] = model }
+    let optionsJSON = options.json
+    if !optionsJSON.isEmpty { message["options"] = optionsJSON }
+    return message
   }
 
   func sendJSON(_ body: [String: Any], timeout: Double = 5) async -> [String: Any]? {
```

```diff
diff --git a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
index 07c1804..92f594a 100644
--- a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
+++ b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
@@ -159,7 +159,12 @@ final class SamplePlugin: DTHubPlugin {
   /// A question for the language model; the answer is shown, and sent as the prompt.
   func askModel() async {
     state.status = "Asking the language model…"
-    guard let text = await host?.askLanguageModel("Describe a quiet harbour at dawn in one short sentence.") else {
+    // `system` and `options` are optional: a system prompt, and how the model should write.
+    let answer = await host?.askLanguageModelAnswer(
+      "Describe a quiet harbour at dawn.", system: "Answer with one short sentence, in English.",
+      options: DTHubLLMOptions(temperature: 0.7, maxTokens: 120))
+    guard case .text(let text)? = answer else {
+      if case .failure(let reason)? = answer { return state.status = reason }
       return state.status = "No answer: is a language model chosen, and is this plug-in on?"
     }
     state.answer = text
```

- [ ] **Step 4: Aggiornare i documenti**

```diff
diff --git a/PluginKit/README.md b/PluginKit/README.md
index ebb1398..c6d3fff 100644
--- a/PluginKit/README.md
+++ b/PluginKit/README.md
@@ -40,7 +40,10 @@ and `import DTHubDesign` in the views (see `Plugins/SphereLight`).
 
 JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.
 
-**App → plug-in:** `context` (model, family, parameters, `tempFolder`: a folder to exchange picture files through),
+**App → plug-in:** `context` (model, family, parameters, `tempFolder`: a folder to exchange picture files through;
+`startImage`: the path of the Control tab's start image when there is one — the Moodboard does not count;
+`languageModels`: `[{"name", "path", "supportsImages"}]`, the language models of the app's models folder — both keys
+are left out when there is nothing to say; the app sends the context again when a plug-in's tab is shown),
 `activate`, `deactivate`.
 
 **Plug-in → app:**
@@ -71,7 +74,15 @@ JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.
   names apart. `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size,
   no model. A name the menu has already is never touched (the user may have changed it), so register them
   whenever you like. The answer is `{"type":"ok","added":n,"existing":m,"rejected":k}`.
-- `llm` — `{"prompt", "images": [paths]}`: a question for the language model. The answer is
-  `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`.
+- `llm` — `{"prompt", "images": [paths], "system", "model", "options"}`: a question for the language model. The answer
+  is `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`. Only `prompt` is
+  needed. `system` is the system prompt. `model` is the `name` of one of `languageModels` and asks for that model
+  instead of the one the user chose (the user's choice stays; an unknown name is an `error`). `options` is an object
+  with `temperature` (0–2), `topP` (0–1), `topK` (0–200), `presencePenalty` (−2–2), `maxTokens` (1–32768) and
+  `thinking` (true/false: lets a reasoning model think first); a number out of range is brought into range, what is
+  not set keeps the app's default (temperature 0.6, 1024 tokens). With the library: `host.askLanguageModel(prompt,
+  system:, model:, options: DTHubLLMOptions(…))` returns the text or nil, `askLanguageModelAnswer` also gives the
+  app's reason; `DTHubLLMOptions.timeout` (seconds, 300 by default, 1800 at most) is how long the library waits and
+  is not sent.
 
 The Sample plug-in (`Examples/Sample`, `Scripts/build-sample.sh OUT [b]`) sends all of these.
```

```diff
diff --git a/docs/superpowers/specs/2026-10-03-plugin-design.md b/docs/superpowers/specs/2026-10-03-plugin-design.md
index 3c7e7f8..2d024f3 100644
--- a/docs/superpowers/specs/2026-10-03-plugin-design.md
+++ b/docs/superpowers/specs/2026-10-03-plugin-design.md
@@ -32,7 +32,7 @@ La classe principale (`NSPrincipalClass`, sottoclasse di `NSObject`) risponde a:
 - `dthubHandle(_ message: Data, reply: @escaping (Data) -> Void)`: l'app parla al plug-in.
 
 **Messaggi:** JSON `{"type": "...", …}`, con una risposta JSON. Un messaggio sconosciuto riceve `{"type":"unsupported"}` e non è un errore.
-- *App → plug-in*: `context` (parametri correnti in sola lettura, modello e famiglia scelti, catalogo di modelli e LoRA, cartella temporanea per le immagini), `activate`, `deactivate`;
+- *App → plug-in*: `context` (parametri correnti in sola lettura, modello e famiglia scelti, catalogo di modelli e LoRA, cartella temporanea per le immagini; dal 5 ottobre anche `startImage`, il file dell'immagine di partenza del tab Control, e `languageModels`, i modelli linguistici della cartella), `activate`, `deactivate`;
 - *plug-in → app*: `notice` (un avviso da mostrare), e in M8b `contribute` (parametri, prompt, negativo, immagine di partenza, moodboard, maschera, pipeline) e `llm` (una richiesta al servizio di linguaggio, spec principale §9).
 - Le **immagini** non viaggiano nei messaggi: si scambiano come file PNG nella cartella temporanea del contesto.
 
@@ -115,7 +115,7 @@ Il contratto resta la **versione 1**: i nuovi messaggi sono aggiunte, e un'app c
 - `startImage`: `{path, name}`, l'immagine di partenza del tab Control (provenienza del plug-in); la maschera non si può contribuire in M8b (backlog).
 - `pipeline`: `{name, steps: [{title, fields, loras, moodboard, startImage, useOutputAsStart}]}`. Il passaggio esegue i campi del tab con le sue modifiche sopra; `loras` e `moodboard` del passaggio **sostituiscono** quelli del tab per quel passaggio (`[]` = nessuno), se assenti restano quelli del tab; `startImage` o l'output del passaggio precedente (`useOutputAsStart`) sostituiscono l'immagine di partenza (inquadrata sul canvas del passaggio, senza la maschera del tab).
 
-**`llm`** (plug-in → app): `{prompt, images:[percorsi]}` → `{"type":"llm","text":…}` oppure `error` (nessun modello scelto, immagini non supportate…). La risposta può tardare (il modello si carica); la libreria dei plug-in aspetta fino a 300 secondi.
+**`llm`** (plug-in → app): `{prompt, images:[percorsi], system?, model?, options?}` → `{"type":"llm","text":…}` oppure `error` (nessun modello scelto, immagini non supportate, modello non trovato…). `system` è il system prompt; `model` è il nome di un modello della cartella dei modelli (lo ricevi in `context.languageModels`) e vale al posto di quello scelto dall'utente, che resta com'è; `options` ha `temperature`, `topP`, `topK`, `presencePenalty`, `maxTokens`, `thinking` (tutti facoltativi, riportati nei loro limiti). La risposta può tardare (il modello si carica); la libreria dei plug-in aspetta 300 secondi, o quanto dice `DTHubLLMOptions.timeout` (al massimo 1800; non viaggia nel messaggio). Aggiunte del 5 ottobre 2026 (tappa 1 di Prompt Master): additive, il numero di contratto resta 1.
 
 **Scelte del prototipo.**
 - Un campo prende il teal finché **contiene** il valore del plug-in; se l'utente lo modifica compare il valore tra parentesi, e se riscrive lo stesso valore il teal torna. Prompt e negativo: teal, mai parentesi. Il segno non si salva: al riavvio i valori restano, senza teal.
```

```diff
diff --git a/docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md b/docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md
index 739b7bf..aed4b1b 100644
--- a/docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md
+++ b/docs/superpowers/specs/2026-10-05-plugin-prompt-master-design.md
@@ -78,11 +78,11 @@ Per `v1` e `sdxl_base_v0.9` c'è un interruttore **«Tag booru»** nel tab (Pony
 **Plug-in → app, `llm`.** Oggi `{prompt, images}`. Chiavi nuove, tutte facoltative:
 - `system`: il system prompt della sessione;
 - `model`: il nome di un modello nella cartella dell'LLM (come lo mostra `availableModels()`); l'app lo carica al posto di quello scelto nelle impostazioni, che resta com'è, e libera la memoria con la regola di inattività esistente. Se non c'è, risposta `error` («modello non trovato»): il plug-in ripiega sul generico;
-- `options`: `temperature`, `topP`, `topK`, `presencePenalty`, `maxTokens`, `thinking` (booleano; arriva al modello come `enable_thinking` del template di chat) e `timeout` (secondi, al massimo 1800; senza, restano i 300 di oggi). Senza `options` valgono i valori attuali (temperatura 0,6, 1024 token).
+- `options`: `temperature` (0–2), `topP` (0–1), `topK` (0–200), `presencePenalty` (−2–2), `maxTokens` (1–32768) e `thinking` (booleano; arriva al modello come `enable_thinking` del template di chat); i numeri fuori limite si riportano nei limiti. Senza `options` valgono i valori attuali (temperatura 0,6, 1024 token). L'attesa del plug-in (`timeout`, 300 secondi se non detto, al massimo 1800) è un parametro della libreria dei plug-in e **non viaggia** nel messaggio: l'app non ha un tempo massimo.
 
-Il servizio MLX (`MLXLanguageModelService`) passa `system` come `instructions` della sessione e le opzioni a `GenerateParameters`/`additionalContext`. `LanguageModelManager.respond` accetta il modello da usare e lo carica con lo stesso controllo della memoria. Il kit dei plug-in (`DTHubHost.askLanguageModel`) prende gli stessi parametri e il timeout.
+Il servizio MLX (`MLXLanguageModelService`) passa `system` come `instructions` della sessione e le opzioni a `GenerateParameters`/`additionalContext`. `LanguageModelManager.respond` accetta il modello da usare e lo carica con lo stesso controllo della memoria. Il kit dei plug-in (`DTHubHost.askLanguageModel` e `askLanguageModelAnswer`, che dà anche il motivo dell'errore) prende gli stessi parametri e il timeout. `context` viene rimandato anche quando l'utente torna sul tab di un plug-in, così un modello aggiunto nel frattempo compare.
 
-**App → plug-in, `context`.** Due chiavi nuove, facoltative: `startImage` (il percorso del file dell'immagine di partenza del tab Control, se c'è) e `languageModels` (nome e percorso dei modelli linguistici della cartella). Il plug-in può così cercare il PE per nome e leggerne il system prompt dalla cartella (§7). Chi non le conosce le ignora: i plug-in esistenti non cambiano.
+**App → plug-in, `context`.** Due chiavi nuove, facoltative: `startImage` (il percorso del file dell'immagine di partenza del tab Control, se c'è) e `languageModels` (nome, percorso e `supportsImages` dei modelli linguistici della cartella). Il plug-in può così cercare il PE per nome e leggerne il system prompt dalla cartella (§7). Chi non le conosce le ignora: i plug-in esistenti non cambiano.
 
 ## 7. Qwen Image 2.1 e i modelli PE
 
```

- [ ] **Step 5: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/PluginKit" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v started`
Expected: due righe: il kit `6 tests` e il design `3 tests`, passati.

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter BundlePluginLoaderTests 2>&1 | grep -E "Test run with|error:" | grep -v started`
Expected: `Test run with 6 tests … passed` (il Sample, costruito con il kit nuovo, si carica ancora).

Run: `rm -rf /tmp/p-smp && "/Users/existenz/Software developement/DT Hub/PluginKit/Scripts/build-sample.sh" /tmp/p-smp | tail -1`
Expected: `/tmp/p-smp/Sample.dthubplugin`.

- [ ] **Step 6: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A PluginKit docs && git commit -m "feat: il kit dei plug-in impara system, modello e opzioni di llm e i nuovi campi del contesto; documenti

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Rimandi nel backlog e verifiche finali

**Files:**
- `docs/superpowers/backlog.md`

- [ ] **Step 1: Il backlog**

```diff
diff --git a/docs/superpowers/backlog.md b/docs/superpowers/backlog.md
index 5628838..584eeac 100644
--- a/docs/superpowers/backlog.md
+++ b/docs/superpowers/backlog.md
@@ -171,3 +171,10 @@ I test di sessione dell'M3 (`GenerationSessionTests`) sono stati resi determinis
 - **Spec del design system:** §6 dice ancora che la risoluzione di `PluginKit` in Xcode è da provare (è provata); §5 nomina `DS.accent` mentre il test usa `DS.panelRadius`.
 - **Il cambio di tab tra due plug-in** non ha un test automatico (è una riga di interfaccia, provata dal vivo).
 
+
+## Rimandi del contratto `llm` (tappa 1 di Prompt Master)
+
+- **Le immagini date all'LLM arrivano a 512 × 512:** `ChatSession` ridimensiona le immagini a quella misura per impostazione predefinita (`processing: .init(resize:)`). Va bene per descrivere; per l'I2I dei PE di Qwen (immagine di partenza) si deve vedere con la prova dal vivo se basta, altrimenti `LanguageModelOptions` ottiene una misura massima.
+- **Nessun annullamento:** una richiesta `llm` non si può interrompere dal plug-in; un modello con il thinking acceso può metterci minuti.
+- **`refreshContext` rilegge la cartella dei modelli** a ogni cambio di tab (una scansione di due livelli): se pesasse, si memorizza l'elenco finché la cartella o le impostazioni non cambiano.
+- **Il Moodboard non è nel contesto:** solo l'immagine di partenza (scelta dell'utente); se Qwen 2.1 con il solo Moodboard dovesse contare come I2I, `context` ottiene `moodboard: [percorsi]`.
```

- [ ] **Step 2: Verifiche finali**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:|✘ Test [a-zA-Z]+\(" | grep -v started`
Expected: gli stessi conteggi del Task 2 (HubKit 110, HubCore 475, LLMBridge 10, DTBridge 66, Catalog 6, PluginHost 6), nessuna riga `✘`.

Run: `cd "/Users/existenz/Software developement/DT Hub/PluginKit" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v started`
Expected: `6 tests` e `3 tests`, passati.

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **` (è la build che l'utente avvia).

- [ ] **Step 3: Provare il Sample dal vivo (a mano, con l'app dell'utente chiusa)**

Costruire il Sample (`PluginKit/Scripts/build-sample.sh <cartella>`), metterlo in `~/Library/Application Support/DT Hub/Plug-ins/`, accenderlo dal menu Plug-in; nel tab Sample premere «Ask the language model»: con un modello linguistico scelto nelle impostazioni la risposta è **una frase breve in inglese** (viene dal `system` e da `maxTokens: 120` del Sample) e finisce nel campo Prompt della Generazione; senza modello scelto il tab mostra il motivo dell'app («No language model is chosen…»).
Expected: la risposta è una sola frase; il motivo dell'errore compare invece di «No answer».

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A docs && git commit -m "docs: rimandi del contratto llm nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

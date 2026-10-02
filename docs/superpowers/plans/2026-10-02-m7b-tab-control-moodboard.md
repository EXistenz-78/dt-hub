# M7b Tab Control — Moodboard — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il tab Control ha la scheda **Moodboard**: più immagini di riferimento (dal Finder, da Risultati con trascinamento o menu, dalla scheda Immagine), ognuna con interruttore acceso/spento, ✕, riordino; il rilascio su una miniatura la sostituisce, altrove aggiunge. Il RUN le manda a Draw Things come hint (tutte con lo stesso peso). La scheda è grigia, con la spiegazione, per le famiglie che non leggono il Moodboard.

**Architecture:**
- **HubKit** riceve `MoodboardEntry`, la lista nel `ControlInputs`, `GenerationHint`/`GenerationInputs.hints` e `moodboardCount` nel job.
- **DTBridge** traduce gli hint con `HintBuilder` (un hint `shuffle`, un tensore per immagine).
- **HubCore** riceve le operazioni dello store (aggiungi, sostituisci, togli, interruttore, riordina, svuota, annulla, persistenza, copie), gli ingressi del RUN (immagini ridotte a 1024 px in PNG), gli avvisi e la lista `FamilyTraits.withoutMoodboard`.
- **L'app** aggiunge la scheda Moodboard, il chip nella striscia, il trascinamento dell'immagine di partenza verso il Moodboard e "Aggiungi al Moodboard" in Risultati.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, ImageIO, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-01-tab-control-design.md` (sezioni 2, 3, 4, 6, 9–12; la 4.1 — le quote — è **rimandata**, vedi sotto).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m7b-moodboard` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift (`HintBuilder`, `HintProto`).
- **Niente quote, niente torta, niente cursori** (decisione dell'utente, 2 ottobre 2026): su FLUX.2 klein e Qwen Image Edit 2511 qualsiasi peso sopra lo 0 dà lo stesso risultato (misurato in Draw Things e dal vivo). Ogni immagine accesa conta uguale: peso 1,0 nel `GenerationHint`. Il peso non è nei dati.
- **Famiglie (spec Control §3):** il Moodboard è attivo per tutte le famiglie tranne la lista di dati `FamilyTraits.withoutMoodboard` = `v1`, `v2`, `sdxl_base_v0.9`, `sdxl_refiner_v0.9`, `ssd_1b`, `z_image` (Z Image misurato: stesso risultato con e senza reference). **Non si usa il `modifier` del catalogo.** Una famiglia sconosciuta o nuova lo mostra attivo.
- **Per una famiglia che lo ignora** gli hint non partono (il RUN è come senza Moodboard), le immagini restano e la striscia avvisa.
- **Regola di rilascio (spec §3):** rilasciare un'immagine su una miniatura la sostituisce (stessa posizione e stesso interruttore); in qualsiasi altro punto della scheda aggiunge. Riordino con il trascinamento di una miniatura sull'altra.
- **Immagini inviate:** le immagini accese, nell'ordine delle miniature, ridotte a 1024 px sul lato lungo e codificate in PNG, decodificate fuori dal thread principale.
- **Annulla (20 passi):** aggiunta, sostituzione, rimozione e svuotamento del Moodboard; interruttore e riordino non sono passi. Le copie si cancellano quando né lo stato né la cronologia le referenziano (vale anche per il Moodboard).
- **Avvisi nella striscia:** più di tre immagini accese (tempo di render), famiglia che ignora il Moodboard.
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; `String(format: String(localized:), …)` per i valori.
- **La logica sta in HubCore (testata); le viste si verificano con la compilazione e con la prova dal vivo (Task 7).**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già su `main`; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Se l'app dell'utente è in esecuzione non lanciare altre istanze** (stesso identificatore, stessi dati): compilare l'app con `-derivedDataPath /tmp/…` e chiedere all'utente di chiuderla prima della verifica dal vivo (Task 7).
- **Fuori da M7b:** quote e pesi, maschera e inpaint (M7c), outpaint, ControlNet, limite 8192, plug-in.

## Review Focus

- **File che non è un'immagine o è troncato come Moodboard:** rifiutato con un messaggio che nomina il file, nessuna copia rimasta (test `anUnreadableMoodboardFileIsRefusedAndLeavesNothing`, Task 4).
- **Immagine enorme nel Moodboard:** si invia ridotta a 1024 px (test `aBigMoodboardPictureIsSentReduced`, Task 4).
- **Copia sparita (all'avvio o fra la scelta e il RUN):** all'avvio la voce si scarta con un avviso; al RUN il motivo compare e il RUN non parte (test `theMoodboardComesBackAtTheNextLaunchAndLostCopiesAreDropped`, `aMoodboardCopyThatVanishedBeforeTheRunIsReported`, Task 4).
- **Famiglia che ignora il Moodboard o sconosciuta:** `z_image` e le vecchie sono grigie e non inviano nulla, le moderne e le sconosciute sono attive (test `theFamiliesThatIgnoreTheMoodboardAreGreyed`, `modernAndUnknownFamiliesUseTheMoodboard`, Task 3; `manyReferencesAndAFamilyThatIgnoresThemAreReported`, Task 4).
- **Tutte le immagini spente o Moodboard vuoto:** il RUN non manda hint; il T2I e l'I2I restano come prima (test `theRunSendsTheMoodboardPicturesThatAreOnAllWithTheSameWeight`, Task 4; `aStartImageAndAMoodboardGoTogetherAndNoHintsMeansNone`, Task 2).
- **Sostituire, togliere, svuotare, annullare e riordinare** con la pulizia delle copie (test `ControlStoreTests`, Task 4).
- **Un file illeggibile nei suggerimenti:** il RUN si ferma con un messaggio, non parte senza (test `aHintThatCannotBeReadStopsTheRunWithAMessage`, Task 2).

---

### Task 1: Tipi del Moodboard e degli ingressi (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Control/ControlInputs.swift` (`MoodboardEntry`, `moodboard`, `GenerationHint`, `GenerationInputs.hints`)
- Modify: `Packages/Sources/HubKit/Generation/GenerationJob.swift` (`moodboardCount`)
- Test: `Packages/Tests/HubKitTests/ControlContractTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct MoodboardEntry: Identifiable, Equatable, Codable, Sendable` (`id` = `image.id`, `image: ReferenceImage`, `isOn: Bool`, `init(image:isOn: = true)`);
  - `ControlInputs.moodboard: [MoodboardEntry]` (lettura permissiva: una voce rovinata non porta via le altre; i file di M7a, senza `moodboard`, si leggono con la lista vuota); l'iniziatore ha `moodboard: [MoodboardEntry] = []`;
  - `struct GenerationHint: Sendable` (`imageData: Data`, `weight: Double`, `init(imageData:weight: = 1)`);
  - `GenerationInputs.hints: [GenerationHint]` (`init(image:hints:)`; `isEmpty` = senza immagine e senza hint);
  - `GenerationJob.moodboardCount: Int` (0 senza Moodboard; lettura permissiva; iniziatore con `moodboardCount: Int = 0`).
- Consumes: `ReferenceImage`, `ControlInputs`, `GenerationInputs`, `GenerationJob` (M7a).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m7b-moodboard
```

```diff
diff --git a/Packages/Tests/HubKitTests/ControlContractTests.swift b/Packages/Tests/HubKitTests/ControlContractTests.swift
index 5e42205..cd90628 100644
--- a/Packages/Tests/HubKitTests/ControlContractTests.swift
+++ b/Packages/Tests/HubKitTests/ControlContractTests.swift
@@ -73,4 +73,37 @@ struct ControlContractTests {
       #expect(!caps(other).isEditModel)
     }
   }
+
+  @Test func moodboardEntriesSurviveEncodingAndOlderFilesHaveNone() throws {
+    let entry = MoodboardEntry(image: image(), isOn: false)
+    #expect(entry.id == entry.image.id)
+    var inputs = ControlInputs()
+    inputs.moodboard = [entry]
+    let decoded = try JSONDecoder().decode(ControlInputs.self, from: JSONEncoder().encode(inputs))
+    #expect(decoded == inputs)
+    let old = try JSONDecoder().decode(ControlInputs.self, from: Data(#"{"strength": 0.5}"#.utf8))
+    #expect(old.moodboard.isEmpty)
+    // A damaged entry does not take the others with it.
+    let mixed = try JSONDecoder().decode(
+      ControlInputs.self, from: Data(#"{"moodboard": [{"nope": 1}]}"#.utf8))
+    #expect(mixed.moodboard.isEmpty)
+  }
+
+  @Test func theHintsMakeTheInputsNonEmpty() {
+    var inputs = GenerationInputs.none
+    #expect(inputs.isEmpty)
+    inputs.hints = [GenerationHint(imageData: Data([1, 2, 3]), weight: 0.5)]
+    #expect(!inputs.isEmpty)
+  }
+
+  @Test func jobsRecordHowManyMoodboardPicturesWentAndOldOnesHaveNone() throws {
+    var job = GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)
+    #expect(job.moodboardCount == 0)
+    job.moodboardCount = 3
+    let round = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
+    #expect(round.moodboardCount == 3)
+    let old = try JSONDecoder().decode(
+      GenerationJob.self, from: Data(#"{"prompt":"p","model":"m.ckpt","parameters":{}}"#.utf8))
+    #expect(old.moodboardCount == 0)
+  }
 }
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MoodboardEntry' in scope`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Control/ControlInputs.swift b/Packages/Sources/HubKit/Control/ControlInputs.swift
index 5f0c3ff..b881766 100644
--- a/Packages/Sources/HubKit/Control/ControlInputs.swift
+++ b/Packages/Sources/HubKit/Control/ControlInputs.swift
@@ -63,18 +63,47 @@ public struct Framing: Equatable, Codable, Sendable {
   }
 }
 
+/// One image of the Moodboard (tab Control spec §3): its picture and the switch. Every picture
+/// that is on counts the same: Draw Things gives the same weight to every picture above 0 on the
+/// models that read the Moodboard (measured, 2 October 2026), so there are no shares yet (§4.1).
+public struct MoodboardEntry: Identifiable, Equatable, Codable, Sendable {
+  public var id: UUID { image.id }
+  public var image: ReferenceImage
+  public var isOn: Bool
+
+  public init(image: ReferenceImage, isOn: Bool = true) {
+    self.image = image
+    self.isOn = isOn
+  }
+}
+
+/// Decodes what it can: a damaged element becomes nil instead of failing the whole list.
+struct Lossy<Value: Decodable>: Decodable {
+  let value: Value?
+
+  init(from decoder: any Decoder) throws {
+    value = try? decoder.singleValueContainer().decode(Value.self)
+  }
+}
+
 /// Everything the Control tab holds (spec §4). Saved as `control.json`.
 public struct ControlInputs: Equatable, Codable, Sendable {
   public var image: ReferenceImage?
+  /// The Moodboard, in the order of the thumbnails.
+  public var moodboard: [MoodboardEntry]
   public var framing: Framing
   /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
   /// to-image ignores the image). The user's choice, once made, wins.
   public var strength: Double?
 
-  public init(image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil) {
+  public init(
+    image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil,
+    moodboard: [MoodboardEntry] = []
+  ) {
     self.image = image
     self.framing = framing
     self.strength = strength
+    self.moodboard = moodboard
   }
 
   /// The strength that is sent and shown, within 0…1.
@@ -88,6 +117,8 @@ public struct ControlInputs: Equatable, Codable, Sendable {
     image = try? container.decodeIfPresent(ReferenceImage.self, forKey: .image)
     framing = (try? container.decodeIfPresent(Framing.self, forKey: .framing)) ?? Framing()
     strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
+    moodboard = ((try? container.decodeIfPresent([Lossy<MoodboardEntry>].self, forKey: .moodboard)) ?? [])
+      .compactMap(\.value)
   }
 }
 
@@ -95,12 +126,26 @@ public struct ControlInputs: Equatable, Codable, Sendable {
 /// `Codable`: images do not go into the PNG metadata.
 public struct GenerationInputs: Sendable {
   public var image: CGImage?
+  /// The Moodboard's pictures that are on, in order.
+  public var hints: [GenerationHint]
 
-  public init(image: CGImage? = nil) {
+  public init(image: CGImage? = nil, hints: [GenerationHint] = []) {
     self.image = image
+    self.hints = hints
   }
 
   public static let none = GenerationInputs()
 
-  public var isEmpty: Bool { image == nil }
+  public var isEmpty: Bool { image == nil && hints.isEmpty }
+}
+
+/// One Moodboard picture of a RUN: encoded image data (PNG) and its weight (1: all count the same).
+public struct GenerationHint: Sendable {
+  public let imageData: Data
+  public let weight: Double
+
+  public init(imageData: Data, weight: Double = 1) {
+    self.imageData = imageData
+    self.weight = weight
+  }
 }
```

```diff
diff --git a/Packages/Sources/HubKit/Generation/GenerationJob.swift b/Packages/Sources/HubKit/Generation/GenerationJob.swift
index b2da416..1beba2d 100644
--- a/Packages/Sources/HubKit/Generation/GenerationJob.swift
+++ b/Packages/Sources/HubKit/Generation/GenerationJob.swift
@@ -10,16 +10,19 @@ public struct GenerationJob: Equatable, Codable, Sendable {
   public let parameters: GenerationParameters
   /// The strength of the start image; nil when the RUN has no start image.
   public var imageStrength: Double?
+  /// How many Moodboard pictures went with this RUN (0 without a Moodboard).
+  public var moodboardCount: Int
 
   public init(
     prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
-    imageStrength: Double? = nil
+    imageStrength: Double? = nil, moodboardCount: Int = 0
   ) {
     self.prompt = prompt
     self.negativePrompt = negativePrompt
     self.model = model
     self.parameters = parameters
     self.imageStrength = imageStrength
+    self.moodboardCount = moodboardCount
   }
 
   /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
@@ -38,6 +41,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     model = try container.decode(String.self, forKey: .model)
     parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
     imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
+    moodboardCount = (try? container.decodeIfPresent(Int.self, forKey: .moodboardCount)) ?? 0
   }
 }
 
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubKit `56 tests … passed`, HubCore 216, DTBridge 52, Catalog 6, LLMBridge 6 (totale **336**).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: tipi del Moodboard e degli ingressi (immagini accese/spente, hint, conteggio nel job)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Il Moodboard nella richiesta a Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift`, `DrawThingsBackend.swift`
- Test: `Packages/Tests/DTBridgeTests/JobMapperTests.swift`

**Interfaces:**
- Consumes: `GenerationInputs.hints`, `GenerationHint` (Task 1); `HintBuilder` della libreria.
- Produces: `JobMapper.request(for: GenerationJob) -> GenerationRequest` (T2I, senza ingressi, non lancia) e `JobMapper.request(for: GenerationJob, inputs: GenerationInputs) throws -> GenerationRequest`: immagine e forza come in M7a, e **un solo hint `shuffle`** con un tensore per ogni `GenerationHint` (peso = `hint.weight`); un'immagine che la libreria non legge lancia `BackendError.generationFailed(messaggio)`. `DrawThingsBackend.generate(_:inputs:)` usa la versione che lancia (dentro il suo `do`/`catch`).

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/DTBridgeTests/JobMapperTests.swift b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
index 0fb7f2c..dfea68a 100644
--- a/Packages/Tests/DTBridgeTests/JobMapperTests.swift
+++ b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
@@ -1,6 +1,8 @@
 import DrawThingsClient
 import HubKit
+import ImageIO
 import Testing
+import UniformTypeIdentifiers
 
 @testable import DTBridge
 
@@ -33,7 +35,7 @@ struct JobMapperTests {
     let image = try #require(TestImages.make(width: 64, height: 48))
     var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
     job.imageStrength = 0.6
-    let request = JobMapper.request(for: job, inputs: GenerationInputs(image: image))
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image))
     #expect(request.image === image)
     #expect(abs(request.configuration.strength - 0.6) < 0.0001)
     // The Control tab's strength wins over a "strength" key of the JSON editor.
@@ -41,19 +43,59 @@ struct JobMapperTests {
     withExtra = GenerationJob(
       prompt: "a fox", model: "m.ckpt",
       parameters: GenerationParameters(extra: ["strength": .double(0.2)]), imageStrength: 0.6)
-    let wins = JobMapper.request(for: withExtra, inputs: GenerationInputs(image: image))
+    let wins = try JobMapper.request(for: withExtra, inputs: GenerationInputs(image: image))
     #expect(abs(wins.configuration.strength - 0.6) < 0.0001)
   }
 
-  @Test func withoutAnImageTheRequestIsTextToImage() {
+  @Test func withoutAnImageTheRequestIsTextToImage() throws {
     var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default)
     job.imageStrength = 0.6
-    let request = JobMapper.request(for: job, inputs: .none)
+    let request = try JobMapper.request(for: job, inputs: .none)
     #expect(request.image == nil)
     #expect(request.configuration.strength == 1.0)
     #expect(JobMapper.request(for: job).image == nil)
   }
 
+  func pngBytes(width: Int = 32, height: Int = 24) throws -> Data {
+    let image = try #require(TestImages.make(width: width, height: height))
+    let data = NSMutableData()
+    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
+    CGImageDestinationAddImage(destination, image, nil)
+    CGImageDestinationFinalize(destination)
+    return data as Data
+  }
+
+  @Test func sendsTheMoodboardAsOneShuffleHintWithTheSharesAsWeights() throws {
+    let bytes = try pngBytes()
+    let inputs = GenerationInputs(hints: [
+      GenerationHint(imageData: bytes, weight: 0.7), GenerationHint(imageData: bytes, weight: 0.3),
+    ])
+    let request = try JobMapper.request(
+      for: GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default), inputs: inputs)
+    #expect(request.image == nil)
+    #expect(request.hints.count == 1)
+    #expect(request.hints[0].hintType == "shuffle")
+    #expect(request.hints[0].tensors.count == 2)
+    #expect(abs(request.hints[0].tensors[0].weight - 0.7) < 0.0001)
+    #expect(abs(request.hints[0].tensors[1].weight - 0.3) < 0.0001)
+  }
+
+  @Test func aStartImageAndAMoodboardGoTogetherAndNoHintsMeansNone() throws {
+    let image = try #require(TestImages.make(width: 64, height: 64))
+    let job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
+    let both = try JobMapper.request(
+      for: job, inputs: GenerationInputs(image: image, hints: [GenerationHint(imageData: try pngBytes(), weight: 1)]))
+    #expect(both.image === image && both.hints.count == 1)
+    #expect(try JobMapper.request(for: job, inputs: GenerationInputs(image: image)).hints.isEmpty)
+  }
+
+  @Test func aHintThatCannotBeReadStopsTheRunWithAMessage() {
+    let inputs = GenerationInputs(hints: [GenerationHint(imageData: Data([1, 2, 3]), weight: 1)])
+    #expect(throws: BackendError.self) {
+      try JobMapper.request(for: GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default), inputs: inputs)
+    }
+  }
+
   @Test func sendsTheNegativePromptAndTheLoRAs() {
     let parameters = GenerationParameters(loras: [
       LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "error:|Fatal error|Expectation failed" | grep -v started | head -3`
Expected: i test dei suggerimenti falliscono (aspettativa non soddisfatta o interruzione `Index out of range`: oggi `request` non produce hint).

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/DTBridge/JobMapper.swift b/Packages/Sources/DTBridge/JobMapper.swift
index f375eca..ab6489c 100644
--- a/Packages/Sources/DTBridge/JobMapper.swift
+++ b/Packages/Sources/DTBridge/JobMapper.swift
@@ -3,14 +3,32 @@ import HubKit
 
 /// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
 enum JobMapper {
-  static func request(for job: GenerationJob, inputs: GenerationInputs = .none) -> GenerationRequest {
+  /// A text-to-image request (no Control tab images).
+  static func request(for job: GenerationJob) -> GenerationRequest {
+    GenerationRequest(
+      prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
+      configuration: configuration(model: job.model, parameters: job.parameters))
+  }
+
+  /// The request with the Control tab's images: the start image (and its strength), and the
+  /// Moodboard as one "shuffle" hint whose weights are the pictures' shares. A picture the library
+  /// cannot read stops the RUN with a message.
+  static func request(for job: GenerationJob, inputs: GenerationInputs) throws -> GenerationRequest {
     var configuration = configuration(model: job.model, parameters: job.parameters)
     // The start image and its strength come from the Control tab, after the JSON editor's
     // extra settings: they win. Without an image the RUN stays text-to-image.
     if inputs.image != nil, let strength = job.imageStrength { configuration.strength = Float(strength) }
+    var hints = HintBuilder()
+    for hint in inputs.hints { hints.addMoodboardImage(hint.imageData, weight: Float(hint.weight)) }
+    let built: [HintProto]
+    do {
+      built = try hints.build()
+    } catch {
+      throw BackendError.generationFailed(error.localizedDescription)
+    }
     return GenerationRequest(
       prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
-      configuration: configuration, image: inputs.image)
+      configuration: configuration, image: inputs.image, hints: built)
   }
 
   /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
```

```diff
diff --git a/Packages/Sources/DTBridge/DrawThingsBackend.swift b/Packages/Sources/DTBridge/DrawThingsBackend.swift
index 55d4157..7ada397 100644
--- a/Packages/Sources/DTBridge/DrawThingsBackend.swift
+++ b/Packages/Sources/DTBridge/DrawThingsBackend.swift
@@ -59,7 +59,7 @@ public actor DrawThingsBackend: GenerationBackend {
       let task = Task {
         do {
           let service = await self.currentService()
-          for try await event in service.stream(JobMapper.request(for: job, inputs: inputs)) {
+          for try await event in service.stream(try JobMapper.request(for: job, inputs: inputs)) {
             if let update = try JobMapper.update(for: event) { continuation.yield(update) }
           }
           continuation.finish()
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: DTBridge `55 tests … passed`; totale 56 + 216 + 55 + 6 + 6 = **339**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: il Moodboard parte per Draw Things come hint shuffle (un tensore per immagine)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Famiglie che ignorano il Moodboard e conteggio nei job (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Family/FamilyTraits.swift`, `Packages/Sources/HubCore/Generation/JobComposer.swift`
- Test: `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift`

**Interfaces:**
- Consumes: `GenerationJob.moodboardCount` (Task 1).
- Produces:
  - `FamilyTraits.usesMoodboard: Bool` (iniziatore `usesMoodboard: Bool = true`); falso per `FamilyTraits.withoutMoodboard` (insieme interno: `v1`, `v2`, `sdxl_base_v0.9`, `sdxl_refiner_v0.9`, `ssd_1b`, `z_image`); `FamilyTraits.of(nil)` e `.all` lo usano;
  - `JobComposer.batches(…, imageStrength: Double? = nil, moodboardCount: Int = 0, randomSeed:)`: ogni job lo porta.

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
index d86944b..962b796 100644
--- a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
+++ b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
@@ -4,6 +4,21 @@ import Testing
 @testable import HubCore
 
 struct FamilyTraitsTests {
+  @Test(arguments: ["v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "z_image"])
+  func theFamiliesThatIgnoreTheMoodboardAreGreyed(family: String) {
+    #expect(!FamilyTraits.of(family).usesMoodboard)
+  }
+
+  @Test(arguments: ["flux2_9b", "flux2_4b", "flux1", "qwen_image", "qwen_image_2.1", "krea_2", "ideogram_4", "sd3", "a_future_family"])
+  func modernAndUnknownFamiliesUseTheMoodboard(family: String) {
+    #expect(FamilyTraits.of(family).usesMoodboard)
+  }
+
+  @Test func anUnknownModelUsesTheMoodboard() {
+    #expect(FamilyTraits.of(nil).usesMoodboard)
+    #expect(FamilyTraits.all.usesMoodboard)
+  }
+
   @Test(arguments: ["flux2_9b", "flux1", "qwen_image", "qwen_image_2.1", "z_image", "krea_2", "ideogram_4", "ernie_image", "sd3"])
   func flowMatchingFamiliesUseShift(family: String) {
     #expect(FamilyTraits.of(family).usesShift)
@@ -68,6 +83,14 @@ struct JobComposerTests {
       parameters: parameters, catalog: catalog) { 7 }
   }
 
+  @Test func everyBatchRecordsHowManyMoodboardPicturesWent() {
+    let jobs = JobComposer.batches(
+      prompt: "fox", negativePrompt: "", model: "m.ckpt", family: nil, parameters: GenerationParameters(batchCount: 2),
+      catalog: catalog, moodboardCount: 3) { 7 }
+    #expect(jobs.count == 2 && jobs.allSatisfy { $0.moodboardCount == 3 })
+    #expect(compose(family: nil, .default).allSatisfy { $0.moodboardCount == 0 })
+  }
+
   @Test func everyBatchRecordsTheStrengthOfTheStartImage() {
     let parameters = GenerationParameters(batchCount: 2)
     let withImage = JobComposer.batches(
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | grep -v started | head -2`
Expected: `has no member 'usesMoodboard'` e `extra argument 'moodboardCount'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Family/FamilyTraits.swift b/Packages/Sources/HubCore/Family/FamilyTraits.swift
index 64370fb..ddab5b6 100644
--- a/Packages/Sources/HubCore/Family/FamilyTraits.swift
+++ b/Packages/Sources/HubCore/Family/FamilyTraits.swift
@@ -9,10 +9,14 @@ public struct FamilyTraits: Equatable, Sendable {
   public let usesShift: Bool
   /// The model reads a negative prompt (it acts only with text guidance above 1).
   public let usesNegativePrompt: Bool
+  /// The Moodboard works without an adapter: the modern families read their references themselves.
+  /// False for the old families that would need an IP-Adapter or a ControlNet (tab Control spec §3).
+  public let usesMoodboard: Bool
 
-  public init(usesShift: Bool, usesNegativePrompt: Bool) {
+  public init(usesShift: Bool, usesNegativePrompt: Bool, usesMoodboard: Bool = true) {
     self.usesShift = usesShift
     self.usesNegativePrompt = usesNegativePrompt
+    self.usesMoodboard = usesMoodboard
   }
 
   public static let all = FamilyTraits(usesShift: true, usesNegativePrompt: true)
@@ -24,6 +28,13 @@ public struct FamilyTraits: Equatable, Sendable {
     "kandinsky2.1", "wurstchen_v3.0_stage_c", "wurstchen_v3.0_stage_b", "svd_i2v",
   ]
 
+  /// Families that do not read the Moodboard. SD 1.x/2.x, SDXL and SSD-1B would need a control
+  /// model they do not have here; Z Image was measured: its result is the same with and without
+  /// a Moodboard picture (1 October 2026). The models that read it (FLUX.2, Qwen Image 2.1…) are
+  /// not listed, and neither is a new or unknown family: hiding what a model uses is worse than
+  /// showing what it ignores. Update this list as families are tried.
+  static let withoutMoodboard: Set<String> = ["v1", "v2", "sdxl_base_v0.9", "sdxl_refiner_v0.9", "ssd_1b", "z_image"]
+
   /// Models that take no text to avoid: upscalers (SeedVR2) and image-to-video (SVD).
   static let withoutNegativePrompt: Set<String> = ["seedvr2_3b", "seedvr2_7b", "svd_i2v"]
 
@@ -31,6 +42,7 @@ public struct FamilyTraits: Equatable, Sendable {
     guard let family else { return .all }
     return FamilyTraits(
       usesShift: !withoutShift.contains(family),
-      usesNegativePrompt: !withoutNegativePrompt.contains(family))
+      usesNegativePrompt: !withoutNegativePrompt.contains(family),
+      usesMoodboard: !withoutMoodboard.contains(family))
   }
 }
```

```diff
diff --git a/Packages/Sources/HubCore/Generation/JobComposer.swift b/Packages/Sources/HubCore/Generation/JobComposer.swift
index 3763eb8..ee1fd51 100644
--- a/Packages/Sources/HubCore/Generation/JobComposer.swift
+++ b/Packages/Sources/HubCore/Generation/JobComposer.swift
@@ -9,7 +9,7 @@ public enum JobComposer {
   public static func batches(
     prompt: String, negativePrompt: String, model: String, family: String?,
     parameters: GenerationParameters, catalog: ModelCatalog, imageStrength: Double? = nil,
-    randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
+    moodboardCount: Int = 0, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
   ) -> [GenerationJob] {
     let traits = FamilyTraits.of(family)
     var sent = parameters
@@ -19,7 +19,8 @@ public enum JobComposer {
     let negative = traits.usesNegativePrompt ? negativePrompt : ""
     return sent.batchesForRun(randomSeed: draw).map {
       GenerationJob(
-        prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength)
+        prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength,
+        moodboardCount: moodboardCount)
     }
   }
 
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `220 tests … passed`; totale 56 + 220 + 55 + 6 + 6 = **343**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: famiglie che ignorano il Moodboard (lista di dati) e conteggio nei job

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Il Moodboard nello store (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift`, `ReferenceStorage.swift`
- Test: `Packages/Tests/HubCoreTests/ControlStoreTests.swift`

**Interfaces:**
- Consumes: `MoodboardEntry`, `GenerationHint`, `GenerationInputs.hints` (Task 1).
- Produces (HubCore, `public`), tutte su `ControlStore`:
  - `addMoodboardImage(data:name:source:) throws(ControlError)`, `addMoodboardImage(_ image: CGImage, name:source:) throws(ControlError)`, `addMoodboardImage(fileURL:source:) async throws(ControlError)` (aggiunge in fondo, accesa; passo di annulla);
  - `replaceMoodboardImage(id:data:name:source:) throws(ControlError)` e `replaceMoodboardImage(id:fileURL:source:) async throws(ControlError)` (stessa posizione e interruttore, nuovo `id` e nuova copia; `notice = .replaced(name:)`; passo di annulla);
  - `removeMoodboardImage(id:)` (`notice = .removed(name:)`), `clearMoodboard()` (`notice = .cleared`, l'immagine di partenza resta), `setMoodboardOn(id:isOn:)`, `moveMoodboardImage(id:before:)` (`before: nil` = in fondo) — interruttore e riordino non sono passi di annulla;
  - `previewRequest(ofMoodboard id: UUID, maxPixel: Int) -> PreviewRequest?`, `copyURL(of: ReferenceImage) -> URL?` (anche `ReferenceStorage.url(for:)`);
  - `warnings(canvasWidth:canvasHeight:usesMoodboard: Bool = true)`: aggiunge `.manyReferences(count:)` (più di tre accese) e `.moodboardIgnored` (accese e famiglia che lo ignora; non si somma a `manyReferences`);
  - `pendingInputs(canvasWidth:canvasHeight:includeMoodboard: Bool = true)`: `render()` produce gli hint (immagini accese, ridotte a 1024 px, PNG, peso 1,0) oltre all'immagine inquadrata; una copia illeggibile lancia `.unreadable(nome)`;
  - `ControlWarning` ha i casi `manyReferences(count: Int)` e `moodboardIgnored`; all'avvio le voci del Moodboard senza copia si scartano con `.missingAtLaunch(name:)`; la pulizia delle copie considera anche il Moodboard.

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/HubCoreTests/ControlStoreTests.swift b/Packages/Tests/HubCoreTests/ControlStoreTests.swift
index 7376bc4..32405fa 100644
--- a/Packages/Tests/HubCoreTests/ControlStoreTests.swift
+++ b/Packages/Tests/HubCoreTests/ControlStoreTests.swift
@@ -275,4 +275,197 @@ struct ControlStoreTests {
     try FileManager.default.removeItem(at: root.appendingPathComponent("Control/\(try #require(store.inputs.image).fileName)"))
     #expect(throws: ControlError.unreadable("a.png")) { try store.pendingInputs(canvasWidth: 64, canvasHeight: 64).render() }
   }
+
+  // MARK: Moodboard
+
+  func addPictures(_ store: ControlStore, _ count: Int) throws {
+    for number in 1...count {
+      try store.addMoodboardImage(
+        data: pictureData(width: 40 + number, height: 30), name: "m\(number).png", source: .pasteboard)
+    }
+  }
+
+  @Test func moodboardPicturesAreCopiedInOrderAndStartOn() throws {
+    let root = folder()
+    let store = store(in: root)
+    try addPictures(store, 3)
+    #expect(store.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png", "m3.png"])
+    #expect(store.inputs.moodboard.allSatisfy { $0.isOn })
+    #expect(copies(in: root).count == 3)
+  }
+
+  @Test func theSwitchTurnsAPictureOffWithoutLosingIt() throws {
+    let store = store(in: folder())
+    try addPictures(store, 3)
+    let second = store.inputs.moodboard[1].id
+    store.setMoodboardOn(id: second, isOn: false)
+    #expect(store.inputs.moodboard.map(\.isOn) == [true, false, true])
+    store.setMoodboardOn(id: second, isOn: true)
+    #expect(store.inputs.moodboard.allSatisfy { $0.isOn })
+  }
+
+  @Test func removingAMoodboardPictureCanBeUndone() throws {
+    let store = store(in: folder())
+    try addPictures(store, 3)
+    let removed = store.inputs.moodboard[0]
+    store.removeMoodboardImage(id: removed.id)
+    #expect(store.inputs.moodboard.count == 2)
+    #expect(store.notice == .removed(name: "m1.png"))
+    store.undo()
+    #expect(store.inputs.moodboard.first == removed)
+    #expect(store.inputs.moodboard.count == 3)
+  }
+
+  @Test func replacingAPictureKeepsItsPlaceAndSwitch() throws {
+    let root = folder()
+    let store = store(in: root)
+    try addPictures(store, 2)
+    let target = store.inputs.moodboard[0].id
+    store.setMoodboardOn(id: target, isOn: false)
+    let before = store.inputs.moodboard[0]
+    try store.replaceMoodboardImage(id: target, data: pictureData(width: 20, height: 20), name: "new.png", source: .result)
+    let after = store.inputs.moodboard[0]
+    #expect(after.image.name == "new.png" && after.image.source == .result)
+    #expect(after.isOn == false && after.isOn == before.isOn)
+    #expect(after.id != before.id)
+    #expect(store.inputs.moodboard.count == 2)
+    #expect(store.notice == .replaced(name: "m1.png"))
+    store.undo()
+    #expect(store.inputs.moodboard[0] == before)
+  }
+
+  @Test func picturesCanBeReordered() throws {
+    let store = store(in: folder())
+    try addPictures(store, 3)
+    let ids = store.inputs.moodboard.map(\.id)
+    store.moveMoodboardImage(id: ids[2], before: ids[0])
+    #expect(store.inputs.moodboard.map(\.id) == [ids[2], ids[0], ids[1]])
+    store.moveMoodboardImage(id: ids[2], before: nil)
+    #expect(store.inputs.moodboard.map(\.id) == [ids[0], ids[1], ids[2]])
+    store.moveMoodboardImage(id: ids[0], before: ids[0])
+    #expect(store.inputs.moodboard.map(\.id) == [ids[0], ids[1], ids[2]])
+  }
+
+  @Test func theMoodboardComesBackAtTheNextLaunchAndLostCopiesAreDropped() throws {
+    let root = folder()
+    let first = store(in: root)
+    try addPictures(first, 3)
+    first.setMoodboardOn(id: first.inputs.moodboard[1].id, isOn: false)
+    let second = store(in: root)
+    #expect(second.inputs.moodboard == first.inputs.moodboard)
+    #expect(second.notice == nil)
+    try FileManager.default.removeItem(
+      at: root.appendingPathComponent("Control/\(first.inputs.moodboard[2].image.fileName)"))
+    let third = store(in: root)
+    #expect(third.inputs.moodboard.map(\.image.name) == ["m1.png", "m2.png"])
+    #expect(third.notice == .missingAtLaunch(name: "m3.png"))
+  }
+
+  @Test func theMoodboardAloneCanBeClearedAndUndone() throws {
+    let store = store(in: folder())
+    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
+    try addPictures(store, 2)
+    store.clearMoodboard()
+    #expect(store.inputs.moodboard.isEmpty && store.inputs.image?.name == "a.png")
+    #expect(store.notice == .cleared)
+    store.clearMoodboard()
+    #expect(store.canUndo)
+    store.undo()
+    #expect(store.inputs.moodboard.count == 2)
+  }
+
+  @Test func clearingTakesTheMoodboardOutToo() throws {
+    let root = folder()
+    let store = store(in: root)
+    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
+    try addPictures(store, 2)
+    store.clear()
+    #expect(store.inputs == ControlInputs())
+    store.undo()
+    #expect(store.inputs.moodboard.count == 2 && store.inputs.image != nil)
+    #expect(copies(in: root).count == 3)
+  }
+
+  @Test func anUnreadableMoodboardFileIsRefusedAndLeavesNothing() throws {
+    let root = folder()
+    let store = store(in: root)
+    #expect(throws: ControlError.unreadable("x.txt")) {
+      try store.addMoodboardImage(data: Data("no".utf8), name: "x.txt", source: .pasteboard)
+    }
+    #expect(store.inputs.moodboard.isEmpty && copies(in: root).isEmpty)
+  }
+
+  @Test func aMoodboardFileFromTheFinderIsTakenAsAFile() async throws {
+    let root = folder()
+    let store = store(in: root)
+    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
+    let file = root.appendingPathComponent("style.png")
+    try pictureData(width: 50, height: 40).write(to: file)
+    try await store.addMoodboardImage(fileURL: file)
+    #expect(store.inputs.moodboard.first?.image.source == .file(path: file.path))
+    try await store.addMoodboardImage(fileURL: file, source: .result)
+    #expect(store.inputs.moodboard.last?.image.source == .result)
+    await #expect(throws: ControlError.unreadable("missing.png")) {
+      try await store.addMoodboardImage(fileURL: root.appendingPathComponent("missing.png"))
+    }
+  }
+
+  @Test func theCopyOfAPictureCanBeDraggedOut() throws {
+    let root = folder()
+    let store = store(in: root)
+    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
+    let image = try #require(store.inputs.image)
+    let url = try #require(store.copyURL(of: image))
+    #expect(FileManager.default.fileExists(atPath: url.path))
+    #expect(url.lastPathComponent == image.fileName)
+  }
+
+  @Test func theRunSendsTheMoodboardPicturesThatAreOnAllWithTheSameWeight() throws {
+    let store = store(in: folder())
+    try addPictures(store, 3)
+    store.setMoodboardOn(id: store.inputs.moodboard[1].id, isOn: false)
+    let inputs = try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render()
+    #expect(inputs.image == nil)
+    #expect(inputs.hints.count == 2 && inputs.hints.allSatisfy { $0.weight == 1 })
+    for hint in inputs.hints {
+      let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
+      #expect(CGImageSourceGetCount(source) == 1)
+    }
+    #expect(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256, includeMoodboard: false).render().isEmpty)
+  }
+
+  @Test func aBigMoodboardPictureIsSentReduced() throws {
+    let store = store(in: folder())
+    try store.addMoodboardImage(data: pictureData(width: 3000, height: 2000), name: "big.png", source: .pasteboard)
+    let hint = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().hints.first)
+    let source = try #require(CGImageSourceCreateWithData(hint.imageData as CFData, nil))
+    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
+    #expect(max(image.width, image.height) == 1024)
+    #expect(image.width > image.height)
+  }
+
+  @Test func aMoodboardCopyThatVanishedBeforeTheRunIsReported() throws {
+    let root = folder()
+    let store = store(in: root)
+    try addPictures(store, 1)
+    try FileManager.default.removeItem(
+      at: root.appendingPathComponent("Control/\(store.inputs.moodboard[0].image.fileName)"))
+    #expect(throws: ControlError.unreadable("m1.png")) {
+      try store.pendingInputs(canvasWidth: 64, canvasHeight: 64).render()
+    }
+  }
+
+  @Test func manyReferencesAndAFamilyThatIgnoresThemAreReported() throws {
+    let store = store(in: folder())
+    try addPictures(store, 3)
+    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512).isEmpty)
+    try addPictures(store, 1)
+    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512) == [.manyReferences(count: 4)])
+    store.setMoodboardOn(id: store.inputs.moodboard[0].id, isOn: false)
+    #expect(store.warnings(canvasWidth: 512, canvasHeight: 512).isEmpty)
+    #expect(
+      store.warnings(canvasWidth: 512, canvasHeight: 512, usesMoodboard: false) == [.moodboardIgnored])
+    let empty = ControlStore(storage: FileReferenceStorage(folder: folder()), fileURL: folder().appendingPathComponent("c.json"))
+    #expect(empty.warnings(canvasWidth: 512, canvasHeight: 512, usesMoodboard: false).isEmpty)
+  }
 }
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | grep -v started | head -2`
Expected: `has no member 'addMoodboardImage'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/ReferenceStorage.swift b/Packages/Sources/HubCore/Control/ReferenceStorage.swift
index 5259152..325ae99 100644
--- a/Packages/Sources/HubCore/Control/ReferenceStorage.swift
+++ b/Packages/Sources/HubCore/Control/ReferenceStorage.swift
@@ -26,6 +26,8 @@ public protocol ReferenceStorage: Sendable {
   /// The picture decoded with its longest side at most `maxPixel`, orientation applied.
   func image(named fileName: String, maxPixel: Int) -> CGImage?
   func exists(_ fileName: String) -> Bool
+  /// Where a copy lives, to drag it out of the app.
+  func url(for fileName: String) -> URL
   func remove(_ fileName: String)
   func allFileNames() -> [String]
 }
@@ -85,6 +87,10 @@ public struct FileReferenceStorage: ReferenceStorage {
     return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
   }
 
+  public func url(for fileName: String) -> URL {
+    folder.appendingPathComponent(fileName)
+  }
+
   public func exists(_ fileName: String) -> Bool {
     FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
   }
```

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index 9b9d459..70aa8ec 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -19,6 +19,10 @@ public enum ControlNotice: Equatable, Sendable {
 public enum ControlWarning: Hashable, Sendable {
   /// The framing cuts off this much of the image (more than a third).
   case strongCrop(percent: Int)
+  /// More than three Moodboard pictures are on: each one adds render time more than linearly.
+  case manyReferences(count: Int)
+  /// The chosen model does not use the Moodboard, and pictures are on.
+  case moodboardIgnored
 }
 
 /// The Control tab's inputs, kept and saved (tab Control spec §4): the start image with its
@@ -51,6 +55,10 @@ public final class ControlStore {
       loaded.framing = Framing()
       notice = .missingAtLaunch(name: image.name)
     }
+    for entry in loaded.moodboard where !storage.exists(entry.image.fileName) {
+      loaded.moodboard.removeAll { $0.id == entry.id }
+      notice = .missingAtLaunch(name: entry.image.name)
+    }
     inputs = loaded
     save()
     collectGarbage()
@@ -78,10 +86,7 @@ public final class ControlStore {
   /// Takes a picture from its bytes: copies it, describes it, and makes it the start image
   /// (the one there was, if any, can be brought back with `undo`). The framing starts centered.
   public func setImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
-    let stored = try storage.save(data, name: name)
-    let image = ReferenceImage(
-      id: UUID(), name: name, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, source: source,
-      fileName: stored.fileName)
+    let image = try reference(from: data, name: name, source: source)
     var next = inputs
     next.image = image
     next.framing = Framing()
@@ -92,12 +97,8 @@ public final class ControlStore {
 
   /// A picture that only exists in memory (a result that could not be saved): stored as PNG.
   public func setImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
-    let data = NSMutableData()
-    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
-    else { throw .cannotSave(name) }
-    CGImageDestinationAddImage(destination, image, nil)
-    guard CGImageDestinationFinalize(destination) else { throw .cannotSave(name) }
-    try setImage(data: data as Data, name: name, source: source)
+    guard let data = Self.pngData(of: image) else { throw .cannotSave(name) }
+    try setImage(data: data, name: name, source: source)
   }
 
   /// Takes a file (from the Finder, or an image the Results window saved); reads it away from
@@ -125,6 +126,88 @@ public final class ControlStore {
     notice = .cleared
   }
 
+  // MARK: Moodboard
+
+  /// Adds a picture to the Moodboard (on, at the end).
+  public func addMoodboardImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
+    let image = try reference(from: data, name: name, source: source)
+    var next = inputs
+    next.moodboard.append(MoodboardEntry(image: image))
+    commit(next)
+  }
+
+  public func addMoodboardImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
+    guard let data = Self.pngData(of: image) else { throw .cannotSave(name) }
+    try addMoodboardImage(data: data, name: name, source: source)
+  }
+
+  public func addMoodboardImage(fileURL url: URL, source: ReferenceImage.Source? = nil) async throws(ControlError) {
+    let name = url.lastPathComponent
+    let data = await Task.detached { try? Data(contentsOf: url) }.value
+    guard let data else { throw .unreadable(name) }
+    try addMoodboardImage(data: data, name: name, source: source ?? .file(path: url.path))
+  }
+
+  /// A picture dropped on one that is there takes its place: the same position and switch.
+  public func replaceMoodboardImage(
+    id: UUID, data: Data, name: String, source: ReferenceImage.Source
+  ) throws(ControlError) {
+    guard let index = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
+    let old = inputs.moodboard[index]
+    let image = try reference(from: data, name: name, source: source)
+    var next = inputs
+    next.moodboard[index] = MoodboardEntry(image: image, isOn: old.isOn)
+    commit(next)
+    notice = .replaced(name: old.image.name)
+  }
+
+  public func replaceMoodboardImage(
+    id: UUID, fileURL url: URL, source: ReferenceImage.Source? = nil
+  ) async throws(ControlError) {
+    let name = url.lastPathComponent
+    let data = await Task.detached { try? Data(contentsOf: url) }.value
+    guard let data else { throw .unreadable(name) }
+    try replaceMoodboardImage(id: id, data: data, name: name, source: source ?? .file(path: url.path))
+  }
+
+  public func removeMoodboardImage(id: UUID) {
+    guard let entry = inputs.moodboard.first(where: { $0.id == id }) else { return }
+    var next = inputs
+    next.moodboard.removeAll { $0.id == id }
+    commit(next)
+    notice = .removed(name: entry.image.name)
+  }
+
+  /// Takes the whole Moodboard out (the start image stays).
+  public func clearMoodboard() {
+    guard !inputs.moodboard.isEmpty else { return }
+    var next = inputs
+    next.moodboard = []
+    commit(next)
+    notice = .cleared
+  }
+
+  /// A picture that is off is not sent but is not lost (not part of the history).
+  public func setMoodboardOn(id: UUID, isOn: Bool) {
+    guard let index = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
+    inputs.moodboard[index].isOn = isOn
+    save()
+  }
+
+  /// Moves a picture before another one, or to the end when `before` is nil.
+  public func moveMoodboardImage(id: UUID, before target: UUID?) {
+    guard id != target, let from = inputs.moodboard.firstIndex(where: { $0.id == id }) else { return }
+    var entries = inputs.moodboard
+    let moved = entries.remove(at: from)
+    if let target, let to = entries.firstIndex(where: { $0.id == target }) {
+      entries.insert(moved, at: to)
+    } else {
+      entries.append(moved)
+    }
+    inputs.moodboard = entries
+    save()
+  }
+
   // MARK: Strength and framing (not part of the history)
 
   /// nil goes back to the automatic strength.
@@ -176,24 +259,66 @@ public final class ControlStore {
     return PreviewRequest(storage: storage, fileName: image.fileName, maxPixel: maxPixel)
   }
 
+  /// The preview of a Moodboard picture, to be decoded away from the main actor.
+  public func previewRequest(ofMoodboard id: UUID, maxPixel: Int) -> PreviewRequest? {
+    guard let entry = inputs.moodboard.first(where: { $0.id == id }) else { return nil }
+    return PreviewRequest(storage: storage, fileName: entry.image.fileName, maxPixel: maxPixel)
+  }
+
+  /// Where the copy of a picture lives, to drag it out (to another card, or another app).
+  public func copyURL(of image: ReferenceImage) -> URL? {
+    storage.exists(image.fileName) ? storage.url(for: image.fileName) : nil
+  }
+
   // MARK: Warnings and RUN
 
-  public func warnings(canvasWidth: Int, canvasHeight: Int) -> [ControlWarning] {
-    guard let image = inputs.image else { return [] }
-    let loss = FramingMath.loss(
-      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
-    return loss.fraction > 1.0 / 3.0 ? [.strongCrop(percent: Int((loss.fraction * 100).rounded()))] : []
+  /// What to look at before RUN. `usesMoodboard` is false for a model that ignores the Moodboard.
+  public func warnings(canvasWidth: Int, canvasHeight: Int, usesMoodboard: Bool = true) -> [ControlWarning] {
+    var warnings: [ControlWarning] = []
+    if let image = inputs.image {
+      let loss = FramingMath.loss(
+        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+        canvasHeight: canvasHeight)
+      if loss.fraction > 1.0 / 3.0 { warnings.append(.strongCrop(percent: Int((loss.fraction * 100).rounded()))) }
+    }
+    let on = inputs.moodboard.filter(\.isOn).count
+    if on > 0, !usesMoodboard {
+      warnings.append(.moodboardIgnored)
+    } else if on > 3 {
+      warnings.append(.manyReferences(count: on))
+    }
+    return warnings
   }
 
-  /// What a RUN needs to prepare its inputs, to be rendered away from the main actor.
-  public func pendingInputs(canvasWidth: Int, canvasHeight: Int) -> PendingInputs {
-    PendingInputs(
+  /// What a RUN needs to prepare its inputs, to be rendered away from the main actor. The Moodboard
+  /// goes only when `includeMoodboard` (the model uses it).
+  public func pendingInputs(canvasWidth: Int, canvasHeight: Int, includeMoodboard: Bool = true) -> PendingInputs {
+    let sent = inputs.moodboard.filter(\.isOn).map { (image: $0.image, weight: 1.0) }
+    return PendingInputs(
       storage: storage, image: inputs.image, framing: inputs.framing, canvasWidth: canvasWidth,
-      canvasHeight: canvasHeight)
+      canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
   }
 
   // MARK: Private
 
+  /// Copies the bytes into the Control folder and describes the picture.
+  private func reference(
+    from data: Data, name: String, source: ReferenceImage.Source
+  ) throws(ControlError) -> ReferenceImage {
+    let stored = try storage.save(data, name: name)
+    return ReferenceImage(
+      id: UUID(), name: name, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, source: source,
+      fileName: stored.fileName)
+  }
+
+  nonisolated static func pngData(of image: CGImage) -> Data? {
+    let data = NSMutableData()
+    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
+    else { return nil }
+    CGImageDestinationAddImage(destination, image, nil)
+    return CGImageDestinationFinalize(destination) ? data as Data : nil
+  }
+
   private func commit(_ next: ControlInputs) {
     undoStack.append(inputs)
     if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
@@ -220,6 +345,7 @@ public final class ControlStore {
     var referenced = Set<String>()
     for state in undoStack + redoStack + [inputs] {
       if let image = state.image { referenced.insert(image.fileName) }
+      for entry in state.moodboard { referenced.insert(entry.image.fileName) }
     }
     for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
   }
@@ -232,18 +358,31 @@ public struct PendingInputs: Sendable {
   let framing: Framing
   let canvasWidth: Int
   let canvasHeight: Int
+  /// The Moodboard pictures that are on, all with the same weight.
+  let moodboard: [(image: ReferenceImage, weight: Double)]
+
+  /// Longest side of a Moodboard picture when it is sent.
+  static let moodboardPixels = 1024
 
-  /// Decodes the copy at the size the canvas needs (a 50-megapixel photo is not decoded whole)
-  /// and frames it. No image: the RUN is text-to-image.
+  /// Decodes the start image at the size the canvas needs (a 50-megapixel photo is not decoded
+  /// whole) and frames it; reduces and encodes the Moodboard pictures. Nothing: the RUN is
+  /// text-to-image.
   public func render() throws(ControlError) -> GenerationInputs {
-    guard let image else { return .none }
+    var hints: [GenerationHint] = []
+    for entry in moodboard {
+      guard let decoded = storage.image(named: entry.image.fileName, maxPixel: Self.moodboardPixels),
+        let data = ControlStore.pngData(of: decoded)
+      else { throw .unreadable(entry.image.name) }
+      hints.append(GenerationHint(imageData: data, weight: entry.weight))
+    }
+    guard let image else { return GenerationInputs(hints: hints) }
     let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
     let longest = max(image.pixelWidth, image.pixelHeight)
     let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
     guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
       let framed = InputComposer.frame(decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing)
     else { throw .unreadable(image.name) }
-    return GenerationInputs(image: framed)
+    return GenerationInputs(image: framed, hints: hints)
   }
 }
 
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `235 tests … passed`; totale 56 + 235 + 55 + 6 + 6 = **358**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: ControlStore — Moodboard (aggiungi, sostituisci, togli, interruttore, riordina, annulla, hint del RUN, avvisi)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Testi della scheda Moodboard (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (13 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `control.strip.moodboard`, `control.moodboard.*` e `control.warning.many` (`%lld`), `control.warning.ignored`, `results.addToMoodboard`, usate dalle viste del Task 6.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

Salvare lo script seguente in un file temporaneo ed eseguirlo dalla radice del repository (`python3 <file>`):

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "control.strip.moodboard": ("Moodboard", "Moodboard"),
    "control.moodboard.title": ("Moodboard", "Moodboard"),
    "control.moodboard.drop": ("Drop images here from Results or the Finder.", "Trascina qui immagini da Risultati o dal Finder."),
    "control.moodboard.equal": ("Every picture that is on counts the same.", "Ogni immagine accesa conta allo stesso modo."),
    "control.moodboard.hint": ("Drop on a picture to replace it, anywhere else to add.", "Rilascia su un'immagine per sostituirla, altrove per aggiungere."),
    "control.moodboard.add": ("Add…", "Aggiungi…"),
    "control.moodboard.turnOff": ("Turn off", "Spegni"),
    "control.moodboard.turnOn": ("Turn on", "Accendi"),
    "control.moodboard.remove": ("Remove from the Moodboard", "Togli dal Moodboard"),
    "control.moodboard.unsupported": ("This model does not use the Moodboard: it would need an adapter. The pictures are kept and not sent.", "Questo modello non usa il Moodboard: servirebbe un adattatore. Le immagini restano e non vengono inviate."),
    "control.warning.many": ("%lld Moodboard pictures: every extra one makes the render much slower.", "%lld immagini nel Moodboard: ognuna in più rallenta molto il render."),
    "control.warning.ignored": ("The chosen model does not use the Moodboard.", "Il modello scelto non usa il Moodboard."),
    "results.addToMoodboard": ("Add to the Moodboard", "Aggiungi al Moodboard"),
}
for key, (en, it) in new.items():
    assert key not in d['strings'], key
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
```

Run: `cd "/Users/existenz/Software developement/DT Hub" && git diff --stat App/Localizable.xcstrings | tail -1`
Expected: `1 file changed, 221 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi del Moodboard (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: La scheda Moodboard e i collegamenti (App)

**Files:**
- Create: `App/Control/MoodboardCard.swift`
- Modify: `App/Control/ControlImport.swift`, `ControlStrip.swift`, `ControlTabView.swift`, `ControlText.swift`, `ImageCard.swift`, `App/Generation/GenerationController.swift`, `App/Results/ResultsView.swift`

**Interfaces:**
- Consumes: tutto ciò che producono i Task 1–5; `MoodboardEntry`, `FamilyTraits.usesMoodboard`, `ControlStore.*Moodboard*`, `GenerationController.family(in:)` (esistente).
- Produces:
  - `MoodboardCard(generation:connection:report:)` con `MoodboardTile` (miniatura 124 px, occhio, ✕, trascinabile con `MoodboardDragToken`), rilascio di file (su una miniatura sostituisce, altrove aggiunge) e di token (riordina);
  - `ControlImport.takeMoodboard(urls:into:)`, `replaceMoodboard(id:urls:into:)`, `chooseMoodboard(into:)`;
  - `ControlStrip(generation:connection:)` con il chip Moodboard (numero delle accese, ✕ = `clearMoodboard`) e gli avvisi con `usesMoodboard`;
  - la miniatura dell'immagine di partenza si trascina come file della sua copia (`DragOut`);
  - il RUN manda gli hint solo se la famiglia usa il Moodboard (`includeMoodboard`), registra `moodboardCount` nel job e `imageStrength` solo con un'immagine di partenza;
  - Risultati: menu e pulsante "Aggiungi al Moodboard".

Questo task è codice di vista: la verifica è la compilazione (Step 3) e la prova dal vivo (Task 7).

- [ ] **Step 1: Creare la scheda**

```swift
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// What is dragged when a Moodboard picture is moved inside the card (tab Control spec §3).
struct MoodboardDragToken: Codable, Transferable {
  let id: UUID

  static var transferRepresentation: some TransferRepresentation {
    CodableRepresentation(contentType: .json)
  }
}

/// The Moodboard (spec: tab Control §3): the pictures with a switch and a ✕ on each, and the drop
/// rule: on a picture replaces it, anywhere else in the card adds. Every picture that is on
/// counts the same (the shares of §4.1 come back when a model honours them).
struct MoodboardCard: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  let report: (ControlMessage) -> Void
  @State private var isTargeted = false

  private var control: ControlStore { generation.control }
  private var entries: [MoodboardEntry] { control.inputs.moodboard }
  private var usable: Bool { FamilyTraits.of(generation.family(in: connection)).usesMoodboard }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.moodboard.title"), systemImage: "square.grid.2x2",
      isExpanded: generation.cards.binding("control.moodboard")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if !usable {
          Label(String(localized: "control.moodboard.unsupported"), systemImage: "info.circle")
            .font(.caption).foregroundStyle(.secondary)
        }
        if !entries.isEmpty {
          HStack(spacing: DS.controlGap) {
            Text("control.moodboard.equal").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("control.moodboard.add") {
              Task { if let message = await ControlImport.chooseMoodboard(into: control) { report(.error(message)) } }
            }
            .buttonStyle(DSPillButtonStyle())
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: DS.rowGap, alignment: .top)], spacing: DS.rowGap) {
            ForEach(entries) { entry in
              MoodboardTile(entry: entry, control: control, report: report)
            }
          }
          Text("control.moodboard.hint").font(.caption).foregroundStyle(.secondary)
        } else {
          emptyZone
        }
      }
      .opacity(usable ? 1 : 0.5)
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
      .dropDestination(for: URL.self) { urls, _ in
        Task { if let message = await ControlImport.takeMoodboard(urls: urls, into: control) { report(.error(message)) } }
        return true
      } isTargeted: { isTargeted = $0 }
      .dropDestination(for: MoodboardDragToken.self) { tokens, _ in
        if let token = tokens.first { control.moveMoodboardImage(id: token.id, before: nil) }
        return true
      }
    }
  }

  private var emptyZone: some View {
    VStack(spacing: DS.controlGap) {
      Image(systemName: "square.grid.2x2").font(.system(size: 24)).foregroundStyle(.secondary)
      Text("control.moodboard.drop").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("control.moodboard.add") {
        Task { if let message = await ControlImport.chooseMoodboard(into: control) { report(.error(message)) } }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
  }
}

/// A picture of the Moodboard: thumbnail with the switch and the ✕. A picture dropped on it
/// replaces it; another tile dropped on it moves before it.
private struct MoodboardTile: View {
  let entry: MoodboardEntry
  let control: ControlStore
  let report: (ControlMessage) -> Void
  @State private var thumbnail: CGImage?
  @State private var isTargeted = false

  var body: some View {
    VStack(spacing: 4) {
      ZStack {
        Group {
          if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
          } else {
            Color.primary.opacity(0.08)
          }
        }
        .frame(width: 124, height: 124)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        .opacity(entry.isOn ? 1 : 0.4)
        .overlay(
          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
            .strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
        VStack {
          HStack {
            overlayButton(
              systemImage: entry.isOn ? "eye" : "eye.slash",
              label: String(localized: entry.isOn ? "control.moodboard.turnOff" : "control.moodboard.turnOn")
            ) { control.setMoodboardOn(id: entry.id, isOn: !entry.isOn) }
            Spacer()
            overlayButton(systemImage: "xmark", label: String(localized: "control.moodboard.remove")) {
              control.removeMoodboardImage(id: entry.id)
            }
          }
          Spacer()
        }
        .padding(4)
      }
      .frame(width: 124, height: 124)
      .draggable(MoodboardDragToken(id: entry.id))
    }
    .dropDestination(for: URL.self) { urls, _ in
      Task {
        if let message = await ControlImport.replaceMoodboard(id: entry.id, urls: urls, into: control) {
          report(.error(message))
        }
      }
      return true
    } isTargeted: { isTargeted = $0 }
    .dropDestination(for: MoodboardDragToken.self) { tokens, _ in
      if let token = tokens.first { control.moveMoodboardImage(id: token.id, before: entry.id) }
      return true
    }
    .task(id: entry.id) {
      guard let request = control.previewRequest(ofMoodboard: entry.id, maxPixel: 280) else { return thumbnail = nil }
      thumbnail = await Task.detached { request.render() }.value
    }
  }

  private func overlayButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .bold))
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color.black.opacity(0.55)))
        .foregroundStyle(.white)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .help(label)
  }
}
```

- [ ] **Step 2: Applicare le modifiche ai file esistenti**

```diff
diff --git a/App/Control/ControlImport.swift b/App/Control/ControlImport.swift
index 3c477bb..1c2435d 100644
--- a/App/Control/ControlImport.swift
+++ b/App/Control/ControlImport.swift
@@ -51,6 +51,45 @@ enum ControlImport {
     return nil
   }
 
+  /// Every file of a drop is added to the Moodboard; the first problem is the message.
+  static func takeMoodboard(urls: [URL], into control: ControlStore) async -> String? {
+    var message: String?
+    for url in urls {
+      guard url.isFileURL else {
+        message = message ?? ControlText.error(.unreadable(url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent))
+        continue
+      }
+      do throws(ControlError) {
+        try await control.addMoodboardImage(fileURL: url)
+      } catch {
+        message = message ?? ControlText.error(error)
+      }
+    }
+    return message
+  }
+
+  /// A file dropped on a Moodboard picture takes its place.
+  static func replaceMoodboard(id: UUID, urls: [URL], into control: ControlStore) async -> String? {
+    guard let url = urls.first(where: { $0.isFileURL }) else {
+      return await takeMoodboard(urls: urls, into: control)
+    }
+    do throws(ControlError) {
+      try await control.replaceMoodboardImage(id: id, fileURL: url)
+      return nil
+    } catch {
+      return ControlText.error(error)
+    }
+  }
+
+  /// The file panel of "Add…" in the Moodboard: several files at once.
+  static func chooseMoodboard(into control: ControlStore) async -> String? {
+    let panel = NSOpenPanel()
+    panel.allowedContentTypes = [.image]
+    panel.allowsMultipleSelection = true
+    guard panel.runModal() == .OK else { return nil }
+    return await takeMoodboard(urls: panel.urls, into: control)
+  }
+
   /// The file panel of "Choose…" and "Replace…".
   static func choose(into control: ControlStore) async -> String? {
     let panel = NSOpenPanel()
```

```diff
diff --git a/App/Control/ControlStrip.swift b/App/Control/ControlStrip.swift
index 5801665..b95b593 100644
--- a/App/Control/ControlStrip.swift
+++ b/App/Control/ControlStrip.swift
@@ -6,11 +6,13 @@ import SwiftUI
 /// "Clear all" and the warnings worth a look before pressing RUN.
 struct ControlStrip: View {
   let generation: GenerationController
+  let connection: DrawThingsConnection
   private var control: ControlStore { generation.control }
 
   var body: some View {
     let warnings = control.warnings(
-      canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)
+      canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height,
+      usesMoodboard: FamilyTraits.of(generation.family(in: connection)).usesMoodboard)
     VStack(alignment: .leading, spacing: DS.controlGap) {
       HStack(spacing: DS.controlGap) {
         DSGroupHeader(title: String(localized: "control.strip.title"))
@@ -19,7 +21,14 @@ struct ControlStrip: View {
             systemImage: "photo", title: String(localized: "control.strip.image"),
             detail: "\(image.pixelWidth)×\(image.pixelHeight)",
             remove: { control.removeImage() })
-        } else {
+        }
+        if !control.inputs.moodboard.isEmpty {
+          chip(
+            systemImage: "square.grid.2x2", title: String(localized: "control.strip.moodboard"),
+            detail: "\(control.inputs.moodboard.filter(\.isOn).count)",
+            remove: { control.clearMoodboard() })
+        }
+        if control.inputs.image == nil, control.inputs.moodboard.isEmpty {
           Text("control.strip.empty").font(.caption).foregroundStyle(.secondary)
         }
         Spacer(minLength: 0)
```

```diff
diff --git a/App/Control/ControlTabView.swift b/App/Control/ControlTabView.swift
index 30960c6..db5ed10 100644
--- a/App/Control/ControlTabView.swift
+++ b/App/Control/ControlTabView.swift
@@ -16,10 +16,13 @@ struct ControlTabView: View {
   var body: some View {
     ScrollView {
       VStack(spacing: DS.groupGap) {
-        ControlStrip(generation: generation)
+        ControlStrip(generation: generation, connection: connection)
         messageBar
         DSCardRow {
-          ImageCard(generation: generation, connection: connection) { message = $0 }
+          VStack(spacing: DS.groupGap) {
+            ImageCard(generation: generation, connection: connection) { message = $0 }
+            MoodboardCard(generation: generation, connection: connection) { message = $0 }
+          }
           CanvasStage(generation: generation)
         }
       }
```

```diff
diff --git a/App/Control/ControlText.swift b/App/Control/ControlText.swift
index cead831..bc137a8 100644
--- a/App/Control/ControlText.swift
+++ b/App/Control/ControlText.swift
@@ -32,6 +32,8 @@ enum ControlText {
   static func warning(_ warning: ControlWarning) -> String {
     switch warning {
     case .strongCrop(let percent): String(format: String(localized: "control.warning.crop"), percent)
+    case .manyReferences(let count): String(format: String(localized: "control.warning.many"), count)
+    case .moodboardIgnored: String(localized: "control.warning.ignored")
     }
   }
 }
```

```diff
diff --git a/App/Control/ImageCard.swift b/App/Control/ImageCard.swift
index 6c9fe4e..b9291c1 100644
--- a/App/Control/ImageCard.swift
+++ b/App/Control/ImageCard.swift
@@ -52,6 +52,7 @@ struct ImageCard: View {
         }
         .frame(width: 104, height: 104)
         .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
+        .modifier(DragOut(url: control.copyURL(of: image)))
         Button {
           control.removeImage()
         } label: {
@@ -137,3 +138,12 @@ enum ControlMessage: Equatable {
   /// The dimensions were adapted; the previous ones can be put back.
   case adapted(Size)
 }
+
+/// The thumbnail can be dragged out as the file of its copy (into the Moodboard, or another app).
+private struct DragOut: ViewModifier {
+  let url: URL?
+
+  func body(content: Content) -> some View {
+    if let url { content.draggable(url) } else { content }
+  }
+}
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 309e73e..aa6ab27 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -171,7 +171,7 @@ final class GenerationController {
       // Memory first: the language model leaves, a server parked for it comes back.
       await languageModel.prepareForRun()
       await connection.ensureServerForRun()
-      let inputs = await renderInputs()
+      let inputs = await renderInputs(in: connection)
       isPreparing = false
       preparation = nil
       guard !Task.isCancelled, let inputs else { return }
@@ -197,15 +197,19 @@ final class GenerationController {
     let batches = JobComposer.batches(
       prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
       parameters: parameters, catalog: connection.monitor.catalog,
-      imageStrength: inputs.isEmpty ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)))
+      imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)),
+      moodboardCount: inputs.hints.count)
     if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
     session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
   }
 
   /// The Control tab's images framed to the canvas, decoded away from the main actor. A failure
   /// is shown as the RUN's failure, and nothing starts.
-  private func renderInputs() async -> GenerationInputs? {
-    let pending = control.pendingInputs(canvasWidth: parameters.width, canvasHeight: parameters.height)
+  private func renderInputs(in connection: DrawThingsConnection) async -> GenerationInputs? {
+    // The Moodboard goes only to a model that uses it (the old families would need an adapter).
+    let pending = control.pendingInputs(
+      canvasWidth: parameters.width, canvasHeight: parameters.height,
+      includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard)
     do {
       return try await Task.detached { try pending.render() }.value
     } catch {
```

```diff
diff --git a/App/Results/ResultsView.swift b/App/Results/ResultsView.swift
index ba408a3..6bbf86e 100644
--- a/App/Results/ResultsView.swift
+++ b/App/Results/ResultsView.swift
@@ -153,6 +153,7 @@ struct ResultsView: View {
     .accessibilityLabel(result.job.prompt)
     .contextMenu {
       Button("results.useAsImage") { useAsImage(result) }
+      Button("results.addToMoodboard") { addToMoodboard(result) }
     }
     if let url = result.fileURL {
       button.draggable(url)
@@ -176,6 +177,22 @@ struct ResultsView: View {
     }
   }
 
+  private func addToMoodboard(_ result: GeneratedImage) {
+    useError = nil
+    Task {
+      do throws(ControlError) {
+        if let url = result.fileURL {
+          try await controller.control.addMoodboardImage(fileURL: url, source: .result)
+        } else {
+          try controller.control.addMoodboardImage(
+            result.image, name: String(localized: "results.unsaved.name"), source: .result)
+        }
+      } catch {
+        useError = ControlText.error(error)
+      }
+    }
+  }
+
   private func actions(for result: GeneratedImage) -> some View {
     HStack(spacing: DS.controlGap) {
       Text(String(format: String(localized: "results.seed"), String(result.job.parameters.seed)))
@@ -191,6 +208,8 @@ struct ResultsView: View {
       Spacer(minLength: 0)
       Button("results.useAsImage") { useAsImage(result) }
         .buttonStyle(DSPillButtonStyle())
+      Button("results.addToMoodboard") { addToMoodboard(result) }
+        .buttonStyle(DSPillButtonStyle())
       if let url = result.fileURL {
         Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
           .buttonStyle(DSPillButtonStyle())
```

- [ ] **Step 3: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m7b-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v started`
Expected: `** BUILD SUCCEEDED **` (in una cartella a parte, per non toccare un'app aperta); test HubKit 56, HubCore 235, DTBridge 55, Catalog 6, LLMBridge 6 = **358** passati.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: scheda Moodboard — miniature con occhio e ✕, rilascio che sostituisce o aggiunge, riordino, Risultati e immagine di partenza

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verifica dal vivo

**Files:**
- Modify: `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (due prove con server vero, inattive senza variabile d'ambiente)

- [ ] **Step 1: Aggiungere le prove dal vivo**

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index f2b4245..1d716dc 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -1,7 +1,9 @@
 import CoreGraphics
 import Foundation
 import HubKit
+import ImageIO
 import Testing
+import UniformTypeIdentifiers
 
 @testable import DTBridge
 
@@ -94,6 +96,50 @@ struct LiveServerTests {
     #expect(greenShare(guided) > greenShare(plain) + 0.05)
   }
 
+  /// FLUX.2 [klein] reads Moodboard pictures as references: with no start image, a reference
+  /// (left half black, right half white) shapes the result. (Its weight does not matter: any value
+  /// above 0 gives the same result, measured in Draw Things and here.)
+  @Test(.enabled(if: address != nil))
+  func anEditModelReadsAMoodboardPicture() async throws {
+    let backend = try await liveBackend()
+    let model = try #require(
+      try await backend.fetchCatalog().models.first { $0.family == "flux2_9b" }?.file,
+      "needs a FLUX.2 [klein] model on the server")
+    let job = GenerationJob(
+      prompt: "the same picture", model: model,
+      parameters: GenerationParameters(width: 512, height: 512, steps: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
+    let data = NSMutableData()
+    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
+    CGImageDestinationAddImage(destination, splitImage(size: 512), nil)
+    CGImageDestinationFinalize(destination)
+    let full = try await run(backend, job, GenerationInputs(hints: [GenerationHint(imageData: data as Data)]))
+    await backend.shutdown()
+    print("LIVE moodboard: right minus left luminance \(rightMinusLeft(full))")
+    #expect(full.width == 512)
+    #expect(rightMinusLeft(full) > 0.15)
+  }
+
+  /// Z Image Turbo has no Edit modifier: does it read a Moodboard picture at all? (Measured, and
+  /// the answer decides which families the Moodboard card is active for.)
+  @Test(.enabled(if: address != nil))
+  func aModernModelWithoutAnEditModifierAndTheMoodboard() async throws {
+    let backend = try await liveBackend()
+    let model = try #require(
+      try await backend.fetchCatalog().models.first { $0.file.hasPrefix("z_image_turbo") }?.file,
+      "needs Z Image Turbo on the server")
+    let job = GenerationJob(
+      prompt: "a photograph of a wall", model: model,
+      parameters: GenerationParameters(width: 512, height: 512, steps: 8, sampler: .ddimTrailing, seed: 7, randomSeed: false))
+    let data = NSMutableData()
+    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
+    CGImageDestinationAddImage(destination, splitImage(size: 512), nil)
+    CGImageDestinationFinalize(destination)
+    let plain = try await run(backend, job, .none)
+    let guided = try await run(backend, job, GenerationInputs(hints: [GenerationHint(imageData: data as Data)]))
+    await backend.shutdown()
+    print("LIVE z-image moodboard: right minus left plain \(rightMinusLeft(plain)) guided \(rightMinusLeft(guided))")
+  }
+
   private func liveBackend() async throws -> DrawThingsBackend {
     let parts = try #require(Self.address?.split(separator: ":"))
     return DrawThingsBackend(host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v started`
Expected: DTBridge `57 tests … passed` (2 inattive), totale **360**.

- [ ] **Step 2: Provarle con un server vero**

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (FLUX.2 klein, Z Image Turbo). Si avvia a mano, solo per la prova, **e solo se l'app dell'utente non sta usando la porta 7860**.

```bash
(nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7860 --model-browser > /tmp/m7b-server.log 2>&1 &); sleep 6
cd "/Users/existenz/Software developement/DT Hub/Packages" && DTHUB_LIVE_DT=localhost:7860 swift test --filter "anEditModelReadsAMoodboard|aModernModelWithoutAnEditModifier" 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
pkill -TERM -f gRPCServerCLI
```

Expected: `LIVE moodboard: right minus left luminance …` (circa 1,0, soglia 0,15) con il primo test passato; `LIVE z-image moodboard: right minus left plain X guided X` con **X uguali** (Z Image ignora il Moodboard: motivo della sua voce in `withoutMoodboard`); il secondo test passa senza asserzioni. Il primo carica il modello dal disco esterno: può volerci qualche minuto.

- [ ] **Step 3: Provare l'app (screenshot)**

Chiedere all'utente di chiudere il suo DT Hub se è aperto. Per non toccare i suoi dati: salvare `~/Library/Application Support/DT Hub` e le preferenze (`defaults export com.exiztenz.DTHub /tmp/m7b-defaults.plist`), usare una cartella di output temporanea (`defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m7b-out`) e il server gestito (`drawThings.managedServer` con `/Users/existenz/Applications/DrawThings-CLI/gRPCServerCLI-macOS`, `/Volumes/LLM-VLM/Models`, porta 7860). Preparare in `Control/` tre copie PNG diverse e un `control.json` a mano con tre voci nel `moodboard` (`image` con `id`, `name`, `pixelWidth`, `pixelHeight`, `source`, `fileName`; `isOn`), la seconda spenta, e aprire l'app (compilata in `build/`).

Checklist:
1. Il tab Control mostra la striscia con il chip Moodboard (numero 2) e la scheda Moodboard con tre miniature, la seconda attenuata con l'occhio barrato, e la riga "Ogni immagine accesa conta allo stesso modo".
2. Con un modello di una famiglia che lo ignora (per esempio Z Image Turbo) la scheda è grigia con la spiegazione e la striscia avvisa "Il modello scelto non usa il Moodboard.".
3. Con FLUX.2 klein e Run: il RUN parte e il PNG salvato ha nei metadati `"moodboardCount":2` (`strings <file> | grep moodboardCount`).
4. Occhio, ✕ (con "Annulla"), riordino per trascinamento e "Aggiungi…" funzionano; chiudere e riaprire l'app: il Moodboard è ancora lì.

- [ ] **Step 4: Pulizia** (sempre, anche se qualcosa non va)

Fermare app e server, ripristinare la cartella `DT Hub` e le preferenze salvate, togliere le chiavi di prova (`output.folder`, `drawThings.managedServer`) e la cartella `/tmp/dthub-m7b-out`; rimettere `session.json`, `cards.json` e `results.json` del backup e togliere `control.json` e la cartella `Control` create dalla prova.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "test: prove dal vivo del Moodboard (modello Edit e modello che lo ignora)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7b

Esito atteso sul branch `m7b-moodboard`:
- **360 test verdi** (2 prove dal vivo inattive senza `DTHUB_LIVE_DT`, provate con il server);
- build Xcode pulita;
- il Moodboard funziona dall'app: immagini dal Finder, da Risultati (trascinamento, menu, pulsante) e dalla scheda Immagine; acceso/spento, ✕ con annulla, riordino, sostituzione per rilascio; famiglie che lo ignorano grigie e senza hint; ripristino all'avvio.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge, e il piano di **M7c** (maschera e inpaint).

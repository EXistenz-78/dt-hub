# M7a Tab Control — immagine di partenza e I2I — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** DT Hub ha il tab **Control**, davanti a Generazione, in cui si sceglie l'**immagine di partenza** (dal Finder, da Risultati con il trascinamento o il menu, con ⌘V), si regolano la forza e l'inquadratura nel canvas, e il RUN genera in image-to-image. Le immagini sono copie nell'app, si ripristinano all'avvio e ogni rimozione si annulla.

**Architecture:**
- **HubKit** riceve i tipi (`ReferenceImage`, `Framing`, `ControlInputs`, `GenerationInputs`), il campo `imageStrength` del job, il `modifier` nelle capacità del modello e il protocollo backend con gli ingressi.
- **DTBridge** traduce: immagine e forza nella richiesta, `modifier` dal catalogo.
- **HubCore** riceve la matematica dell'inquadratura e il compositore (funzioni pure), lo store delle copie con annulla e persistenza, e il collegamento al RUN (forza nei batch, ingressi alla sessione, `fail`).
- **L'app** aggiunge il tab Control (striscia "Con Run parte", scheda Immagine, anteprima del canvas con ritaglio trascinabile), l'importazione (trascinamento, ⌘V, pannello file) e le modifiche a Risultati.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, ImageIO e Core Graphics, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-01-tab-control-design.md` (sezioni 1–6, 8–12; la 4.1 e il Moodboard sono di M7b, la maschera di M7c) e `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md` (§4, §7, §13).

## Global Constraints

- **Repository e dipendenze:**
  - radice `<repo>` (percorsi tra virgolette);
  - branch `m7a-tab-control` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift (`GenerationRequest`, `DrawThingsConfiguration`); HubKit e HubCore non importano nulla di esterno.
- **Dopo un riavvio del Mac** SwiftPM può avere in cache il vecchio percorso del Metal Toolchain: se `swift test` dà `unable to spawn process … metal`, eseguire `swift package clean` in `Packages` e riprovare.
- **Ingressi (spec Control §2, §4):** solo l'immagine di partenza; Moodboard, maschera, ControlNet e hint non esistono in M7a. `GenerationJob` non cambia salvo `imageStrength`; gli ingressi vuoti riproducono il T2I di oggi.
- **Copie:** ogni immagine aggiunta si copia in `~/Library/Application Support/DT Hub/Control/<uuid>.<estensione>` byte per byte; lo stato sta in `control.json` accanto a `session.json`; le copie non referenziate (dallo stato attuale o dalla cronologia di annulla) si cancellano. Annulla: 20 passi.
- **Forza (spec Control §3):** automatica finché l'utente non la sceglie — **1,0 per i modelli Edit, 0,7 per gli altri**; Edit = `modifier` del modello in `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing`. La forza e lo spostamento non entrano nella cronologia di annulla.
- **Inquadratura (spec Control §5):** solo "Riempi" (canvas invariato, ritaglio, spostamento -1…1 sull'asse ritagliato); "Adatta le dimensioni" = rapporto dell'immagine, area uguale a quella del canvas, multipli di 64, tra 64 e 2048. Un ritaglio oltre **un terzo** dell'immagine dà un avviso nella striscia.
- **Memoria:** le immagini si decodificano con ImageIO alla dimensione necessaria (anteprima 1400 px, miniatura 240 px, RUN alla scala del canvas); mai a piena risoluzione se il canvas è più piccolo.
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; `String(format: String(localized:), …)` per i valori; `Text("chiave")` per i letterali.
- **Il tab è una vista; la logica sta in HubCore** (testata). L'app non ha test di vista: si verifica con la compilazione e con la prova dal vivo (Task 7).
- **Blocchi `diff`:** sono le modifiche ai file che esistono già su `main`; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Fuori da M7a:** Moodboard (M7b), maschera e inpaint (M7c), outpaint e modo "Contieni", limite 8192 con Tiled Diffusion, plug-in.

## Review Focus

- **File che non è un'immagine, danneggiato o illeggibile:** rifiutato con un messaggio che nomina il file, nessuna copia rimasta, lo stato non cambia (test `anUnreadableFileIsRefusedAndLeavesNothing`, Task 3).
- **Foto con orientamento EXIF (iPhone, 90°):** le dimensioni mostrate e l'inquadratura usano l'immagine ruotata (test `theSizeFollowsTheExifOrientation`, Task 3).
- **Rapporto diverso dal canvas:** quadrata in 4:3 perde il 25% senza avviso, 3:4 in 4:3 perde il 44% con avviso; lo spostamento agisce solo sull'asse ritagliato (test `FramingMathTests`, Task 2; `aStrongCropIsReported`, Task 3).
- **Copia sparita (all'avvio o fra la scelta e il RUN):** all'avvio la voce si scarta con un avviso; al RUN il motivo compare nella finestra Risultati e **non** parte un T2I a insaputa dell'utente (test `aMissingCopyIsDroppedWithANotice`, `aCopyThatVanishedBeforeTheRunIsReported`, Task 3; `aRunThatCannotStartCanBeReportedAsAFailure`, Task 4).
- **Foto enorme o immagine minuscola:** riempiono il canvas alla dimensione esatta senza decodificare tutta la foto (test `aBigPhotoAndATinyPictureBothFillTheCanvas`, Task 3).
- **Sostituire, togliere, svuotare, annullare, ripetere** e la pulizia delle copie orfane (test `ControlStoreTests`, Task 3).
- **Tab vuoto = T2I invariato:** nessun ingresso, nessuna `strength` nella richiesta (test `withoutAnImageTheRequestIsTextToImage`, Task 1; `theBackendReceivesTheControlInputsOfEveryBatch`, Task 4).

---

### Task 1: Contratto degli ingressi e la sua traduzione per Draw Things (HubKit, DTBridge)

**Files:**
- Create: `Packages/Sources/HubKit/Control/ControlInputs.swift`
- Modify: `Packages/Sources/HubKit/Generation/GenerationJob.swift` (`imageStrength`)
- Modify: `Packages/Sources/HubKit/Catalog/ModelCapabilities.swift` (`modifier`, `isEditModel`)
- Modify: `Packages/Sources/HubKit/Backend/GenerationBackend.swift` (`generate(_:inputs:)`)
- Modify: `Packages/Sources/DTBridge/JobMapper.swift`, `DrawThingsBackend.swift`, `CatalogBuilder.swift`
- Modify: `Packages/Tests/HubCoreTests/FakeBackend.swift` (registra gli ingressi)
- Test: `Packages/Tests/HubKitTests/ControlContractTests.swift` (nuovo), `Packages/Tests/DTBridgeTests/JobMapperTests.swift`, `CatalogBuilderTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct ReferenceImage: Identifiable, Equatable, Codable, Sendable` (`id`, `name`, `pixelWidth`, `pixelHeight`, `source: Source`, `fileName`; `enum Source { file(path:), result, pasteboard, plugin(id:) }`);
  - `struct Framing: Equatable, Codable, Sendable` (`mode: Mode` con il solo caso `fill`, `offsetX`, `offsetY`, `clamped()`);
  - `struct ControlInputs: Equatable, Codable, Sendable` (`image: ReferenceImage?`, `framing`, `strength: Double?`, `effectiveStrength(editModel:) -> Double`);
  - `struct GenerationInputs: Sendable` (`image: CGImage?`, `isEmpty`, `static let none`);
  - `GenerationJob.imageStrength: Double?` (iniziatore con `imageStrength: Double? = nil`);
  - `ModelCapabilities.modifier: String?` e `isEditModel: Bool`;
  - `GenerationBackend.generate(_ job:, inputs:)`; l'estensione `generate(_ job:)` equivale a `inputs: .none`.
- Consumes: nulla.

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "<repo>" && git switch main && git switch -c m7a-tab-control
```

Creare `Packages/Tests/HubKitTests/ControlContractTests.swift`:

```swift
import Foundation
import Testing

@testable import HubKit

struct ControlContractTests {
  func image(source: ReferenceImage.Source = .pasteboard) -> ReferenceImage {
    ReferenceImage(id: UUID(), name: "cat.png", pixelWidth: 800, pixelHeight: 600, source: source, fileName: "a.png")
  }

  @Test func referenceImagesSurviveEncoding() throws {
    for source in [ReferenceImage.Source.file(path: "/x/cat.png"), .result, .pasteboard, .plugin(id: "pm2")] {
      let original = image(source: source)
      let decoded = try JSONDecoder().decode(ReferenceImage.self, from: JSONEncoder().encode(original))
      #expect(decoded == original)
    }
  }

  @Test func emptyControlInputsLoadFromAnyOlderFile() throws {
    let decoded = try JSONDecoder().decode(ControlInputs.self, from: Data("{}".utf8))
    #expect(decoded == ControlInputs())
    #expect(decoded.image == nil)
    #expect(decoded.framing == Framing())
    #expect(decoded.strength == nil)
  }

  @Test func strengthIsAutomaticUntilTheUserChoosesOne() {
    var inputs = ControlInputs()
    #expect(inputs.effectiveStrength(editModel: true) == 1.0)
    #expect(inputs.effectiveStrength(editModel: false) == 0.7)
    inputs.strength = 0.4
    #expect(inputs.effectiveStrength(editModel: true) == 0.4)
    inputs.strength = 3
    #expect(inputs.effectiveStrength(editModel: false) == 1.0)
    inputs.strength = -1
    #expect(inputs.effectiveStrength(editModel: false) == 0.0)
  }

  @Test func theFramingStartsCentered() {
    let framing = Framing()
    #expect(framing.mode == .fill)
    #expect(framing.offsetX == 0)
    #expect(framing.offsetY == 0)
    #expect(Framing(offsetX: 5, offsetY: -5).clamped() == Framing(offsetX: 1, offsetY: -1))
  }

  @Test func noInputsMeansTextToImage() {
    #expect(GenerationInputs.none.isEmpty)
  }

  @Test func oldJobsHaveNoImageStrength() throws {
    let job = GenerationJob(prompt: "p", model: "m.ckpt", parameters: .default)
    #expect(job.imageStrength == nil)
    let old = try JSONDecoder().decode(
      GenerationJob.self, from: Data(#"{"prompt":"p","model":"m.ckpt","parameters":{}}"#.utf8))
    #expect(old.imageStrength == nil)
    var withImage = job
    withImage.imageStrength = 0.6
    let round = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(withImage))
    #expect(round.imageStrength == 0.6)
  }

  @Test func editModelsAreRecognisedByTheirModifier() {
    func caps(_ modifier: String?) -> ModelCapabilities {
      var c = ModelCapabilities.unknown
      c.modifier = modifier
      return c
    }
    for edit in ["kontext", "kontext_kv", "qwenimage_edit_plus", "editing"] {
      #expect(caps(edit).isEditModel)
    }
    for other in [nil, "inpainting", "none", "depth"] as [String?] {
      #expect(!caps(other).isEditModel)
    }
  }
}
```

Applicare le modifiche ai test esistenti (salvare ogni blocco in un file e `git apply`):

```diff
diff --git a/Packages/Tests/DTBridgeTests/JobMapperTests.swift b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
index b8cbfcd..0fb7f2c 100644
--- a/Packages/Tests/DTBridgeTests/JobMapperTests.swift
+++ b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
@@ -29,6 +29,31 @@ struct JobMapperTests {
     #expect(!configuration.resolutionDependentShift)
   }
 
+  @Test func sendsTheStartImageAndItsStrength() throws {
+    let image = try #require(TestImages.make(width: 64, height: 48))
+    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
+    job.imageStrength = 0.6
+    let request = JobMapper.request(for: job, inputs: GenerationInputs(image: image))
+    #expect(request.image === image)
+    #expect(abs(request.configuration.strength - 0.6) < 0.0001)
+    // The Control tab's strength wins over a "strength" key of the JSON editor.
+    var withExtra = job
+    withExtra = GenerationJob(
+      prompt: "a fox", model: "m.ckpt",
+      parameters: GenerationParameters(extra: ["strength": .double(0.2)]), imageStrength: 0.6)
+    let wins = JobMapper.request(for: withExtra, inputs: GenerationInputs(image: image))
+    #expect(abs(wins.configuration.strength - 0.6) < 0.0001)
+  }
+
+  @Test func withoutAnImageTheRequestIsTextToImage() {
+    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: .default)
+    job.imageStrength = 0.6
+    let request = JobMapper.request(for: job, inputs: .none)
+    #expect(request.image == nil)
+    #expect(request.configuration.strength == 1.0)
+    #expect(JobMapper.request(for: job).image == nil)
+  }
+
   @Test func sendsTheNegativePromptAndTheLoRAs() {
     let parameters = GenerationParameters(loras: [
       LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
@@ -165,3 +190,16 @@ struct JobMapperTests {
     #expect(JobMapper.backendError(for: CancellationError()) is CancellationError)
   }
 }
+
+import CoreGraphics
+
+enum TestImages {
+  static func make(width: Int, height: Int) -> CGImage? {
+    let context = CGContext(
+      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
+    context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
+    context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
+    return context?.makeImage()
+  }
+}
```

```diff
diff --git a/Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift b/Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift
index 72a5c28..b250d1f 100644
--- a/Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift
+++ b/Packages/Tests/DTBridgeTests/CatalogBuilderTests.swift
@@ -18,6 +18,13 @@ struct CatalogBuilderTests {
      {"name": "No file"}]
     """.utf8)
 
+  @Test func readsTheModifierOfAModel() {
+    #expect(CatalogBuilder.capabilities(["modifier": "kontext"]).modifier == "kontext")
+    #expect(CatalogBuilder.capabilities(["modifier": "kontext"]).isEditModel)
+    #expect(CatalogBuilder.capabilities([:]).modifier == nil)
+    #expect(!CatalogBuilder.capabilities(["modifier": "inpainting"]).isEditModel)
+  }
+
   @Test func modelsAreTheFilesWithASpec() {
     let catalog = CatalogBuilder.build(
       files: [klein, vae, describedLoRA, bareLoRA], modelSpecs: specs, loraMetadata: loraJSON)
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find type 'ReferenceImage' in scope`.

- [ ] **Step 3: Implementare**

Creare `Packages/Sources/HubKit/Control/ControlInputs.swift`:

```swift
import CoreGraphics
import Foundation

/// An image the user gave to the Control tab, kept as a copy in the app's Control folder so the
/// original (or a Results image) can go away without breaking the input (tab Control spec §4).
public struct ReferenceImage: Identifiable, Equatable, Codable, Sendable {
  public enum Source: Equatable, Codable, Sendable {
    /// A file chosen or dropped from the Finder; the path is only for showing where it came from.
    case file(path: String)
    /// An image of the Results window.
    case result
    case pasteboard
    /// Given by a plug-in (from M8).
    case plugin(id: String)
  }

  public let id: UUID
  public let name: String
  public let pixelWidth: Int
  public let pixelHeight: Int
  public let source: Source
  /// The copy, in the Control folder.
  public let fileName: String

  public init(id: UUID, name: String, pixelWidth: Int, pixelHeight: Int, source: Source, fileName: String) {
    self.id = id
    self.name = name
    self.pixelWidth = pixelWidth
    self.pixelHeight = pixelHeight
    self.source = source
    self.fileName = fileName
  }
}

/// How the start image sits in the canvas (spec §5). Only "fill" exists for now; "contain" comes
/// with the outpaint.
public struct Framing: Equatable, Codable, Sendable {
  public enum Mode: String, Codable, Sendable {
    case fill
  }

  public var mode: Mode
  /// Where the cut falls on the axis that is cropped: -1 shows the start (left or top) of the
  /// image, 0 is centered, 1 shows the end.
  public var offsetX: Double
  public var offsetY: Double

  public init(mode: Mode = .fill, offsetX: Double = 0, offsetY: Double = 0) {
    self.mode = mode
    self.offsetX = offsetX
    self.offsetY = offsetY
  }

  public func clamped() -> Framing {
    Framing(mode: mode, offsetX: min(1, max(-1, offsetX)), offsetY: min(1, max(-1, offsetY)))
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .fill
    offsetX = (try? container.decodeIfPresent(Double.self, forKey: .offsetX)) ?? 0
    offsetY = (try? container.decodeIfPresent(Double.self, forKey: .offsetY)) ?? 0
  }
}

/// Everything the Control tab holds (spec §4). Saved as `control.json`.
public struct ControlInputs: Equatable, Codable, Sendable {
  public var image: ReferenceImage?
  public var framing: Framing
  /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
  /// to-image ignores the image). The user's choice, once made, wins.
  public var strength: Double?

  public init(image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil) {
    self.image = image
    self.framing = framing
    self.strength = strength
  }

  /// The strength that is sent and shown, within 0…1.
  public func effectiveStrength(editModel: Bool) -> Double {
    min(1, max(0, strength ?? (editModel ? 1.0 : 0.7)))
  }

  /// Lenient, like the other saved files: a missing or unreadable field takes its default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    image = try? container.decodeIfPresent(ReferenceImage.self, forKey: .image)
    framing = (try? container.decodeIfPresent(Framing.self, forKey: .framing)) ?? Framing()
    strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
  }
}

/// What a RUN sends besides the job: the start image already framed to the canvas size. Not
/// `Codable`: images do not go into the PNG metadata.
public struct GenerationInputs: Sendable {
  public var image: CGImage?

  public init(image: CGImage? = nil) {
    self.image = image
  }

  public static let none = GenerationInputs()

  public var isEmpty: Bool { image == nil }
}
```

Applicare le modifiche (HubKit):

```diff
diff --git a/Packages/Sources/HubKit/Generation/GenerationJob.swift b/Packages/Sources/HubKit/Generation/GenerationJob.swift
index 05a0708..b2da416 100644
--- a/Packages/Sources/HubKit/Generation/GenerationJob.swift
+++ b/Packages/Sources/HubKit/Generation/GenerationJob.swift
@@ -8,12 +8,18 @@ public struct GenerationJob: Equatable, Codable, Sendable {
   public let negativePrompt: String
   public let model: String
   public let parameters: GenerationParameters
+  /// The strength of the start image; nil when the RUN has no start image.
+  public var imageStrength: Double?
 
-  public init(prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters) {
+  public init(
+    prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
+    imageStrength: Double? = nil
+  ) {
     self.prompt = prompt
     self.negativePrompt = negativePrompt
     self.model = model
     self.parameters = parameters
+    self.imageStrength = imageStrength
   }
 
   /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
@@ -31,6 +37,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
     model = try container.decode(String.self, forKey: .model)
     parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
+    imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
index e183f16..0156d00 100644
--- a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
+++ b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
@@ -15,10 +15,20 @@ public struct ModelCapabilities: Equatable, Sendable {
   public var clipSkip: Bool
   /// Native size in pixels (`default_scale` × 64); the Hires fix starts here. nil when unknown.
   public var nativeSize: Int?
+  /// The spec's `modifier`: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing` (Edit models),
+  /// `inpainting`, `depth`… nil when the spec has none.
+  public var modifier: String?
+
+  /// Edit and in-context models: the canvas image is the one to modify, and the Moodboard
+  /// brings extra references (tab Control spec §2).
+  public var isEditModel: Bool {
+    guard let modifier else { return false }
+    return ["kontext", "kontext_kv", "qwenimage_edit_plus", "editing"].contains(modifier)
+  }
 
   public init(
     guidanceEmbed: Bool, teaCache: Bool, clipL: Bool, openClipG: Bool, t5: Bool,
-    optionalT5: Bool, clipSkip: Bool, nativeSize: Int?
+    optionalT5: Bool, clipSkip: Bool, nativeSize: Int?, modifier: String? = nil
   ) {
     self.guidanceEmbed = guidanceEmbed
     self.teaCache = teaCache
@@ -28,6 +38,7 @@ public struct ModelCapabilities: Equatable, Sendable {
     self.optionalT5 = optionalT5
     self.clipSkip = clipSkip
     self.nativeSize = nativeSize
+    self.modifier = modifier
   }
 
   /// A model without a specification: everything may apply.
```

```diff
diff --git a/Packages/Sources/HubKit/Backend/GenerationBackend.swift b/Packages/Sources/HubKit/Backend/GenerationBackend.swift
index 0167b09..fa41648 100644
--- a/Packages/Sources/HubKit/Backend/GenerationBackend.swift
+++ b/Packages/Sources/HubKit/Backend/GenerationBackend.swift
@@ -15,9 +15,16 @@ public enum BackendError: Error, Equatable, Sendable {
 public protocol GenerationBackend: Sendable {
   /// Asks the server what it has installed. Doubles as the connection check.
   func fetchCatalog() async throws -> ModelCatalog
-  /// Runs one generation. Cancelling the consuming task cancels it on the server.
-  /// The stream ends with `.finished` or throws a `BackendError`.
-  func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error>
+  /// Runs one generation, with the images of the Control tab. Cancelling the consuming task
+  /// cancels it on the server. The stream ends with `.finished` or throws a `BackendError`.
+  func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error>
   /// Closes the connection. The backend is not used afterwards.
   func shutdown() async
 }
+
+extension GenerationBackend {
+  /// A text-to-image RUN, without the Control tab's images.
+  public func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error> {
+    generate(job, inputs: .none)
+  }
+}
```

Applicare le modifiche (DTBridge e backend finto dei test):

```diff
diff --git a/Packages/Sources/DTBridge/JobMapper.swift b/Packages/Sources/DTBridge/JobMapper.swift
index ea6b2f8..f375eca 100644
--- a/Packages/Sources/DTBridge/JobMapper.swift
+++ b/Packages/Sources/DTBridge/JobMapper.swift
@@ -3,10 +3,14 @@ import HubKit
 
 /// Translates DT Hub's `GenerationJob` and the library's events (spec §5).
 enum JobMapper {
-  static func request(for job: GenerationJob) -> GenerationRequest {
-    GenerationRequest(
+  static func request(for job: GenerationJob, inputs: GenerationInputs = .none) -> GenerationRequest {
+    var configuration = configuration(model: job.model, parameters: job.parameters)
+    // The start image and its strength come from the Control tab, after the JSON editor's
+    // extra settings: they win. Without an image the RUN stays text-to-image.
+    if inputs.image != nil, let strength = job.imageStrength { configuration.strength = Float(strength) }
+    return GenerationRequest(
       prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
-      configuration: configuration(model: job.model, parameters: job.parameters))
+      configuration: configuration, image: inputs.image)
   }
 
   /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
```

```diff
diff --git a/Packages/Sources/DTBridge/DrawThingsBackend.swift b/Packages/Sources/DTBridge/DrawThingsBackend.swift
index 081d107..55d4157 100644
--- a/Packages/Sources/DTBridge/DrawThingsBackend.swift
+++ b/Packages/Sources/DTBridge/DrawThingsBackend.swift
@@ -54,12 +54,12 @@ public actor DrawThingsBackend: GenerationBackend {
     return CatalogBuilder.build(files: reply.files, modelSpecs: specs, loraMetadata: reply.override.loras)
   }
 
-  public nonisolated func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error> {
+  public nonisolated func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error> {
     AsyncThrowingStream { continuation in
       let task = Task {
         do {
           let service = await self.currentService()
-          for try await event in service.stream(JobMapper.request(for: job)) {
+          for try await event in service.stream(JobMapper.request(for: job, inputs: inputs)) {
             if let update = try JobMapper.update(for: event) { continuation.yield(update) }
           }
           continuation.finish()
```

```diff
diff --git a/Packages/Sources/DTBridge/CatalogBuilder.swift b/Packages/Sources/DTBridge/CatalogBuilder.swift
index 8ff2d0b..9c0bc98 100644
--- a/Packages/Sources/DTBridge/CatalogBuilder.swift
+++ b/Packages/Sources/DTBridge/CatalogBuilder.swift
@@ -93,6 +93,7 @@ enum CatalogBuilder {
       t5: has("t5_xxl"),
       optionalT5: spec["t5_encoder"] != nil,
       clipSkip: textEncoder.contains("clip_vit") || textEncoder.contains("open_clip"),
-      nativeSize: (spec["default_scale"] as? Int).map { $0 * 64 })
+      nativeSize: (spec["default_scale"] as? Int).map { $0 * 64 },
+      modifier: spec["modifier"] as? String)
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/FakeBackend.swift b/Packages/Tests/HubCoreTests/FakeBackend.swift
index 24deace..60976d6 100644
--- a/Packages/Tests/HubCoreTests/FakeBackend.swift
+++ b/Packages/Tests/HubCoreTests/FakeBackend.swift
@@ -13,6 +13,7 @@ actor FakeBackend: GenerationBackend {
   private var scriptError: BackendError?
   private var stepDelay: Duration = .zero
   private(set) var jobs: [GenerationJob] = []
+  private(set) var inputs: [GenerationInputs] = []
   /// From this job on (1-based), `generate` fails at once with `failure`.
   private var failFrom: (job: Int, error: BackendError)?
 
@@ -45,10 +46,10 @@ actor FakeBackend: GenerationBackend {
     return try result.get()
   }
 
-  nonisolated func generate(_ job: GenerationJob) -> AsyncThrowingStream<GenerationUpdate, any Error> {
+  nonisolated func generate(_ job: GenerationJob, inputs: GenerationInputs) -> AsyncThrowingStream<GenerationUpdate, any Error> {
     AsyncThrowingStream { continuation in
       let task = Task {
-        let (updates, error, pause) = await self.start(job)
+        let (updates, error, pause) = await self.start(job, inputs: inputs)
         do {
           for update in updates {
             try await Task.sleep(for: pause)
@@ -64,8 +65,9 @@ actor FakeBackend: GenerationBackend {
     }
   }
 
-  private func start(_ job: GenerationJob) -> ([GenerationUpdate], BackendError?, Duration) {
+  private func start(_ job: GenerationJob, inputs: GenerationInputs) -> ([GenerationUpdate], BackendError?, Duration) {
     jobs.append(job)
+    self.inputs.append(inputs)
     if let failFrom, jobs.count >= failFrom.job { return ([], failFrom.error, .zero) }
     return (script, scriptError, stepDelay)
   }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubKit `53 tests … passed`, HubCore 175, DTBridge `50`, Catalog 6, LLMBridge 6 (totale 290).

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: contratto degli ingressi del tab Control (immagine, forza, inquadratura) e sua traduzione per Draw Things

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Matematica dell'inquadratura e compositore (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Control/FramingMath.swift`, `InputComposer.swift`
- Test: `Packages/Tests/HubCoreTests/FramingTests.swift`

**Interfaces:**
- Consumes: `Framing`, `GenerationParameters.sizeRange` (Task 1 / esistenti).
- Produces (HubCore, `public`):
  - `struct Size: Equatable, Sendable` (`width`, `height`);
  - `enum FramingMath` con `cropRect(imageWidth:imageHeight:canvasWidth:canvasHeight:framing:) -> CGRect` (pixel dell'immagine, origine in alto a sinistra), `loss(imageWidth:imageHeight:canvasWidth:canvasHeight:) -> (axis: Axis?, fraction: Double)` (`Axis`: `.horizontal`, `.vertical`), `adaptedSize(imageWidth:imageHeight:currentWidth:currentHeight:limit:) -> Size`;
  - `enum InputComposer` con `frame(_ image: CGImage, toWidth:height:framing:) -> CGImage?` (immagine alla dimensione esatta del canvas, opaca).

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `Packages/Tests/HubCoreTests/FramingTests.swift`:

```swift
import CoreGraphics
import HubKit
import Testing

@testable import HubCore

struct FramingMathTests {
  func crop(_ iw: Int, _ ih: Int, canvas cw: Int, _ ch: Int, x: Double = 0, y: Double = 0) -> CGRect {
    FramingMath.cropRect(
      imageWidth: iw, imageHeight: ih, canvasWidth: cw, canvasHeight: ch, framing: Framing(offsetX: x, offsetY: y))
  }

  @Test func aSquareImageInA43CanvasLosesAQuarterAboveAndBelow() {
    let rect = crop(1000, 1000, canvas: 1200, 900)
    #expect(rect == CGRect(x: 0, y: 125, width: 1000, height: 750))
    let loss = FramingMath.loss(imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(loss.axis == .vertical)
    #expect(abs(loss.fraction - 0.25) < 0.0001)
  }

  @Test func theOffsetMovesTheCutAlongTheCroppedAxisOnly() {
    #expect(crop(1000, 1000, canvas: 1200, 900, x: 1, y: -1) == CGRect(x: 0, y: 0, width: 1000, height: 750))
    #expect(crop(1000, 1000, canvas: 1200, 900, x: -1, y: 1) == CGRect(x: 0, y: 250, width: 1000, height: 750))
  }

  @Test func aTallImageInA43CanvasLosesMoreThanAThird() {
    let rect = crop(750, 1000, canvas: 1200, 900)
    #expect(rect.width == 750)
    #expect(abs(rect.height - 562.5) < 0.0001)
    let loss = FramingMath.loss(imageWidth: 750, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(loss.axis == .vertical)
    #expect(abs(loss.fraction - 0.4375) < 0.0001)
  }

  @Test func aWideImageInASquareCanvasLosesSidewaysAndTheOffsetFollows() {
    #expect(crop(2000, 1000, canvas: 512, 512) == CGRect(x: 500, y: 0, width: 1000, height: 1000))
    #expect(crop(2000, 1000, canvas: 512, 512, x: -1) == CGRect(x: 0, y: 0, width: 1000, height: 1000))
    #expect(FramingMath.loss(imageWidth: 2000, imageHeight: 1000, canvasWidth: 512, canvasHeight: 512).axis == .horizontal)
  }

  @Test func theSameRatioLosesNothing() {
    #expect(crop(1600, 1200, canvas: 1024, 768) == CGRect(x: 0, y: 0, width: 1600, height: 1200))
    let loss = FramingMath.loss(imageWidth: 1600, imageHeight: 1200, canvasWidth: 1024, canvasHeight: 768)
    #expect(loss.axis == nil)
    #expect(loss.fraction == 0)
  }

  @Test func adaptingKeepsTheAreaAndSnapsTo64() {
    // 1344×1024 = 1 376 256 px²; a square of that area is 1173 px, snapped to 1152.
    #expect(FramingMath.adaptedSize(imageWidth: 800, imageHeight: 800, currentWidth: 1344, currentHeight: 1024) == Size(width: 1152, height: 1152))
    // 3:4 portrait: 1016×1355 → 1024×1344.
    #expect(FramingMath.adaptedSize(imageWidth: 768, imageHeight: 1024, currentWidth: 1344, currentHeight: 1024) == Size(width: 1024, height: 1344))
  }

  @Test func adaptingStaysInsideTheLimits() {
    let wide = FramingMath.adaptedSize(imageWidth: 10_000, imageHeight: 100, currentWidth: 1024, currentHeight: 1024)
    #expect(wide.width <= 2048 && wide.height >= 64)
    let high = FramingMath.adaptedSize(imageWidth: 100, imageHeight: 10_000, currentWidth: 1024, currentHeight: 1024)
    #expect(high.height <= 2048 && high.width >= 64)
    let limited = FramingMath.adaptedSize(imageWidth: 100, imageHeight: 100, currentWidth: 2048, currentHeight: 2048, limit: 1024)
    #expect(limited == Size(width: 1024, height: 1024))
  }
}

struct InputComposerTests {
  /// An image whose left half is red and right half is blue.
  func twoTone(width: Int = 200, height: Int = 100) -> CGImage {
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
    return context.makeImage()!
  }

  /// Red and blue of the pixel at (x, y), counted from the top-left.
  func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, b: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(bytes[0]), Int(bytes[2]))
  }

  @Test func theFramedImageHasTheExactCanvasSize() throws {
    let framed = try #require(InputComposer.frame(twoTone(), toWidth: 128, height: 64, framing: Framing()))
    #expect(framed.width == 128)
    #expect(framed.height == 64)
  }

  @Test func aSquareCanvasShowsTheLeftOrTheRightHalfAccordingToTheOffset() throws {
    let left = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing(offsetX: -1)))
    #expect(pixel(left, 5, 32).r > 250 && pixel(left, 58, 32).r > 250)
    let right = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing(offsetX: 1)))
    #expect(pixel(right, 5, 32).b > 250 && pixel(right, 58, 32).b > 250)
    let centered = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing()))
    #expect(pixel(centered, 5, 32).r > 250)
    #expect(pixel(centered, 58, 32).b > 250)
  }

  @Test func theFramedImageIsOpaque() throws {
    let framed = try #require(InputComposer.frame(twoTone(), toWidth: 64, height: 64, framing: Framing()))
    #expect(framed.alphaInfo == .noneSkipLast || framed.alphaInfo == .premultipliedLast)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'FramingMath' in scope`.

- [ ] **Step 3: Implementare**

Creare `Packages/Sources/HubCore/Control/FramingMath.swift` (il ritaglio parte da un lato, lo spostamento -1…1 divide l'avanzo sull'asse ritagliato; `adaptedSize` mantiene l'area e arrotonda a 64) e `InputComposer.swift` (disegna l'immagine in un contesto opaco alla dimensione del canvas):

```swift
import CoreGraphics
import Foundation
import HubKit

/// A width and a height in pixels.
public struct Size: Equatable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }
}

/// How a start image is cut to fill the canvas, and what that costs (tab Control spec §5).
public enum FramingMath {
  public enum Axis: Equatable, Sendable {
    case horizontal
    case vertical
  }

  /// The part of the image, in its pixels counted from the top-left, that fills the canvas
  /// ("fill"): the whole image on the axis that fits, a cut on the other, placed by the offset.
  public static func cropRect(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
  ) -> CGRect {
    let iw = Double(imageWidth)
    let ih = Double(imageHeight)
    let canvasRatio = Double(canvasWidth) / Double(max(canvasHeight, 1))
    let imageRatio = iw / max(ih, 1)
    let offset = framing.clamped()
    if imageRatio > canvasRatio {
      let width = ih * canvasRatio
      return CGRect(x: (iw - width) * (1 + offset.offsetX) / 2, y: 0, width: width, height: ih)
    }
    if imageRatio < canvasRatio {
      let height = iw / canvasRatio
      return CGRect(x: 0, y: (ih - height) * (1 + offset.offsetY) / 2, width: iw, height: height)
    }
    return CGRect(x: 0, y: 0, width: iw, height: ih)
  }

  /// The share of the image that falls outside the canvas, and on which axis (nil when none).
  public static func loss(
    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int
  ) -> (axis: Axis?, fraction: Double) {
    let rect = cropRect(
      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      framing: Framing())
    let horizontal = 1 - rect.width / Double(imageWidth)
    let vertical = 1 - rect.height / Double(imageHeight)
    if horizontal > 0.000_001 { return (.horizontal, horizontal) }
    if vertical > 0.000_001 { return (.vertical, vertical) }
    return (nil, 0)
  }

  /// "Adapt the dimensions": the image's ratio, the area of the current canvas, both sides
  /// multiples of 64 and within 64…`limit`.
  public static func adaptedSize(
    imageWidth: Int, imageHeight: Int, currentWidth: Int, currentHeight: Int,
    limit: Int = GenerationParameters.sizeRange.upperBound
  ) -> Size {
    let ratio = Double(imageWidth) / Double(max(imageHeight, 1))
    let area = Double(currentWidth * currentHeight)
    let height = (area / ratio).squareRoot()
    let width = ratio * height
    func snap(_ value: Double) -> Int { min(max(Int((value / 64).rounded()) * 64, 64), limit) }
    return Size(width: snap(width), height: snap(height))
  }
}
```

```swift
import CoreGraphics
import HubKit

/// Prepares the Control tab's images for a RUN (tab Control spec §6).
public enum InputComposer {
  /// The start image cut and scaled to the exact canvas size, opaque. nil when the context cannot
  /// be made (a size of zero).
  public static func frame(_ image: CGImage, toWidth width: Int, height: Int, framing: Framing) -> CGImage? {
    guard width > 0, height > 0 else { return nil }
    let crop = FramingMath.cropRect(
      imageWidth: image.width, imageHeight: image.height, canvasWidth: width, canvasHeight: height, framing: framing)
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.interpolationQuality = .high
    // The image drawn so that the cut fills the canvas (Core Graphics counts from the bottom-left).
    let scale = Double(width) / crop.width
    let drawn = CGRect(
      x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
      width: Double(image.width) * scale, height: Double(image.height) * scale)
    context.draw(image, in: drawn)
    return context.makeImage()
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `185 tests … passed` (175 + 7 + 3), gli altri invariati.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: matematica dell'inquadratura e compositore dell'immagine di partenza

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Copie su disco, store con annulla e persistenza (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Control/ReferenceStorage.swift`, `ControlStore.swift`
- Test: `Packages/Tests/HubCoreTests/ControlStoreTests.swift`

**Interfaces:**
- Consumes: `ReferenceImage`, `Framing`, `ControlInputs`, `GenerationInputs` (Task 1); `FramingMath`, `InputComposer` (Task 2).
- Produces (HubCore, `public`):
  - `enum ControlError: Error, Equatable, Sendable { unreadable(String), cannotSave(String) }`;
  - `protocol ReferenceStorage: Sendable` (`save(_:name:) throws(ControlError) -> StoredPicture`, `image(named:maxPixel:) -> CGImage?`, `exists(_:)`, `remove(_:)`, `allFileNames()`) e `struct FileReferenceStorage` (`init(folder:)`, `static var defaultFolder: URL`);
  - `enum ControlNotice: Equatable, Sendable { removed(name:), replaced(name:), cleared, missingAtLaunch(name:) }`; `enum ControlWarning: Hashable, Sendable { strongCrop(percent: Int) }`;
  - `@MainActor @Observable final class ControlStore` — `init(storage:fileURL:undoLimit:)`, `static var defaultFileURL: URL`, `inputs: ControlInputs`, `notice: ControlNotice?`, `canUndo`, `canRedo`; `setImage(data:name:source:) throws(ControlError)`, `setImage(_ image: CGImage, name:source:) throws(ControlError)`, `setImage(fileURL:source:) async throws(ControlError)` (source predefinita = il file), `removeImage()`, `clear()`, `setStrength(_:)`, `setOffset(x:y:)`, `undo()`, `redo()`, `dismissNotice()`, `preview(maxPixel:) -> CGImage?`, `warnings(canvasWidth:canvasHeight:) -> [ControlWarning]`, `pendingInputs(canvasWidth:canvasHeight:) -> PendingInputs`;
  - `struct PendingInputs: Sendable` con `render() throws(ControlError) -> GenerationInputs` (decodifica alla scala del canvas e inquadra; senza immagine: `.none`).

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `Packages/Tests/HubCoreTests/ControlStoreTests.swift`:

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HubCore

/// PNG (or JPEG) bytes of a solid picture; `orientation` is the EXIF orientation to write.
func pictureData(width: Int, height: Int, type: UTType = .png, orientation: Int? = nil) -> Data {
  let context = CGContext(
    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
  var properties: [CFString: Any] = [:]
  if let orientation { properties[kCGImagePropertyOrientation] = orientation }
  CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
  CGImageDestinationFinalize(destination)
  return data as Data
}

@MainActor
struct ControlStoreTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL, undoLimit: Int = 20) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"), undoLimit: undoLimit)
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  @Test func anImageIsCopiedAndDescribed() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 300, height: 200), name: "cat.png", source: .file(path: "/x/cat.png"))
    let image = try #require(store.inputs.image)
    #expect(image.pixelWidth == 300 && image.pixelHeight == 200)
    #expect(image.name == "cat.png")
    #expect(image.source == .file(path: "/x/cat.png"))
    #expect(copies(in: root) == [image.fileName])
    #expect(image.fileName.hasSuffix(".png"))
  }

  @Test func theSizeFollowsTheExifOrientation() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 300, height: 200, type: .jpeg, orientation: 6), name: "p.jpg", source: .pasteboard)
    #expect(store.inputs.image?.pixelWidth == 200)
    #expect(store.inputs.image?.pixelHeight == 300)
  }

  @Test func anUnreadableFileIsRefusedAndLeavesNothing() throws {
    let root = folder()
    let store = store(in: root)
    #expect(throws: ControlError.unreadable("notes.txt")) {
      try store.setImage(data: Data("not an image".utf8), name: "notes.txt", source: .pasteboard)
    }
    #expect(store.inputs.image == nil)
    #expect(copies(in: root).isEmpty)
  }

  @Test func removingAnImageCanBeUndoneAndRedone() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    let image = try #require(store.inputs.image)
    store.removeImage()
    #expect(store.inputs.image == nil)
    #expect(store.notice == .removed(name: "a.png"))
    #expect(store.canUndo)
    store.undo()
    #expect(store.inputs.image == image)
    #expect(store.canRedo)
    store.redo()
    #expect(store.inputs.image == nil)
  }

  @Test func replacingKeepsTheOldCopyWhileItCanBeUndoneAndDropsItAfterwards() throws {
    let root = folder()
    let store = store(in: root, undoLimit: 2)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "one.png", source: .pasteboard)
    let first = try #require(store.inputs.image)
    try store.setImage(data: pictureData(width: 32, height: 32), name: "two.png", source: .pasteboard)
    #expect(store.notice == .replaced(name: "one.png"))
    #expect(copies(in: root).count == 2)
    store.undo()
    #expect(store.inputs.image == first)
    store.redo()
    // Two more changes push the first state out of the history: its copy goes away.
    try store.setImage(data: pictureData(width: 16, height: 16), name: "three.png", source: .pasteboard)
    try store.setImage(data: pictureData(width: 8, height: 8), name: "four.png", source: .pasteboard)
    #expect(!copies(in: root).contains(first.fileName))
  }

  @Test func clearingRemovesEverythingTheTabHolds() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    store.setStrength(0.3)
    store.setOffset(x: 0.5, y: -0.5)
    store.clear()
    #expect(store.inputs == ControlInputs())
    #expect(store.notice == .cleared)
    store.undo()
    #expect(store.inputs.image?.name == "a.png")
    #expect(store.inputs.strength == 0.3)
  }

  @Test func strengthAndOffsetAreClampedAndNewImagesStartCentered() throws {
    let store = store(in: folder())
    store.setStrength(7)
    #expect(store.inputs.strength == 1)
    store.setStrength(nil)
    #expect(store.inputs.strength == nil)
    store.setOffset(x: 9, y: -9)
    #expect(store.inputs.framing == Framing(offsetX: 1, offsetY: -1))
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    #expect(store.inputs.framing == Framing())
  }

  @Test func everythingComesBackAtTheNextLaunch() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "a.png", source: .result)
    first.setStrength(0.4)
    first.setOffset(x: 0.25, y: 0)
    let second = store(in: root)
    #expect(second.inputs == first.inputs)
    #expect(second.notice == nil)
    #expect(!second.canUndo)
  }

  @Test func aMissingCopyIsDroppedWithANotice() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "gone.png", source: .pasteboard)
    first.setStrength(0.4)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control/\(try #require(first.inputs.image).fileName)"))
    let second = store(in: root)
    #expect(second.inputs.image == nil)
    #expect(second.notice == .missingAtLaunch(name: "gone.png"))
    #expect(second.inputs.strength == 0.4)
  }

  @Test func strayFilesAreSweptAtLaunch() throws {
    let root = folder()
    let first = store(in: root)
    try first.setImage(data: pictureData(width: 90, height: 60), name: "a.png", source: .pasteboard)
    let kept = try #require(first.inputs.image).fileName
    try Data(count: 10).write(to: root.appendingPathComponent("Control/orphan.png"))
    _ = store(in: root)
    #expect(copies(in: root) == [kept])
  }

  @Test func aStrongCropIsReported() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 750, height: 1000), name: "tall.png", source: .pasteboard)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900) == [.strongCrop(percent: 44)])
    try store.setImage(data: pictureData(width: 1000, height: 1000), name: "square.png", source: .pasteboard)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)  // 25 %: below a third
    #expect(store.warnings(canvasWidth: 1000, canvasHeight: 1000).isEmpty)
  }

  @Test func anImageInMemoryBecomesAPNGCopy() throws {
    let root = folder()
    let store = store(in: root)
    let source = try #require(CGImageSourceCreateWithData(pictureData(width: 40, height: 30) as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    try store.setImage(image, name: "result.png", source: .result)
    #expect(store.inputs.image?.pixelWidth == 40)
    #expect(copies(in: root).count == 1)
  }

  @Test func aFileFromResultsKeepsItsSourceAndAnUnreadableOneIsReported() async throws {
    let root = folder()
    let store = store(in: root)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("made.png")
    try pictureData(width: 50, height: 40).write(to: file)
    try await store.setImage(fileURL: file, source: .result)
    #expect(store.inputs.image?.source == .result)
    try await store.setImage(fileURL: file)
    #expect(store.inputs.image?.source == .file(path: file.path))
    await #expect(throws: ControlError.unreadable("missing.png")) {
      try await store.setImage(fileURL: root.appendingPathComponent("missing.png"))
    }
  }

  @Test func thePreviewIsDecodedSmallAndOnlyForAnExistingImage() throws {
    let store = store(in: folder())
    #expect(store.preview(maxPixel: 100) == nil)
    try store.setImage(data: pictureData(width: 800, height: 400), name: "a.png", source: .pasteboard)
    let preview = try #require(store.preview(maxPixel: 100))
    #expect(preview.width == 100 && preview.height == 50)
  }

  @Test func theRunGetsTheImageFramedToTheCanvas() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 600, height: 400), name: "a.png", source: .pasteboard)
    let framed = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().image)
    #expect(framed.width == 256 && framed.height == 256)
    let empty = ControlStore(storage: FileReferenceStorage(folder: folder()), fileURL: folder().appendingPathComponent("c.json"))
    #expect(try empty.pendingInputs(canvasWidth: 64, canvasHeight: 64).render().isEmpty)
  }

  @Test func aBigPhotoAndATinyPictureBothFillTheCanvas() throws {
    let store = store(in: folder())
    try store.setImage(data: pictureData(width: 3000, height: 2000), name: "big.png", source: .pasteboard)
    let reduced = try #require(try store.pendingInputs(canvasWidth: 256, canvasHeight: 256).render().image)
    #expect(reduced.width == 256 && reduced.height == 256)
    try store.setImage(data: pictureData(width: 40, height: 30), name: "tiny.png", source: .pasteboard)
    let enlarged = try #require(try store.pendingInputs(canvasWidth: 512, canvasHeight: 384).render().image)
    #expect(enlarged.width == 512 && enlarged.height == 384)
  }

  @Test func aCopyThatVanishedBeforeTheRunIsReported() throws {
    let root = folder()
    let store = store(in: root)
    try store.setImage(data: pictureData(width: 64, height: 64), name: "a.png", source: .pasteboard)
    try FileManager.default.removeItem(at: root.appendingPathComponent("Control/\(try #require(store.inputs.image).fileName)"))
    #expect(throws: ControlError.unreadable("a.png")) { try store.pendingInputs(canvasWidth: 64, canvasHeight: 64).render() }
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find type 'ControlStore' in scope`.

- [ ] **Step 3: Implementare**

Creare `ReferenceStorage.swift` (la lettura delle dimensioni e dell'orientamento con ImageIO; la miniatura con `kCGImageSourceCreateThumbnailWithTransform`) e `ControlStore.swift` (cronologia di istantanee del valore `ControlInputs`, pulizia delle copie non referenziate dopo ogni cambiamento, salvataggio atomico di `control.json`):

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why an image could not be taken into the Control tab.
public enum ControlError: Error, Equatable, Sendable {
  /// The file is not an image the system can read; the detail is its name.
  case unreadable(String)
  /// The copy could not be written (disk full, folder not writable); the detail says why.
  case cannotSave(String)
}

/// A copy that was just written.
public struct StoredPicture: Equatable, Sendable {
  public let fileName: String
  public let pixelWidth: Int
  public let pixelHeight: Int
}

/// Where the copies of the Control tab's images live (tab Control spec §4). The real one is a
/// folder; tests may use another.
public protocol ReferenceStorage: Sendable {
  /// Reads the picture's size (orientation applied) and writes a copy of the bytes as they are.
  func save(_ data: Data, name: String) throws(ControlError) -> StoredPicture
  /// The picture decoded with its longest side at most `maxPixel`, orientation applied.
  func image(named fileName: String, maxPixel: Int) -> CGImage?
  func exists(_ fileName: String) -> Bool
  func remove(_ fileName: String)
  func allFileNames() -> [String]
}

/// Copies in `~/Library/Application Support/DT Hub/Control/`.
public struct FileReferenceStorage: ReferenceStorage {
  public let folder: URL

  public init(folder: URL) {
    self.folder = folder
  }

  public static var defaultFolder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("Control", isDirectory: true)
  }

  public func save(_ data: Data, name: String) throws(ControlError) -> StoredPicture {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
    else { throw .unreadable(name) }
    // EXIF orientations 5…8 turn the picture on its side: the size shown is the turned one.
    let turned = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
    let type = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
    let fileName = "\(UUID().uuidString).\(type?.preferredFilenameExtension ?? "img")"
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
    } catch {
      throw .cannotSave(error.localizedDescription)
    }
    return StoredPicture(fileName: fileName, pixelWidth: turned ? height : width, pixelHeight: turned ? width : height)
  }

  public func image(named fileName: String, maxPixel: Int) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(fileName) as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(maxPixel, 1),
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  }

  public func exists(_ fileName: String) -> Bool {
    FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
  }

  public func remove(_ fileName: String) {
    try? FileManager.default.removeItem(at: folder.appendingPathComponent(fileName))
  }

  public func allFileNames() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
  }
}
```

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// What the Control tab says about the last change; the app shows it as a message, with
/// "Undo" where the change can be undone.
public enum ControlNotice: Equatable, Sendable {
  case removed(name: String)
  case replaced(name: String)
  case cleared
  /// At launch the copy of the saved image was gone.
  case missingAtLaunch(name: String)
}

/// A reason to look before pressing RUN; shown in the strip.
public enum ControlWarning: Hashable, Sendable {
  /// The framing cuts off this much of the image (more than a third).
  case strongCrop(percent: Int)
}

/// The Control tab's inputs, kept and saved (tab Control spec §4): the start image with its
/// framing and strength, the copies on disk, the history for Undo.
@MainActor
@Observable
public final class ControlStore {
  public private(set) var inputs: ControlInputs
  public private(set) var notice: ControlNotice?

  @ObservationIgnored private let storage: any ReferenceStorage
  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let undoLimit: Int
  @ObservationIgnored private var undoStack: [ControlInputs] = []
  @ObservationIgnored private var redoStack: [ControlInputs] = []

  /// Restores `fileURL` (an image whose copy is gone is dropped, with a notice) and sweeps the
  /// copies nothing refers to.
  public init(storage: any ReferenceStorage, fileURL: URL, undoLimit: Int = 20) {
    self.storage = storage
    self.fileURL = fileURL
    self.undoLimit = undoLimit
    var loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(ControlInputs.self, from: $0) }
      ?? ControlInputs()
    if let image = loaded.image, !storage.exists(image.fileName) {
      loaded.image = nil
      loaded.framing = Framing()
      notice = .missingAtLaunch(name: image.name)
    }
    inputs = loaded
    save()
    collectGarbage()
  }

  /// ~/Library/Application Support/DT Hub/control.json.
  public static var defaultFileURL: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("DT Hub", isDirectory: true)
      .appendingPathComponent("control.json")
  }

  public var canUndo: Bool { !undoStack.isEmpty }
  public var canRedo: Bool { !redoStack.isEmpty }

  // MARK: Image

  /// Takes a picture from its bytes: copies it, describes it, and makes it the start image
  /// (the one there was, if any, can be brought back with `undo`). The framing starts centered.
  public func setImage(data: Data, name: String, source: ReferenceImage.Source) throws(ControlError) {
    let stored = try storage.save(data, name: name)
    let image = ReferenceImage(
      id: UUID(), name: name, pixelWidth: stored.pixelWidth, pixelHeight: stored.pixelHeight, source: source,
      fileName: stored.fileName)
    var next = inputs
    next.image = image
    next.framing = Framing()
    let replaced = inputs.image
    commit(next)
    notice = replaced.map { .replaced(name: $0.name) }
  }

  /// A picture that only exists in memory (a result that could not be saved): stored as PNG.
  public func setImage(_ image: CGImage, name: String, source: ReferenceImage.Source) throws(ControlError) {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw .cannotSave(name) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw .cannotSave(name) }
    try setImage(data: data as Data, name: name, source: source)
  }

  /// Takes a file (from the Finder, or an image the Results window saved); reads it away from
  /// the main actor. `source` defaults to the file itself.
  public func setImage(fileURL url: URL, source: ReferenceImage.Source? = nil) async throws(ControlError) {
    let name = url.lastPathComponent
    let data = await Task.detached { try? Data(contentsOf: url) }.value
    guard let data else { throw .unreadable(name) }
    try setImage(data: data, name: name, source: source ?? .file(path: url.path))
  }

  public func removeImage() {
    guard let image = inputs.image else { return }
    var next = inputs
    next.image = nil
    next.framing = Framing()
    commit(next)
    notice = .removed(name: image.name)
  }

  /// Takes everything out of the tab.
  public func clear() {
    guard inputs != ControlInputs() else { return }
    commit(ControlInputs())
    notice = .cleared
  }

  // MARK: Strength and framing (not part of the history)

  /// nil goes back to the automatic strength.
  public func setStrength(_ value: Double?) {
    inputs.strength = value.map { min(1, max(0, $0)) }
    save()
  }

  public func setOffset(x: Double, y: Double) {
    inputs.framing = Framing(mode: inputs.framing.mode, offsetX: x, offsetY: y).clamped()
    save()
  }

  // MARK: History

  public func undo() {
    guard let previous = undoStack.popLast() else { return }
    redoStack.append(inputs)
    inputs = previous
    notice = nil
    save()
    collectGarbage()
  }

  public func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(inputs)
    inputs = next
    notice = nil
    save()
    collectGarbage()
  }

  public func dismissNotice() {
    notice = nil
  }

  /// The start image decoded for the screen, its longest side at most `maxPixel`.
  public func preview(maxPixel: Int) -> CGImage? {
    guard let image = inputs.image else { return nil }
    return storage.image(named: image.fileName, maxPixel: maxPixel)
  }

  // MARK: Warnings and RUN

  public func warnings(canvasWidth: Int, canvasHeight: Int) -> [ControlWarning] {
    guard let image = inputs.image else { return [] }
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
    return loss.fraction > 1.0 / 3.0 ? [.strongCrop(percent: Int((loss.fraction * 100).rounded()))] : []
  }

  /// What a RUN needs to prepare its inputs, to be rendered away from the main actor.
  public func pendingInputs(canvasWidth: Int, canvasHeight: Int) -> PendingInputs {
    PendingInputs(
      storage: storage, image: inputs.image, framing: inputs.framing, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
  }

  // MARK: Private

  private func commit(_ next: ControlInputs) {
    undoStack.append(inputs)
    if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
    redoStack = []
    inputs = next
    notice = nil
    save()
    collectGarbage()
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(inputs).write(to: fileURL, options: .atomic)
    } catch {
      // A failed save only loses the restore at the next launch.
    }
  }

  /// Deletes the copies that neither the inputs nor the history refer to.
  private func collectGarbage() {
    var referenced = Set<String>()
    for state in undoStack + redoStack + [inputs] {
      if let image = state.image { referenced.insert(image.fileName) }
    }
    for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
  }
}

/// The start image and canvas of a RUN, ready to be framed on a background thread.
public struct PendingInputs: Sendable {
  let storage: any ReferenceStorage
  let image: ReferenceImage?
  let framing: Framing
  let canvasWidth: Int
  let canvasHeight: Int

  /// Decodes the copy at the size the canvas needs (a 50-megapixel photo is not decoded whole)
  /// and frames it. No image: the RUN is text-to-image.
  public func render() throws(ControlError) -> GenerationInputs {
    guard let image else { return .none }
    let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
    let longest = max(image.pixelWidth, image.pixelHeight)
    let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
    guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
      let framed = InputComposer.frame(decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing)
    else { throw .unreadable(image.name) }
    return GenerationInputs(image: framed)
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `202 tests … passed` (185 + 17).

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: ControlStore — copie delle immagini, annulla, ripristino e avvisi

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Tab nella barra e collegamento al RUN (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Workspace/WorkspaceTab.swift`, `WorkspaceState.swift`
- Modify: `Packages/Sources/HubCore/Generation/JobComposer.swift`, `GenerationSession.swift`
- Test: `Packages/Tests/HubCoreTests/WorkspaceStateTests.swift` (riscritto), `FamilyTraitsTests.swift`, `GenerationSessionTests.swift`

**Interfaces:**
- Consumes: `GenerationInputs`, `GenerationJob.imageStrength` (Task 1).
- Produces:
  - `WorkspaceTab.controlID = "control"`; `WorkspaceState.init(controlTab:generationTab:defaults:)`, `tabs = [controlTab, generationTab] + plug-in`, `WorkspaceState.selectedTabKey = "workspace.selectedTab"` (si apre l'ultimo tab usato se è Control, altrimenti Generazione);
  - `JobComposer.batches(…, imageStrength: Double? = nil, randomSeed:)`: ogni job porta la forza;
  - `GenerationSession.start(_ batches:, inputs: GenerationInputs = .none, backend:, monitor:)` e `fail(with: BackendError)`.

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/HubCoreTests/WorkspaceStateTests.swift b/Packages/Tests/HubCoreTests/WorkspaceStateTests.swift
index 3b379e6..dc3e210 100644
--- a/Packages/Tests/HubCoreTests/WorkspaceStateTests.swift
+++ b/Packages/Tests/HubCoreTests/WorkspaceStateTests.swift
@@ -1,41 +1,49 @@
+import Foundation
 import Testing
 
 @testable import HubCore
 
 @MainActor
 struct WorkspaceStateTests {
+  let control = WorkspaceTab(id: WorkspaceTab.controlID, title: "Control", systemImage: "photo.on.rectangle")
   let generation = WorkspaceTab(
     id: WorkspaceTab.generationID, title: "Generation", systemImage: "slider.horizontal.3")
   let promptMaster = WorkspaceTab(id: "promptmaster", title: "Prompt Master", systemImage: "text.quote")
   let sphereLight = WorkspaceTab(id: "spherelight", title: "Sphere Light", systemImage: "circle.lefthalf.filled")
 
-  @Test func startsWithOnlyGenerationSelected() {
-    let state = WorkspaceState(generationTab: generation)
-    #expect(state.tabs == [generation])
+  func state(_ defaults: UserDefaults? = nil) -> WorkspaceState {
+    WorkspaceState(
+      controlTab: control, generationTab: generation,
+      defaults: defaults ?? UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!)
+  }
+
+  @Test func controlComesBeforeGenerationAndGenerationIsSelectedAtFirst() {
+    let state = state()
+    #expect(state.tabs == [control, generation])
     #expect(state.selectedTabID == WorkspaceTab.generationID)
   }
 
   @Test func pluginTabsFollowGenerationInOrder() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     state.setPluginTabs([promptMaster, sphereLight])
-    #expect(state.tabs == [generation, promptMaster, sphereLight])
+    #expect(state.tabs == [control, generation, promptMaster, sphereLight])
   }
 
   @Test func selectsAPluginTab() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     state.setPluginTabs([promptMaster])
     state.select(promptMaster.id)
     #expect(state.selectedTabID == promptMaster.id)
   }
 
   @Test func ignoresSelectionOfUnknownTab() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     state.select("missing")
     #expect(state.selectedTabID == WorkspaceTab.generationID)
   }
 
   @Test func fallsBackToGenerationWhenSelectedTabIsRemoved() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     state.setPluginTabs([promptMaster, sphereLight])
     state.select(sphereLight.id)
     state.setPluginTabs([promptMaster])
@@ -43,24 +51,39 @@ struct WorkspaceStateTests {
   }
 
   @Test func keepsSelectionWhenSelectedTabSurvives() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     state.setPluginTabs([promptMaster])
     state.select(promptMaster.id)
     state.setPluginTabs([promptMaster, sphereLight])
     #expect(state.selectedTabID == promptMaster.id)
   }
 
-  @Test func pluginCannotReplaceGenerationTab() {
-    let state = WorkspaceState(generationTab: generation)
-    let impostor = WorkspaceTab(id: WorkspaceTab.generationID, title: "Fake", systemImage: "xmark")
-    state.setPluginTabs([impostor, promptMaster])
-    #expect(state.tabs == [generation, promptMaster])
+  @Test func pluginCannotReplaceTheBuiltInTabs() {
+    let state = state()
+    let fakeGeneration = WorkspaceTab(id: WorkspaceTab.generationID, title: "Fake", systemImage: "xmark")
+    let fakeControl = WorkspaceTab(id: WorkspaceTab.controlID, title: "Fake", systemImage: "xmark")
+    state.setPluginTabs([fakeGeneration, fakeControl, promptMaster])
+    #expect(state.tabs == [control, generation, promptMaster])
   }
 
   @Test func duplicatePluginIDsKeepTheFirst() {
-    let state = WorkspaceState(generationTab: generation)
+    let state = state()
     let duplicate = WorkspaceTab(id: promptMaster.id, title: "Other", systemImage: "xmark")
     state.setPluginTabs([promptMaster, duplicate])
-    #expect(state.tabs == [generation, promptMaster])
+    #expect(state.tabs == [control, generation, promptMaster])
+  }
+
+  @Test func theLastTabUsedOpensAtTheNextLaunch() {
+    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
+    let first = state(defaults)
+    first.select(WorkspaceTab.controlID)
+    let second = state(defaults)
+    #expect(second.selectedTabID == WorkspaceTab.controlID)
+  }
+
+  @Test func aSavedTabThatNoLongerExistsOpensGeneration() {
+    let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
+    defaults.set("promptmaster", forKey: WorkspaceState.selectedTabKey)
+    #expect(state(defaults).selectedTabID == WorkspaceTab.generationID)
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
index 6e7df54..d86944b 100644
--- a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
+++ b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
@@ -68,6 +68,16 @@ struct JobComposerTests {
       parameters: parameters, catalog: catalog) { 7 }
   }
 
+  @Test func everyBatchRecordsTheStrengthOfTheStartImage() {
+    let parameters = GenerationParameters(batchCount: 2)
+    let withImage = JobComposer.batches(
+      prompt: "fox", negativePrompt: "", model: "m.ckpt", family: nil, parameters: parameters,
+      catalog: catalog, imageStrength: 0.6) { 7 }
+    #expect(withImage.count == 2)
+    #expect(withImage.allSatisfy { $0.imageStrength == 0.6 })
+    #expect(compose(family: nil, parameters).allSatisfy { $0.imageStrength == nil })
+  }
+
   @Test func sendsOnlyTheUsableLoRAs() {
     let parameters = GenerationParameters(loras: [
       LoRASelection(file: "a.safetensors", weight: 0.8), LoRASelection(file: "q.safetensors"),
```

```diff
diff --git a/Packages/Tests/HubCoreTests/GenerationSessionTests.swift b/Packages/Tests/HubCoreTests/GenerationSessionTests.swift
index 44e16b6..18af3ad 100644
--- a/Packages/Tests/HubCoreTests/GenerationSessionTests.swift
+++ b/Packages/Tests/HubCoreTests/GenerationSessionTests.swift
@@ -34,6 +34,31 @@ struct GenerationSessionTests {
     return monitor
   }
 
+  @Test func theBackendReceivesTheControlInputsOfEveryBatch() async {
+    let backend = FakeBackend(.success(catalog))
+    await backend.setGeneration([.finished([testImage()])])
+    let monitor = await connected(backend)
+    let session = GenerationSession(store: MemoryImageStore())
+    let start = testImage(width: 16, height: 16)
+    session.start([job, job], inputs: GenerationInputs(image: start), backend: backend, monitor: monitor)
+    await session.waitUntilFinished()
+    let received = await backend.inputs
+    #expect(received.count == 2)
+    #expect(received.allSatisfy { $0.image === start })
+    session.start(job, backend: backend, monitor: monitor)
+    await session.waitUntilFinished()
+    #expect(await backend.inputs.last?.isEmpty == true)
+  }
+
+  @Test func aRunThatCannotStartCanBeReportedAsAFailure() {
+    let session = GenerationSession(store: MemoryImageStore())
+    session.fail(with: .generationFailed("The start image could not be read"))
+    #expect(session.phase == .failed(.generationFailed("The start image could not be read")))
+    #expect(!session.isRunning)
+    session.dismissFailure()
+    #expect(session.phase == .idle)
+  }
+
   @Test func runsAGenerationAndKeepsTheSavedImages() async {
     let backend = FakeBackend(.success(catalog))
     await backend.setGeneration([.progress(step: nil, totalSteps: 4), .progress(step: 2, totalSteps: 4), .finished([testImage(), testImage()])])
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "<repo>/Packages" && swift test --filter HubCoreTests 2>&1 | grep -E "error:" | head -3`
Expected: errori di compilazione (`WorkspaceTab` non ha `controlID`, `extra arguments` su `JobComposer.batches`, `GenerationSession` non ha `fail`).

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Workspace/WorkspaceTab.swift b/Packages/Sources/HubCore/Workspace/WorkspaceTab.swift
index 82f18ee..7c5e5be 100644
--- a/Packages/Sources/HubCore/Workspace/WorkspaceTab.swift
+++ b/Packages/Sources/HubCore/Workspace/WorkspaceTab.swift
@@ -1,6 +1,7 @@
 /// One entry of the tab bar under the header.
 public struct WorkspaceTab: Identifiable, Equatable, Sendable {
-  /// Identifier of the built-in Generation tab, the only tab the app ships with.
+  /// Identifiers of the two built-in tabs, Control and Generation.
+  public static let controlID = "control"
   public static let generationID = "generation"
 
   public let id: String
```

```diff
diff --git a/Packages/Sources/HubCore/Workspace/WorkspaceState.swift b/Packages/Sources/HubCore/Workspace/WorkspaceState.swift
index 2535a3c..d184bd9 100644
--- a/Packages/Sources/HubCore/Workspace/WorkspaceState.swift
+++ b/Packages/Sources/HubCore/Workspace/WorkspaceState.swift
@@ -1,34 +1,45 @@
+import Foundation
 import Observation
 
-/// The tab bar under the header: the built-in Generation tab first, then one tab
-/// per active plug-in, in activation order (spec §7).
+/// The tab bar under the header: the built-in Control and Generation tabs first, then one tab
+/// per active plug-in, in activation order (spec §7, tab Control spec §3).
 @MainActor
 @Observable
 public final class WorkspaceState {
+  public static let selectedTabKey = "workspace.selectedTab"
+
+  public let controlTab: WorkspaceTab
   public let generationTab: WorkspaceTab
   public private(set) var pluginTabs: [WorkspaceTab] = []
   public private(set) var selectedTabID: WorkspaceTab.ID
 
-  public init(generationTab: WorkspaceTab) {
+  @ObservationIgnored private let defaults: UserDefaults
+
+  /// Opens the tab used last, when it still exists; otherwise Generation.
+  public init(controlTab: WorkspaceTab, generationTab: WorkspaceTab, defaults: UserDefaults = .standard) {
+    self.controlTab = controlTab
     self.generationTab = generationTab
-    self.selectedTabID = generationTab.id
+    self.defaults = defaults
+    let saved = defaults.string(forKey: Self.selectedTabKey)
+    selectedTabID = saved == controlTab.id ? controlTab.id : generationTab.id
   }
 
-  public var tabs: [WorkspaceTab] { [generationTab] + pluginTabs }
+  public var tabs: [WorkspaceTab] { [controlTab, generationTab] + pluginTabs }
 
-  /// Replaces the plug-in tabs. A tab reusing the Generation id, or an id already
-  /// listed, is dropped. If the selected tab disappears, Generation is selected.
+  /// Replaces the plug-in tabs. A tab reusing a built-in id, or an id already listed, is
+  /// dropped. If the selected tab disappears, Generation is selected.
   public func setPluginTabs(_ newTabs: [WorkspaceTab]) {
-    var seen: Set<WorkspaceTab.ID> = [generationTab.id]
+    var seen: Set<WorkspaceTab.ID> = [controlTab.id, generationTab.id]
     pluginTabs = newTabs.filter { seen.insert($0.id).inserted }
     if !tabs.contains(where: { $0.id == selectedTabID }) {
       selectedTabID = generationTab.id
     }
   }
 
-  /// Selects a tab; an id that is not in the bar is ignored.
+  /// Selects a tab (and remembers it); an id that is not in the bar is ignored.
   public func select(_ id: WorkspaceTab.ID) {
     guard tabs.contains(where: { $0.id == id }) else { return }
     selectedTabID = id
+    defaults.set(id, forKey: Self.selectedTabKey)
   }
 }
```

```diff
diff --git a/Packages/Sources/HubCore/Generation/JobComposer.swift b/Packages/Sources/HubCore/Generation/JobComposer.swift
index 5d1ee0c..3763eb8 100644
--- a/Packages/Sources/HubCore/Generation/JobComposer.swift
+++ b/Packages/Sources/HubCore/Generation/JobComposer.swift
@@ -8,7 +8,7 @@ import HubKit
 public enum JobComposer {
   public static func batches(
     prompt: String, negativePrompt: String, model: String, family: String?,
-    parameters: GenerationParameters, catalog: ModelCatalog,
+    parameters: GenerationParameters, catalog: ModelCatalog, imageStrength: Double? = nil,
     randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
   ) -> [GenerationJob] {
     let traits = FamilyTraits.of(family)
@@ -18,7 +18,8 @@ public enum JobComposer {
     sent.advanced = advanced(parameters, model: catalog.model(forFile: model), catalog: catalog)
     let negative = traits.usesNegativePrompt ? negativePrompt : ""
     return sent.batchesForRun(randomSeed: draw).map {
-      GenerationJob(prompt: prompt, negativePrompt: negative, model: model, parameters: $0)
+      GenerationJob(
+        prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength)
     }
   }
 
```

```diff
diff --git a/Packages/Sources/HubCore/Generation/GenerationSession.swift b/Packages/Sources/HubCore/Generation/GenerationSession.swift
index 5c1594f..1a2921f 100644
--- a/Packages/Sources/HubCore/Generation/GenerationSession.swift
+++ b/Packages/Sources/HubCore/Generation/GenerationSession.swift
@@ -60,8 +60,12 @@ public final class GenerationSession {
   }
 
   /// Starts a RUN made of batches, run one after the other (see `batchesForRun`); ignored
-  /// while one is running. The monitor's checks pause meanwhile.
-  public func start(_ batches: [GenerationJob], backend: any GenerationBackend, monitor: ConnectionMonitor) {
+  /// while one is running. The monitor's checks pause meanwhile. Every batch gets the same
+  /// `inputs` (the Control tab's images).
+  public func start(
+    _ batches: [GenerationJob], inputs: GenerationInputs = .none, backend: any GenerationBackend,
+    monitor: ConnectionMonitor
+  ) {
     guard !isRunning, let first = batches.first else { return }
     phase = .running(step: nil, totalSteps: first.parameters.steps)
     batch = Batch(index: 1, count: batches.count)
@@ -75,7 +79,7 @@ public final class GenerationSession {
           try Task.checkCancellation()
           batch = Batch(index: number + 1, count: batches.count)
           phase = .running(step: nil, totalSteps: job.parameters.steps)
-          for try await update in backend.generate(job) {
+          for try await update in backend.generate(job, inputs: inputs) {
             switch update {
             case .progress(let step, let total):
               phase = .running(step: step, totalSteps: total)
@@ -108,6 +112,12 @@ public final class GenerationSession {
     await task?.value
   }
 
+  /// Shows a failure for a RUN that could not start (its inputs could not be prepared).
+  public func fail(with error: BackendError) {
+    guard !isRunning else { return }
+    phase = .failed(error)
+  }
+
   /// Hides a failure message.
   public func dismissFailure() {
     if case .failed = phase { phase = .idle }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `207 tests … passed`; totale 53 + 207 + 50 + 6 + 6 = **322**.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "feat: tab Control nella barra, forza nei batch e ingressi alla sessione

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Testi del tab (catalogo stringhe)

**Files:**
- Modify: `App/Localizable.xcstrings` (40 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `tab.control`, `control.*`, `results.useAsImage`, `results.unsaved.name` usate dalle viste del Task 6. Con valori: `control.image.info` (`%1$lld×%2$lld · %3$@`), `control.stage.size` (`%1$lld×%2$lld`), `control.stage.loss.*` e `control.warning.crop` (`%lld%%`), `control.source.plugin`, `control.notice.*`, `control.error.*` (`%@`) si usano con `String(format:)`.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

Salvare lo script seguente in un file temporaneo ed eseguirlo dalla radice del repository (`python3 <file>`):

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "tab.control": ("Control", "Control"),
    "control.strip.title": ("Sent with Run", "Con Run parte"),
    "control.strip.empty": ("Nothing: Run generates from scratch.", "Niente: Run genera da zero."),
    "control.strip.image": ("Image", "Immagine"),
    "control.strip.remove": ("Remove", "Togli"),
    "control.strip.clear": ("Clear all", "Svuota tutto"),
    "control.image.title": ("Image", "Immagine"),
    "control.image.drop": ("Drop an image here from Results or the Finder, or paste it.", "Trascina qui un'immagine da Risultati o dal Finder, oppure incollala."),
    "control.image.choose": ("Choose…", "Scegli…"),
    "control.image.replace": ("Replace…", "Sostituisci…"),
    "control.image.remove": ("Remove the image", "Togli l'immagine"),
    "control.image.adapt": ("Adapt the dimensions", "Adatta le dimensioni"),
    "control.image.adapt.help": ("Gives the canvas the image's ratio, with a similar area.", "Dà al canvas il rapporto dell'immagine, con area simile."),
    "control.image.info": ("%1$lld×%2$lld · %3$@", "%1$lld×%2$lld · %3$@"),
    "control.source.file": ("from the Finder", "dal Finder"),
    "control.source.result": ("from Results", "da Risultati"),
    "control.source.pasteboard": ("from the clipboard", "dagli appunti"),
    "control.source.plugin": ("from %@", "da %@"),
    "control.strength": ("Strength", "Forza"),
    "control.strength.edit": ("Edit model: the image is modified, strength at 100%.", "Modello Edit: l'immagine viene modificata, forza al 100%."),
    "control.strength.auto": ("Automatic", "Automatica"),
    "control.stage.title": ("Canvas", "Canvas"),
    "control.stage.empty": ("The canvas is empty: Run generates from scratch.", "Il canvas è vuoto: Run genera da zero."),
    "control.stage.size": ("Canvas %1$lld×%2$lld", "Canvas %1$lld×%2$lld"),
    "control.stage.loss.vertical": ("%lld%% of the image is cut off, above and below.", "Si perde il %lld%% dell'immagine, sopra e sotto."),
    "control.stage.loss.horizontal": ("%lld%% of the image is cut off, at the sides.", "Si perde il %lld%% dell'immagine, ai lati."),
    "control.stage.drag": ("Drag to choose which part to keep.", "Trascina per scegliere quale parte tenere."),
    "control.warning.crop": ("Strong crop: %lld%% of the image is cut off.", "Ritaglio forte: si perde il %lld%% dell'immagine."),
    "control.notice.removed": ("Removed: %@", "Rimossa: %@"),
    "control.notice.replaced": ("Replaced: %@", "Sostituita: %@"),
    "control.notice.cleared": ("Cleared", "Svuotato"),
    "control.notice.missing": ("The image %@ was not found.", "L'immagine %@ non è stata trovata."),
    "control.undo": ("Undo", "Annulla"),
    "control.dismiss": ("Dismiss", "Chiudi"),
    "control.adapted": ("Dimensions adapted to the image.", "Dimensioni adattate all'immagine."),
    "control.pasted.name": ("Pasted image", "Immagine incollata"),
    "control.error.unreadable": ("Can't read “%@” as an image.", "Non riesco a leggere «%@» come immagine."),
    "control.error.cannotSave": ("Can't save the copy: %@", "Non riesco a salvare la copia: %@"),
    "results.useAsImage": ("Use as image", "Usa come immagine"),
    "results.unsaved.name": ("Result", "Risultato"),
}
for key, (en, it) in new.items():
    assert key not in d['strings'], key
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
```

Run: `cd "<repo>" && git diff --stat App/Localizable.xcstrings | tail -1`
Expected: `1 file changed, 680 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "<repo>/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed`.

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add App/Localizable.xcstrings && git commit -m "feat: testi del tab Control (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Il tab Control e le modifiche a Risultati (App)

**Files:**
- Create: `App/Control/ControlText.swift`, `ControlImport.swift`, `ControlStrip.swift`, `ImageCard.swift`, `CanvasStage.swift`, `ControlTabView.swift`
- Modify: `App/Generation/GenerationController.swift`, `App/MainWindow/MainWindowView.swift`, `App/DTHubApp.swift`, `App/Results/ResultsView.swift`

**Interfaces:**
- Consumes: tutto ciò che producono i Task 1–5; `DSCollapsibleCard`, `DSPillButtonStyle`, `DSGroupHeader`, `dsPanel()`, `CardRow`, `IntField`, `DSCardRow` (esistenti).
- Produces:
  - `GenerationController.control: ControlStore`, `init(languageModel:control:sessionStore:)`, `isEditModel(in:)`, `adaptDimensionsToImage() -> Size?`, `restoreDimensions(_:)`; il RUN prepara gli ingressi in `Task.detached` (`renderInputs()`), mostra l'errore con `session.fail(with:)` e passa forza e ingressi; `resume` riprende la forza del risultato;
  - `ControlTabView(generation:connection:)`, `ControlStrip`, `ImageCard`, `CanvasStage`, `ControlImport`, `ControlText`, `ControlMessage`;
  - `ResultsView`: miniature trascinabili (`.draggable(url)`), menu e pulsante "Usa come immagine".

Questo task è codice di vista: non ha test, la verifica è la compilazione (Step 3) e la prova dal vivo (Task 7).

- [ ] **Step 1: Creare i file nuovi**

Il tab e le sue parti:

```swift
import HubCore
import HubKit
import SwiftUI

/// The words for the Control tab: where an image came from, what changed, what went wrong.
enum ControlText {
  static func error(_ error: ControlError) -> String {
    switch error {
    case .unreadable(let name): String(format: String(localized: "control.error.unreadable"), name)
    case .cannotSave(let detail): String(format: String(localized: "control.error.cannotSave"), detail)
    }
  }

  static func source(_ source: ReferenceImage.Source) -> String {
    switch source {
    case .file: String(localized: "control.source.file")
    case .result: String(localized: "control.source.result")
    case .pasteboard: String(localized: "control.source.pasteboard")
    case .plugin(let id): String(format: String(localized: "control.source.plugin"), id)
    }
  }

  static func notice(_ notice: ControlNotice) -> String {
    switch notice {
    case .removed(let name): String(format: String(localized: "control.notice.removed"), name)
    case .replaced(let name): String(format: String(localized: "control.notice.replaced"), name)
    case .cleared: String(localized: "control.notice.cleared")
    case .missingAtLaunch(let name): String(format: String(localized: "control.notice.missing"), name)
    }
  }

  static func warning(_ warning: ControlWarning) -> String {
    switch warning {
    case .strongCrop(let percent): String(format: String(localized: "control.warning.crop"), percent)
    }
  }
}
```

```swift
import AppKit
import HubCore
import HubKit
import SwiftUI
import UniformTypeIdentifiers

/// How pictures reach the Control tab: dropped files, the paste command, the file panel.
/// Failures are returned as words for the message bar, never thrown at the interface.
@MainActor
enum ControlImport {
  /// The first usable file of a drop. nil when it worked, the message when it did not.
  static func take(urls: [URL], into control: ControlStore) async -> String? {
    guard let url = urls.first(where: { $0.isFileURL }) else { return nil }
    do throws(ControlError) {
      try await control.setImage(fileURL: url)
      return nil
    } catch {
      return ControlText.error(error)
    }
  }

  /// What the paste command offers: a file copied in the Finder, or the picture itself.
  static func take(providers: [NSItemProvider], into control: ControlStore) async -> String? {
    if let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) {
      let url = await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
      }
      if let url { return await take(urls: [url], into: control) }
    }
    if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
      let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
          continuation.resume(returning: data)
        }
      }
      let name = String(localized: "control.pasted.name")
      guard let data else { return ControlText.error(.unreadable(name)) }
      do throws(ControlError) {
        try control.setImage(data: data, name: name, source: .pasteboard)
        return nil
      } catch {
        return ControlText.error(error)
      }
    }
    return nil
  }

  /// The file panel of "Choose…" and "Replace…".
  static func choose(into control: ControlStore) async -> String? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.image]
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return await take(urls: [url], into: control)
  }
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// "Sent with RUN": one chip per input that will go (spec: tab Control §3), each with a ✕, a
/// "Clear all" and the warnings worth a look before pressing RUN.
struct ControlStrip: View {
  let generation: GenerationController
  private var control: ControlStore { generation.control }

  var body: some View {
    let warnings = control.warnings(
      canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        DSGroupHeader(title: String(localized: "control.strip.title"))
        if let image = control.inputs.image {
          chip(
            systemImage: "photo", title: String(localized: "control.strip.image"),
            detail: "\(image.pixelWidth)×\(image.pixelHeight)",
            remove: { control.removeImage() })
        } else {
          Text("control.strip.empty").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if control.inputs != ControlInputs() {
          Button("control.strip.clear") { control.clear() }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.remove)
        }
      }
      ForEach(warnings, id: \.self) { warning in
        Label(ControlText.warning(warning), systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(DS.remove)
      }
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .dsPanel()
  }

  private func chip(systemImage: String, title: String, detail: String, remove: @escaping () -> Void) -> some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
      Text(title).font(.caption.weight(.semibold))
      Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
      Button(action: remove) {
        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "control.strip.remove"))
      .help(String(localized: "control.strip.remove"))
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 5)
    .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.07)))
  }
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// The start image (spec: tab Control §3): thumbnail with its origin, replace and remove, a drop
/// zone, adapt the dimensions, and the strength.
struct ImageCard: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  /// Reports what went wrong with an import, or that the dimensions were adapted.
  let report: (ControlMessage) -> Void
  @State private var thumbnail: CGImage?
  @State private var isTargeted = false

  private var control: ControlStore { generation.control }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.image.title"), systemImage: "photo",
      isExpanded: generation.cards.binding("control.image")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let image = control.inputs.image {
          loaded(image)
          strengthRow
        } else {
          emptyZone
        }
      }
      .overlay(RoundedRectangle(cornerRadius: DS.boxRadius).strokeBorder(DS.accent, lineWidth: isTargeted ? 2 : 0))
      .dropDestination(for: URL.self) { urls, _ in
        Task { if let message = await ControlImport.take(urls: urls, into: control) { report(.error(message)) } }
        return true
      } isTargeted: { isTargeted = $0 }
    }
    .task(id: control.inputs.image?.id) { thumbnail = control.preview(maxPixel: 240) }
  }

  private func loaded(_ image: ReferenceImage) -> some View {
    HStack(alignment: .top, spacing: DS.rowGap) {
      ZStack(alignment: .topTrailing) {
        Group {
          if let thumbnail {
            Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
          } else {
            Color.primary.opacity(0.08)
          }
        }
        .frame(width: 104, height: 104)
        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
        Button {
          control.removeImage()
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 18)).symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.black.opacity(0.55))
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel(String(localized: "control.image.remove"))
        .help(String(localized: "control.image.remove"))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(verbatim: image.name).font(.callout.weight(.semibold)).lineLimit(2)
        Text(
          String(
            format: String(localized: "control.image.info"), image.pixelWidth, image.pixelHeight,
            ControlText.source(image.source))
        )
        .font(.caption).foregroundStyle(.secondary)
        HStack(spacing: DS.controlGap) {
          Button("control.image.replace") {
            Task { if let message = await ControlImport.choose(into: control) { report(.error(message)) } }
          }
          .buttonStyle(DSPillButtonStyle())
          Button("control.image.adapt") {
            if let previous = generation.adaptDimensionsToImage() { report(.adapted(previous)) }
          }
          .buttonStyle(DSPillButtonStyle())
          .help(String(localized: "control.image.adapt.help"))
        }
        .padding(.top, 4)
      }
    }
  }

  private var emptyZone: some View {
    VStack(spacing: DS.controlGap) {
      Image(systemName: "photo.badge.plus").font(.system(size: 26)).foregroundStyle(.secondary)
      Text("control.image.drop").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
      Button("control.image.choose") {
        Task { if let message = await ControlImport.choose(into: control) { report(.error(message)) } }
      }
      .buttonStyle(DSPillButtonStyle(prominent: true))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 18)
    .background(
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
  }

  private var strengthRow: some View {
    let edit = generation.isEditModel(in: connection)
    let value = control.inputs.effectiveStrength(editModel: edit)
    return VStack(alignment: .leading, spacing: 4) {
      CardRow(label: String(localized: "control.strength")) {
        Slider(
          value: Binding(get: { value }, set: { control.setStrength($0) }), in: 0...1, step: 0.01
        )
        .frame(minWidth: 120)
      } control: {
        IntField(
          label: String(localized: "control.strength"),
          value: Binding(get: { Int((value * 100).rounded()) }, set: { control.setStrength(Double($0) / 100) }),
          range: 0...100, step: 5, commit: { $0 })
      }
      HStack(spacing: DS.controlGap) {
        if edit {
          Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
        }
        if control.inputs.strength != nil {
          Button("control.strength.auto") { control.setStrength(nil) }
            .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(DS.accent)
        }
      }
    }
  }
}

/// A line of the Control tab's message bar.
enum ControlMessage: Equatable {
  case error(String)
  /// The dimensions were adapted; the previous ones can be put back.
  case adapted(Size)
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// The canvas as Draw Things will get it (spec: tab Control §3, §5): the start image with the
/// part that is cut off darkened. Dragging moves the cut along the axis that is cropped.
struct CanvasStage: View {
  let generation: GenerationController
  @State private var picture: CGImage?
  @State private var dragStart: Framing?

  private var control: ControlStore { generation.control }
  private var canvasWidth: Int { generation.parameters.width }
  private var canvasHeight: Int { generation.parameters.height }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.stage.title"), systemImage: "rectangle.dashed",
      isExpanded: generation.cards.binding("control.stage")
    ) {
      VStack(spacing: DS.rowGap) {
        if let image = control.inputs.image {
          stage(for: image)
          caption(for: image)
        } else {
          empty
        }
      }
    }
    .task(id: control.inputs.image?.id) { picture = control.preview(maxPixel: 1400) }
  }

  private var empty: some View {
    ZStack {
      RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
      Text("control.stage.empty").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        .padding()
    }
    .aspectRatio(Double(canvasWidth) / Double(max(canvasHeight, 1)), contentMode: .fit)
    .frame(maxHeight: 300)
  }

  private func stage(for image: ReferenceImage) -> some View {
    GeometryReader { geometry in
      let size = geometry.size
      let crop = FramingMath.cropRect(
        imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
        canvasHeight: canvasHeight, framing: control.inputs.framing)
      let rect = CGRect(
        x: crop.minX / Double(image.pixelWidth) * size.width, y: crop.minY / Double(image.pixelHeight) * size.height,
        width: crop.width / Double(image.pixelWidth) * size.width,
        height: crop.height / Double(image.pixelHeight) * size.height)
      ZStack {
        if let picture {
          Image(decorative: picture, scale: 1).resizable().interpolation(.high)
        } else {
          Color.primary.opacity(0.08)
        }
        Path { path in
          path.addRect(CGRect(origin: .zero, size: size))
          path.addRect(rect)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
      }
      .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .onChanged { value in
            let start = dragStart ?? control.inputs.framing
            dragStart = start
            move(from: start, by: value.translation, in: size, image: image, crop: crop)
          }
          .onEnded { _ in dragStart = nil })
    }
    .aspectRatio(Double(image.pixelWidth) / Double(max(image.pixelHeight, 1)), contentMode: .fit)
    .frame(maxHeight: 340)
  }

  /// The cut follows the pointer along the cropped axis; the other axis has nothing to move.
  private func move(from start: Framing, by translation: CGSize, in size: CGSize, image: ReferenceImage, crop: CGRect) {
    let slackX = Double(image.pixelWidth) - crop.width
    let slackY = Double(image.pixelHeight) - crop.height
    var x = start.offsetX
    var y = start.offsetY
    if slackX > 0.5 {
      x += translation.width * (Double(image.pixelWidth) / size.width) / (slackX / 2)
    }
    if slackY > 0.5 {
      y += translation.height * (Double(image.pixelHeight) / size.height) / (slackY / 2)
    }
    control.setOffset(x: x, y: y)
  }

  @ViewBuilder private func caption(for image: ReferenceImage) -> some View {
    let loss = FramingMath.loss(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight)
    VStack(alignment: .leading, spacing: 2) {
      Text(
        String(
          format: String(localized: "control.stage.size"), canvasWidth, canvasHeight)
      )
      .font(.caption).foregroundStyle(.secondary)
      if let axis = loss.axis {
        Text(
          String(
            format: String(localized: axis == .vertical ? "control.stage.loss.vertical" : "control.stage.loss.horizontal"),
            Int((loss.fraction * 100).rounded()))
        )
        .font(.caption).foregroundStyle(.secondary)
        Text("control.stage.drag").font(.caption).foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
```

```swift
import HubCore
import HubKit
import SwiftUI

/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt. In this first
/// step the start image; the Moodboard and the mask come next.
struct ControlTabView: View {
  let generation: GenerationController
  let connection: DrawThingsConnection
  @State private var message: ControlMessage?

  private var control: ControlStore { generation.control }

  var body: some View {
    ScrollView {
      VStack(spacing: DS.groupGap) {
        ControlStrip(generation: generation)
        messageBar
        DSCardRow {
          ImageCard(generation: generation, connection: connection) { message = $0 }
          CanvasStage(generation: generation)
        }
      }
      .padding(.bottom, DS.groupGap)
    }
    .scrollIndicators(.automatic)
    .onPasteCommand(of: [.fileURL, .image]) { providers in
      Task { if let text = await ControlImport.take(providers: providers, into: control) { message = .error(text) } }
    }
    .background { undoShortcuts }
    .task(id: control.notice) {
      guard control.notice != nil else { return }
      try? await Task.sleep(for: .seconds(8))
      control.dismissNotice()
    }
  }

  /// ⌘Z and ⇧⌘Z while the tab is on screen; a text field in focus keeps its own undo.
  private var undoShortcuts: some View {
    HStack {
      Button { control.undo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: .command).disabled(!control.canUndo)
      Button { control.redo() } label: { EmptyView() }
        .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!control.canRedo)
    }
    .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
  }

  @ViewBuilder private var messageBar: some View {
    if let notice = control.notice {
      bar(systemImage: "info.circle", text: ControlText.notice(notice), tint: .secondary) {
        if control.canUndo { Button("control.undo") { control.undo() }.buttonStyle(DSPillButtonStyle()) }
      }
    }
    if let message {
      switch message {
      case .error(let text):
        bar(systemImage: "exclamationmark.triangle.fill", text: text, tint: DS.remove) {
          Button("control.dismiss") { self.message = nil }.buttonStyle(DSPillButtonStyle())
        }
      case .adapted(let previous):
        bar(systemImage: "aspectratio", text: String(localized: "control.adapted"), tint: .secondary) {
          Button("control.undo") {
            generation.restoreDimensions(previous)
            self.message = nil
          }
          .buttonStyle(DSPillButtonStyle())
        }
      }
    }
  }

  private func bar<Actions: View>(
    systemImage: String, text: String, tint: Color, @ViewBuilder actions: () -> Actions
  ) -> some View {
    HStack(spacing: DS.controlGap) {
      Image(systemName: systemImage).foregroundStyle(tint)
      Text(verbatim: text).font(.callout)
      Spacer(minLength: 0)
      actions()
    }
    .padding(DS.panelPadding)
    .frame(maxWidth: .infinity)
    .dsPanel()
  }
}
```

- [ ] **Step 2: Applicare le modifiche ai file esistenti**

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 4fac051..49eeb7a 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -35,6 +35,8 @@ final class GenerationController {
 
   /// The language model, freed when RUN is pressed if the settings say so (spec §9).
   @ObservationIgnored let languageModel: LanguageModelManager
+  /// The Control tab's images (tab Control spec): the start image goes with every RUN.
+  @ObservationIgnored let control: ControlStore
   /// True between pressing RUN and the generation starting: the language model is being freed
   /// and a parked server brought back.
   private(set) var isPreparing = false
@@ -46,10 +48,11 @@ final class GenerationController {
 
   /// Restores the last prompt and parameters (spec §11).
   init(
-    languageModel: LanguageModelManager,
+    languageModel: LanguageModelManager, control: ControlStore,
     sessionStore: SessionStore = SessionStore(fileURL: SessionStore.defaultFileURL)
   ) {
     self.languageModel = languageModel
+    self.control = control
     self.sessionStore = sessionStore
     outputFolder = outputSettings.folder()
     if let snapshot = sessionStore.load() {
@@ -165,10 +168,11 @@ final class GenerationController {
       // Memory first: the language model leaves, a server parked for it comes back.
       await languageModel.prepareForRun()
       await connection.ensureServerForRun()
+      let inputs = await renderInputs()
       isPreparing = false
       preparation = nil
-      guard !Task.isCancelled else { return }
-      start(with: connection)
+      guard !Task.isCancelled, let inputs else { return }
+      start(with: connection, inputs: inputs)
     }
     return true
   }
@@ -181,7 +185,7 @@ final class GenerationController {
 
   /// The generation itself, once the memory is ready. The job is composed now, not at the
   /// click: a parked server has no catalog until it is back.
-  private func start(with connection: DrawThingsConnection) {
+  private func start(with connection: DrawThingsConnection, inputs: GenerationInputs) {
     guard !session.isRunning, let backend = connection.monitor.backend,
       let model = connection.selection.selectedFile,
       RunAvailability.blocker(
@@ -189,9 +193,47 @@ final class GenerationController {
     else { return }
     let batches = JobComposer.batches(
       prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
-      parameters: parameters, catalog: connection.monitor.catalog)
+      parameters: parameters, catalog: connection.monitor.catalog,
+      imageStrength: inputs.isEmpty ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)))
     if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
-    session.start(batches, backend: backend, monitor: connection.monitor)
+    session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
+  }
+
+  /// The Control tab's images framed to the canvas, decoded away from the main actor. A failure
+  /// is shown as the RUN's failure, and nothing starts.
+  private func renderInputs() async -> GenerationInputs? {
+    let pending = control.pendingInputs(canvasWidth: parameters.width, canvasHeight: parameters.height)
+    do {
+      return try await Task.detached { try pending.render() }.value
+    } catch {
+      let text = (error as? ControlError).map(ControlText.error) ?? error.localizedDescription
+      session.fail(with: .generationFailed(text))
+      return nil
+    }
+  }
+
+  /// True when the chosen model is an Edit model (the canvas image is the one to modify).
+  func isEditModel(in connection: DrawThingsConnection) -> Bool {
+    selectedModel(in: connection)?.capabilities.isEditModel ?? false
+  }
+
+  /// "Adapt the dimensions": the canvas takes the start image's ratio, with a similar area.
+  /// Returns the dimensions it had, to put back.
+  @discardableResult
+  func adaptDimensionsToImage() -> Size? {
+    guard let image = control.inputs.image else { return nil }
+    let previous = Size(width: parameters.width, height: parameters.height)
+    let adapted = FramingMath.adaptedSize(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, currentWidth: previous.width,
+      currentHeight: previous.height)
+    restoreDimensions(adapted)
+    return previous
+  }
+
+  func restoreDimensions(_ size: Size) {
+    parameters.width = size.width
+    parameters.height = size.height
+    if lockRatio { lockedRatio = currentRatio }
   }
 
   /// "Resume parameters": puts back the prompt, negative prompt, model and parameters of the
@@ -202,6 +244,7 @@ final class GenerationController {
     negativePrompt = result.job.negativePrompt
     parameters = result.job.parameters
     if lockRatio { lockedRatio = currentRatio }
+    if let strength = result.job.imageStrength { control.setStrength(strength) }
     connection.selection.select(result.job.model)
   }
 
```

```diff
diff --git a/App/MainWindow/MainWindowView.swift b/App/MainWindow/MainWindowView.swift
index d1fdea0..ff28cfe 100644
--- a/App/MainWindow/MainWindowView.swift
+++ b/App/MainWindow/MainWindowView.swift
@@ -24,7 +24,9 @@ struct MainWindowView: View {
   }
 
   @ViewBuilder private var tabContent: some View {
-    if workspace.selectedTabID == WorkspaceTab.generationID {
+    if workspace.selectedTabID == WorkspaceTab.controlID {
+      ControlTabView(generation: generation, connection: connection)
+    } else if workspace.selectedTabID == WorkspaceTab.generationID {
       GenerationTabView(controller: generation, connection: connection)
     } else {
       // Plug-in tabs arrive with the plug-in contract (M7).
```

```diff
diff --git a/App/DTHubApp.swift b/App/DTHubApp.swift
index aa0bf99..e6932f0 100644
--- a/App/DTHubApp.swift
+++ b/App/DTHubApp.swift
@@ -7,6 +7,10 @@ import SwiftUI
 @main
 struct DTHubApp: App {
   @State private var workspace = WorkspaceState(
+    controlTab: WorkspaceTab(
+      id: WorkspaceTab.controlID,
+      title: String(localized: "tab.control"),
+      systemImage: "photo.on.rectangle"),
     generationTab: WorkspaceTab(
       id: WorkspaceTab.generationID,
       title: String(localized: "tab.generation"),
@@ -22,7 +26,9 @@ struct DTHubApp: App {
     let languageModel = LanguageModelManager(
       service: MLXLanguageModelService(), releaseImageModel: { await connection.releaseImageModel() },
       isImageModelBusy: { connection.isImageWorkActive() })
-    let generation = GenerationController(languageModel: languageModel)
+    let control = ControlStore(
+      storage: FileReferenceStorage(folder: FileReferenceStorage.defaultFolder), fileURL: ControlStore.defaultFileURL)
+    let generation = GenerationController(languageModel: languageModel, control: control)
     // The language model never takes the image model's memory while an image is being made.
     connection.isImageWorkActive = { generation.session.isRunning || generation.isPreparing }
     _connection = State(initialValue: connection)
```

```diff
diff --git a/App/Results/ResultsView.swift b/App/Results/ResultsView.swift
index 702abc4..18f85df 100644
--- a/App/Results/ResultsView.swift
+++ b/App/Results/ResultsView.swift
@@ -9,6 +9,8 @@ struct ResultsView: View {
   let controller: GenerationController
   let connection: DrawThingsConnection
   @State private var selectedID: GeneratedImage.ID?
+  /// Why "Use as image" did not work.
+  @State private var useError: String?
 
   private var session: GenerationSession { controller.session }
   private var selected: GeneratedImage? {
@@ -115,20 +117,7 @@ struct ResultsView: View {
     ScrollView(.horizontal) {
       HStack(spacing: DS.controlGap) {
         ForEach(session.results) { result in
-          Button {
-            selectedID = result.id
-          } label: {
-            Image(decorative: result.image, scale: 1)
-              .resizable()
-              .scaledToFill()
-              .frame(width: 72, height: 72)
-              .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
-              .overlay(
-                RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
-                  .strokeBorder(result.id == selected?.id ? DS.accent : Color.clear, lineWidth: 2))
-          }
-          .buttonStyle(.plain)
-          .accessibilityLabel(result.job.prompt)
+          thumbnail(of: result)
         }
       }
       .padding(2)
@@ -136,6 +125,48 @@ struct ResultsView: View {
     .frame(height: 80)
   }
 
+  /// One picture of the strip: it can be dragged into the Control tab (or any app) as its file,
+  /// and the menu uses it as the start image.
+  @ViewBuilder private func thumbnail(of result: GeneratedImage) -> some View {
+    let button = Button {
+      selectedID = result.id
+    } label: {
+      Image(decorative: result.image, scale: 1)
+        .resizable()
+        .scaledToFill()
+        .frame(width: 72, height: 72)
+        .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
+        .overlay(
+          RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous)
+            .strokeBorder(result.id == selected?.id ? DS.accent : Color.clear, lineWidth: 2))
+    }
+    .buttonStyle(.plain)
+    .accessibilityLabel(result.job.prompt)
+    .contextMenu {
+      Button("results.useAsImage") { useAsImage(result) }
+    }
+    if let url = result.fileURL {
+      button.draggable(url)
+    } else {
+      button
+    }
+  }
+
+  private func useAsImage(_ result: GeneratedImage) {
+    useError = nil
+    Task {
+      do throws(ControlError) {
+        if let url = result.fileURL {
+          try await controller.control.setImage(fileURL: url, source: .result)
+        } else {
+          try controller.control.setImage(result.image, name: String(localized: "results.unsaved.name"), source: .result)
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
@@ -145,7 +176,12 @@ struct ResultsView: View {
       if let error = result.saveError {
         Text("results.notSaved").font(.caption).foregroundStyle(DS.remove).help(error)
       }
+      if let useError {
+        Text(verbatim: useError).font(.caption).foregroundStyle(DS.remove).lineLimit(2)
+      }
       Spacer(minLength: 0)
+      Button("results.useAsImage") { useAsImage(result) }
+        .buttonStyle(DSPillButtonStyle())
       if let url = result.fileURL {
         Button("results.showInFinder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
           .buttonStyle(DSPillButtonStyle())
```

- [ ] **Step 3: Compilare e provare**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v started`
Expected: `** BUILD SUCCEEDED **`; test HubKit 53, HubCore 207, DTBridge 50, Catalog 6, LLMBridge 6 = **322** passati (le viste usano solo chiavi del catalogo).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add App && git commit -m "feat: tab Control — striscia, scheda Immagine, anteprima del canvas, importazione e Risultati

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Verifica dal vivo

**Files:**
- Modify: `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (due prove con server vero, inattive senza variabile d'ambiente)

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (FLUX.2 [klein] e Juggernaut Reborn). Si avvia a mano, solo per la prova, e si ferma dopo.

- [ ] **Step 1: Aggiungere le prove dal vivo**

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index df8d099..f2b4245 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -53,4 +53,106 @@ struct LiveServerTests {
     #expect(images.count == 1)
     #expect(images.first?.width == 512)
   }
+
+  /// FLUX.2 [klein] is an Edit model: the start image (left half black, right half white) is a
+  /// reference at strength 100 %, and the result keeps the layout: the right side is brighter.
+  @Test(.enabled(if: address != nil))
+  func anEditModelKeepsTheLayoutOfTheStartImage() async throws {
+    let backend = try await liveBackend()
+    let model = try #require(
+      try await backend.fetchCatalog().models.first { $0.family == "flux2_9b" }?.file,
+      "needs a FLUX.2 [klein] model on the server")
+    var job = GenerationJob(
+      prompt: "the same picture", model: model,
+      parameters: GenerationParameters(width: 512, height: 512, steps: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
+    job.imageStrength = 1.0
+    let guided = try await run(backend, job, GenerationInputs(image: splitImage(size: 512)))
+    await backend.shutdown()
+    let difference = rightMinusLeft(guided)
+    print("LIVE edit model: right minus left luminance \(difference)")
+    #expect(guided.width == 512)
+    #expect(difference > 0.15)
+  }
+
+  /// A normal model (Juggernaut Reborn, SD 1.5) does image-to-image: at strength 50 % a solid
+  /// green start image pulls the result toward green compared with the same RUN without it.
+  @Test(.enabled(if: address != nil))
+  func aNormalModelFollowsTheStartImageAtMidStrength() async throws {
+    let backend = try await liveBackend()
+    let model = try #require(
+      try await backend.fetchCatalog().models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file,
+      "needs Juggernaut Reborn on the server")
+    var job = GenerationJob(
+      prompt: "a red apple", model: model,
+      parameters: GenerationParameters(
+        width: 512, height: 512, steps: 12, guidanceScale: 4, sampler: .ddimTrailing, seed: 7, randomSeed: false))
+    let plain = try await run(backend, job, .none)
+    job.imageStrength = 0.5
+    let guided = try await run(backend, job, GenerationInputs(image: solid(red: 0, green: 255, blue: 0, size: 512)))
+    await backend.shutdown()
+    print("LIVE normal model: green share plain \(greenShare(plain)) guided \(greenShare(guided))")
+    #expect(greenShare(guided) > greenShare(plain) + 0.05)
+  }
+
+  private func liveBackend() async throws -> DrawThingsBackend {
+    let parts = try #require(Self.address?.split(separator: ":"))
+    return DrawThingsBackend(host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
+  }
+
+  private func run(_ backend: DrawThingsBackend, _ job: GenerationJob, _ inputs: GenerationInputs) async throws -> CGImage {
+    var final: [CGImage] = []
+    for try await update in backend.generate(job, inputs: inputs) {
+      if case .finished(let images) = update { final = images }
+    }
+    return try #require(final.first)
+  }
+
+  private func splitImage(size: Int) -> CGImage {
+    let context = CGContext(
+      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
+    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
+    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
+    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
+    context.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
+    return context.makeImage()!
+  }
+
+  /// Average luminance of the right half minus the left half, 0…1.
+  private func rightMinusLeft(_ image: CGImage) -> Double {
+    func luminance(of rect: CGRect) -> Double {
+      guard let part = image.cropping(to: rect) else { return 0 }
+      var bytes = [UInt8](repeating: 0, count: 4)
+      let context = CGContext(
+        data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
+        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+      context.interpolationQuality = .medium
+      context.draw(part, in: CGRect(x: 0, y: 0, width: 1, height: 1))
+      return (0.299 * Double(bytes[0]) + 0.587 * Double(bytes[1]) + 0.114 * Double(bytes[2])) / 255
+    }
+    let half = image.width / 2
+    return luminance(of: CGRect(x: half, y: 0, width: half, height: image.height))
+      - luminance(of: CGRect(x: 0, y: 0, width: half, height: image.height))
+  }
+
+  private func solid(red: Double, green: Double, blue: Double, size: Int) -> CGImage? {
+    let context = CGContext(
+      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
+    context?.setFillColor(CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1))
+    context?.fill(CGRect(x: 0, y: 0, width: size, height: size))
+    return context?.makeImage()
+  }
+
+  /// Green's share of the average colour, 0…1.
+  private func greenShare(_ image: CGImage) -> Double {
+    var bytes = [UInt8](repeating: 0, count: 4)
+    let context = CGContext(
+      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+    context.interpolationQuality = .medium
+    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
+    let total = Double(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2]))
+    return total == 0 ? 0 : Double(bytes[1]) / total
+  }
 }
```

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v started`
Expected: DTBridge `52 tests … passed` (2 inattive), totale **324**.

- [ ] **Step 2: Provarle con un server vero**

```bash
(nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7860 --model-browser > /tmp/m7a-server.log 2>&1 &); sleep 6
cd "<repo>/Packages" && DTHUB_LIVE_DT=localhost:7860 swift test --filter "anEditModel|aNormalModel" 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
```

Expected: `LIVE edit model: right minus left luminance …` (circa 1,0, soglia 0,15) e `LIVE normal model: green share plain 0.3… guided 0.9…` (guidato superiore di almeno 0,05); i due test passano. Il primo carica il modello dal disco esterno: può volerci qualche minuto.

```bash
pkill -TERM -f gRPCServerCLI
```

- [ ] **Step 3: Provare l'app (screenshot) con un'immagine ripristinata**

Per non toccare i dati dell'utente: salvare `~/Library/Application Support/DT Hub` e le preferenze (`defaults export com.exiztenz.DTHub /tmp/m7a-defaults.plist`), usare una cartella di output temporanea (`defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m7a-out`) e il server gestito (`drawThings.managedServer` con `~/Applications/DrawThings-CLI/gRPCServerCLI-macOS`, `/Volumes/LLM-VLM/Models`, porta 7860). Preparare una copia e un `control.json` a mano (un PNG 600×800 con un gradiente e un cerchio bianco, `source` = file) e aprire l'app.

Checklist:
1. La barra mostra **Control** prima di Generazione; il tab Control mostra la striscia "Con Run parte" con il chip Immagine (600×800), la scheda Immagine (miniatura, nome, "600×800 · dal Finder", forza 70 con un modello normale) e il canvas con la parte persa oscurata ("Si perde il 25% … sopra e sotto").
2. "Adatta le dimensioni" porta il canvas a 896×1152 (3:4, area simile) e compare "Dimensioni adattate all'immagine." con "Annulla".
3. Con un modello normale (Juggernaut Reborn) e Run, il PNG salvato nella cartella temporanea ha la dimensione del canvas, segue il gradiente dell'immagine, e porta `"imageStrength":0.7` nei metadati (`strings <file> | grep imageStrength`).
4. Chiudere e riaprire l'app: l'immagine è ancora lì.

- [ ] **Step 4: Pulizia** (sempre, anche se qualcosa non va)

Fermare app e server, ripristinare la cartella `DT Hub` e le preferenze salvate, e togliere le chiavi di prova:

```bash
pkill -TERM -x "DT Hub"; pkill -TERM -f gRPCServerCLI; defaults delete com.exiztenz.DTHub output.folder; defaults delete com.exiztenz.DTHub drawThings.managedServer; rm -rf /tmp/dthub-m7a-out
```

Poi rimettere `session.json` e `cards.json` del backup e togliere `control.json` e la cartella `Control` create dalla prova.

- [ ] **Step 5: Commit**

```bash
cd "<repo>" && git add Packages && git commit -m "test: prove dal vivo dell'immagine di partenza (modello Edit e modello normale)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7a

Esito atteso sul branch `m7a-tab-control`:
- **324 test verdi** (2 prove dal vivo inattive senza `DTHUB_LIVE_DT`, provate con il server);
- build Xcode pulita;
- l'I2I funziona dall'app: immagine dal Finder, da Risultati (trascinando o dal menu) o con ⌘V; forza automatica per modello; inquadratura con ritaglio visibile e trascinabile; "Adatta le dimensioni"; annulla; ripristino all'avvio.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge, e il piano di **M7b** (Moodboard con le quote della torta, sezione 4.1 della spec).

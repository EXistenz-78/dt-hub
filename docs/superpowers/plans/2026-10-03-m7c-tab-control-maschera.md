# M7c Tab Control — Maschera e inpaint — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Il tab Control ha la scheda **Maschera**: si dipinge con un pennello (e una gomma) ciò che Draw Things deve rigenerare, sul canvas così come parte; Inverti, Svuota, Annulla/Ripeti; Sfumatura, Margine e "Conserva l'originale" come in Draw Things. Il RUN manda immagine, maschera e impostazioni, e **l'inpaint funziona**.

**Architecture:**
- **HubKit** riceve `MaskSettings`, `MaskReference`, i campi `mask`/`maskSettings` di `ControlInputs`, `GenerationInputs.mask`/`enableInpainting`, `GenerationJob.maskSettings` e `ModelCapabilities.needsInpaintControl`.
- **DTBridge** manda la maschera e le impostazioni nella richiesta (`JobMapper`).
- **HubCore** riceve `MaskBitmap` (buffer a 8 bit con pennello, gomma, inverti, PNG, geometria vista→maschera), `InputComposer.mask` (la maschera scalata al canvas, nello stesso ritaglio dell'immagine), le operazioni dello store (ogni tratto è un passo della cronologia) e gli ingressi del RUN.
- **L'app** aggiunge `MaskCard` (sotto il Canvas), il chip "Maschera" nella striscia e i collegamenti nel RUN.

**Tech Stack:** Swift 6, SwiftUI (`Canvas`), macOS 26, Xcode 27, Swift Testing, ImageIO, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-01-tab-control-design.md` (sezioni 3, 4, 6, 9; aggiornata il 3 ottobre 2026 con le decisioni sotto).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m7c-maschera` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift.
- **Maschera netta, senza morbidezza del pennello** (misurato nel client: un pixel con alfa < 255 è «da rigenerare», altrimenti no; non ci sono mezzi toni). Il bordo si ammorbidisce con la Sfumatura (`maskBlur`) di Draw Things.
- **Misurato dal vivo il 3 ottobre 2026** (SD 1.5 Juggernaut Reborn e FLUX.2 klein, immagine blu con la metà destra mascherata, «papaveri rossi»): la sinistra resta identica e la destra si rigenera a forza 100% (rosso 0,58 e 0,54); a forza 70% la parte mascherata resta blu; `enableInpainting` acceso o spento dà risultati identici. **Quindi: forza automatica 100% con la maschera** (una scelta dell'utente vince) e `enableInpainting` **solo per i modelli con `modifier` `inpainting`** (regola del client; quei modelli non sono installati, la regola per loro non è provata).
- **La maschera appartiene all'immagine:** cambiare o togliere l'immagine di partenza toglie la maschera (si annulla); una maschera senza immagine non si legge dal file salvato. Una maschera vuota non esiste (cancellare tutto = nessuna maschera).
- **Dimensione di lavoro:** il rapporto dell'immagine, lato lungo al massimo 1024 pixel (`MaskBitmap.workingSize`). Al RUN si scala al canvas con interpolazione alta nello stesso ritaglio dell'immagine e si taglia a metà (`InputComposer.mask`).
- **Cronologia unica:** ogni tratto, Inverti e Svuota sono passi della cronologia del tab (20, ⌘Z); ogni passo scrive un PNG nuovo nella cartella `Control` e lo stato tiene il riferimento (`MaskReference`); le copie si spazzano come le altre. Impostazioni della maschera (Sfumatura, Margine, Conserva) **non** sono passi.
- **Nel PNG salvato** finiscono le impostazioni della maschera (`maskSettings` nel job) solo se il RUN aveva una maschera; "Riprendi parametri" le rimette.
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; mai una stringa vuota come titolo di un controllo (il test del catalogo la segnala).
- **La logica sta in HubCore (testata); le viste si verificano con la compilazione e con la prova dal vivo (Task 8).**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già su `main`; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Se l'app dell'utente è in esecuzione non lanciare altre istanze** (stesso identificatore, stessi dati): compilare con `-derivedDataPath /tmp/…` e chiedere all'utente di chiuderla prima della verifica dal vivo (Task 8).
- **Fuori da M7c:** outpaint e modo «Contieni», Tiled Diffusion 8192, avviso per una maschera tutta fuori dal ritaglio, plug-in.

## Review Focus

- **Coordinate:** il punto della vista → pixel della maschera passa dal ritaglio (`MaskBitmap.point(forViewPoint:…)`), e la maschera del RUN segue lo stesso ritaglio dell'immagine (test `MaskGeometryTests`, `theMaskFollowsTheCut`, `paintAtTheTopOfTheMaskIsAtTheTopOfTheCanvas`, Task 3–4). Un ritaglio forte con la maschera dipinta fuori dal ritaglio manda una maschera vuota: è nei fuori-perimetro, il revisore dica se lo ritiene da correggere.
- **Maschera vuota = nessuna maschera:** cancellare tutto o Inverti due volte toglie il riferimento e la striscia (test `anEmptyMaskIsNoMask`, `invertingAMaskDrawnNothingPaintsEverything`, Task 5).
- **Immagine cambiata o tolta:** la maschera va via e torna con Annulla; una maschera senza immagine nel file salvato non si legge (test `theMaskGoesWithTheImage`, `aMaskWithoutAnImageIsNotKept`, Task 1 e 5).
- **Copia della maschera sparita all'avvio:** la maschera si scarta con un avviso, l'immagine resta (test `aMaskWhoseCopyIsGoneIsDroppedWithANotice`, Task 5).
- **Immagine enorme:** la maschera resta a 1024 pixel e l'immagine si decodifica alla dimensione che serve al canvas (test `theMaskIsDrawnAtTheWorkingSizeOfTheImage`, Task 5).
- **Pennello ai bordi e fuori:** non scrive fuori dal buffer (test `theBrushStaysInsideTheMask`, Task 3).
- **Cronologia:** i passi della maschera e quelli delle immagini condividono i 20; una copia usata dalla cronologia non si cancella (test `eachStrokeIsAStepOfTheHistory`, `theCopiesOfOldMasksAreSweptWhenNothingRefersToThem`, Task 5).
- **Prestazioni del pennello:** l'anteprima in arancio si ricostruisce a ogni evento (1024² pixel); il revisore dica se vede un rischio su canvas grandi (non c'è un test, la verifica è dal vivo, Task 8).
- **`enableInpainting` per i modelli inpainting** non è provato dal vivo (nessun modello inpainting installato): il revisore controlli la regola contro il client.

---

### Task 1: Tipi della maschera (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Control/ControlInputs.swift`, `Packages/Sources/HubKit/Generation/GenerationJob.swift`, `Packages/Sources/HubKit/Catalog/ModelCapabilities.swift`
- Test: `Packages/Tests/HubKitTests/MaskContractTests.swift` (nuovo)

**Interfaces:**
- Produces (HubKit, `public`):
  - `struct MaskSettings: Equatable, Codable, Sendable` (`blur: Double` 1,5; `outset: Int` 0; `preserveOriginal: Bool` true; `static let blurRange = 0.0...30.0`, `outsetRange = 0...100`; `clamped()`; lettura permissiva che applica i limiti);
  - `struct MaskReference: Equatable, Codable, Sendable` (`fileName: String`, `coverage: Double` 0…1);
  - `ControlInputs.mask: MaskReference?` (letta solo se c'è l'immagine) e `maskSettings: MaskSettings`; l'iniziatore ha `mask: MaskReference? = nil, maskSettings: MaskSettings = MaskSettings()`; `effectiveStrength(editModel:)` dà 1,0 anche con una maschera;
  - `GenerationInputs.mask: CGImage?` (trasparente = da rigenerare) e `enableInpainting: Bool`; `init(image:hints:mask:enableInpainting:)`; `isEmpty` considera la maschera;
  - `GenerationJob.maskSettings: MaskSettings?` (nil senza maschera; lettura permissiva; l'iniziatore ha `maskSettings: MaskSettings? = nil`);
  - `ModelCapabilities.needsInpaintControl: Bool` (`modifier == "inpainting"`).
- Consumes: `ControlInputs`, `GenerationInputs`, `GenerationJob`, `ModelCapabilities` (M7a/b).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m7c-maschera
```

```swift
import Foundation
import Testing

@testable import HubKit

struct MaskContractTests {
  @Test func maskSettingsStartAtDrawThingsDefaults() {
    let settings = MaskSettings()
    #expect(settings.blur == 1.5 && settings.outset == 0 && settings.preserveOriginal)
  }

  @Test func savedInputsWithoutAMaskStillLoad() throws {
    let old = Data(#"{"framing":{"mode":"fill","offsetX":0,"offsetY":0}}"#.utf8)
    let inputs = try JSONDecoder().decode(ControlInputs.self, from: old)
    #expect(inputs.mask == nil)
    #expect(inputs.maskSettings == MaskSettings())
  }

  @Test func aMaskWithoutAnImageIsNotKept() throws {
    let json = Data(#"{"mask":{"fileName":"x.png","coverage":0.2}}"#.utf8)
    #expect(try JSONDecoder().decode(ControlInputs.self, from: json).mask == nil)
  }

  @Test func damagedMaskSettingsFallBackToTheDefaults() throws {
    let json = Data(#"{"maskSettings":{"blur":"lots","outset":999}}"#.utf8)
    let settings = try JSONDecoder().decode(ControlInputs.self, from: json).maskSettings
    #expect(settings.blur == 1.5)
    #expect(settings.outset == MaskSettings.outsetRange.upperBound)
  }

  @Test func aJobCarriesTheMaskSettingsAndOldJobsLoad() throws {
    var job = GenerationJob(prompt: "x", model: "m", parameters: GenerationParameters())
    #expect(job.maskSettings == nil)
    job.maskSettings = MaskSettings(blur: 3, outset: 4, preserveOriginal: false)
    let back = try JSONDecoder().decode(GenerationJob.self, from: JSONEncoder().encode(job))
    #expect(back.maskSettings == job.maskSettings)
    let old = Data(#"{"prompt":"x","model":"m","parameters":{}}"#.utf8)
    #expect(try JSONDecoder().decode(GenerationJob.self, from: old).maskSettings == nil)
  }

  @Test func onlyAnInpaintingModelNeedsTheInpaintControl() {
    func capabilities(_ modifier: String?) -> ModelCapabilities {
      ModelCapabilities(
        guidanceEmbed: false, teaCache: false, clipL: false, openClipG: false, t5: false, optionalT5: false,
        clipSkip: false, nativeSize: nil, modifier: modifier)
    }
    #expect(capabilities("inpainting").needsInpaintControl)
    #expect(!capabilities("kontext").needsInpaintControl)
    #expect(!capabilities(nil).needsInpaintControl)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MaskSettings' in scope`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Control/ControlInputs.swift b/Packages/Sources/HubKit/Control/ControlInputs.swift
index b881766..f8e8d16 100644
--- a/Packages/Sources/HubKit/Control/ControlInputs.swift
+++ b/Packages/Sources/HubKit/Control/ControlInputs.swift
@@ -63,6 +63,53 @@ public struct Framing: Equatable, Codable, Sendable {
   }
 }
 
+/// What Draw Things does with the inpaint mask (tab Control spec §3). The defaults are Draw Things'.
+public struct MaskSettings: Equatable, Codable, Sendable {
+  /// How much the edge of the mask is softened (`maskBlur`).
+  public var blur: Double
+  /// How far the area around the mask is taken in (`maskBlurOutset`).
+  public var outset: Int
+  /// Keeps the original pixels outside the mask after the generation (`preserveOriginalAfterInpaint`).
+  public var preserveOriginal: Bool
+
+  public static let blurRange = 0.0...30.0
+  public static let outsetRange = 0...100
+
+  public init(blur: Double = 1.5, outset: Int = 0, preserveOriginal: Bool = true) {
+    self.blur = blur
+    self.outset = outset
+    self.preserveOriginal = preserveOriginal
+  }
+
+  public func clamped() -> MaskSettings {
+    MaskSettings(
+      blur: min(Self.blurRange.upperBound, max(Self.blurRange.lowerBound, blur)),
+      outset: min(Self.outsetRange.upperBound, max(Self.outsetRange.lowerBound, outset)),
+      preserveOriginal: preserveOriginal)
+  }
+
+  public init(from decoder: any Decoder) throws {
+    let container = try decoder.container(keyedBy: CodingKeys.self)
+    blur = (try? container.decodeIfPresent(Double.self, forKey: .blur)) ?? 1.5
+    outset = (try? container.decodeIfPresent(Int.self, forKey: .outset)) ?? 0
+    preserveOriginal = (try? container.decodeIfPresent(Bool.self, forKey: .preserveOriginal)) ?? true
+    self = clamped()
+  }
+}
+
+/// The inpaint mask the tab holds: a PNG copy in the Control folder, drawn in the start image's
+/// own coordinates (so it follows the framing), and how much of the image it covers.
+public struct MaskReference: Equatable, Codable, Sendable {
+  public let fileName: String
+  /// 0…1, the share of the image the mask covers.
+  public let coverage: Double
+
+  public init(fileName: String, coverage: Double) {
+    self.fileName = fileName
+    self.coverage = coverage
+  }
+}
+
 /// One image of the Moodboard (tab Control spec §3): its picture and the switch. Every picture
 /// that is on counts the same: Draw Things gives the same weight to every picture above 0 on the
 /// models that read the Moodboard (measured, 2 October 2026), so there are no shares yet (§4.1).
@@ -92,14 +139,20 @@ public struct ControlInputs: Equatable, Codable, Sendable {
   /// The Moodboard, in the order of the thumbnails.
   public var moodboard: [MoodboardEntry]
   public var framing: Framing
-  /// nil = automatic: 100 % for the Edit models, 70 % for the others (at 100 % a normal image-
-  /// to-image ignores the image). The user's choice, once made, wins.
+  /// The inpaint mask, over the start image. Never without it: the mask goes when the image goes.
+  public var mask: MaskReference?
+  public var maskSettings: MaskSettings
+  /// nil = automatic: 100 % for the Edit models and with a mask (the painted area is regenerated
+  /// whole), 70 % for the others (at 100 % a normal image-to-image ignores the image). The
+  /// user's choice, once made, wins.
   public var strength: Double?
 
   public init(
     image: ReferenceImage? = nil, framing: Framing = Framing(), strength: Double? = nil,
-    moodboard: [MoodboardEntry] = []
+    moodboard: [MoodboardEntry] = [], mask: MaskReference? = nil, maskSettings: MaskSettings = MaskSettings()
   ) {
+    self.mask = mask
+    self.maskSettings = maskSettings
     self.image = image
     self.framing = framing
     self.strength = strength
@@ -108,7 +161,7 @@ public struct ControlInputs: Equatable, Codable, Sendable {
 
   /// The strength that is sent and shown, within 0…1.
   public func effectiveStrength(editModel: Bool) -> Double {
-    min(1, max(0, strength ?? (editModel ? 1.0 : 0.7)))
+    min(1, max(0, strength ?? (editModel || mask != nil ? 1.0 : 0.7)))
   }
 
   /// Lenient, like the other saved files: a missing or unreadable field takes its default.
@@ -117,6 +170,9 @@ public struct ControlInputs: Equatable, Codable, Sendable {
     image = try? container.decodeIfPresent(ReferenceImage.self, forKey: .image)
     framing = (try? container.decodeIfPresent(Framing.self, forKey: .framing)) ?? Framing()
     strength = try? container.decodeIfPresent(Double.self, forKey: .strength)
+    // A mask belongs to an image: one without it is not kept.
+    mask = image == nil ? nil : try? container.decodeIfPresent(MaskReference.self, forKey: .mask)
+    maskSettings = (try? container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings)) ?? MaskSettings()
     moodboard = ((try? container.decodeIfPresent([Lossy<MoodboardEntry>].self, forKey: .moodboard)) ?? [])
       .compactMap(\.value)
   }
@@ -126,17 +182,23 @@ public struct ControlInputs: Equatable, Codable, Sendable {
 /// `Codable`: images do not go into the PNG metadata.
 public struct GenerationInputs: Sendable {
   public var image: CGImage?
+  /// The inpaint mask at the canvas size: transparent pixels are regenerated, opaque ones kept.
+  public var mask: CGImage?
+  /// Asks Draw Things for its inpaint control (see `JobMapper`).
+  public var enableInpainting: Bool
   /// The Moodboard's pictures that are on, in order.
   public var hints: [GenerationHint]
 
-  public init(image: CGImage? = nil, hints: [GenerationHint] = []) {
+  public init(image: CGImage? = nil, hints: [GenerationHint] = [], mask: CGImage? = nil, enableInpainting: Bool = false) {
     self.image = image
     self.hints = hints
+    self.mask = mask
+    self.enableInpainting = enableInpainting
   }
 
   public static let none = GenerationInputs()
 
-  public var isEmpty: Bool { image == nil && hints.isEmpty }
+  public var isEmpty: Bool { image == nil && mask == nil && hints.isEmpty }
 }
 
 /// One Moodboard picture of a RUN: encoded image data (PNG) and its weight (1: all count the same).
```

```diff
diff --git a/Packages/Sources/HubKit/Generation/GenerationJob.swift b/Packages/Sources/HubKit/Generation/GenerationJob.swift
index 1beba2d..5f406a9 100644
--- a/Packages/Sources/HubKit/Generation/GenerationJob.swift
+++ b/Packages/Sources/HubKit/Generation/GenerationJob.swift
@@ -12,10 +12,12 @@ public struct GenerationJob: Equatable, Codable, Sendable {
   public var imageStrength: Double?
   /// How many Moodboard pictures went with this RUN (0 without a Moodboard).
   public var moodboardCount: Int
+  /// What Draw Things does with the mask; nil when the RUN has no mask.
+  public var maskSettings: MaskSettings?
 
   public init(
     prompt: String, negativePrompt: String = "", model: String, parameters: GenerationParameters,
-    imageStrength: Double? = nil, moodboardCount: Int = 0
+    imageStrength: Double? = nil, moodboardCount: Int = 0, maskSettings: MaskSettings? = nil
   ) {
     self.prompt = prompt
     self.negativePrompt = negativePrompt
@@ -23,6 +25,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     self.parameters = parameters
     self.imageStrength = imageStrength
     self.moodboardCount = moodboardCount
+    self.maskSettings = maskSettings
   }
 
   /// What Draw Things receives: the trigger words of the job's LoRAs, in order, then the
@@ -42,6 +45,7 @@ public struct GenerationJob: Equatable, Codable, Sendable {
     parameters = try container.decode(GenerationParameters.self, forKey: .parameters)
     imageStrength = try? container.decodeIfPresent(Double.self, forKey: .imageStrength)
     moodboardCount = (try? container.decodeIfPresent(Int.self, forKey: .moodboardCount)) ?? 0
+    maskSettings = try? container.decodeIfPresent(MaskSettings.self, forKey: .maskSettings)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
index 0156d00..e14c42b 100644
--- a/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
+++ b/Packages/Sources/HubKit/Catalog/ModelCapabilities.swift
@@ -19,6 +19,10 @@ public struct ModelCapabilities: Equatable, Sendable {
   /// `inpainting`, `depth`… nil when the spec has none.
   public var modifier: String?
 
+  /// An inpainting model (SD inpainting, FLUX Fill...): Draw Things wants its inpaint control for
+  /// the mask. The other models take a mask without it (measured on SD 1.5 and FLUX.2 klein).
+  public var needsInpaintControl: Bool { modifier == "inpainting" }
+
   /// Edit and in-context models: the canvas image is the one to modify, and the Moodboard
   /// brings extra references (tab Control spec §2).
   public var isEditModel: Bool {
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubKit `62 tests … passed`, HubCore 238, DTBridge 57, Catalog 6, LLMBridge 6 (totale **369**).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: tipi della maschera (impostazioni, riferimento, ingressi, job, controllo inpaint)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: La maschera nella richiesta a Draw Things (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/JobMapper.swift`
- Test: `Packages/Tests/DTBridgeTests/JobMapperTests.swift`

**Interfaces:**
- Consumes: `GenerationInputs.mask`/`enableInpainting`, `GenerationJob.maskSettings`, `MaskSettings` (Task 1).
- Produces: `JobMapper.request(for:inputs:)` con un'immagine e una maschera imposta `request.mask`, `maskBlur`, `maskBlurOutset` (limitati), `preserveOriginalAfterInpaint` (da `job.maskSettings`, o i valori predefiniti di Draw Things senza) e `enableInpainting = inputs.enableInpainting`. Una maschera **senza immagine non parte** (la richiesta resta senza maschera e senza modifiche alla configurazione).

- [ ] **Step 1: Scrivere i test che falliscono**

```diff
diff --git a/Packages/Tests/DTBridgeTests/JobMapperTests.swift b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
index dfea68a..76dd755 100644
--- a/Packages/Tests/DTBridgeTests/JobMapperTests.swift
+++ b/Packages/Tests/DTBridgeTests/JobMapperTests.swift
@@ -96,6 +96,53 @@ struct JobMapperTests {
     }
   }
 
+  @Test func sendsTheMaskWithItsSettings() throws {
+    let image = try #require(TestImages.make(width: 64, height: 48))
+    let mask = try #require(TestImages.make(width: 64, height: 48))
+    var job = GenerationJob(prompt: "a fox", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 48))
+    job.imageStrength = 1
+    job.maskSettings = MaskSettings(blur: 4, outset: 12, preserveOriginal: false)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.mask === mask)
+    #expect(request.configuration.maskBlur == 4)
+    #expect(request.configuration.maskBlurOutset == 12)
+    #expect(!request.configuration.preserveOriginalAfterInpaint)
+    // No inpaint control unless the model needs it.
+    #expect(!request.configuration.enableInpainting)
+    let control = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask, enableInpainting: true))
+    #expect(control.configuration.enableInpainting)
+  }
+
+  @Test func aMaskWithoutSettingsGetsDrawThingsDefaults() throws {
+    let image = try #require(TestImages.make(width: 32, height: 32))
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    let job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: GenerationParameters(width: 64, height: 64))
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.configuration.maskBlur == 1.5)
+    #expect(request.configuration.maskBlurOutset == 0)
+    #expect(request.configuration.preserveOriginalAfterInpaint)
+  }
+
+  @Test func aMaskWithoutAnImageIsNotSent() throws {
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
+    job.maskSettings = MaskSettings(blur: 9, outset: 9, preserveOriginal: false)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(mask: mask, enableInpainting: true))
+    #expect(request.mask == nil)
+    #expect(request.configuration.maskBlur != 9)
+    #expect(!request.configuration.enableInpainting)
+  }
+
+  @Test func theMaskSettingsAreClampedBeforeTheyAreSent() throws {
+    let image = try #require(TestImages.make(width: 32, height: 32))
+    let mask = try #require(TestImages.make(width: 32, height: 32))
+    var job = GenerationJob(prompt: "x", model: "m.ckpt", parameters: .default)
+    job.maskSettings = MaskSettings(blur: 900, outset: 900, preserveOriginal: true)
+    let request = try JobMapper.request(for: job, inputs: GenerationInputs(image: image, mask: mask))
+    #expect(request.configuration.maskBlur == Float(MaskSettings.blurRange.upperBound))
+    #expect(request.configuration.maskBlurOutset == Int32(MaskSettings.outsetRange.upperBound))
+  }
+
   @Test func sendsTheNegativePromptAndTheLoRAs() {
     let parameters = GenerationParameters(loras: [
       LoRASelection(file: "style.safetensors", weight: 0.75, mode: .base), LoRASelection(file: "detail.safetensors"),
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter DTBridgeTests 2>&1 | grep -E "error:|Expectation failed" | grep -v started | head -3`
Expected: i test della maschera falliscono (aspettativa non soddisfatta: `request.mask` è nil).

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/DTBridge/JobMapper.swift b/Packages/Sources/DTBridge/JobMapper.swift
index ab6489c..33311f3 100644
--- a/Packages/Sources/DTBridge/JobMapper.swift
+++ b/Packages/Sources/DTBridge/JobMapper.swift
@@ -1,3 +1,4 @@
+import CoreGraphics
 import DrawThingsClient
 import HubKit
 
@@ -18,6 +19,16 @@ enum JobMapper {
     // The start image and its strength come from the Control tab, after the JSON editor's
     // extra settings: they win. Without an image the RUN stays text-to-image.
     if inputs.image != nil, let strength = job.imageStrength { configuration.strength = Float(strength) }
+    // The mask needs an image under it; Draw Things regenerates the transparent pixels.
+    var mask: CGImage?
+    if let drawn = inputs.mask, inputs.image != nil {
+      let settings = (job.maskSettings ?? MaskSettings()).clamped()
+      configuration.maskBlur = Float(settings.blur)
+      configuration.maskBlurOutset = Int32(settings.outset)
+      configuration.preserveOriginalAfterInpaint = settings.preserveOriginal
+      configuration.enableInpainting = inputs.enableInpainting
+      mask = drawn
+    }
     var hints = HintBuilder()
     for hint in inputs.hints { hints.addMoodboardImage(hint.imageData, weight: Float(hint.weight)) }
     let built: [HintProto]
@@ -28,7 +39,7 @@ enum JobMapper {
     }
     return GenerationRequest(
       prompt: job.promptWithTriggers, negativePrompt: job.negativePrompt,
-      configuration: configuration, image: inputs.image, hints: built)
+      configuration: configuration, image: inputs.image, mask: mask, hints: built)
   }
 
   /// The Draw Things configuration for a model and parameters: clamped, the Advanced cards
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: DTBridge `61 tests … passed`; totale 62 + 238 + 61 + 6 + 6 = **373**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la maschera e le sue impostazioni partono per Draw Things

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `MaskBitmap` — pennello, gomma, inverti, PNG, geometria (HubCore)

**Files:**
- Create: `Packages/Sources/HubCore/Control/MaskBitmap.swift`
- Test: `Packages/Tests/HubCoreTests/MaskBitmapTests.swift` (nuovo)

**Interfaces:**
- Produces (HubCore, `public`), `struct MaskBitmap: Equatable, Sendable`:
  - `width`, `height`, `pixels` (255 = da rigenerare), `static let maxSide = 1024`, `init(width:height:)` (vuota), `static func workingSize(imageWidth:imageHeight:) -> (width: Int, height: Int)`;
  - `isEmpty`, `coverage` (quota dei pixel ≥ 128);
  - `mutating func stroke(from:to:radius:erase:)` (pennello rotondo con un pixel di antialiasing lungo il segmento, in pixel della maschera), `invert()`, `clear()`;
  - `pngData()`, `init?(image: CGImage)` (qualunque immagine, letta in grigio alla sua dimensione);
  - `point(forViewPoint:viewSize:crop:imageWidth:)` e `brushRadius(diameter:canvasWidth:crop:imageWidth:)` (dalla vista alla maschera passando dal ritaglio);
  - `overlay(red:green:blue:opacity:) -> CGImage?` (colore traslucido premoltiplicato) e `grayImage()` (interno al modulo).

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskBitmapTests {
  func painted(_ bitmap: MaskBitmap, _ x: Int, _ y: Int) -> Bool { bitmap.pixels[y * bitmap.width + x] >= 128 }

  @Test func theWorkingSizeKeepsTheRatioAndCapsTheLongestSide() {
    #expect(MaskBitmap.workingSize(imageWidth: 4000, imageHeight: 2000) == (1024, 512))
    #expect(MaskBitmap.workingSize(imageWidth: 600, imageHeight: 800) == (600, 800))
    #expect(MaskBitmap.workingSize(imageWidth: 1000, imageHeight: 3000) == (341, 1024))
  }

  @Test func aNewMaskIsEmpty() {
    let mask = MaskBitmap(width: 40, height: 30)
    #expect(mask.isEmpty)
    #expect(mask.coverage == 0)
  }

  @Test func theBrushPaintsARoundSpot() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 10, erase: false)
    #expect(painted(mask, 50, 50))
    #expect(painted(mask, 58, 50))
    #expect(!painted(mask, 62, 50))
    // Round, not square: the corner of the square around the spot is clear.
    #expect(!painted(mask, 58, 58))
    #expect(!mask.isEmpty)
  }

  @Test func aStrokeLeavesNoGapBetweenItsEnds() {
    var mask = MaskBitmap(width: 200, height: 40)
    mask.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 180, y: 20), radius: 4, erase: false)
    for x in 20...180 { #expect(painted(mask, x, 20)) }
    #expect(!painted(mask, 100, 30))
  }

  @Test func theEraserTakesPaintAwayAndLeavesTheRest() {
    var mask = MaskBitmap(width: 100, height: 100)
    mask.stroke(from: CGPoint(x: 20, y: 50), to: CGPoint(x: 80, y: 50), radius: 8, erase: false)
    mask.stroke(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 50, y: 50), radius: 8, erase: true)
    #expect(!painted(mask, 50, 50))
    #expect(painted(mask, 30, 50))
    #expect(painted(mask, 70, 50))
  }

  @Test func theBrushStaysInsideTheMask() {
    var mask = MaskBitmap(width: 50, height: 50)
    mask.stroke(from: CGPoint(x: -30, y: -30), to: CGPoint(x: 5, y: 5), radius: 6, erase: false)
    mask.stroke(from: CGPoint(x: 45, y: 45), to: CGPoint(x: 90, y: 90), radius: 6, erase: false)
    #expect(painted(mask, 0, 0))
    #expect(painted(mask, 49, 49))
    mask.stroke(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 6, erase: false)
  }

  @Test func invertingSwapsPaintedAndClear() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 3, erase: false)
    let before = mask.coverage
    mask.invert()
    #expect(abs(mask.coverage - (1 - before)) < 0.01)
    #expect(!painted(mask, 5, 5))
    #expect(painted(mask, 19, 19))
  }

  @Test func clearingEmptiesTheMask() {
    var mask = MaskBitmap(width: 20, height: 20)
    mask.invert()
    #expect(mask.coverage == 1)
    mask.clear()
    #expect(mask.isEmpty)
  }

  @Test func theCoverageIsTheShareOfPaintedPixels() {
    var mask = MaskBitmap(width: 10, height: 10)
    for y in 0..<10 { mask.stroke(from: CGPoint(x: 0.5, y: Double(y) + 0.5), to: CGPoint(x: 4.5, y: Double(y) + 0.5), radius: 0.6, erase: false) }
    #expect(mask.coverage > 0.4 && mask.coverage < 0.6)
  }

  @Test func aPNGBringsTheSameMaskBack() throws {
    var mask = MaskBitmap(width: 64, height: 48)
    mask.stroke(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30), radius: 5, erase: false)
    let data = try #require(mask.pngData())
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let back = try #require(MaskBitmap(image: image))
    #expect(back.width == 64 && back.height == 48)
    #expect(back == mask)
  }

  @Test func theOverlayIsClearWhereNothingIsPainted() throws {
    var mask = MaskBitmap(width: 10, height: 10)
    mask.stroke(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), radius: 2, erase: false)
    let overlay = try #require(mask.overlay(red: 255, green: 140, blue: 0, opacity: 0.5))
    #expect(overlay.width == 10 && overlay.height == 10)
    let bytes = try #require(overlay.dataProvider?.data as Data?)
    #expect(bytes[3] == 0)  // top-left corner: nothing painted
    let centre = (5 * 10 + 5) * 4
    #expect(bytes[centre + 3] > 100)
    #expect(bytes[centre] > bytes[centre + 2])  // orange: more red than blue
  }
}

struct MaskGeometryTests {
  @Test func theWholeImageInTheViewMapsCornerToCorner() {
    let mask = MaskBitmap(width: 100, height: 50)
    let crop = CGRect(x: 0, y: 0, width: 200, height: 100)
    let view = CGSize(width: 400, height: 200)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 0, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 400, y: 200), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
    #expect(mask.point(forViewPoint: CGPoint(x: 200, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 25))
  }

  @Test func aCutShowsOnlyItsPartOfTheMask() {
    let mask = MaskBitmap(width: 100, height: 50)
    // The right half of a 200×100 image fills the view.
    let crop = CGRect(x: 100, y: 0, width: 100, height: 100)
    let view = CGSize(width: 100, height: 100)
    #expect(mask.point(forViewPoint: .zero, viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 50, y: 0))
    #expect(mask.point(forViewPoint: CGPoint(x: 100, y: 100), viewSize: view, crop: crop, imageWidth: 200) == CGPoint(x: 100, y: 50))
  }

  @Test func theBrushIsMeasuredOnTheCanvas() {
    let mask = MaskBitmap(width: 512, height: 512)
    // A 1024-pixel image shown whole on a 1024 canvas, mask at half size: a 100 px brush is 25 mask px of radius.
    let crop = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: crop, imageWidth: 1024) == 25)
    // A cut of half the image on the same canvas magnifies it: the same brush covers half as much of the image.
    let cut = CGRect(x: 0, y: 0, width: 512, height: 1024)
    #expect(mask.brushRadius(diameter: 100, canvasWidth: 1024, crop: cut, imageWidth: 1024) == 12.5)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter MaskBitmapTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'MaskBitmap' in scope`.

- [ ] **Step 3: Implementare**

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The inpaint mask as the tab draws it (tab Control spec §3): one byte per pixel, 255 where the
/// picture is to be regenerated. It lives at a working size (the start image's ratio, its longest
/// side at most 1024 px) so the brush stays fluent on any image; a RUN scales it to the canvas.
/// Draw Things takes a mask with no shades, so the brush has no softness: the edge is softened
/// there (`MaskSettings.blur`).
public struct MaskBitmap: Equatable, Sendable {
  public let width: Int
  public let height: Int
  public private(set) var pixels: [UInt8]

  /// Longest side of the working mask.
  public static let maxSide = 1024

  public init(width: Int, height: Int) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    pixels = [UInt8](repeating: 0, count: self.width * self.height)
  }

  /// The working size for an image: its ratio, the longest side at most `maxSide`.
  public static func workingSize(imageWidth: Int, imageHeight: Int) -> (width: Int, height: Int) {
    let longest = max(imageWidth, imageHeight, 1)
    let scale = min(1, Double(maxSide) / Double(longest))
    return (max(1, Int((Double(imageWidth) * scale).rounded())), max(1, Int((Double(imageHeight) * scale).rounded())))
  }

  /// True when nothing is painted.
  public var isEmpty: Bool { !pixels.contains { $0 >= 128 } }

  /// The share of the whole mask that is painted, 0…1.
  public var coverage: Double {
    Double(pixels.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) }) / Double(pixels.count)
  }

  // MARK: Drawing

  /// Paints (or erases) a round brush of `radius` pixels along the segment from `start` to `end`,
  /// in mask pixels. The edge has one pixel of antialiasing.
  public mutating func stroke(from start: CGPoint, to end: CGPoint, radius: Double, erase: Bool) {
    let radius = max(radius, 0.5)
    let length = hypot(end.x - start.x, end.y - start.y)
    let steps = max(1, Int((length / max(radius / 3, 0.5)).rounded(.up)))
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      stamp(
        at: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t), radius: radius,
        erase: erase)
    }
  }

  private mutating func stamp(at center: CGPoint, radius: Double, erase: Bool) {
    let minX = max(0, Int((center.x - radius - 1).rounded(.down)))
    let maxX = min(width - 1, Int((center.x + radius + 1).rounded(.up)))
    let minY = max(0, Int((center.y - radius - 1).rounded(.down)))
    let maxY = min(height - 1, Int((center.y + radius + 1).rounded(.up)))
    guard minX <= maxX, minY <= maxY else { return }
    for y in minY...maxY {
      for x in minX...maxX {
        // The pixel's centre against the circle; one pixel of edge is partly covered.
        let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
        let cover = min(1, max(0, radius + 0.5 - distance))
        guard cover > 0 else { continue }
        let index = y * width + x
        if erase {
          pixels[index] = UInt8(Double(pixels[index]) * (1 - cover))
        } else {
          pixels[index] = max(pixels[index], UInt8((cover * 255).rounded()))
        }
      }
    }
  }

  public mutating func invert() {
    for index in pixels.indices { pixels[index] = 255 - pixels[index] }
  }

  public mutating func clear() {
    pixels = [UInt8](repeating: 0, count: pixels.count)
  }

  // MARK: Files

  public func pngData() -> Data? {
    guard let image = grayImage() else { return nil }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
  }

  /// A mask read back from its PNG (any image: it is drawn in grey at the PNG's own size).
  public init?(image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: width * height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.width = width
    self.height = height
    pixels = bytes
  }

  func grayImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  // MARK: From the screen

  /// Where a point of the paint view falls in the mask. The view shows the cut `crop` (in the start
  /// image's pixels) of the image `imageWidth` pixels wide, and fills `viewSize`.
  public func point(forViewPoint point: CGPoint, viewSize: CGSize, crop: CGRect, imageWidth: Int) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0, imageWidth > 0 else { return .zero }
    let toMask = Double(width) / Double(imageWidth)
    return CGPoint(
      x: (crop.minX + point.x / viewSize.width * crop.width) * toMask,
      y: (crop.minY + point.y / viewSize.height * crop.height) * toMask)
  }

  /// The brush's radius in mask pixels for a brush `diameter` wide in canvas pixels.
  public func brushRadius(diameter: Double, canvasWidth: Int, crop: CGRect, imageWidth: Int) -> Double {
    guard canvasWidth > 0, imageWidth > 0 else { return 0 }
    return diameter / 2 * (crop.width / Double(canvasWidth)) * (Double(width) / Double(imageWidth))
  }

  // MARK: Showing and sending

  /// The mask as a translucent colour overlay (premultiplied), for the screen.
  public func overlay(red: UInt8, green: UInt8, blue: UInt8, opacity: Double) -> CGImage? {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for index in pixels.indices where pixels[index] > 0 {
      let alpha = Double(pixels[index]) / 255 * opacity
      bytes[index * 4] = UInt8((Double(red) * alpha).rounded())
      bytes[index * 4 + 1] = UInt8((Double(green) * alpha).rounded())
      bytes[index * 4 + 2] = UInt8((Double(blue) * alpha).rounded())
      bytes[index * 4 + 3] = UInt8((alpha * 255).rounded())
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `252 tests … passed` (14 nuovi); totale **387**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: MaskBitmap — pennello, gomma, inverti, PNG e geometria dalla vista alla maschera

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: La maschera per il canvas (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/InputComposer.swift`
- Test: `Packages/Tests/HubCoreTests/MaskComposerTests.swift` (nuovo)

**Interfaces:**
- Consumes: `MaskBitmap` (Task 3), `FramingMath.cropRect`, `Framing`.
- Produces: `InputComposer.mask(_ mask: MaskBitmap, imageWidth:imageHeight:toWidth:height:framing:) -> CGImage?`: RGBA premoltiplicato della dimensione esatta del canvas, **trasparente dove si rigenera** (maschera ≥ 128 dopo la scala) e opaco altrove, nello stesso ritaglio dell'immagine; `nil` se una dimensione è zero.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

struct MaskComposerTests {
  /// Alpha of the pixel at (x, y), counted from the top-left.
  func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return Int(bytes[3])
  }

  /// A 100×50 mask whose right half is painted.
  func rightHalf() -> MaskBitmap {
    var mask = MaskBitmap(width: 100, height: 50)
    for x in 50..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 50), radius: 0.7, erase: false) }
    return mask
  }

  @Test func thePaintedHalfIsTransparentAndTheRestOpaque() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 200, height: 100, framing: Framing()))
    #expect(canvas.width == 200 && canvas.height == 100)
    #expect(alpha(canvas, 20, 50) == 255)
    #expect(alpha(canvas, 180, 50) == 0)
  }

  @Test func theMaskFollowsTheCut() throws {
    // A square canvas over a 2:1 image shows its left half (offset −1): the painted half is out.
    let left = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: -1)))
    #expect(alpha(left, 10, 32) == 255 && alpha(left, 54, 32) == 255)
    // Offset 1 shows the right half: all of it is painted.
    let right = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(offsetX: 1)))
    #expect(alpha(right, 10, 32) == 0 && alpha(right, 54, 32) == 0)
  }

  @Test func theMaskIsScaledToTheCanvasWithAHardEdge() throws {
    let canvas = try #require(InputComposer.mask(rightHalf(), imageWidth: 200, imageHeight: 100, toWidth: 400, height: 200, framing: Framing()))
    var shades = Set<Int>()
    for x in stride(from: 0, to: 400, by: 7) { shades.insert(alpha(canvas, x, 100)) }
    #expect(shades == [0, 255])
  }

  @Test func paintAtTheTopOfTheMaskIsAtTheTopOfTheCanvas() throws {
    var mask = MaskBitmap(width: 100, height: 100)
    for x in 0..<100 { mask.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0.5), to: CGPoint(x: Double(x) + 0.5, y: 20.5), radius: 0.7, erase: false) }
    let canvas = try #require(InputComposer.mask(mask, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing()))
    #expect(alpha(canvas, 50, 5) == 0)
    #expect(alpha(canvas, 50, 90) == 255)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter MaskComposerTests 2>&1 | grep -E "error:" | head -2`
Expected: `type 'InputComposer' has no member 'mask'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/InputComposer.swift b/Packages/Sources/HubCore/Control/InputComposer.swift
index 0c36a4c..1a6514a 100644
--- a/Packages/Sources/HubCore/Control/InputComposer.swift
+++ b/Packages/Sources/HubCore/Control/InputComposer.swift
@@ -1,4 +1,5 @@
 import CoreGraphics
+import Foundation
 import HubKit
 
 /// Prepares the Control tab's images for a RUN (tab Control spec §6).
@@ -23,4 +24,41 @@ public enum InputComposer {
     context.draw(image, in: drawn)
     return context.makeImage()
   }
+
+  /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
+  /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
+  /// smoothing as the image and then cut at half, so its edge is clean at any scale.
+  public static func mask(
+    _ mask: MaskBitmap, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing
+  ) -> CGImage? {
+    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0, let gray = mask.grayImage() else { return nil }
+    let crop = FramingMath.cropRect(
+      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
+    var bytes = [UInt8](repeating: 0, count: width * height)
+    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
+      guard
+        let context = CGContext(
+          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
+          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
+      else { return false }
+      context.interpolationQuality = .high
+      let scale = Double(width) / crop.width
+      context.draw(
+        gray,
+        in: CGRect(
+          x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
+          height: Double(imageHeight) * scale))
+      return true
+    }
+    guard drawn else { return nil }
+    // Transparent (0) where regenerated; black, premultiplied, so the colour channels stay 0.
+    var rgba = [UInt8](repeating: 0, count: width * height * 4)
+    for index in bytes.indices where bytes[index] < 128 { rgba[index * 4 + 3] = 255 }
+    guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
+    return CGImage(
+      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
+      space: CGColorSpaceCreateDeviceRGB(),
+      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
+      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
+  }
 }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v started`
Expected: HubCore `256 tests … passed`; totale **391**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la maschera scalata al canvas nello stesso ritaglio dell'immagine

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: La maschera nello store e negli ingressi del RUN (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift`, `Packages/Sources/HubCore/Generation/JobComposer.swift`
- Test: `Packages/Tests/HubCoreTests/ControlStoreMaskTests.swift` (nuovo), `Packages/Tests/HubCoreTests/FamilyTraitsTests.swift`

**Interfaces:**
- Consumes: `MaskBitmap`, `InputComposer.mask`, `MaskReference`, `MaskSettings`, `ControlInputs.mask` (Task 1–4).
- Produces:
  - `ControlNotice.maskCleared`, `.maskMissingAtLaunch`;
  - `ControlStore.maskBitmap() -> MaskBitmap?`, `maskSize: (width: Int, height: Int)?` (nil senza immagine), `commitMask(_:) throws(ControlError)` (un passo della cronologia; vuota = nessuna maschera; niente senza immagine), `invertMask() throws(ControlError)`, `clearMask()` (con avviso e annulla), `setMaskSettings(_:)` (limitata, non è un passo);
  - cambiare o togliere l'immagine toglie la maschera; un avvio senza la copia scarta la maschera con `.maskMissingAtLaunch`; la pulizia delle copie considera le maschere di stato e cronologia;
  - `PendingInputs.render()` aggiunge `GenerationInputs.mask` (al canvas, nel ritaglio) se c'è maschera e immagine;
  - `JobComposer.batches(…, maskSettings: MaskSettings? = nil, …)` lo registra in ogni job.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import ImageIO
import Testing

@testable import HubCore

@MainActor
struct ControlStoreMaskTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ControlStoreMaskTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func copies(in root: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Control").path)) ?? []).sorted()
  }

  func withImage(_ root: URL, width: Int = 400, height: Int = 300) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: width, height: height), name: "a.png", source: .pasteboard)
    return store
  }

  func spot(_ store: ControlStore, at point: CGPoint = CGPoint(x: 50, y: 50), radius: Double = 10) -> MaskBitmap {
    let size = store.maskSize!
    var bitmap = store.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    bitmap.stroke(from: point, to: point, radius: radius, erase: false)
    return bitmap
  }

  @Test func theMaskIsDrawnAtTheWorkingSizeOfTheImage() throws {
    let store = try withImage(folder(), width: 4000, height: 2000)
    let size = try #require(store.maskSize)
    #expect(size.width == 1024 && size.height == 512)
  }

  @Test func aCommittedMaskIsKeptAndComesBackFromDisk() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    let reference = try #require(store.inputs.mask)
    #expect(reference.coverage > 0)
    let back = try #require(store.maskBitmap())
    #expect(back.width == 400 && back.height == 300)
    #expect(back.pixels[50 * back.width + 50] >= 128)
    #expect(copies(in: root).contains(reference.fileName))
  }

  @Test func eachStrokeIsAStepOfTheHistory() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    let first = store.inputs.mask
    try store.commitMask(spot(store, at: CGPoint(x: 300, y: 200)))
    #expect(store.inputs.mask != first)
    store.undo()
    #expect(store.inputs.mask == first)
    let back = try #require(store.maskBitmap())
    #expect(back.pixels[200 * back.width + 300] < 128)
    store.undo()
    #expect(store.inputs.mask == nil)
    store.redo()
    store.redo()
    #expect(store.inputs.mask != first)
  }

  @Test func anEmptyMaskIsNoMask() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    var bitmap = try #require(store.maskBitmap())
    bitmap.clear()
    try store.commitMask(bitmap)
    #expect(store.inputs.mask == nil)
  }

  @Test func committingAnEmptyMaskWithoutOneChangesNothing() throws {
    let store = try withImage(folder())
    let size = try #require(store.maskSize)
    try store.commitMask(MaskBitmap(width: size.width, height: size.height))
    #expect(store.inputs.mask == nil)
    #expect(store.canUndo)  // only the image's step
    store.undo()
    #expect(store.inputs.image == nil)
  }

  @Test func invertingAMaskDrawnNothingPaintsEverything() throws {
    let store = try withImage(folder())
    try store.invertMask()
    #expect(try #require(store.inputs.mask).coverage == 1)
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func clearingTheMaskSaysSoAndCanBeUndone() throws {
    let store = try withImage(folder())
    try store.commitMask(spot(store))
    let reference = store.inputs.mask
    store.clearMask()
    #expect(store.inputs.mask == nil)
    #expect(store.notice == .maskCleared)
    store.undo()
    #expect(store.inputs.mask == reference)
  }

  @Test func theMaskGoesWithTheImage() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store))
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.mask == nil)
    store.undo()
    #expect(store.inputs.mask != nil)
    store.removeImage()
    #expect(store.inputs.mask == nil)
  }

  @Test func withoutAnImageThereIsNothingToDraw() throws {
    let store = store(in: folder())
    #expect(store.maskSize == nil)
    try store.commitMask(MaskBitmap(width: 10, height: 10))
    try store.invertMask()
    #expect(store.inputs.mask == nil)
  }

  @Test func theMaskSurvivesARestart() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      store.setMaskSettings(MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    }
    let again = store(in: root)
    #expect(again.inputs.mask != nil)
    #expect(again.inputs.maskSettings == MaskSettings(blur: 4, outset: 8, preserveOriginal: false))
    #expect(again.maskBitmap() != nil)
  }

  @Test func aMaskWhoseCopyIsGoneIsDroppedWithANotice() throws {
    let root = folder()
    do {
      let store = try withImage(root)
      try store.commitMask(spot(store))
      let name = try #require(store.inputs.mask?.fileName)
      try FileManager.default.removeItem(at: root.appendingPathComponent("Control").appendingPathComponent(name))
    }
    let again = store(in: root)
    #expect(again.inputs.mask == nil)
    #expect(again.inputs.image != nil)
    #expect(again.notice == .maskMissingAtLaunch)
  }

  @Test func theCopiesOfOldMasksAreSweptWhenNothingRefersToThem() throws {
    let root = folder()
    let store = try withImage(root)
    try store.commitMask(spot(store, at: CGPoint(x: 50, y: 50)))
    try store.commitMask(spot(store, at: CGPoint(x: 100, y: 100)))
    let image = try #require(store.inputs.image).fileName
    #expect(copies(in: root).count == 3)  // image + the two masks (the first one is in the history)
    store.clear()
    store.undo()
    #expect(copies(in: root).count == 3)
    #expect(copies(in: root).contains(image))
  }

  @Test func theMaskSettingsAreClamped() throws {
    let store = try withImage(folder())
    store.setMaskSettings(MaskSettings(blur: 500, outset: -4, preserveOriginal: true))
    #expect(store.inputs.maskSettings.blur == MaskSettings.blurRange.upperBound)
    #expect(store.inputs.maskSettings.outset == 0)
  }

  @Test func withAMaskTheAutomaticStrengthIsFull() throws {
    let store = try withImage(folder())
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.7)
    try store.commitMask(spot(store))
    #expect(store.inputs.effectiveStrength(editModel: false) == 1.0)
    store.setStrength(0.4)
    #expect(store.inputs.effectiveStrength(editModel: false) == 0.4)
  }

  @Test func aRunGetsTheMaskAtTheCanvasSizeNextToTheImage() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    try store.commitMask(spot(store, at: CGPoint(x: 20, y: 20), radius: 15))
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    let mask = try #require(inputs.mask)
    #expect(mask.width == 256 && mask.height == 192)
    #expect(inputs.image?.width == 256)
    #expect(inputs.isEmpty == false)
  }

  @Test func withoutAMaskARunHasNone() async throws {
    let store = try withImage(folder())
    let pending = store.pendingInputs(canvasWidth: 128, canvasHeight: 96)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.mask == nil)
  }
}
```

```diff
diff --git a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
index 962b796..fc80361 100644
--- a/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
+++ b/Packages/Tests/HubCoreTests/FamilyTraitsTests.swift
@@ -91,6 +91,15 @@ struct JobComposerTests {
     #expect(compose(family: nil, .default).allSatisfy { $0.moodboardCount == 0 })
   }
 
+  @Test func everyBatchRecordsTheMaskSettings() {
+    let settings = MaskSettings(blur: 4, outset: 6, preserveOriginal: false)
+    let jobs = JobComposer.batches(
+      prompt: "fox", negativePrompt: "", model: "m.ckpt", family: nil, parameters: GenerationParameters(batchCount: 2),
+      catalog: catalog, maskSettings: settings) { 7 }
+    #expect(jobs.count == 2 && jobs.allSatisfy { $0.maskSettings == settings })
+    #expect(compose(family: nil, .default).allSatisfy { $0.maskSettings == nil })
+  }
+
   @Test func everyBatchRecordsTheStrengthOfTheStartImage() {
     let parameters = GenerationParameters(batchCount: 2)
     let withImage = JobComposer.batches(
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "ControlStoreMaskTests|FamilyTraitsTests" 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'ControlStore' has no member 'commitMask'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index 6c08df4..a13e1b1 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -11,6 +11,10 @@ public enum ControlNotice: Equatable, Sendable {
   case removed(name: String)
   case replaced(name: String)
   case cleared
+  /// The mask was emptied.
+  case maskCleared
+  /// At launch the copy of the saved mask was gone.
+  case maskMissingAtLaunch
   /// At launch the copy of the saved image was gone.
   case missingAtLaunch(name: String)
 }
@@ -55,6 +59,10 @@ public final class ControlStore {
       loaded.framing = Framing()
       notice = .missingAtLaunch(name: image.name)
     }
+    if let mask = loaded.mask, !storage.exists(mask.fileName) {
+      loaded.mask = nil
+      notice = .maskMissingAtLaunch
+    }
     for entry in loaded.moodboard where !storage.exists(entry.image.fileName) {
       loaded.moodboard.removeAll { $0.id == entry.id }
       notice = .missingAtLaunch(name: entry.image.name)
@@ -90,6 +98,7 @@ public final class ControlStore {
     var next = inputs
     next.image = image
     next.framing = Framing()
+    next.mask = nil  // drawn over the other picture
     let replaced = inputs.image
     commit(next)
     notice = replaced.map { .replaced(name: $0.name) }
@@ -115,6 +124,7 @@ public final class ControlStore {
     var next = inputs
     next.image = nil
     next.framing = Framing()
+    next.mask = nil
     commit(next)
     notice = .removed(name: image.name)
   }
@@ -126,6 +136,58 @@ public final class ControlStore {
     notice = .cleared
   }
 
+  // MARK: Mask
+
+  /// The mask as it is drawn, nil when there is none.
+  public func maskBitmap() -> MaskBitmap? {
+    guard let mask = inputs.mask, let image = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide)
+    else { return nil }
+    return MaskBitmap(image: image)
+  }
+
+  /// The size a mask over the start image is drawn at; nil without an image.
+  public var maskSize: (width: Int, height: Int)? {
+    inputs.image.map { MaskBitmap.workingSize(imageWidth: $0.pixelWidth, imageHeight: $0.pixelHeight) }
+  }
+
+  /// Takes the mask as drawn (one step of the history). An empty mask is no mask. Nothing without
+  /// a start image.
+  public func commitMask(_ bitmap: MaskBitmap) throws(ControlError) {
+    guard inputs.image != nil else { return }
+    var next = inputs
+    if bitmap.isEmpty {
+      guard inputs.mask != nil else { return }
+      next.mask = nil
+    } else {
+      guard let data = bitmap.pngData() else { throw .cannotSave("mask") }
+      let stored = try storage.save(data, name: "mask.png")
+      next.mask = MaskReference(fileName: stored.fileName, coverage: bitmap.coverage)
+    }
+    commit(next)
+  }
+
+  /// Paints what was clear and clears what was painted (a mask not drawn yet becomes everything).
+  public func invertMask() throws(ControlError) {
+    guard let size = maskSize else { return }
+    var bitmap = maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
+    bitmap.invert()
+    try commitMask(bitmap)
+  }
+
+  public func clearMask() {
+    guard inputs.mask != nil else { return }
+    var next = inputs
+    next.mask = nil
+    commit(next)
+    notice = .maskCleared
+  }
+
+  /// How Draw Things treats the mask; not part of the history.
+  public func setMaskSettings(_ settings: MaskSettings) {
+    inputs.maskSettings = settings.clamped()
+    save()
+  }
+
   // MARK: Moodboard
 
   /// Adds a picture to the Moodboard (on, at the end).
@@ -297,8 +359,8 @@ public final class ControlStore {
   public func pendingInputs(canvasWidth: Int, canvasHeight: Int, includeMoodboard: Bool = true) -> PendingInputs {
     let sent = inputs.moodboard.filter(\.isOn).map { (image: $0.image, weight: 1.0) }
     return PendingInputs(
-      storage: storage, image: inputs.image, framing: inputs.framing, canvasWidth: canvasWidth,
-      canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
+      storage: storage, image: inputs.image, mask: inputs.image == nil ? nil : inputs.mask, framing: inputs.framing,
+      canvasWidth: canvasWidth, canvasHeight: canvasHeight, moodboard: includeMoodboard ? sent : [])
   }
 
   // MARK: Private
@@ -363,6 +425,7 @@ public final class ControlStore {
     var referenced = Set<String>()
     for state in undoStack + redoStack + [inputs] {
       if let image = state.image { referenced.insert(image.fileName) }
+      if let mask = state.mask { referenced.insert(mask.fileName) }
       for entry in state.moodboard { referenced.insert(entry.image.fileName) }
     }
     for name in storage.allFileNames() where !referenced.contains(name) { storage.remove(name) }
@@ -373,6 +436,7 @@ public final class ControlStore {
 public struct PendingInputs: Sendable {
   let storage: any ReferenceStorage
   let image: ReferenceImage?
+  let mask: MaskReference?
   let framing: Framing
   let canvasWidth: Int
   let canvasHeight: Int
@@ -400,7 +464,14 @@ public struct PendingInputs: Sendable {
     guard let decoded = storage.image(named: image.fileName, maxPixel: maxPixel),
       let framed = InputComposer.frame(decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing)
     else { throw .unreadable(image.name) }
-    return GenerationInputs(image: framed, hints: hints)
+    guard let mask else { return GenerationInputs(image: framed, hints: hints) }
+    guard let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
+      let bitmap = MaskBitmap(image: stored),
+      let scaled = InputComposer.mask(
+        bitmap, imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, toWidth: canvasWidth,
+        height: canvasHeight, framing: framing)
+    else { throw .unreadable(image.name) }
+    return GenerationInputs(image: framed, hints: hints, mask: scaled)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubCore/Generation/JobComposer.swift b/Packages/Sources/HubCore/Generation/JobComposer.swift
index ee1fd51..d996075 100644
--- a/Packages/Sources/HubCore/Generation/JobComposer.swift
+++ b/Packages/Sources/HubCore/Generation/JobComposer.swift
@@ -9,7 +9,7 @@ public enum JobComposer {
   public static func batches(
     prompt: String, negativePrompt: String, model: String, family: String?,
     parameters: GenerationParameters, catalog: ModelCatalog, imageStrength: Double? = nil,
-    moodboardCount: Int = 0, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
+    moodboardCount: Int = 0, maskSettings: MaskSettings? = nil, randomSeed draw: () -> UInt32 = { UInt32.random(in: .min ... .max) }
   ) -> [GenerationJob] {
     let traits = FamilyTraits.of(family)
     var sent = parameters
@@ -20,7 +20,7 @@ public enum JobComposer {
     return sent.batchesForRun(randomSeed: draw).map {
       GenerationJob(
         prompt: prompt, negativePrompt: negative, model: model, parameters: $0, imageStrength: imageStrength,
-        moodboardCount: moodboardCount)
+        moodboardCount: moodboardCount, maskSettings: maskSettings)
     }
   }
 
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `273 tests … passed` (17 nuovi); totale **408**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la maschera nello store (un passo per tratto, copie, ripristino) e negli ingressi del RUN

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: I testi della maschera (catalogo)

**Files:**
- Modify: `App/Localizable.xcstrings` (19 chiavi nuove)
- Test: `Packages/Tests/CatalogTests/LocalizationCatalogTests.swift` (esistente)

**Interfaces:**
- Produces: le chiavi `control.strip.mask`, `control.mask.*`, `control.redo`, `control.notice.maskCleared`, `control.notice.maskMissing`, `control.strength.mask`, usate dalle viste del Task 7.

- [ ] **Step 1: Aggiungere le chiavi senza riformattare il catalogo**

Salvare lo script seguente in un file temporaneo ed eseguirlo dalla radice del repository (`python3 <file>`):

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "control.strip.mask": ("Mask", "Maschera"),
    "control.mask.title": ("Mask", "Maschera"),
    "control.mask.empty": ("Load an image to draw the mask.", "Carica un'immagine per disegnare la maschera."),
    "control.mask.hint": ("Paint what Draw Things should regenerate. The picture is shown as it is sent.", "Dipingi ciò che Draw Things deve rigenerare. L'immagine è mostrata come viene inviata."),
    "control.mask.tool": ("Tool", "Strumento"),
    "control.mask.brush": ("Brush", "Pennello"),
    "control.mask.eraser": ("Eraser", "Gomma"),
    "control.mask.size": ("Size", "Dimensione"),
    "control.mask.invert": ("Invert", "Inverti"),
    "control.mask.clear": ("Clear", "Svuota"),
    "control.mask.blur": ("Blur", "Sfumatura"),
    "control.mask.outset": ("Margin", "Margine"),
    "control.mask.preserve": ("Keep the original outside the mask", "Conserva l'originale fuori dalla maschera"),
    "control.mask.blur.help": ("How much the edge of the mask is softened.", "Quanto si ammorbidisce il bordo della maschera."),
    "control.mask.outset.help": ("How far the area around the mask is taken into the render.", "Quanto dell'area intorno alla maschera entra nel render."),
    "control.redo": ("Redo", "Ripeti"),
    "control.notice.maskCleared": ("Mask cleared.", "Maschera svuotata."),
    "control.notice.maskMissing": ("The saved mask was gone and was dropped.", "La maschera salvata non c'era più ed è stata scartata."),
    "control.strength.mask": ("With a mask the strength is 100%: the painted area is regenerated whole.", "Con la maschera la forza è al 100%: l'area dipinta viene rigenerata per intero."),
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
Expected: `1 file changed, 323 insertions(+)` e nessuna riga tolta.

- [ ] **Step 2: Verificare il catalogo**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter CatalogTests 2>&1 | grep -E "Test run with|Missing|Not in"`
Expected: `6 tests … passed` (le chiavi non ancora usate non sono un errore).

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App/Localizable.xcstrings && git commit -m "feat: testi della maschera (it, en)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: La scheda Maschera e i collegamenti (App)

**Files:**
- Create: `App/Control/MaskCard.swift`
- Modify: `App/Control/ControlStrip.swift`, `ControlTabView.swift`, `ControlText.swift`, `ImageCard.swift`, `App/Generation/GenerationController.swift`

**Interfaces:**
- Consumes: tutto ciò che producono i Task 1–6; `GenerationController.selectedModel(in:)` (esistente).
- Produces:
  - `MaskCard(generation:report:)`: strumenti (Pennello/Gomma, Annulla/Ripeti della cronologia del tab, Inverti, Svuota, Dimensione), area di disegno (`Canvas`, ritaglio del canvas con la maschera in arancio e il cerchio del pennello; ogni tratto è un passo: `commitMask` a fine tratto), Sfumatura, Margine, "Conserva l'originale"; senza immagine il testo "Carica un'immagine…";
  - il chip "Maschera N%" nella striscia (✕ = `clearMask`);
  - il testo della forza che dice «con la maschera 100%»;
  - il RUN: `maskSettings` nel job solo con una maschera, `enableInpainting` dal modello (`needsInpaintControl`), "Riprendi parametri" rimette le impostazioni.

Questo task è codice di vista: la verifica è la compilazione (Step 3) e la prova dal vivo (Task 8).

- [ ] **Step 1: Creare la scheda**

```swift
import HubCore
import HubKit
import SwiftUI

/// The inpaint mask (spec: tab Control §3): the canvas as Draw Things gets it, with the area to
/// regenerate painted in orange; brush, eraser, invert, clear, and the settings of the mask.
/// Each stroke is one step of the tab's history (⌘Z).
struct MaskCard: View {
  let generation: GenerationController
  let report: (ControlMessage) -> Void
  @State private var picture: CGImage?
  /// The mask being drawn: read from the store, changed by the brush, given back at the end of a stroke.
  @State private var working: MaskBitmap?
  @State private var overlay: CGImage?
  /// What `working` was read from, so a stroke we committed ourselves is not read back.
  @State private var loadedKey: LoadKey?
  @State private var lastPoint: CGPoint?
  @State private var hover: CGPoint?
  @State private var erasing = false
  /// The brush's diameter in canvas pixels.
  @AppStorage("control.brushSize") private var brushSize = 96.0

  private struct LoadKey: Hashable {
    let image: UUID?
    let mask: String?
  }

  private var control: ControlStore { generation.control }
  private var canvasWidth: Int { generation.parameters.width }
  private var canvasHeight: Int { generation.parameters.height }
  private var key: LoadKey { LoadKey(image: control.inputs.image?.id, mask: control.inputs.mask?.fileName) }

  var body: some View {
    DSCollapsibleCard(
      String(localized: "control.mask.title"), systemImage: "paintbrush.pointed",
      isExpanded: generation.cards.binding("control.mask")
    ) {
      VStack(alignment: .leading, spacing: DS.rowGap) {
        if let image = control.inputs.image {
          tools
          paintArea(for: image)
          Text("control.mask.hint").font(.caption).foregroundStyle(.secondary)
          settings
        } else {
          Text("control.mask.empty").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 18)
        }
      }
    }
    .task(id: control.inputs.image?.id) {
      guard let request = control.previewRequest(maxPixel: 1400) else { return picture = nil }
      picture = await Task.detached { request.render() }.value
    }
    .task(id: key) { load() }
  }

  // MARK: Tools

  private var tools: some View {
    VStack(alignment: .leading, spacing: DS.controlGap) {
      HStack(spacing: DS.controlGap) {
        Picker(String(localized: "control.mask.tool"), selection: $erasing) {
          Text("control.mask.brush").tag(false)
          Text("control.mask.eraser").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 190)
        Spacer(minLength: 0)
        Button("control.undo") { control.undo() }.disabled(!control.canUndo).buttonStyle(DSPillButtonStyle())
        Button("control.redo") { control.redo() }.disabled(!control.canRedo).buttonStyle(DSPillButtonStyle())
      }
      HStack(spacing: DS.controlGap) {
        Button("control.mask.invert") { attempt { () throws(ControlError) in try control.invertMask() } }.buttonStyle(DSPillButtonStyle())
        Button("control.mask.clear") { control.clearMask() }
          .disabled(control.inputs.mask == nil).buttonStyle(DSPillButtonStyle())
        Spacer(minLength: 0)
      }
      CardRow(label: String(localized: "control.mask.size")) {
        Slider(value: $brushSize, in: 8...512, step: 1).frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(Int(brushSize)) px").font(.callout).monospacedDigit().foregroundStyle(.secondary)
          .frame(width: 64, alignment: .trailing)
      }
    }
  }

  private var settings: some View {
    let binding = Binding(get: { control.inputs.maskSettings }, set: { control.setMaskSettings($0) })
    return VStack(alignment: .leading, spacing: DS.controlGap) {
      CardRow(label: String(localized: "control.mask.blur")) {
        Slider(
          value: Binding(get: { binding.wrappedValue.blur }, set: { binding.wrappedValue.blur = $0 }),
          in: MaskSettings.blurRange, step: 0.5
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: binding.wrappedValue.blur.formatted(.number.precision(.fractionLength(1))))
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.blur.help"))
      CardRow(label: String(localized: "control.mask.outset")) {
        Slider(
          value: Binding(
            get: { Double(binding.wrappedValue.outset) }, set: { binding.wrappedValue.outset = Int($0.rounded()) }),
          in: Double(MaskSettings.outsetRange.lowerBound)...Double(MaskSettings.outsetRange.upperBound), step: 1
        )
        .frame(minWidth: 120)
      } control: {
        Text(verbatim: "\(binding.wrappedValue.outset)")
          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
      }
      .help(String(localized: "control.mask.outset.help"))
      Toggle(
        isOn: Binding(
          get: { binding.wrappedValue.preserveOriginal }, set: { binding.wrappedValue.preserveOriginal = $0 })
      ) {
        Text("control.mask.preserve")
      }
    }
  }

  // MARK: Painting

  private func paintArea(for image: ReferenceImage) -> some View {
    let crop = FramingMath.cropRect(
      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, framing: control.inputs.framing)
    let ratio = Double(canvasWidth) / Double(max(canvasHeight, 1))
    // A fixed height keeps the card's ideal size; the picture takes the largest rectangle of the
    // canvas' ratio that fits, centered.
    return GeometryReader { outer in
      let width = min(outer.size.width, Self.paintHeight * ratio)
      let size = CGSize(width: width, height: width / max(ratio, 0.01))
      painting(image: image, crop: crop, size: size)
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: Self.paintHeight)
  }

  private static let paintHeight = 380.0

  private func painting(image: ReferenceImage, crop: CGRect, size: CGSize) -> some View {
    Canvas { context, size in
      // The whole image, placed so that the cut fills the view: what shows is what is sent.
      let scale = size.width / crop.width
      let rect = CGRect(
        x: -crop.minX * scale, y: -crop.minY * scale, width: Double(image.pixelWidth) * scale,
        height: Double(image.pixelHeight) * scale)
      if let picture {
        context.draw(Image(decorative: picture, scale: 1), in: rect)
      } else {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.08)))
      }
      if let overlay { context.draw(Image(decorative: overlay, scale: 1), in: rect) }
      if let hover {
        let radius = brushSize / 2 * size.width / Double(max(canvasWidth, 1))
        let ring = Path(ellipseIn: CGRect(x: hover.x - radius, y: hover.y - radius, width: radius * 2, height: radius * 2))
        context.stroke(ring, with: .color(.black.opacity(0.6)), lineWidth: 2.5)
        context.stroke(ring, with: .color(.white), lineWidth: 1.2)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
    .contentShape(Rectangle())
    .onContinuousHover { phase in
      switch phase {
      case .active(let point): hover = point
      case .ended: hover = nil
      }
    }
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { value in paint(to: value.location, in: size, image: image, crop: crop) }
        .onEnded { _ in endStroke() })
  }

  /// Continues the stroke to a point of the view.
  private func paint(to point: CGPoint, in size: CGSize, image: ReferenceImage, crop: CGRect) {
    guard var bitmap = working, size.width > 0, size.height > 0 else { return }
    hover = point
    // View → image pixels (through the cut) → mask pixels.
    let radius = bitmap.brushRadius(diameter: brushSize, canvasWidth: canvasWidth, crop: crop, imageWidth: image.pixelWidth)
    let end = bitmap.point(forViewPoint: point, viewSize: size, crop: crop, imageWidth: image.pixelWidth)
    let start = lastPoint.map { bitmap.point(forViewPoint: $0, viewSize: size, crop: crop, imageWidth: image.pixelWidth) } ?? end
    lastPoint = point
    bitmap.stroke(from: start, to: end, radius: radius, erase: erasing)
    overlay = bitmap.overlay(red: 255, green: 140, blue: 0, opacity: 0.55)
    working = bitmap
  }

  private func endStroke() {
    guard lastPoint != nil, let bitmap = working else { return }
    lastPoint = nil
    do {
      try control.commitMask(bitmap)
      loadedKey = key
    } catch {
      report(.error(ControlText.error(error)))
    }
  }

  /// Reads the mask from the store when the image or the mask changed under us (undo, redo, clear,
  /// a new image); a stroke just committed here is already on screen.
  private func load() {
    guard loadedKey != key, let size = control.maskSize else {
      if control.inputs.image == nil { working = nil; overlay = nil; loadedKey = nil }
      return
    }
    let bitmap = control.maskBitmap() ?? MaskBitmap(width: size.width, height: size.height)
    working = bitmap
    overlay = bitmap.isEmpty ? nil : bitmap.overlay(red: 255, green: 140, blue: 0, opacity: 0.55)
    loadedKey = key
  }

  private func attempt(_ action: () throws(ControlError) -> Void) {
    do { try action() } catch { report(.error(ControlText.error(error))) }
  }
}
```

- [ ] **Step 2: Applicare le modifiche ai file esistenti**

```diff
diff --git a/App/Control/ControlStrip.swift b/App/Control/ControlStrip.swift
index b95b593..749df21 100644
--- a/App/Control/ControlStrip.swift
+++ b/App/Control/ControlStrip.swift
@@ -22,6 +22,11 @@ struct ControlStrip: View {
             detail: "\(image.pixelWidth)×\(image.pixelHeight)",
             remove: { control.removeImage() })
         }
+        if let mask = control.inputs.mask {
+          chip(
+            systemImage: "paintbrush.pointed", title: String(localized: "control.strip.mask"),
+            detail: "\(max(1, Int((mask.coverage * 100).rounded())))%", remove: { control.clearMask() })
+        }
         if !control.inputs.moodboard.isEmpty {
           chip(
             systemImage: "square.grid.2x2", title: String(localized: "control.strip.moodboard"),
```

```diff
diff --git a/App/Control/ControlTabView.swift b/App/Control/ControlTabView.swift
index db5ed10..7a3abfb 100644
--- a/App/Control/ControlTabView.swift
+++ b/App/Control/ControlTabView.swift
@@ -2,8 +2,8 @@ import HubCore
 import HubKit
 import SwiftUI
 
-/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt. In this first
-/// step the start image; the Moodboard and the mask come next.
+/// The Control tab (spec: tab Control): what goes into a RUN besides the prompt: the start image,
+/// the Moodboard and the inpaint mask.
 struct ControlTabView: View {
   let generation: GenerationController
   let connection: DrawThingsConnection
@@ -23,7 +23,10 @@ struct ControlTabView: View {
             ImageCard(generation: generation, connection: connection) { message = $0 }
             MoodboardCard(generation: generation, connection: connection) { message = $0 }
           }
-          CanvasStage(generation: generation)
+          VStack(spacing: DS.groupGap) {
+            CanvasStage(generation: generation)
+            MaskCard(generation: generation) { message = $0 }
+          }
         }
       }
       .padding(.bottom, DS.groupGap)
```

```diff
diff --git a/App/Control/ControlText.swift b/App/Control/ControlText.swift
index bc137a8..792fe72 100644
--- a/App/Control/ControlText.swift
+++ b/App/Control/ControlText.swift
@@ -26,6 +26,8 @@ enum ControlText {
     case .replaced(let name): String(format: String(localized: "control.notice.replaced"), name)
     case .cleared: String(localized: "control.notice.cleared")
     case .missingAtLaunch(let name): String(format: String(localized: "control.notice.missing"), name)
+    case .maskCleared: String(localized: "control.notice.maskCleared")
+    case .maskMissingAtLaunch: String(localized: "control.notice.maskMissing")
     }
   }
 
```

```diff
diff --git a/App/Control/ImageCard.swift b/App/Control/ImageCard.swift
index b9291c1..1232d98 100644
--- a/App/Control/ImageCard.swift
+++ b/App/Control/ImageCard.swift
@@ -122,6 +122,8 @@ struct ImageCard: View {
       HStack(spacing: DS.controlGap) {
         if edit {
           Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
+        } else if control.inputs.mask != nil, control.inputs.strength == nil {
+          Text("control.strength.mask").font(.caption).foregroundStyle(.secondary)
         }
         if control.inputs.strength != nil {
           Button("control.strength.auto") { control.setStrength(nil) }
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index aa6ab27..21d02d5 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -198,7 +198,8 @@ final class GenerationController {
       prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
       parameters: parameters, catalog: connection.monitor.catalog,
       imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)),
-      moodboardCount: inputs.hints.count)
+      moodboardCount: inputs.hints.count,
+      maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
     if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
     session.start(batches, inputs: inputs, backend: backend, monitor: connection.monitor)
   }
@@ -211,7 +212,9 @@ final class GenerationController {
       canvasWidth: parameters.width, canvasHeight: parameters.height,
       includeMoodboard: FamilyTraits.of(family(in: connection)).usesMoodboard)
     do {
-      return try await Task.detached { try pending.render() }.value
+      var inputs = try await Task.detached { try pending.render() }.value
+      inputs.enableInpainting = selectedModel(in: connection)?.capabilities.needsInpaintControl ?? false
+      return inputs
     } catch {
       let text = (error as? ControlError).map(ControlText.error) ?? error.localizedDescription
       session.fail(with: .generationFailed(text))
@@ -252,6 +255,7 @@ final class GenerationController {
     parameters = result.job.parameters
     if lockRatio { lockedRatio = currentRatio }
     if let strength = result.job.imageStrength { control.setStrength(strength) }
+    if let settings = result.job.maskSettings { control.setMaskSettings(settings) }
     connection.selection.select(result.job.model)
   }
 
```

- [ ] **Step 3: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m7c-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v "started\|reportsFailures"`
Expected: `** BUILD SUCCEEDED **` (in una cartella a parte, per non toccare un'app aperta); test HubKit 62, HubCore 273, DTBridge 61, Catalog 6, LLMBridge 6 = **408** passati.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: scheda Maschera — pennello, gomma, inverti, svuota, impostazioni, chip nella striscia e RUN con inpaint

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Verifica dal vivo

**Files:**
- Modify: `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (una prova con server vero, inattiva senza variabile d'ambiente)

- [ ] **Step 1: Aggiungere la prova dal vivo**

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index 1d716dc..dd20e29 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -140,6 +140,73 @@ struct LiveServerTests {
     print("LIVE z-image moodboard: right minus left plain \(rightMinusLeft(plain)) guided \(rightMinusLeft(guided))")
   }
 
+  /// Inpainting, measured on SD 1.5 (Juggernaut Reborn) and FLUX.2 klein: a solid blue picture whose
+  /// right half is masked is asked to become red poppies. The left half stays as it was and the
+  /// right half is regenerated, at strength 100 % and without the inpaint control (which changed
+  /// nothing on these models: measured with it on and off). At strength 70 % the masked half
+  /// stayed blue, so the tab's automatic strength with a mask is 100 %.
+  @Test(.enabled(if: address != nil))
+  func aMaskKeepsTheOutsideAndRegeneratesTheInside() async throws {
+    let backend = try await liveBackend()
+    let models = try await backend.fetchCatalog().models
+    let cases: [(label: String, file: String, steps: Int, guidance: Double)] = [
+      ("sd15", models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file ?? "", 12, 4),
+      ("klein", models.first { $0.family == "flux2_9b" }?.file ?? "", 4, 1),
+    ]
+    let source = try #require(solid(red: 0, green: 0, blue: 255, size: 512))
+    let sourceLeft = blueShare(try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512))))
+    let mask = halfMask(size: 512)
+    var ran = 0
+    for item in cases where !item.file.isEmpty {
+      var job = GenerationJob(
+        prompt: "a field of bright red poppies", model: item.file,
+        parameters: GenerationParameters(
+          width: 512, height: 512, steps: item.steps, guidanceScale: item.guidance, sampler: .ddimTrailing, seed: 7,
+          randomSeed: false))
+      job.imageStrength = 1.0
+      job.maskSettings = MaskSettings()
+      let out = try await run(backend, job, GenerationInputs(image: source, mask: mask))
+      let left = try #require(out.cropping(to: CGRect(x: 0, y: 0, width: 256, height: 512)))
+      let right = try #require(out.cropping(to: CGRect(x: 256, y: 0, width: 256, height: 512)))
+      print("LIVE inpaint \(item.label): left blue \(blueShare(left)) (source \(sourceLeft)) right red \(redShare(right))")
+      #expect(abs(blueShare(left) - sourceLeft) < 0.03)
+      #expect(redShare(right) > 0.3)
+      ran += 1
+    }
+    await backend.shutdown()
+    #expect(ran > 0, "needs Juggernaut Reborn or a FLUX.2 klein model on the server")
+  }
+
+  /// 512×512, the right half transparent (to regenerate), the left half opaque (to keep).
+  private func halfMask(size: Int) -> CGImage {
+    let context = CGContext(
+      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
+    context.fill(CGRect(x: 0, y: 0, width: size / 2, height: size))
+    return context.makeImage()!
+  }
+
+  private func averageColor(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
+    var bytes = [UInt8](repeating: 0, count: 4)
+    let context = CGContext(
+      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
+      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
+    context.interpolationQuality = .medium
+    context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
+    return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255)
+  }
+
+  private func redShare(_ image: CGImage) -> Double {
+    let c = averageColor(image)
+    return c.r / max(c.r + c.g + c.b, 0.001)
+  }
+
+  private func blueShare(_ image: CGImage) -> Double {
+    let c = averageColor(image)
+    return c.b / max(c.r + c.g + c.b, 0.001)
+  }
+
   private func liveBackend() async throws -> DrawThingsBackend {
     let parts = try #require(Self.address?.split(separator: ":"))
     return DrawThingsBackend(host: String(parts[0]), port: Int(parts[1]) ?? 7859, useTLS: true, sharedSecret: nil)
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: DTBridge `62 tests … passed` (la prova è inattiva), totale **409**.

- [ ] **Step 2: Provarla con un server vero**

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (Juggernaut Reborn, FLUX.2 klein). Si avvia a mano, solo per la prova, **e solo se l'app dell'utente non sta usando la porta**: qui la 7861.

```bash
(nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7861 --model-browser > /tmp/m7c-server.log 2>&1 &); sleep 6
cd "/Users/existenz/Software developement/DT Hub/Packages" && DTHUB_LIVE_DT=localhost:7861 swift test --filter aMaskKeepsTheOutside 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
pkill -TERM -f gRPCServerCLI
```

Expected: due righe `LIVE inpaint …: left blue X (source X) right red …` con X uguali (la parte fuori dalla maschera non cambia) e il rosso a destra sopra 0,3; il test passa. Può volerci qualche minuto (carica i modelli dal disco esterno).

- [ ] **Step 3: Provare l'app**

Chiedere all'utente di chiudere il suo DT Hub se è aperto. Per non toccare i suoi dati: salvare `~/Library/Application Support/DT Hub` (`cp -R`) e le preferenze (`defaults export com.exiztenz.DTHub /tmp/m7c-defaults.plist`); preparare una immagine di prova (768×512, una casa su un prato) in `Control/` e un `control.json` con quell'immagine; in `session.json` canvas 768×512, 12 passi, modello Juggernaut Reborn; cartella di output temporanea (`defaults write com.exiztenz.DTHub output.folder /tmp/dthub-m7c-out`). Aprire l'app compilata in una cartella a parte.

Checklist:
1. Il tab Control mostra la scheda Maschera sotto il Canvas con l'immagine del canvas e il cerchio del pennello che segue il puntatore.
2. Un tratto lo colora in arancio e fa comparire il chip "Maschera N%" nella striscia; la Forza mostra 100 con la frase «Con la maschera la forza è al 100%…».
3. Run: il PNG salvato rigenera solo la zona dipinta (il resto è identico) e nei metadati ha `"maskSettings":{"blur":1.5,"outset":0,"preserveOriginal":true}` e `"imageStrength":1`.
4. Inverti colora tutto il resto (il chip mostra la percentuale complementare); Annulla toglie l'inversione; la Gomma cancella dove si passa; Svuota toglie la maschera (avviso e Annulla).
5. Chiudere e riaprire l'app: la maschera è ancora lì (stessa percentuale).
6. Con un tratto abbastanza lungo la fluidità del pennello è accettabile (si annota a occhio).

- [ ] **Step 4: Pulizia** (sempre, anche se qualcosa non va)

Fermare app e server, ripristinare la cartella `DT Hub` e le preferenze salvate, togliere `output.folder` e la cartella `/tmp/dthub-m7c-out`; rimettere `workspace.selectedTab` e `drawThings.selectedModel` dell'utente.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "test: prova dal vivo dell'inpaint (SD 1.5 e FLUX.2 klein)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7c

Esito atteso sul branch `m7c-maschera`:
- **409 test verdi** (1 prova dal vivo in più inattiva senza `DTHUB_LIVE_DT`, provata con il server);
- build Xcode pulita;
- l'inpaint funziona dall'app: si dipinge la maschera sul canvas, il RUN rigenera solo quella zona, tutto si annulla, tutto torna all'avvio.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M7c: Tiled Diffusion 8192, outpaint, M8 Plug-in.

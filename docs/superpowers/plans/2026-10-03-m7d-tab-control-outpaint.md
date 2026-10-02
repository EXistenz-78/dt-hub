# M7d Tab Control — Outpaint (slider Zoom) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La card **Canvas** del tab Control ha uno slider **Zoom** da −100 a +100 che rimpicciolisce (margini da rigenerare: **outpaint**) o ingrandisce l'immagine di partenza nel canvas; il trascinamento la sposta; il RUN manda l'immagine nella sua posizione, i margini estesi dal bordo e una maschera che li rigenera. **L'outpaint funziona.**

**Architecture:**
- **HubKit**: `Framing` perde il modo e ottiene `zoom` (−100…+100); `effectiveStrength` conosce i margini.
- **HubCore**: la finestra sull'immagine (`FramingMath.cropRect`) può uscire dall'immagine: la parte fuori è margine. `FramingMath` calcola fattore, margini, zoom "contiene", quota usata; `InputComposer` estende i bordi nei margini e fa la maschera anche senza maschera dipinta; lo store ha `setZoom`, `resetFraming`, `hasMargins` e manda la maschera dei margini nel RUN. Maschera e Pennello non cambiano (coordinate dell'immagine).
- **L'app**: `CanvasStage` mostra il canvas con una cornice scura attorno, margini a scacchi, slider con scatto magnetico, drag a due assi; in Disegno i margini sono colorati come la maschera.

**Tech Stack:** Swift 6, SwiftUI, macOS 26, Xcode 27, Swift Testing, CoreGraphics, DrawThings-Swift 2.2.x (solo in DTBridge).

**Spec:** `docs/superpowers/specs/2026-10-03-outpaint-design.md` (con l'unica correzione del Task 6: i margini si riempiono con i bordi estesi, non con il grigio); contesto in `docs/superpowers/specs/2026-10-01-tab-control-design.md` (§5, §6).

## Global Constraints

- **Repository e dipendenze:**
  - radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette);
  - branch `m7d-outpaint` da `main`;
  - macOS 26, Swift 6, Xcode 27;
  - solo DTBridge importa DrawThings-Swift.
- **Il modello:** `zoom` −100…+100, 0 = riempie il canvas (com'è oggi). Fattore `4^(zoom/100)` (+100 → 4 volte, −100 → un quarto). La finestra è quella di riempimento divisa per il fattore, posta da `x = (iw − w)·(1 + offsetX)/2` (idem `y`): con la finestra più grande dell'immagine la differenza è negativa e `offset` −1/0/+1 attacca l'immagine al bordo iniziale/centro/bordo finale del canvas. Un margine sotto mezzo pixel di canvas è arrotondamento, non margine.
- **Scatti dello slider** a 0 e a `zoomContain` (zoom ≤ 0 a cui l'immagine sta tutta nel canvas), cattura entro ±3 punti, con un tick (`NSHapticFeedbackManager`).
- **Zoom e spostamento non sono passi della cronologia** (come lo spostamento oggi): si salvano in `control.json`, Annulla/Ripeti non li toccano (`keepingSettings`, già in uso); cambiare o togliere l'immagine li riporta a 0.
- **Al RUN:** i margini sono riempiti **con i pixel del bordo dell'immagine stesi in fuori** (gli angoli con il pixel d'angolo). **Misurato dal vivo il 3 ottobre 2026** (SD 1.5 Juggernaut Reborn, 512×512 in un canvas 768×512 con 128 px di margine per lato, forza 100%, Sfumatura 1,5, Conserva l'originale): con un grigio neutro nei margini "Conserva l'originale" lasciava una **riga chiara** sulla giunzione; con i bordi estesi la riga non c'è e il paesaggio continua in modo naturale. Il centro resta identico all'originale in entrambi i casi.
- **La maschera dei margini** è l'unione di margini (da rigenerare) e maschera dipinta, ridotta al canvas con lo stesso taglio dell'immagine; senza maschera dipinta il RUN manda comunque la maschera. Forza automatica 100% con maschera **o** margini (una forza scelta a mano vince); Edit 100%. `enableInpainting` e l'invio della maschera restano come in M7c.
- **Decodifica:** la dimensione a cui si decodifica l'immagine si calcola dalla finestra (`canvasWidth / crop.width`), così con lo zoom positivo si legge più risoluzione.
- **Avvisi:** l'avviso di ritaglio forte (oltre un terzo) solo con zoom ≤ 0, calcolato sulla finestra di quello zoom.
- **Interfaccia (deciso con l'utente, 3 ottobre 2026):** uno slider nella card Canvas (modo Canvas); il drag sposta l'immagine nel canvas su entrambi gli assi (l'immagine segue il puntatore); lo stage mostra sempre il canvas con una cornice scura attorno (12% per lato) dove si vede, oscurato, ciò che esce; i margini sono a scacchi; in Disegno il canvas com'è inviato, con i margini colorati come la maschera (il pennello non dipinge nei margini).
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo; mai una stringa vuota come titolo di un controllo (il test del catalogo la segnala).
- **La logica sta in HubCore (testata); le viste si verificano con la compilazione e con la prova dal vivo (Task 6).**
- **Blocchi `diff`:** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Prove con l'app:** si lancia una copia isolata dai dati dell'utente con `CFFIXED_USER_HOME=/tmp/m7dhome` (cartella Application Support e preferenze a parte), compilata con `-derivedDataPath /tmp/m7d-dd`: l'app dell'utente, se è aperta, non si tocca.
- **Fuori da M7d:** Tiled Diffusion e canvas oltre 2048; outpaint a passi in automatico; pennello nei margini; riempimento dei margini scelto dall'utente; avviso per una maschera tutta fuori dal ritaglio; plug-in.

## Review Focus

- **Giunzione dei margini:** i margini continuano i colori del bordo (non una tinta piatta) e la maschera li rigenera; il centro non cambia (test `theImageSitsInTheMiddleAndTheMarginsTakeTheColoursOfItsEdges`, `theMarginsAboveAndBelowAndTheCornersToo`, Task 3; prova dal vivo, Task 6).
- **Maschera dipinta con l'immagine spostata o ingrandita:** segue l'immagine, non il canvas (test `thePaintedMaskFollowsTheImageWhenItIsMoved`, `aPositiveZoomCutsTheMaskLikeTheImage`, Task 3).
- **Margine-polvere:** un'immagine che riempie esattamente il canvas (stesso rapporto, zoom 0, o zoom "contiene") non genera maschera né margini per arrotondamento (test `theFillAndAPositiveZoomHaveNoMargins`, `theZoomWhereTheWholeImageFits`, `aRunAtTheFillWithoutAMaskHasNoMask`, Task 2 e 4).
- **File vecchi o strani:** un `control.json` con `mode` e senza `zoom`, o con `zoom` fuori scala o di tipo sbagliato, si legge e si limita (test `theZoomIsLimitedAndAnOldFramingStillLoads`, Task 1).
- **Foto enormi con lo zoom al massimo:** la decodifica segue la finestra e il RUN finisce (test `theBiggestZoomOfAHugeImageStillRenders`, Task 4).
- **Forza:** margini senza maschera dipinta → 100% automatica; una forza scelta a mano resta (test `marginsMakeTheAutomaticStrengthFull`, Task 1).
- **Zoom e cronologia:** Annulla/Ripeti non lo portano indietro, una nuova immagine lo azzera (test `theZoomIsNotAStepOfTheHistory`, `aNewImageStartsAtTheFillAndResetPutsItBack`, Task 4).
- **Vista:** `CanvasStage` non ha test (codice di vista): il revisore controlli a occhio il verso del drag (l'immagine segue il puntatore, su entrambi gli assi), lo scatto dello slider, la cornice, il riquadro di Disegno con i margini, e che il pennello in Disegno non scriva nei margini.
- **`enableInpainting` per i modelli inpainting** con i margini non è provato (nessun modello inpainting installato); le prove dal vivo sono su SD 1.5.

---

### Task 1: Lo zoom nel modello (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Control/ControlInputs.swift`, `Packages/Sources/HubCore/Control/ControlStore.swift` (una riga)
- Test: `Packages/Tests/HubKitTests/ControlContractTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `Framing` senza `Mode`: `zoom: Double` (−100…+100, predefinito 0), `offsetX`, `offsetY`; `static let zoomRange = -100.0...100.0`; `init(zoom: Double = 0, offsetX: Double = 0, offsetY: Double = 0)`; `clamped()` limita tutto; la lettura è permissiva (un campo mancante o di tipo sbagliato vale il predefinito, un `mode` vecchio si ignora) e limita i valori;
  - `ControlInputs.effectiveStrength(editModel: Bool, hasMargins: Bool = false) -> Double`: 1,0 anche con `hasMargins`.
- Consumes: `ControlInputs` (M7a–c).

- [ ] **Step 1: Creare il ramo e scrivere i test**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git switch main && git switch -c m7d-outpaint
```

```diff
diff --git a/Packages/Tests/HubKitTests/ControlContractTests.swift b/Packages/Tests/HubKitTests/ControlContractTests.swift
index cd90628..f9c3bf0 100644
--- a/Packages/Tests/HubKitTests/ControlContractTests.swift
+++ b/Packages/Tests/HubKitTests/ControlContractTests.swift
@@ -36,9 +36,28 @@ struct ControlContractTests {
     #expect(inputs.effectiveStrength(editModel: false) == 0.0)
   }
 
+  @Test func marginsMakeTheAutomaticStrengthFull() {
+    var inputs = ControlInputs()
+    #expect(inputs.effectiveStrength(editModel: false, hasMargins: true) == 1.0)
+    #expect(inputs.effectiveStrength(editModel: false, hasMargins: false) == 0.7)
+    inputs.strength = 0.4
+    #expect(inputs.effectiveStrength(editModel: false, hasMargins: true) == 0.4)
+  }
+
+  @Test func theZoomIsLimitedAndAnOldFramingStillLoads() throws {
+    #expect(Framing(zoom: 900).clamped().zoom == 100)
+    #expect(Framing(zoom: -900).clamped().zoom == -100)
+    let old = try JSONDecoder().decode(Framing.self, from: Data(#"{"mode": "fill", "offsetX": 0.5}"#.utf8))
+    #expect(old == Framing(zoom: 0, offsetX: 0.5, offsetY: 0))
+    let wild = try JSONDecoder().decode(Framing.self, from: Data(#"{"zoom": 900, "offsetY": -9}"#.utf8))
+    #expect(wild == Framing(zoom: 100, offsetX: 0, offsetY: -1))
+    let text = try JSONDecoder().decode(Framing.self, from: Data(#"{"zoom": "far"}"#.utf8))
+    #expect(text.zoom == 0)
+  }
+
   @Test func theFramingStartsCentered() {
     let framing = Framing()
-    #expect(framing.mode == .fill)
+    #expect(framing.zoom == 0)
     #expect(framing.offsetX == 0)
     #expect(framing.offsetY == 0)
     #expect(Framing(offsetX: 5, offsetY: -5).clamped() == Framing(offsetX: 1, offsetY: -1))
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter HubKitTests 2>&1 | grep -E "error:" | head -2`
Expected: `extra argument 'hasMargins'` o `value of type 'Framing' has no member 'zoom'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Control/ControlInputs.swift b/Packages/Sources/HubKit/Control/ControlInputs.swift
index c49716d..9431f4c 100644
--- a/Packages/Sources/HubKit/Control/ControlInputs.swift
+++ b/Packages/Sources/HubKit/Control/ControlInputs.swift
@@ -32,34 +32,38 @@ public struct ReferenceImage: Identifiable, Equatable, Codable, Sendable {
   }
 }
 
-/// How the start image sits in the canvas (spec §5). Only "fill" exists for now; "contain" comes
-/// with the outpaint.
+/// How the start image sits in the canvas (spec: outpaint §3). `zoom` 0 is "fill" (the image fills the
+/// canvas and is cut); below 0 the image is smaller and leaves margins to regenerate (outpaint); above
+/// 0 it is larger and only a part of it is used.
 public struct Framing: Equatable, Codable, Sendable {
-  public enum Mode: String, Codable, Sendable {
-    case fill
-  }
+  public static let zoomRange = -100.0...100.0
 
-  public var mode: Mode
-  /// Where the cut falls on the axis that is cropped: -1 shows the start (left or top) of the
-  /// image, 0 is centered, 1 shows the end.
+  /// −100…+100; 0 fills the canvas.
+  public var zoom: Double
+  /// Where the cut falls on the axis where the image and the canvas do not coincide: -1 puts the
+  /// image against the start (left or top) of the canvas, 0 centres it, 1 against the end.
   public var offsetX: Double
   public var offsetY: Double
 
-  public init(mode: Mode = .fill, offsetX: Double = 0, offsetY: Double = 0) {
-    self.mode = mode
+  public init(zoom: Double = 0, offsetX: Double = 0, offsetY: Double = 0) {
+    self.zoom = zoom
     self.offsetX = offsetX
     self.offsetY = offsetY
   }
 
   public func clamped() -> Framing {
-    Framing(mode: mode, offsetX: min(1, max(-1, offsetX)), offsetY: min(1, max(-1, offsetY)))
+    Framing(
+      zoom: min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, zoom)),
+      offsetX: min(1, max(-1, offsetX)), offsetY: min(1, max(-1, offsetY)))
   }
 
+  /// Lenient: a missing field takes its default and an old `mode` is ignored.
   public init(from decoder: any Decoder) throws {
     let container = try decoder.container(keyedBy: CodingKeys.self)
-    mode = (try? container.decodeIfPresent(Mode.self, forKey: .mode)) ?? .fill
+    zoom = (try? container.decodeIfPresent(Double.self, forKey: .zoom)) ?? 0
     offsetX = (try? container.decodeIfPresent(Double.self, forKey: .offsetX)) ?? 0
     offsetY = (try? container.decodeIfPresent(Double.self, forKey: .offsetY)) ?? 0
+    self = clamped()
   }
 }
 
@@ -173,9 +177,10 @@ public struct ControlInputs: Equatable, Codable, Sendable {
     self.moodboard = moodboard
   }
 
-  /// The strength that is sent and shown, within 0…1.
-  public func effectiveStrength(editModel: Bool) -> Double {
-    min(1, max(0, strength ?? (editModel || mask != nil ? 1.0 : 0.7)))
+  /// The strength that is sent and shown, within 0…1. A mask, or margins to regenerate, make the
+  /// automatic strength 100%.
+  public func effectiveStrength(editModel: Bool, hasMargins: Bool = false) -> Double {
+    min(1, max(0, strength ?? (editModel || mask != nil || hasMargins ? 1.0 : 0.7)))
   }
 
   /// Lenient, like the other saved files: a missing or unreadable field takes its default.
```

`Framing` non ha più `mode`: in `ControlStore.setOffset` (HubCore) la riga che lo usa va cambiata perché il pacchetto compili (il resto dello store è del Task 4):

```swift
    inputs.framing = Framing(zoom: inputs.framing.zoom, offsetX: x, offsetY: y).clamped()
```

al posto di `inputs.framing = Framing(mode: inputs.framing.mode, offsetX: x, offsetY: y).clamped()`.

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `65 tests … passed` (2 nuovi), HubCore 312, DTBridge 62, Catalog 6, LLMBridge 6 (totale **451**).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: lo zoom nel modello dell'inquadratura e la forza automatica con i margini

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: La finestra con lo zoom, i margini e gli scatti (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/FramingMath.swift`
- Test: `Packages/Tests/HubCoreTests/OutpaintGeometryTests.swift` (nuovo)

**Interfaces:**
- Consumes: `Framing(zoom:offsetX:offsetY:)` (Task 1).
- Produces (HubCore, `public`, in `FramingMath`):
  - `static func factor(zoom: Double) -> Double` (`4^(zoom/100)`, zoom limitato a −100…100);
  - `cropRect(imageWidth:imageHeight:canvasWidth:canvasHeight:framing:) -> CGRect` ora con lo zoom: la finestra di riempimento divisa per il fattore, posta dall'offset; **può uscire dall'immagine**;
  - `struct Margins: Equatable, Sendable` (`left`, `top`, `right`, `bottom` in pixel del canvas; `isEmpty` se tutti sotto 0,5) e `static func margins(imageWidth:imageHeight:canvasWidth:canvasHeight:framing:) -> Margins`;
  - `static func zoomContain(imageWidth:imageHeight:canvasWidth:canvasHeight:) -> Double` (≤ 0: lo zoom a cui l'immagine sta tutta nel canvas; 0 con lo stesso rapporto);
  - `static func usedShare(imageWidth:imageHeight:canvasWidth:canvasHeight:framing:) -> Double` (0…1, quota dell'area dell'immagine dentro la finestra);
  - `loss(imageWidth:imageHeight:canvasWidth:canvasHeight:zoom: Double = 0)` calcolata sulla finestra di quello zoom.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct OutpaintGeometryTests {
  func crop(_ framing: Framing, image: (Int, Int) = (1000, 1000), canvas: (Int, Int) = (1200, 900)) -> CGRect {
    FramingMath.cropRect(
      imageWidth: image.0, imageHeight: image.1, canvasWidth: canvas.0, canvasHeight: canvas.1, framing: framing)
  }

  @Test func theFactorIsExponentialAndLimited() {
    #expect(FramingMath.factor(zoom: 0) == 1)
    #expect(FramingMath.factor(zoom: 100) == 4)
    #expect(FramingMath.factor(zoom: -100) == 0.25)
    #expect(FramingMath.factor(zoom: 900) == 4)
    #expect(FramingMath.factor(zoom: -900) == 0.25)
  }

  @Test func aZoomOfZeroIsTheFill() {
    #expect(crop(Framing()) == CGRect(x: 0, y: 125, width: 1000, height: 750))
  }

  @Test func aPositiveZoomShrinksTheWindowAroundTheCentre() {
    #expect(crop(Framing(zoom: 100)) == CGRect(x: 375, y: 406.25, width: 250, height: 187.5))
  }

  @Test func aNegativeZoomMakesTheWindowLargerThanTheImage() {
    #expect(crop(Framing(zoom: -100)) == CGRect(x: -1500, y: -1000, width: 4000, height: 3000))
  }

  @Test func theOffsetPutsTheImageAgainstTheStartOrTheEndOfTheCanvas() {
    #expect(crop(Framing(zoom: -100, offsetX: -1, offsetY: -1)) == CGRect(x: 0, y: 0, width: 4000, height: 3000))
    #expect(crop(Framing(zoom: -100, offsetX: 1, offsetY: 1)) == CGRect(x: -3000, y: -2000, width: 4000, height: 3000))
  }

  @Test func theZoomWhereTheWholeImageFits() {
    let contain = FramingMath.zoomContain(imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900)
    #expect(abs(contain + 20.752) < 0.01)
    #expect(FramingMath.zoomContain(imageWidth: 400, imageHeight: 300, canvasWidth: 800, canvasHeight: 600) == 0)
    let margins = FramingMath.margins(
      imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: contain))
    #expect(abs(margins.left - 150) < 0.01 && abs(margins.right - 150) < 0.01)
    #expect(margins.top < 0.01 && margins.bottom < 0.01)
    let loss = FramingMath.loss(
      imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, zoom: contain)
    #expect(loss.axis == nil)
  }

  @Test func theFillAndAPositiveZoomHaveNoMargins() {
    for zoom in [0.0, 30, 100] {
      let margins = FramingMath.margins(
        imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: zoom))
      #expect(margins.isEmpty)
    }
    let same = FramingMath.margins(
      imageWidth: 400, imageHeight: 300, canvasWidth: 800, canvasHeight: 600, framing: Framing())
    #expect(same.isEmpty)
  }

  @Test func marginsAreMeasuredInCanvasPixelsOnEachSide() {
    // 100×100 in a 200×100 canvas at −50: the image is 100 wide, centred; against the start it has no left margin.
    let centred = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 200, canvasHeight: 100, framing: Framing(zoom: -50))
    #expect(abs(centred.left - 50) < 0.01 && abs(centred.right - 50) < 0.01)
    let atStart = FramingMath.margins(
      imageWidth: 100, imageHeight: 100, canvasWidth: 200, canvasHeight: 100, framing: Framing(zoom: -50, offsetX: -1))
    #expect(atStart.left < 0.01 && abs(atStart.right - 100) < 0.01)
  }

  @Test func theShareOfTheImageThatIsUsed() {
    func share(_ zoom: Double) -> Double {
      FramingMath.usedShare(
        imageWidth: 1000, imageHeight: 1000, canvasWidth: 1200, canvasHeight: 900, framing: Framing(zoom: zoom))
    }
    #expect(abs(share(0) - 0.75) < 0.0001)
    #expect(abs(share(100) - 0.046875) < 0.0001)
    #expect(share(-100) == 1)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter OutpaintGeometry 2>&1 | grep -E "error:" | head -2`
Expected: `type 'FramingMath' has no member 'factor'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/FramingMath.swift b/Packages/Sources/HubCore/Control/FramingMath.swift
index 1545c9d..ce52151 100644
--- a/Packages/Sources/HubCore/Control/FramingMath.swift
+++ b/Packages/Sources/HubCore/Control/FramingMath.swift
@@ -20,34 +20,94 @@ public enum FramingMath {
     case vertical
   }
 
-  /// The part of the image, in its pixels counted from the top-left, that fills the canvas
-  /// ("fill"): the whole image on the axis that fits, a cut on the other, placed by the offset.
-  public static func cropRect(
-    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
-  ) -> CGRect {
+  /// What the zoom does to the window: +100 shows a quarter of the fill window (the image is 4 times
+  /// larger), −100 shows 4 times more (the image is a quarter of the size). Exponential, so the same
+  /// distance on the slider has the same effect on both sides of 0.
+  public static func factor(zoom: Double) -> Double {
+    pow(4, min(100, max(-100, zoom)) / 100)
+  }
+
+  /// The window of the fill (zoom 0) in image pixels: the whole image on the axis that fits, a cut on
+  /// the other.
+  private static func fillSize(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> (
+    width: Double, height: Double
+  ) {
     let iw = Double(imageWidth)
     let ih = Double(imageHeight)
     let canvasRatio = Double(canvasWidth) / Double(max(canvasHeight, 1))
     let imageRatio = iw / max(ih, 1)
-    let offset = framing.clamped()
-    if imageRatio > canvasRatio {
-      let width = ih * canvasRatio
-      return CGRect(x: (iw - width) * (1 + offset.offsetX) / 2, y: 0, width: width, height: ih)
-    }
-    if imageRatio < canvasRatio {
-      let height = iw / canvasRatio
-      return CGRect(x: 0, y: (ih - height) * (1 + offset.offsetY) / 2, width: iw, height: height)
-    }
-    return CGRect(x: 0, y: 0, width: iw, height: ih)
+    if imageRatio > canvasRatio { return (ih * canvasRatio, ih) }
+    if imageRatio < canvasRatio { return (iw, iw / canvasRatio) }
+    return (iw, ih)
+  }
+
+  /// The window on the image, in its pixels counted from the top-left, that fills the canvas: the fill
+  /// window divided by the zoom factor, placed by the offset. It can be larger than the image (the
+  /// part outside is margin) and then the offset puts the image against the start (-1), the centre
+  /// (0) or the end (1) of the canvas.
+  public static func cropRect(
+    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
+  ) -> CGRect {
+    let fill = fillSize(
+      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
+    let framing = framing.clamped()
+    let factor = factor(zoom: framing.zoom)
+    let width = fill.width / factor
+    let height = fill.height / factor
+    return CGRect(
+      x: (Double(imageWidth) - width) * (1 + framing.offsetX) / 2,
+      y: (Double(imageHeight) - height) * (1 + framing.offsetY) / 2, width: width, height: height)
+  }
+
+  /// The margins around the image in the canvas, in canvas pixels.
+  public struct Margins: Equatable, Sendable {
+    public var left: Double
+    public var top: Double
+    public var right: Double
+    public var bottom: Double
+
+    /// A margin under half a pixel is rounding, not margin.
+    public var isEmpty: Bool { max(left, top, right, bottom) < 0.5 }
+  }
+
+  public static func margins(
+    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
+  ) -> Margins {
+    let crop = cropRect(
+      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
+      framing: framing)
+    let scale = Double(canvasWidth) / crop.width
+    return Margins(
+      left: max(0, -crop.minX) * scale, top: max(0, -crop.minY) * scale,
+      right: max(0, crop.maxX - Double(imageWidth)) * scale, bottom: max(0, crop.maxY - Double(imageHeight)) * scale)
+  }
+
+  /// The zoom (0 or less) at which the whole image just fits in the canvas.
+  public static func zoomContain(imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int) -> Double {
+    let across = Double(canvasWidth) / Double(max(imageWidth, 1))
+    let down = Double(canvasHeight) / Double(max(imageHeight, 1))
+    return 100 * log(min(across, down) / max(across, down)) / log(4)
+  }
+
+  /// The share (0…1) of the image's area that is inside the window.
+  public static func usedShare(
+    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, framing: Framing
+  ) -> Double {
+    let crop = cropRect(
+      imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
+      framing: framing)
+    let inside = crop.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
+    return inside.isNull ? 0 : inside.width * inside.height / (Double(imageWidth) * Double(imageHeight))
   }
 
-  /// The share of the image that falls outside the canvas, and on which axis (nil when none).
+  /// The share of the image that falls outside the canvas, and on which axis (nil when none). With a
+  /// `zoom` the window is the one of that zoom.
   public static func loss(
-    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int
+    imageWidth: Int, imageHeight: Int, canvasWidth: Int, canvasHeight: Int, zoom: Double = 0
   ) -> (axis: Axis?, fraction: Double) {
     let rect = cropRect(
       imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
-      framing: Framing())
+      framing: Framing(zoom: zoom))
     let horizontal = 1 - rect.width / Double(imageWidth)
     let vertical = 1 - rect.height / Double(imageHeight)
     if horizontal > 0.000_001 { return (.horizontal, horizontal) }
```

I calcoli di riempimento (`fillSize`) tengono i rami di prima (immagine più larga, più alta, stesso rapporto) per non cambiare di un bit i risultati a zoom 0; il fattore vale esattamente 1 a zoom 0.

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `321 tests … passed` (9 nuovi; i test dell'inquadratura di prima passano senza modifiche); totale 65 + 321 + 62 + 6 + 6 = **460**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: la finestra sull'immagine con lo zoom (può uscire dall'immagine), margini, zoom che contiene, quota usata

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Immagine e maschera con i margini (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/InputComposer.swift`
- Test: `Packages/Tests/HubCoreTests/OutpaintComposerTests.swift` (nuovo)

**Interfaces:**
- Consumes: `FramingMath.cropRect` (Task 2).
- Produces (HubCore, `public`, in `InputComposer`):
  - `frame(_:toWidth:height:framing:paint:)` invariata nella firma: l'immagine nella posizione della finestra; **ciò che non copre si riempie con i pixel del bordo stesi in fuori** (strisce di un pixel per i lati, il pixel d'angolo per gli angoli), poi il Pennello sopra;
  - `mask(_ mask: MaskBitmap?, imageWidth:imageHeight:toWidth:height:framing:) -> CGImage?`: la maschera dipinta è **opzionale**; fuori dall'immagine (margini) è sempre da rigenerare (alfa 0), dentro vale la maschera dipinta (o "tenuto" senza); sempre ridotta con lo stesso taglio e tagliata a metà.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

struct OutpaintComposerTests {
  /// A 100×100 image: red and blue halves, side by side (left red) or one over the other (top red).
  func halves(vertical: Bool) -> CGImage {
    let context = CGContext(
      data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(vertical ? CGRect(x: 0, y: 50, width: 100, height: 50) : CGRect(x: 0, y: 0, width: 50, height: 100))
    return context.makeImage()!
  }

  func sample(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(
      data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return bytes.map(Int.init)
  }

  func isRed(_ pixel: [Int]) -> Bool { pixel[0] > 250 && pixel[2] < 5 }
  func isBlue(_ pixel: [Int]) -> Bool { pixel[2] > 250 && pixel[0] < 5 }

  @Test func theImageSitsInTheMiddleAndTheMarginsTakeTheColoursOfItsEdges() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(isRed(sample(framed, 10, 50)))  // the left margin continues the red edge
    #expect(isRed(sample(framed, 70, 50)) && isBlue(sample(framed, 130, 50)))  // the image itself
    #expect(isBlue(sample(framed, 190, 50)))  // the right margin continues the blue edge
  }

  @Test func theMarginsAboveAndBelowAndTheCornersToo() throws {
    // 100×100 in a 100×200 canvas at −50: the image keeps its size and sits in the middle of the height.
    let framed = try #require(
      InputComposer.frame(halves(vertical: true), toWidth: 100, height: 200, framing: Framing(zoom: -50)))
    #expect(isRed(sample(framed, 50, 10)) && isRed(sample(framed, 5, 10)) && isRed(sample(framed, 95, 10)))
    #expect(isBlue(sample(framed, 50, 190)) && isBlue(sample(framed, 5, 190)) && isBlue(sample(framed, 95, 190)))
    #expect(isRed(sample(framed, 50, 80)) && isBlue(sample(framed, 50, 120)))
  }

  @Test func theOffsetMovesTheImageInTheCanvas() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 200, height: 100, framing: Framing(zoom: -50, offsetX: -1)))
    #expect(isRed(sample(framed, 10, 50)) && isRed(sample(framed, 40, 50)))  // image against the start
    #expect(isBlue(sample(framed, 80, 50)) && isBlue(sample(framed, 190, 50)))
  }

  @Test func aPositiveZoomShowsAPartOfTheImageOnly() throws {
    let framed = try #require(
      InputComposer.frame(halves(vertical: false), toWidth: 64, height: 64, framing: Framing(zoom: 100)))
    // A quarter of the image around its centre: red on the left of the centre line, blue on the right.
    #expect(isRed(sample(framed, 2, 32)) && isBlue(sample(framed, 61, 32)))
  }

  @Test func theMarginsAreRegeneratedEvenWithoutAPaintedMask() throws {
    let mask = try #require(
      InputComposer.mask(nil, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(mask.width == 200 && mask.height == 100)
    #expect(sample(mask, 10, 50)[3] == 0)
    #expect(sample(mask, 100, 50)[3] == 255)
    #expect(sample(mask, 190, 50)[3] == 0)
  }

  @Test func thePaintedMaskGoesWithTheImageAndTheMarginsAddToIt() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50)))
    #expect(sample(mask, 10, 50)[3] == 0)  // margin
    #expect(sample(mask, 70, 50)[3] == 255)  // image, kept
    #expect(sample(mask, 130, 50)[3] == 0)  // image, painted
  }

  @Test func thePaintedMaskFollowsTheImageWhenItIsMoved() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    // Image against the start of the canvas: it covers x 0…100, the right half of it is painted.
    let mask = try #require(
      InputComposer.mask(
        painted, imageWidth: 100, imageHeight: 100, toWidth: 200, height: 100, framing: Framing(zoom: -50, offsetX: -1)))
    #expect(sample(mask, 20, 50)[3] == 255)  // image, kept
    #expect(sample(mask, 80, 50)[3] == 0)  // image, painted
    #expect(sample(mask, 150, 50)[3] == 0)  // margin
  }

  @Test func aPositiveZoomCutsTheMaskLikeTheImage() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    for x in 50..<100 {
      painted.stroke(from: CGPoint(x: Double(x) + 0.5, y: 0), to: CGPoint(x: Double(x) + 0.5, y: 100), radius: 0.7, erase: false)
    }
    // A quarter of the image around its centre: its left half is kept, its right half painted.
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 64, height: 64, framing: Framing(zoom: 100)))
    #expect(sample(mask, 5, 32)[3] == 255)
    #expect(sample(mask, 58, 32)[3] == 0)
  }

  @Test func withoutMarginsTheMaskIsAsBefore() throws {
    var painted = MaskBitmap(width: 100, height: 100)
    painted.stroke(from: CGPoint(x: 80, y: 50), to: CGPoint(x: 80, y: 50), radius: 8, erase: false)
    let mask = try #require(
      InputComposer.mask(painted, imageWidth: 100, imageHeight: 100, toWidth: 100, height: 100, framing: Framing()))
    #expect(sample(mask, 80, 50)[3] == 0)
    #expect(sample(mask, 10, 10)[3] == 255)
    #expect(sample(mask, 0, 0)[3] == 255 && sample(mask, 99, 99)[3] == 255)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter OutpaintComposer 2>&1 | grep -E "error:|Expectation failed" | head -3`
Expected: i test falliscono (margini non estesi; `mask(nil, …)` non compila: `nil` non è un `MaskBitmap`).

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/InputComposer.swift b/Packages/Sources/HubCore/Control/InputComposer.swift
index c0d7bc8..fd197bb 100644
--- a/Packages/Sources/HubCore/Control/InputComposer.swift
+++ b/Packages/Sources/HubCore/Control/InputComposer.swift
@@ -20,26 +20,64 @@ public enum InputComposer {
         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
     else { return nil }
     context.interpolationQuality = .high
+    // Neutral grey under the image: it shows where the image leaves margins (the mask regenerates them).
+    context.setFillColorSpace(CGColorSpaceCreateDeviceRGB())
+    context.setFillColor([0.5, 0.5, 0.5, 1])
+    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
     // The image drawn so that the cut fills the canvas (Core Graphics counts from the bottom-left).
     let scale = Double(width) / crop.width
     let drawn = CGRect(
       x: -crop.minX * scale, y: -(Double(image.height) - crop.maxY) * scale,
       width: Double(image.width) * scale, height: Double(image.height) * scale)
+    extendEdges(of: image, drawn: drawn, in: context, width: width, height: height)
     context.draw(image, in: drawn)
     if let layer = paint?.cgImage() { context.draw(layer, in: drawn) }
     return context.makeImage()
   }
 
+  /// Fills what the image leaves uncovered with its own edge pixels stretched outwards (and the corner
+  /// pixels in the corners). The mask regenerates it anyway; this way the edge Draw Things blends
+  /// back ("keep the original") carries the colours of the picture, not a stripe of grey.
+  private static func extendEdges(of image: CGImage, drawn: CGRect, in context: CGContext, width: Int, height: Int) {
+    let canvas = CGRect(x: 0, y: 0, width: width, height: height)
+    guard !drawn.contains(canvas), image.width > 0, image.height > 0 else { return }
+    let right = Double(width) - drawn.maxX
+    let top = Double(height) - drawn.maxY
+    let w = image.width
+    let h = image.height
+    func strip(_ x: Int, _ y: Int, _ cropWidth: Int, _ cropHeight: Int, into rect: CGRect) {
+      guard rect.width > 0, rect.height > 0,
+        let part = image.cropping(to: CGRect(x: x, y: y, width: cropWidth, height: cropHeight))
+      else { return }
+      context.draw(part, in: rect)
+    }
+    // Core Graphics counts from the bottom-left; the crops count from the top-left.
+    strip(0, 0, 1, h, into: CGRect(x: 0, y: drawn.minY, width: drawn.minX, height: drawn.height))
+    strip(w - 1, 0, 1, h, into: CGRect(x: drawn.maxX, y: drawn.minY, width: right, height: drawn.height))
+    strip(0, 0, w, 1, into: CGRect(x: drawn.minX, y: drawn.maxY, width: drawn.width, height: top))
+    strip(0, h - 1, w, 1, into: CGRect(x: drawn.minX, y: 0, width: drawn.width, height: drawn.minY))
+    strip(0, 0, 1, 1, into: CGRect(x: 0, y: drawn.maxY, width: drawn.minX, height: top))
+    strip(w - 1, 0, 1, 1, into: CGRect(x: drawn.maxX, y: drawn.maxY, width: right, height: top))
+    strip(0, h - 1, 1, 1, into: CGRect(x: 0, y: 0, width: drawn.minX, height: drawn.minY))
+    strip(w - 1, h - 1, 1, 1, into: CGRect(x: drawn.maxX, y: 0, width: right, height: drawn.minY))
+  }
+
   /// The mask for the canvas, in the same cut as the start image: transparent where the picture is
   /// regenerated, opaque where it is kept (what the client wants). The mask is scaled with the same
-  /// smoothing as the image and then cut at half, so its edge is clean at any scale.
+  /// smoothing as the image and then cut at half, so its edge is clean at any scale. What the image
+  /// does not cover (its margins in the canvas) is always regenerated; with no `mask` that is all.
   public static func mask(
-    _ mask: MaskBitmap, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing
+    _ mask: MaskBitmap?, imageWidth: Int, imageHeight: Int, toWidth width: Int, height: Int, framing: Framing
   ) -> CGImage? {
-    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0, let gray = mask.grayImage() else { return nil }
+    guard width > 0, height > 0, imageWidth > 0, imageHeight > 0 else { return nil }
+    var gray: CGImage?
+    if let mask {
+      gray = mask.grayImage()
+      if gray == nil { return nil }
+    }
     let crop = FramingMath.cropRect(
       imageWidth: imageWidth, imageHeight: imageHeight, canvasWidth: width, canvasHeight: height, framing: framing)
-    var bytes = [UInt8](repeating: 0, count: width * height)
+    var bytes = [UInt8](repeating: 255, count: width * height)
     let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
       guard
         let context = CGContext(
@@ -48,11 +86,13 @@ public enum InputComposer {
       else { return false }
       context.interpolationQuality = .high
       let scale = Double(width) / crop.width
-      context.draw(
-        gray,
-        in: CGRect(
-          x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
-          height: Double(imageHeight) * scale))
+      // Where the image is: kept, unless the mask says otherwise.
+      let drawn = CGRect(
+        x: -crop.minX * scale, y: -(Double(imageHeight) - crop.maxY) * scale, width: Double(imageWidth) * scale,
+        height: Double(imageHeight) * scale)
+      context.setFillColor(gray: 0, alpha: 1)
+      context.fill(drawn)
+      if let gray { context.draw(gray, in: drawn) }
       return true
     }
     guard drawn else { return nil }
```

Nota: il colore di base dell'immagine è impostato nello spazio colore del contesto (`setFillColorSpace` con DeviceRGB prima delle componenti), altrimenti un grigio generico viene convertito e non vale 128; l'estensione dei bordi lavora con ritagli di un pixel (`CGImage.cropping`) disegnati allargati con interpolazione alta.

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `330 tests … passed` (9 nuovi; i test della maschera e dell'inquadratura di prima invariati); totale 65 + 330 + 62 + 6 + 6 = **469**.

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages && git commit -m "feat: i margini dell'outpaint — bordi estesi nell'immagine, maschera dei margini anche senza maschera dipinta

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Lo store, gli avvisi e il RUN (HubCore e app)

**Files:**
- Modify: `Packages/Sources/HubCore/Control/ControlStore.swift`, `App/Generation/GenerationController.swift`
- Test: `Packages/Tests/HubCoreTests/OutpaintStoreTests.swift` (nuovo)

**Interfaces:**
- Consumes: `FramingMath.margins`/`cropRect`/`loss(zoom:)` (Task 2), `InputComposer.mask(_:…)` con maschera opzionale (Task 3), `effectiveStrength(editModel:hasMargins:)` (Task 1).
- Produces (HubCore, `public`, su `ControlStore`):
  - `setZoom(_ value: Double)` (limitato, salva), `resetFraming()` (zoom e spostamento a 0, salva), `hasMargins(canvasWidth:canvasHeight:) -> Bool` (falso senza immagine);
  - `setOffset` mantiene lo zoom;
  - `warnings(canvasWidth:canvasHeight:usesMoodboard:)`: `.strongCrop` solo con zoom ≤ 0, calcolato sulla finestra di `min(0, zoom)`;
  - `PendingInputs.render()`: la dimensione di decodifica viene dalla finestra (`canvasWidth / crop.width`); con margini il RUN manda la maschera dei margini anche senza maschera dipinta (`GenerationInputs.mask`); senza margini né maschera niente maschera.
  - `GenerationController`: la forza del job conosce i margini.

- [ ] **Step 1: Scrivere i test che falliscono**

```swift
import CoreGraphics
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct OutpaintStoreTests {
  func folder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("OutpaintStoreTests-\(UUID())", isDirectory: true)
  }

  func store(in root: URL) -> ControlStore {
    ControlStore(
      storage: FileReferenceStorage(folder: root.appendingPathComponent("Control", isDirectory: true)),
      fileURL: root.appendingPathComponent("control.json"))
  }

  func withImage(_ root: URL, width: Int = 400, height: Int = 300) throws -> ControlStore {
    let store = store(in: root)
    try store.setImage(data: pictureData(width: width, height: height), name: "a.png", source: .pasteboard)
    return store
  }

  @Test func theZoomIsLimitedAndKeptAcrossARestart() throws {
    let root = folder()
    let first = try withImage(root)
    first.setZoom(-300)
    #expect(first.inputs.framing.zoom == -100)
    first.setZoom(-40)
    first.setOffset(x: 0.5, y: 0)
    #expect(first.inputs.framing == Framing(zoom: -40, offsetX: 0.5))
    let second = store(in: root)
    #expect(second.inputs.framing == Framing(zoom: -40, offsetX: 0.5))
  }

  @Test func theZoomIsNotAStepOfTheHistory() throws {
    let store = try withImage(folder())
    store.setZoom(-40)
    var mask = MaskBitmap(width: store.maskSize!.width, height: store.maskSize!.height)
    mask.stroke(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 20), radius: 5, erase: false)
    try store.commitMask(mask)
    store.undo()
    #expect(store.inputs.framing.zoom == -40)
    store.redo()
    #expect(store.inputs.framing.zoom == -40)
  }

  @Test func aNewImageStartsAtTheFillAndResetPutsItBack() throws {
    let store = try withImage(folder())
    store.setZoom(-40)
    store.setOffset(x: 1, y: 1)
    store.resetFraming()
    #expect(store.inputs.framing == Framing())
    store.setZoom(60)
    try store.setImage(data: pictureData(width: 200, height: 200), name: "b.png", source: .pasteboard)
    #expect(store.inputs.framing == Framing())
  }

  @Test func marginsExistOnlyWhenTheImageIsSmallerThanTheCanvas() throws {
    let store = try withImage(folder(), width: 400, height: 300)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
    store.setZoom(-50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300))
    store.setZoom(50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
    store.removeImage()
    store.setZoom(-50)
    #expect(store.hasMargins(canvasWidth: 400, canvasHeight: 300) == false)
  }

  @Test func theStrongCropWarningIsOnlyForAZoomOfZeroOrLess() throws {
    let store = try withImage(folder(), width: 300, height: 400)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900) == [.strongCrop(percent: 44)])
    store.setZoom(-100)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)
    store.setZoom(50)
    #expect(store.warnings(canvasWidth: 1200, canvasHeight: 900).isEmpty)
  }

  @Test func aRunWithMarginsGetsTheMaskAndTheGreyImageAtTheCanvasSize() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    store.setZoom(-50)
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    let image = try #require(inputs.image)
    let mask = try #require(inputs.mask)
    #expect(image.width == 256 && image.height == 192)
    #expect(mask.width == 256 && mask.height == 192)
    #expect(inputs.isEmpty == false)
  }

  @Test func aRunAtTheFillWithoutAMaskHasNoMask() async throws {
    let store = try withImage(folder(), width: 400, height: 300)
    let pending = store.pendingInputs(canvasWidth: 256, canvasHeight: 192)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.mask == nil)
  }

  @Test func theBiggestZoomOfAHugeImageStillRenders() async throws {
    let store = try withImage(folder(), width: 4000, height: 3000)
    store.setZoom(100)
    let pending = store.pendingInputs(canvasWidth: 512, canvasHeight: 384)
    let inputs = try await Task.detached { try pending.render() }.value
    #expect(inputs.image?.width == 512 && inputs.mask == nil)
  }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter OutpaintStore 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'ControlStore' has no member 'setZoom'`.

- [ ] **Step 3: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Control/ControlStore.swift b/Packages/Sources/HubCore/Control/ControlStore.swift
index 8bf3116..d55a1cf 100644
--- a/Packages/Sources/HubCore/Control/ControlStore.swift
+++ b/Packages/Sources/HubCore/Control/ControlStore.swift
@@ -320,6 +320,27 @@ public final class ControlStore {
     save()
   }
 
+  /// The zoom of the image in the canvas (−100…+100; below 0 the margins are regenerated).
+  public func setZoom(_ value: Double) {
+    inputs.framing = Framing(zoom: value, offsetX: inputs.framing.offsetX, offsetY: inputs.framing.offsetY).clamped()
+    save()
+  }
+
+  /// Back to the fill, centred.
+  public func resetFraming() {
+    inputs.framing = Framing()
+    save()
+  }
+
+  /// Whether the image leaves margins in the canvas (they are regenerated).
+  public func hasMargins(canvasWidth: Int, canvasHeight: Int) -> Bool {
+    guard let image = inputs.image else { return false }
+    return !FramingMath.margins(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight, framing: inputs.framing
+    ).isEmpty
+  }
+
   // MARK: History
 
   public func undo() {
@@ -379,10 +400,11 @@ public final class ControlStore {
   public func warnings(canvasWidth: Int, canvasHeight: Int, usesMoodboard: Bool = true) -> [ControlWarning] {
     var warnings: [ControlWarning] = []
     if let image = inputs.image {
+      // With a zoom above 0 the cut is the user's choice: no warning.
       let loss = FramingMath.loss(
         imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
-        canvasHeight: canvasHeight)
-      if loss.fraction > 1.0 / 3.0 { warnings.append(.strongCrop(percent: Int((loss.fraction * 100).rounded()))) }
+        canvasHeight: canvasHeight, zoom: min(0, inputs.framing.zoom))
+      if inputs.framing.zoom <= 0, loss.fraction > 1.0 / 3.0 { warnings.append(.strongCrop(percent: Int((loss.fraction * 100).rounded()))) }
     }
     let on = inputs.moodboard.filter(\.isOn).count
     if on > 0, !usesMoodboard {
@@ -511,7 +533,10 @@ public struct PendingInputs: Sendable {
       hints.append(GenerationHint(imageData: data, weight: entry.weight))
     }
     guard let image else { return GenerationInputs(hints: hints) }
-    let scale = max(Double(canvasWidth) / Double(image.pixelWidth), Double(canvasHeight) / Double(image.pixelHeight))
+    let crop = FramingMath.cropRect(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight, framing: framing)
+    let scale = Double(canvasWidth) / crop.width
     let longest = max(image.pixelWidth, image.pixelHeight)
     let maxPixel = scale < 1 ? Int((Double(longest) * scale).rounded(.up)) + 1 : longest
     var layer: PaintBitmap?
@@ -525,9 +550,19 @@ public struct PendingInputs: Sendable {
       let framed = InputComposer.frame(
         decoded, toWidth: canvasWidth, height: canvasHeight, framing: framing, paint: layer)
     else { throw .unreadable(image.name) }
-    guard let mask else { return GenerationInputs(image: framed, hints: hints) }
-    guard let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
-      let bitmap = MaskBitmap(image: stored),
+    let margins = !FramingMath.margins(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight, framing: framing
+    ).isEmpty
+    if mask == nil, !margins { return GenerationInputs(image: framed, hints: hints) }
+    var bitmap: MaskBitmap?
+    if let mask {
+      guard let stored = storage.image(named: mask.fileName, maxPixel: MaskBitmap.maxSide),
+        let decodedMask = MaskBitmap(image: stored)
+      else { throw .unreadable(image.name) }
+      bitmap = decodedMask
+    }
+    guard
       let scaled = InputComposer.mask(
         bitmap, imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, toWidth: canvasWidth,
         height: canvasHeight, framing: framing)
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 21d02d5..dbef342 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -197,7 +197,9 @@ final class GenerationController {
     let batches = JobComposer.batches(
       prompt: prompt, negativePrompt: negativePrompt, model: model, family: family(in: connection),
       parameters: parameters, catalog: connection.monitor.catalog,
-      imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(editModel: isEditModel(in: connection)),
+      imageStrength: inputs.image == nil ? nil : control.inputs.effectiveStrength(
+        editModel: isEditModel(in: connection),
+        hasMargins: control.hasMargins(canvasWidth: parameters.width, canvasHeight: parameters.height)),
       moodboardCount: inputs.hints.count,
       maskSettings: inputs.mask == nil ? nil : control.inputs.maskSettings)
     if parameters.randomSeed, let first = batches.first { parameters.seed = first.parameters.seed }
```

- [ ] **Step 4: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `338 tests … passed` (8 nuovi); totale 65 + 338 + 62 + 6 + 6 = **477**. (Se un test di sessione dell'M3, `reportsProgressAndPreviewWhileRunning`, fallisce una volta sotto carico, è la flakiness nota del backlog: rilanciare.)

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages App && git commit -m "feat: zoom nello store (non è un passo della cronologia), avvisi, decodifica dalla finestra, RUN con la maschera dei margini

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Lo slider Zoom e lo stage con la cornice (app)

**Files:**
- Modify: `App/Control/CanvasStage.swift`, `App/Control/ImageCard.swift`, `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `ControlStore.setZoom`/`resetFraming`/`setOffset`/`hasMargins`, `FramingMath.zoomContain`/`margins`/`usedShare`/`loss(zoom:)` (Task 2, 4), `Framing.zoomRange` (Task 1).
- Produces: in `CanvasStage` (modo Canvas) lo stage con il rapporto del canvas e la cornice scura (12% per lato), la scacchiera sotto il canvas, i tre strati (immagine, Pennello, maschera) posti con `imageLayer(_:origin:size:)`, il drag che muove l'immagine su entrambi gli assi (`Δoffset = −2·traslazione / (scala · differenza)` dove la differenza è `larghezza immagine − larghezza finestra`, e idem in verticale; assi con differenza sotto mezzo pixel immobili), la riga `zoomRow` (slider −100…+100, valore, pulsante "ripristina") con lo scatto magnetico (`setZoom(_:contain:)`: cattura entro ±3 punti a 0 e a `zoomContain`, un tick quando si arriva su uno scatto), la didascalia (dimensione; margini per lato in percentuale; con zoom > 0 la quota usata; altrimenti la perdita; il suggerimento del drag solo se c'è qualcosa da spostare). In Disegno il fondo è un grigio neutro e i margini hanno il colore della maschera (arancio, 55%). `ImageCard`: la forza automatica e la frase "con la maschera o i margini" tengono conto dei margini. Nuove stringhe en+it e due stringhe cambiate (`control.stage.drag`, `control.strength.mask`).

- [ ] **Step 1: Stringhe**

```python
import json
p = 'App/Localizable.xcstrings'
d = json.load(open(p))
new = {
    "control.stage.zoom": ("Zoom", "Zoom"),
    "control.stage.zoom.reset": ("Reset zoom and position", "Ripristina zoom e posizione"),
    "control.stage.margins": ("Margins to regenerate: %@", "Margini da rigenerare: %@"),
    "control.stage.margin.top": ("above %lld%%", "sopra %lld%%"),
    "control.stage.margin.bottom": ("below %lld%%", "sotto %lld%%"),
    "control.stage.margin.left": ("left %lld%%", "sinistra %lld%%"),
    "control.stage.margin.right": ("right %lld%%", "destra %lld%%"),
    "control.stage.used": ("%lld%% of the image is used.", "Si usa il %lld%% dell'immagine."),
}
changed = {
    "control.stage.drag": ("Drag to move the image in the canvas.", "Trascina per spostare l'immagine nel canvas."),
    "control.strength.mask": (
        "With a mask or margins the strength is 100%: the area to regenerate is made whole.",
        "Con la maschera o i margini la forza è al 100%: l'area da rigenerare viene rifatta per intero."),
}
for key, (en, it) in new.items():
    assert key not in d['strings'], key
    d['strings'][key] = {"extractionState": "manual", "localizations": {
        "en": {"stringUnit": {"state": "translated", "value": en}},
        "it": {"stringUnit": {"state": "translated", "value": it}}}}
for key, (en, it) in changed.items():
    units = d['strings'][key]['localizations']
    units['en']['stringUnit']['value'] = en
    units['it']['stringUnit']['value'] = it
d['strings'] = dict(sorted(d['strings'].items()))
open(p, 'w').write(json.dumps(d, ensure_ascii=False, indent=2))
```

Salvare lo script come `/tmp/m7d_keys.py` e lanciarlo dalla radice: `cd "/Users/existenz/Software developement/DT Hub" && python3 /tmp/m7d_keys.py`. Controllare con `git diff --stat App/Localizable.xcstrings` (solo righe aggiunte e due valori cambiati).

- [ ] **Step 2: La scheda Immagine**

```diff
diff --git a/App/Control/ImageCard.swift b/App/Control/ImageCard.swift
index 1232d98..0ab2104 100644
--- a/App/Control/ImageCard.swift
+++ b/App/Control/ImageCard.swift
@@ -106,7 +106,8 @@ struct ImageCard: View {
 
   private var strengthRow: some View {
     let edit = generation.isEditModel(in: connection)
-    let value = control.inputs.effectiveStrength(editModel: edit)
+    let margins = control.hasMargins(canvasWidth: generation.parameters.width, canvasHeight: generation.parameters.height)
+    let value = control.inputs.effectiveStrength(editModel: edit, hasMargins: margins)
     return VStack(alignment: .leading, spacing: 4) {
       CardRow(label: String(localized: "control.strength")) {
         Slider(
@@ -122,7 +123,7 @@ struct ImageCard: View {
       HStack(spacing: DS.controlGap) {
         if edit {
           Text("control.strength.edit").font(.caption).foregroundStyle(.secondary)
-        } else if control.inputs.mask != nil, control.inputs.strength == nil {
+        } else if control.inputs.mask != nil || margins, control.inputs.strength == nil {
           Text("control.strength.mask").font(.caption).foregroundStyle(.secondary)
         }
         if control.inputs.strength != nil {
```

- [ ] **Step 3: La card Canvas**

```diff
diff --git a/App/Control/CanvasStage.swift b/App/Control/CanvasStage.swift
index f3c15b8..6acf6b4 100644
--- a/App/Control/CanvasStage.swift
+++ b/App/Control/CanvasStage.swift
@@ -51,6 +51,7 @@ struct CanvasStage: View {
           if mode == .draw { tools }
           if mode == .canvas {
             stage(for: image)
+            zoomRow(for: image)
             caption(for: image)
           } else {
             drawArea(for: image)
@@ -116,8 +117,12 @@ struct CanvasStage: View {
       .frame(maxWidth: .infinity)
   }
 
+  /// The board around the canvas in Canvas mode, as a share of the canvas on each side: what the image
+  /// puts outside the canvas shows there, darkened.
+  private static let boardMargin = 0.12
+
   private func stage(for image: ReferenceImage) -> some View {
-    sized(ratio: Double(image.pixelWidth) / Double(max(image.pixelHeight, 1))) {
+    sized(ratio: Double(canvasWidth) / Double(max(canvasHeight, 1))) {
       stageContent(for: image)
     }
   }
@@ -128,26 +133,33 @@ struct CanvasStage: View {
       let crop = FramingMath.cropRect(
         imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
         canvasHeight: canvasHeight, framing: control.inputs.framing)
-      let rect = CGRect(
-        x: crop.minX / Double(image.pixelWidth) * size.width, y: crop.minY / Double(image.pixelHeight) * size.height,
-        width: crop.width / Double(image.pixelWidth) * size.width,
-        height: crop.height / Double(image.pixelHeight) * size.height)
-      ZStack {
-        if let picture {
-          Image(decorative: picture, scale: 1).resizable().interpolation(.high)
+      let inset = Self.boardMargin / (1 + 2 * Self.boardMargin)
+      let canvas = CGRect(
+        x: size.width * inset, y: size.height * inset, width: size.width * (1 - 2 * inset),
+        height: size.height * (1 - 2 * inset))
+      let scale = canvas.width / crop.width
+      let frame = CGSize(width: Double(image.pixelWidth) * scale, height: Double(image.pixelHeight) * scale)
+      let origin = CGPoint(x: canvas.minX - crop.minX * scale, y: canvas.minY - crop.minY * scale)
+      ZStack(alignment: .topLeading) {
+        Color.primary.opacity(0.08)
+        checkerboard(in: canvas)
+        if picture != nil {
+          imageLayer(picture, origin: origin, size: frame)
         } else {
-          Color.primary.opacity(0.08)
+          Color.primary.opacity(0.08).frame(width: frame.width, height: frame.height).position(
+            x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
         }
-        if let paintImage = drawing.paintImage { Image(decorative: paintImage, scale: 1).resizable().interpolation(.high) }
-        if let maskImage = drawing.maskImage { Image(decorative: maskImage, scale: 1).resizable().interpolation(.high) }
+        imageLayer(drawing.paintImage, origin: origin, size: frame)
+        imageLayer(drawing.maskImage, origin: origin, size: frame)
         Path { path in
           path.addRect(CGRect(origin: .zero, size: size))
-          path.addRect(rect)
+          path.addRect(canvas)
         }
         .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
-        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: rect.width, height: rect.height)
-          .position(x: rect.midX, y: rect.midY)
+        Rectangle().strokeBorder(DS.accent, lineWidth: 2).frame(width: canvas.width, height: canvas.height)
+          .position(x: canvas.midX, y: canvas.midY)
       }
+      .frame(width: size.width, height: size.height)
       .clipShape(RoundedRectangle(cornerRadius: DS.boxRadius, style: .continuous))
       .contentShape(Rectangle())
       .gesture(
@@ -155,50 +167,147 @@ struct CanvasStage: View {
           .onChanged { value in
             let start = dragStart ?? control.inputs.framing
             dragStart = start
-            move(from: start, by: value.translation, in: size, image: image, crop: crop)
+            move(from: start, by: value.translation, scale: scale, image: image, crop: crop)
           }
           .onEnded { _ in dragStart = nil })
     }
   }
 
-  /// The cut follows the pointer along the cropped axis; the other axis has nothing to move.
-  private func move(from start: Framing, by translation: CGSize, in size: CGSize, image: ReferenceImage, crop: CGRect) {
+  /// A layer of the image's own size and place in the view.
+  private func imageLayer(_ picture: CGImage?, origin: CGPoint, size: CGSize) -> some View {
+    Group {
+      if let picture { Image(decorative: picture, scale: 1).resizable().interpolation(.high) }
+    }
+    .frame(width: size.width, height: size.height)
+    .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
+  }
+
+  /// Squares under the canvas: what the image does not cover shows through them.
+  private func checkerboard(in rect: CGRect) -> some View {
+    Canvas { context, _ in
+      let cell = 10.0
+      context.fill(Path(rect), with: .color(Color(white: 0.86)))
+      var dark = Path()
+      var row = 0
+      var y = rect.minY
+      while y < rect.maxY {
+        var column = 0
+        var x = rect.minX
+        while x < rect.maxX {
+          if (row + column) % 2 == 0 {
+            dark.addRect(CGRect(x: x, y: y, width: min(cell, rect.maxX - x), height: min(cell, rect.maxY - y)))
+          }
+          x += cell
+          column += 1
+        }
+        y += cell
+        row += 1
+      }
+      context.fill(dark, with: .color(Color(white: 0.7)))
+    }
+    .allowsHitTesting(false)
+  }
+
+  /// The image follows the pointer on the axes where it and the canvas do not coincide.
+  private func move(from start: Framing, by translation: CGSize, scale: Double, image: ReferenceImage, crop: CGRect) {
     let slackX = Double(image.pixelWidth) - crop.width
     let slackY = Double(image.pixelHeight) - crop.height
     var x = start.offsetX
     var y = start.offsetY
-    if slackX > 0.5 {
-      x += translation.width * (Double(image.pixelWidth) / size.width) / (slackX / 2)
+    if abs(slackX) > 0.5 { x -= 2 * translation.width / scale / slackX }
+    if abs(slackY) > 0.5 { y -= 2 * translation.height / scale / slackY }
+    control.setOffset(x: x, y: y)
+  }
+
+  /// The zoom: −100 shrinks the image (margins to regenerate), +100 enlarges it. It stops, with a tick,
+  /// at 0 (fill) and where the whole image just fits.
+  private func zoomRow(for image: ReferenceImage) -> some View {
+    let contain = FramingMath.zoomContain(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight)
+    let zoom = control.inputs.framing.zoom
+    return CardRow(label: String(localized: "control.stage.zoom")) {
+      Slider(
+        value: Binding(get: { zoom }, set: { setZoom($0, contain: contain) }), in: Framing.zoomRange
+      )
+      .frame(minWidth: 120)
+    } control: {
+      HStack(spacing: 2) {
+        Text(verbatim: Int(zoom.rounded()).formatted(.number.sign(strategy: .always(includingZero: false))))
+          .font(.callout).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
+        iconButton("arrow.counterclockwise", "control.stage.zoom.reset", enabled: control.inputs.framing != Framing()) {
+          control.resetFraming()
+        }
+      }
     }
-    if slackY > 0.5 {
-      y += translation.height * (Double(image.pixelHeight) / size.height) / (slackY / 2)
+  }
+
+  private func setZoom(_ raw: Double, contain: Double) {
+    var value = raw
+    for target in [0.0, contain] where abs(raw - target) < 3 { value = target }
+    if value != raw, value != control.inputs.framing.zoom {
+      NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
     }
-    control.setOffset(x: x, y: y)
+    control.setZoom(value)
   }
 
   @ViewBuilder private func caption(for image: ReferenceImage) -> some View {
+    let framing = control.inputs.framing
+    let margins = FramingMath.margins(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight, framing: framing)
     let loss = FramingMath.loss(
       imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
-      canvasHeight: canvasHeight)
+      canvasHeight: canvasHeight, zoom: min(0, framing.zoom))
+    let crop = FramingMath.cropRect(
+      imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+      canvasHeight: canvasHeight, framing: framing)
+    let canMove =
+      abs(Double(image.pixelWidth) - crop.width) > 0.5 || abs(Double(image.pixelHeight) - crop.height) > 0.5
     VStack(alignment: .leading, spacing: 2) {
       Text(
         String(
           format: String(localized: "control.stage.size"), canvasWidth, canvasHeight)
       )
       .font(.caption).foregroundStyle(.secondary)
-      if let axis = loss.axis {
+      if !margins.isEmpty {
+        Text(String(format: String(localized: "control.stage.margins"), marginList(margins)))
+          .font(.caption).foregroundStyle(.secondary)
+      }
+      if framing.zoom > 0 {
+        let share = FramingMath.usedShare(
+          imageWidth: image.pixelWidth, imageHeight: image.pixelHeight, canvasWidth: canvasWidth,
+          canvasHeight: canvasHeight, framing: framing)
+        Text(String(format: String(localized: "control.stage.used"), Int((share * 100).rounded())))
+          .font(.caption).foregroundStyle(.secondary)
+      } else if let axis = loss.axis {
         Text(
           String(
             format: String(localized: axis == .vertical ? "control.stage.loss.vertical" : "control.stage.loss.horizontal"),
             Int((loss.fraction * 100).rounded()))
         )
         .font(.caption).foregroundStyle(loss.fraction > 1.0 / 3.0 ? DS.remove : .secondary)
-        Text("control.stage.drag").font(.caption).foregroundStyle(.secondary)
       }
+      if canMove { Text("control.stage.drag").font(.caption).foregroundStyle(.secondary) }
     }
     .frame(maxWidth: .infinity, alignment: .leading)
   }
 
+  /// "left 12%, right 12%": the sides that have a margin, as a share of the canvas.
+  private func marginList(_ margins: FramingMath.Margins) -> String {
+    var parts: [String] = []
+    func add(_ key: String.LocalizationValue, _ pixels: Double, of side: Int) {
+      if pixels >= 0.5 {
+        parts.append(String(format: String(localized: key), Int((pixels / Double(max(side, 1)) * 100).rounded())))
+      }
+    }
+    add("control.stage.margin.top", margins.top, of: canvasHeight)
+    add("control.stage.margin.bottom", margins.bottom, of: canvasHeight)
+    add("control.stage.margin.left", margins.left, of: canvasWidth)
+    add("control.stage.margin.right", margins.right, of: canvasWidth)
+    return parts.joined(separator: ", ")
+  }
+
   // MARK: Draw mode: tools
 
   /// One row like a toolbar: the tools, then what belongs to the tool chosen (invert and clear for the
@@ -341,10 +450,17 @@ struct CanvasStage: View {
       .position(x: origin.x + frame.width / 2, y: origin.y + frame.height / 2)
     }
     return ZStack(alignment: .topLeading) {
-      Color.primary.opacity(0.08)
+      Color(white: 0.5)
       layer(picture)
       layer(drawing.paintImage)
       layer(drawing.maskImage)
+      // What the image leaves uncovered is regenerated: it shows like the mask.
+      Path { path in
+        path.addRect(CGRect(origin: .zero, size: size))
+        path.addRect(CGRect(origin: origin, size: frame))
+      }
+      .fill(Color(red: 1, green: 140 / 255, blue: 0).opacity(0.55), style: FillStyle(eoFill: true))
+      .allowsHitTesting(false)
       if let hover {
         let radius = brushSize / 2 * size.width / Double(max(canvasWidth, 1))
         ZStack {
```

- [ ] **Step 4: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/m7d-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"; cd Packages && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|Missing|Not in" | grep -v "started\|reportsFailures"`
Expected: `** BUILD SUCCEEDED **`; test HubKit 65, HubCore 338, DTBridge 62, Catalog 6, LLMBridge 6 = **477** passati (il test del catalogo controlla le nuove chiavi).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add App && git commit -m "feat: slider Zoom nella card Canvas — stage con cornice e scacchiera, drag a due assi, scatti, margini in Disegno

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Verifica dal vivo e documenti

**Files:**
- Modify: `Packages/Package.swift` (il test di DTBridge vede HubCore), `Packages/Tests/DTBridgeTests/LiveServerTests.swift` (una prova con server vero, inattiva senza variabile d'ambiente), `docs/superpowers/specs/2026-10-03-outpaint-design.md`

- [ ] **Step 1: Aggiungere la prova dal vivo**

```diff
diff --git a/Packages/Package.swift b/Packages/Package.swift
index 90299e5..807da32 100644
--- a/Packages/Package.swift
+++ b/Packages/Package.swift
@@ -48,7 +48,7 @@ let package = Package(
     .testTarget(name: "LLMBridgeTests", dependencies: ["LLMBridge", "HubKit"]),
     .testTarget(name: "HubKitTests", dependencies: ["HubKit"]),
     .testTarget(name: "HubCoreTests", dependencies: ["HubCore", "HubKit"]),
-    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit"]),
+    .testTarget(name: "DTBridgeTests", dependencies: ["DTBridge", "HubKit", "HubCore"]),
     // Checks App/Localizable.xcstrings: every string translated in en and it (spec §12).
     .testTarget(name: "CatalogTests"),
   ]
```

```diff
diff --git a/Packages/Tests/DTBridgeTests/LiveServerTests.swift b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
index dd20e29..73a8730 100644
--- a/Packages/Tests/DTBridgeTests/LiveServerTests.swift
+++ b/Packages/Tests/DTBridgeTests/LiveServerTests.swift
@@ -6,6 +6,7 @@ import Testing
 import UniformTypeIdentifiers
 
 @testable import DTBridge
+@testable import HubCore
 
 /// Needs a real Draw Things gRPC server with "Model browsing" on. Run with:
 /// `DTHUB_LIVE_DT=localhost:7859 swift test --filter LiveServerTests`
@@ -177,6 +178,55 @@ struct LiveServerTests {
     #expect(ran > 0, "needs Juggernaut Reborn or a FLUX.2 klein model on the server")
   }
 
+  /// Outpaint, measured on SD 1.5 (Juggernaut Reborn): a 512×512 picture is put in a 768×512 canvas at
+  /// the zoom where it just fits, so it has 128 pixels of margin on each side (grey in the image,
+  /// regenerated by the mask). The picture stays as it was and the margins are painted. The pictures
+  /// go to the folder in `DTHUB_LIVE_OUT`, if set, for a look at the seams.
+  @Test(.enabled(if: address != nil))
+  func theMarginsAreRegeneratedAndThePictureStays() async throws {
+    let backend = try await liveBackend()
+    let models = try await backend.fetchCatalog().models
+    let file = try #require(models.first { $0.file.hasPrefix("juggernaut_reborn") }?.file, "needs Juggernaut Reborn")
+    var make = GenerationJob(
+      prompt: "a photograph of a quiet mountain lake at dusk, pine trees, soft light", model: file,
+      parameters: GenerationParameters(
+        width: 512, height: 512, steps: 16, guidanceScale: 4, sampler: .ddimTrailing, seed: 11, randomSeed: false))
+    make.imageStrength = nil
+    let source = try await run(backend, make, .none)
+    let contain = FramingMath.zoomContain(imageWidth: 512, imageHeight: 512, canvasWidth: 768, canvasHeight: 512)
+    let framing = Framing(zoom: contain)
+    let framed = try #require(InputComposer.frame(source, toWidth: 768, height: 512, framing: framing))
+    let mask = try #require(
+      InputComposer.mask(nil, imageWidth: 512, imageHeight: 512, toWidth: 768, height: 512, framing: framing))
+    var job = GenerationJob(
+      prompt: make.prompt, model: file,
+      parameters: GenerationParameters(
+        width: 768, height: 512, steps: 16, guidanceScale: 4, sampler: .ddimTrailing, seed: 11, randomSeed: false))
+    job.imageStrength = 1.0
+    job.maskSettings = MaskSettings()
+    let out = try await run(backend, job, GenerationInputs(image: framed, mask: mask))
+    await backend.shutdown()
+    if let folder = ProcessInfo.processInfo.environment["DTHUB_LIVE_OUT"] {
+      for (name, image) in [("source", source), ("framed", framed), ("mask", mask), ("outpaint", out)] {
+        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
+        if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
+          CGImageDestinationAddImage(destination, image, nil)
+          CGImageDestinationFinalize(destination)
+        }
+      }
+    }
+    #expect(out.width == 768 && out.height == 512)
+    let centre = try #require(out.cropping(to: CGRect(x: 160, y: 32, width: 448, height: 448)))
+    let before = try #require(source.cropping(to: CGRect(x: 32, y: 32, width: 448, height: 448)))
+    let a = averageColor(centre)
+    let b = averageColor(before)
+    print("LIVE outpaint: centre \(a) source \(b)")
+    #expect(abs(a.r - b.r) < 0.03 && abs(a.g - b.g) < 0.03 && abs(a.b - b.b) < 0.03)
+    let left = averageColor(try #require(out.cropping(to: CGRect(x: 0, y: 0, width: 120, height: 512))))
+    print("LIVE outpaint: left margin \(left)")
+    #expect(abs(left.r - 0.5) + abs(left.g - 0.5) + abs(left.b - 0.5) > 0.03, "the margin must not stay grey")
+  }
+
   /// 512×512, the right half transparent (to regenerate), the left half opaque (to keep).
   private func halfMask(size: Int) -> CGImage {
     let context = CGContext(
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: DTBridge `63 tests … passed` (la prova è inattiva), totale **478**.

- [ ] **Step 2: Provarla con un server vero**

Serve il server di Draw Things con i modelli di `/Volumes/LLM-VLM/Models` (Juggernaut Reborn). Si avvia a mano, solo per la prova, **e solo se non c'è già un `gRPCServerCLI` in esecuzione** (`pgrep -fl gRPCServerCLI`): qui la porta 7871.

```bash
mkdir -p /tmp/m7d-out && (nohup "$HOME/Applications/DrawThings-CLI/gRPCServerCLI-macOS" /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7871 --model-browser > /tmp/m7d-server.log 2>&1 &); sleep 6
cd "/Users/existenz/Software developement/DT Hub/Packages" && DTHUB_LIVE_OUT=/tmp/m7d-out DTHUB_LIVE_DT=127.0.0.1:7871 swift test --filter theMarginsAreRegenerated 2>&1 | grep -E "LIVE|passed|failed|error:" | grep -v started
pkill -TERM -f "gRPCServerCLI-macOS /Volumes/LLM-VLM/Models --address 127.0.0.1 --port 7871"
```

Expected: due righe `LIVE outpaint: …` (centro uguale alla sorgente; margine sinistro non grigio) e il test passa. **Guardare `/tmp/m7d-out/outpaint.png`** (768×512): nessuna riga chiara alle giunzioni a x≈128 e x≈640, il paesaggio continua; `framed.png` mostra i margini con i bordi estesi. Può volerci qualche minuto.

- [ ] **Step 3: Provare l'app, isolata**

Preparare una copia dei dati fuori dai dati dell'utente (nessun file dell'utente si tocca):

```bash
H=/tmp/m7dhome; rm -rf $H; mkdir -p "$H/Library/Application Support/DT Hub/Control"
cp /tmp/m7d-out/source.png "$H/Library/Application Support/DT Hub/Control/AAAA0000-0000-0000-0000-000000000001.png"
echo '{"image":{"id":"AAAA0000-0000-0000-0000-0000000000AA","name":"lake.png","fileName":"AAAA0000-0000-0000-0000-000000000001.png","pixelWidth":512,"pixelHeight":512,"source":{"result":{}}},"moodboard":[],"framing":{"offsetX":0,"offsetY":0,"zoom":-60}}' > "$H/Library/Application Support/DT Hub/control.json"
(CFFIXED_USER_HOME=$H nohup "/tmp/m7d-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/m7d-app.log 2>&1 &)
```

Checklist (a occhio o con gli strumenti di schermo):
1. Con zoom −60 il canvas mostra l'immagine più piccola, i margini a scacchi, la cornice scura attorno; la didascalia dice "Margini da rigenerare: sopra …, sotto …, sinistra …, destra …"; la card Immagine dice che con la maschera o i margini la forza è al 100%.
2. Con zoom 0 e rapporto diverso: l'immagine esce dal canvas e la cornice la mostra oscurata; con zoom +60 la didascalia dice "Si usa il N% dell'immagine" e la forza torna 70.
3. Trascinare l'immagine: segue il puntatore su entrambi gli assi quando c'è spazio, si ferma ai limiti.
4. Lo slider si ferma (con un tick) su 0 e sul valore in cui l'immagine sta tutta nel canvas; il pulsante "ripristina" riporta zoom e posizione a 0.
5. In Disegno i margini sono arancio come la maschera; Maschera +/− e Pennello lavorano sull'immagine e non scrivono nei margini; con zoom positivo il canvas mostra la parte ingrandita.
6. Chiudere e riaprire: zoom e posizione sono ancora lì; Annulla/Ripeti di un tratto non cambiano lo zoom.
7. Il tratto resta fluido anche con lo zoom diverso da 0 (a occhio).

Alla fine: chiudere l'app (`pkill -f "m7d-dd/Build/Products/Debug/DT Hub.app"`) e togliere `/tmp/m7dhome`.

- [ ] **Step 4: Aggiornare la spec**

Dalla radice, con questo script (due correzioni di testo e la nota di tappa):

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-03-outpaint-design.md'
s = open(p).read()
old = "I margini si riempiono di **grigio neutro** (50%). Il prototipo prova anche l'estensione dei bordi e, se la giunzione è migliore, la sostituisce (ruling)."
new = "I margini si riempiono con i **pixel del bordo dell'immagine stesi in fuori** (gli angoli con il pixel d'angolo). Provato dal vivo il 3 ottobre 2026 (SD 1.5, 512×512 in un canvas 768×512): con un grigio neutro \"Conserva l'originale\" lasciava una riga chiara sulla giunzione, con i bordi estesi no."
assert old in s
s = s.replace(old, new)
old = "compositore: pixel reali (immagine nella posizione, margini grigi, il Pennello nello stesso taglio)"
new = "compositore: pixel reali (immagine nella posizione, margini con il colore del bordo, il Pennello nello stesso taglio)"
assert old in s
s = s.replace(old, new)
s = s.replace("Stato: bozza da approvare", "Stato: realizzata (M7d)")
s = s.replace("**Dal vivo con un server vero:** un'immagine rimpicciolita in un canvas più largo; i margini si rigenerano, l'immagine resta (Conserva l'originale), giunzione senza cucitura visibile; confronto grigio e bordi estesi; forza al 100%.", "**Dal vivo con un server vero** (fatto il 3 ottobre 2026): un'immagine rimpicciolita in un canvas più largo; i margini si rigenerano, l'immagine resta (Conserva l'originale), giunzione senza cucitura visibile con i bordi estesi (con il grigio c'era una riga chiara); forza al 100%.")
open(p, 'w').write(s)
PY
git diff --stat docs
```

Expected: una riga di statistica sulla sola spec dell'outpaint (circa 3 righe cambiate).

- [ ] **Step 5: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add Packages docs && git commit -m "test: prova dal vivo dell'outpaint (SD 1.5), spec con i bordi estesi al posto del grigio

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine della M7d

Esito atteso sul branch `m7d-outpaint`:
- **478 test verdi** (1 prova dal vivo in più, inattiva senza `DTHUB_LIVE_DT`, provata con il server);
- build Xcode pulita;
- l'outpaint funziona dall'app: lo slider Zoom rimpicciolisce l'immagine nel canvas, i margini si rigenerano con una giunzione naturale, il drag sposta l'immagine, lo zoom positivo usa una porzione; maschera e Pennello continuano a funzionare.

Poi: revisione indipendente, correzioni, prove dell'utente (**lasciare l'app aperta**), merge. Dopo M7d: Tiled Diffusion 8192, M8 Plug-in, Galleria.

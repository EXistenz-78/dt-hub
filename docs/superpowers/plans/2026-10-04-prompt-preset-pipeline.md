# Prompt nei preset e pipeline di preset — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (P1) Il preset contiene anche il **prompt** e **non ha più le dimensioni**: caricarlo non cambia il formato del canvas. (P2) Un plug-in aggiunge **preset al menu Preset** (segnati «da <plug-in>»), e la pipeline diventa una sequenza di **«lancia PresA, poi PresB»** con gli ingressi che i preset non hanno: l'utente apre i preset, vede e modifica i parametri dei passaggi, e il Run usa quello che c'è nel menu al momento di partire. Il plug-in di esempio passa a 1.3.

**Architecture:**
- **HubKit**: `Preset` ottiene `prompt` e `origin`; `PipelineStep` perde `fields` e `loras` e ottiene `preset`; nuovo messaggio `presets` (`PluginPresets`).
- **HubCore**: `PresetLoad` (prompt, dimensioni del tab), `PresetStore.add(fromPlugin:)`, `PipelinePresets` (i preset mancanti, i campi di un passaggio), `PluginRegistry` instrada `presets`.
- **L'app**: salva e carica con il prompt, il menu Preset segna i preset dei plug-in, `runPipeline` usa i preset e il Run controlla prima che ci siano tutti.
- **PluginKit**: `registerPresets`, il plug-in di esempio 1.3 (i suoi due preset, la pipeline che li nomina, niente slider del peso).

**Tech Stack:** Swift 6, SwiftUI/AppKit, macOS 26, Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-04-preset-pipeline-design.md` (tutta). Parte da M8b: il piano dell'M8b è `2026-10-04-m8b-contributi-plugin.md` e il branch è lo stesso.

## Global Constraints

- **Repository e dipendenze:** radice `<repo>` (percorsi tra virgolette); **si lavora sul branch `m8b-plugin`** (già esistente, un solo merge alla fine, deciso con l'utente), senza crearne altri; macOS 26, Swift 6, Xcode 27; solo DTBridge importa DrawThings-Swift, solo LLMBridge importa MLX; `PluginKit/` non dipende da nulla dell'app.
- **Il contratto resta la versione 1**; i passaggi di M8b con `fields` e `loras` non si sono mai distribuiti: nessuna compatibilità da mantenere.
- **Le dimensioni non sono nei preset**: salvare un preset scrive larghezza e altezza di un `GenerationParameters` nuovo; caricarlo lascia quelle del tab (e, se il preset spegne il Tiled Diffusion e un lato supera 2048, `fitSizeToLimit`). Le dimensioni dei file vecchi e degli import restano nel file e non si usano.
- **Il prompt**: un preset con il prompt vuoto non tocca il prompt del tab; uno con il prompt lo sostituisce. Stessa regola del negativo. Nessuna casella: chi non lo vuole svuota il campo prima di salvare.
- **Il modello** resta nei preset come oggi (caricare dal menu lo cambia); **nei passaggi della pipeline si ignora**; un preset di un plug-in non ha modello.
- **Preset di un plug-in**: `origin` = identificatore del plug-in; mai sovrascritti dal plug-in (un nome già presente, anche di un preset dell'utente, conta come «existing»); l'utente può aprirli, cambiarli, salvarli con lo stesso nome (restano del plug-in) e cancellarli; spegnere il plug-in non li toglie. Solo un plug-in **attivo** può mandare `presets` (come `contribute`).
- **La pipeline**: un passaggio è `{title, preset, moodboard, startImage, useOutputAsStart}`; il preset si applica sui campi del tab (parametri, prompt e negativo se non vuoti), `moodboard` e `startImage` del passaggio e il risultato del passaggio precedente come in M8b. Se manca un preset il Run non parte e dice «Preset non trovato: <nomi>» (errore di Run nella finestra Risultati).
- **Stringhe**: ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo.
- **I blocchi `diff`** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi (o riscritti per intero, dove il testo lo dice) si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Compilazione dell'app:** i Task 2 e 3 cambiano `PipelineStep` e lasciano per un po' l'app senza compilare (`runPipeline` usa ancora `fields(over:)`); **torna a compilare nel Task 4**. I test dei pacchetti (`swift test`) sono il cancello dei Task 1–3.
- **L'app di prova** condivide le preferenze (`UserDefaults`) con quella dell'utente anche con `CFFIXED_USER_HOME` (i file no): se si cambia il modello per la prova, **rimetterlo alla fine** (Task 6).
- **Fuori:** passaggi con valori propri; preset condivisi tra plug-in; esportare i preset dei plug-in; un editor di pipeline.

## Review Focus

- **Cambia il comportamento di tutti i preset**: un preset già salvato (senza prompt, con le dimensioni nel file) si carica senza cambiare il prompt né il canvas; un file di preset illeggibile o con campi mancanti non fa perdere gli altri (test `aFileSavedBeforeHasNoPromptAndNoOrigin`, `theCanvasSizeOfTheTabStaysWhateverThePresetSays`, Task 1).
- **Il Tiled Diffusion**: un preset che spegne il Tiled Diffusion con un canvas grande nel tab riporta il canvas nel limite, e uno che lo accende non lo tocca (test `aPresetWithoutTheTiledDiffusionBringsABigCanvasBackWithinTheLimit`, Task 1).
- **Un plug-in non rovina i preset dell'utente**: nome già occupato (anche per maiuscole o accenti), preset modificato dall'utente, nome vuoto, messaggio malformato (test `aTakenNameIsNeverTouchedNotEvenByTheSamePlugin`, `anInactivePluginOrABadMessageAddsNothing`, `aMessageWithoutAPresetsListIsRefused`, Task 2 e 3).
- **La pipeline non parte a metà**: un preset mancante ferma tutto *prima* del primo passaggio (`run(with:)`), uno cancellato durante il Run ricade sui campi del tab (`PipelinePresets.fields`); **`run(with:)` e `runPipeline` non hanno test automatici**: il revisore li legga e li provi la prova dal vivo (Task 6).
- **La pipeline copia i valori del preset sul tab per ogni passaggio**: il seed casuale, il Tiled e le Avanzate vengono dal preset; il campo Seed del tab non si aggiorna (come in M8b).
- **I preset dei plug-in** arrivano quando il plug-in riceve `activate`: se il registro invia `activate` prima che la riga sia attiva, il messaggio `presets` viene rifiutato (verificato dal vivo nel prototipo che arriva; nessun test del registro lo copre).

---

### Task 1: Il prompt nei preset, le dimensioni fuori (P1)

**Files:**
- Modify: `App/Generation/GenerationController.swift`, `App/Localizable.xcstrings`, `Packages/Sources/HubCore/Presets/PresetImport.swift`, `Packages/Sources/HubCore/Presets/PresetStore.swift`, `Packages/Sources/HubKit/Generation/Preset.swift`, `Packages/Tests/HubCoreTests/PresetPromptTests.swift`, `Packages/Tests/HubCoreTests/PresetTests.swift`

**Interfaces:**
- Produces:
  - `Preset` (HubKit): `prompt: String` (vuoto = nessuno), `origin: String?` (l'identificatore del plug-in; letti in modo permissivo), nell'`init` dopo `model` e in fondo; i file vecchi si leggono;
  - `PresetLoad.of(_ preset: Preset, current: GenerationFields, catalog: ModelCatalog) -> PresetLoad` (era `currentNegativePrompt:`): `prompt`, `negativePrompt`, `parameters`, `model?`; le dimensioni sono quelle di `current`, poi `fitSizeToLimit()`;
  - `PresetStore.save` scrive i preset con le dimensioni predefinite (`withoutSize`);
  - `GenerationController.savePreset` salva anche il prompt, `load` lo rimette se non è vuoto; il testo `preset.save.contents` lo dice.
- Consumes: `GenerationFields` (M8b), `GenerationParameters.fitSizeToLimit` (M7e).

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Packages/Tests/HubCoreTests/PresetPromptTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PresetPromptTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)

  func tempFile() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PresetPromptTests-\(UUID())", isDirectory: true).appendingPathComponent("presets.json")
  }

  @Test func theTabsPromptStaysWhenThePresetHasNone() {
    let tab = GenerationFields(prompt: "my prompt", negativePrompt: "my negative")
    let without = PresetLoad.of(Preset(name: "a"), current: tab, catalog: catalog)
    #expect(without.prompt == "my prompt" && without.negativePrompt == "my negative")
    let with = PresetLoad.of(Preset(name: "b", prompt: "preset prompt"), current: tab, catalog: catalog)
    #expect(with.prompt == "preset prompt")
  }

  @Test func theCanvasSizeOfTheTabStaysWhateverThePresetSays() {
    var tab = GenerationFields()
    tab.parameters.width = 768
    tab.parameters.height = 1280
    let preset = Preset(name: "wide", parameters: GenerationParameters(width: 2048, height: 512, steps: 6))
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    #expect(load.parameters.width == 768 && load.parameters.height == 1280)
    #expect(load.parameters.steps == 6)
  }

  @Test func aPresetWithoutTheTiledDiffusionBringsABigCanvasBackWithinTheLimit() {
    var tab = GenerationFields()
    tab.parameters.advanced.tiledDiffusion = true
    tab.parameters.width = 4096
    tab.parameters.height = 2048
    let load = PresetLoad.of(Preset(name: "plain"), current: tab, catalog: catalog)
    #expect(load.parameters.width == 2048 && load.parameters.height == 1024)
    var tiled = Preset(name: "tiled")
    tiled.parameters.advanced.tiledDiffusion = true
    #expect(PresetLoad.of(tiled, current: tab, catalog: catalog).parameters.width == 4096)
  }

  @Test func theSavedPresetKeepsPromptAndOriginButNoSize() {
    let file = tempFile()
    let store = PresetStore(fileURL: file)
    store.save(Preset(name: "P", prompt: "a cat", parameters: GenerationParameters(width: 512, height: 1536), origin: "com.x"))
    let again = PresetStore(fileURL: file).preset(named: "p")
    #expect(again?.prompt == "a cat" && again?.origin == "com.x")
    #expect(again?.parameters.width == GenerationParameters.default.width)
    #expect(again?.parameters.height == GenerationParameters.default.height)
  }

  @Test func aFileSavedBeforeHasNoPromptAndNoOrigin() throws {
    let file = tempFile()
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"[{"name":"old","model":"m.ckpt","negativePrompt":"blur","parameters":{"steps":9,"width":512}}]"#.utf8).write(to: file)
    let old = try #require(PresetStore(fileURL: file).preset(named: "old"))
    #expect(old.prompt.isEmpty && old.origin == nil && old.parameters.steps == 9)
  }
}
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PresetTests.swift b/Packages/Tests/HubCoreTests/PresetTests.swift
index 5d78df8..825fbad 100644
--- a/Packages/Tests/HubCoreTests/PresetTests.swift
+++ b/Packages/Tests/HubCoreTests/PresetTests.swift
@@ -141,14 +141,14 @@ struct PresetLoadTests {
   @Test func loadingAPresetKeepsTheNegativePromptItDoesNotHave() {
     let withNegative = Preset(name: "a", model: "m.ckpt", negativePrompt: "blurry")
     let without = Preset(name: "b")
-    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "blurry")
-    #expect(PresetLoad.of(withNegative, currentNegativePrompt: "mine", catalog: catalog).model == "m.ckpt")
-    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).negativePrompt == "mine")
-    #expect(PresetLoad.of(without, currentNegativePrompt: "mine", catalog: catalog).model == nil)
+    #expect(PresetLoad.of(withNegative, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).negativePrompt == "blurry")
+    #expect(PresetLoad.of(withNegative, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).model == "m.ckpt")
+    #expect(PresetLoad.of(without, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).negativePrompt == "mine")
+    #expect(PresetLoad.of(without, current: GenerationFields(negativePrompt: "mine"), catalog: catalog).model == nil)
   }
 
   @Test func loadedParametersAreClamped() {
     let preset = Preset(name: "wild", parameters: GenerationParameters(steps: 9999))
-    #expect(PresetLoad.of(preset, currentNegativePrompt: "", catalog: catalog).parameters.steps == 150)
+    #expect(PresetLoad.of(preset, current: GenerationFields(), catalog: catalog).parameters.steps == 150)
   }
 }
```

Run: `cd "<repo>/Packages" && swift test --filter "PresetPromptTests|PresetLoadTests" 2>&1 | grep -E "error:" | head -2`
Expected: un errore di compilazione sulla firma di `PresetLoad.of(_:current:catalog:)` o su `prompt:`/`origin:` di `Preset` (non ci sono ancora).

- [ ] **Step 2: Implementare**

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 7ff92dc..0bb9f26 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -108,20 +108,22 @@ final class GenerationController {
     }
   }
 
-  /// Saves the tab as a preset (parameters, model, negative prompt; never the prompt).
-  /// False when the name is empty.
+  /// Saves the tab as a preset (parameters but not the size, model, prompt and negative prompt). Whoever does
+  /// not want the prompt in it empties the field first. False when the name is empty.
   @discardableResult
   func savePreset(named name: String, with connection: DrawThingsConnection) -> Bool {
     presets.save(
       Preset(
-        name: name, model: connection.selection.selectedFile ?? "", negativePrompt: negativePrompt,
+        name: name, model: connection.selection.selectedFile ?? "", prompt: prompt, negativePrompt: negativePrompt,
         parameters: parameters))
   }
 
-  /// Puts a preset on the tab; the prompt stays.
+  /// Puts a preset on the tab: its parameters (the canvas size stays), its prompt and negative prompt when it
+  /// has them, its model when it names one.
   func load(_ preset: Preset, with connection: DrawThingsConnection) {
-    let load = PresetLoad.of(preset, currentNegativePrompt: negativePrompt, catalog: connection.monitor.catalog)
+    let load = PresetLoad.of(preset, current: fields, catalog: connection.monitor.catalog)
     parameters = load.parameters
+    prompt = load.prompt
     negativePrompt = load.negativePrompt
     if lockRatio { lockedRatio = currentRatio }
     if let model = load.model { connection.selection.select(model) }
```

```diff
diff --git a/App/Localizable.xcstrings b/App/Localizable.xcstrings
index 067377c..883dff9 100644
--- a/App/Localizable.xcstrings
+++ b/App/Localizable.xcstrings
@@ -5413,13 +5413,13 @@
         "en": {
           "stringUnit": {
             "state": "translated",
-            "value": "Saves the model, the settings and the negative prompt, not the prompt."
+            "value": "Saves the model, the settings, the prompt and the negative prompt, not the size of the canvas."
           }
         },
         "it": {
           "stringUnit": {
             "state": "translated",
-            "value": "Salva il modello, le impostazioni e il prompt negativo, non il prompt."
+            "value": "Salva il modello, le impostazioni, il prompt e il prompt negativo, non le dimensioni del canvas."
           }
         }
       }
```

```diff
diff --git a/Packages/Sources/HubCore/Presets/PresetImport.swift b/Packages/Sources/HubCore/Presets/PresetImport.swift
index f42dff4..fa76057 100644
--- a/Packages/Sources/HubCore/Presets/PresetImport.swift
+++ b/Packages/Sources/HubCore/Presets/PresetImport.swift
@@ -57,17 +57,24 @@ extension GenerationParameters {
 
 /// What loading a preset puts on the tab.
 public struct PresetLoad: Equatable, Sendable {
-  public var parameters: GenerationParameters
+  public var prompt: String
   public var negativePrompt: String
+  public var parameters: GenerationParameters
   /// nil when the preset names no model: the chosen one stays.
   public var model: String?
 
-  /// The preset's parameters (clamped, triggers filled in), its negative prompt when it has
-  /// one, its model when it names one. The prompt is never touched.
-  public static func of(_ preset: Preset, currentNegativePrompt: String, catalog: ModelCatalog) -> PresetLoad {
-    PresetLoad(
-      parameters: preset.parameters.clamped().fillingTriggers(from: catalog),
-      negativePrompt: preset.negativePrompt.isEmpty ? currentNegativePrompt : preset.negativePrompt,
-      model: preset.model.isEmpty ? nil : preset.model)
+  /// The tab with the preset on it: the preset's parameters (clamped, triggers filled in) but the tab's own
+  /// width and height; the preset's prompt and negative prompt when it has them, the tab's otherwise; its
+  /// model when it names one. A side beyond the limit the preset's Tiled Diffusion setting allows comes back
+  /// within it, keeping the ratio.
+  public static func of(_ preset: Preset, current: GenerationFields, catalog: ModelCatalog) -> PresetLoad {
+    var parameters = preset.parameters.clamped().fillingTriggers(from: catalog)
+    parameters.width = current.parameters.width
+    parameters.height = current.parameters.height
+    parameters.fitSizeToLimit()
+    return PresetLoad(
+      prompt: preset.prompt.isEmpty ? current.prompt : preset.prompt,
+      negativePrompt: preset.negativePrompt.isEmpty ? current.negativePrompt : preset.negativePrompt,
+      parameters: parameters, model: preset.model.isEmpty ? nil : preset.model)
   }
 }
```

```diff
diff --git a/Packages/Sources/HubCore/Presets/PresetStore.swift b/Packages/Sources/HubCore/Presets/PresetStore.swift
index 54fd3bd..5fe26eb 100644
--- a/Packages/Sources/HubCore/Presets/PresetStore.swift
+++ b/Packages/Sources/HubCore/Presets/PresetStore.swift
@@ -33,7 +33,7 @@ public final class PresetStore {
   /// Saves under `preset.name`, replacing the preset of the same name. An empty name is refused.
   @discardableResult
   public func save(_ preset: Preset) -> Bool {
-    var preset = preset
+    var preset = preset.withoutSize()
     preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
     guard !preset.name.isEmpty else { return false }
     if let index = presets.firstIndex(where: { Self.same($0.name, preset.name) }) {
@@ -103,6 +103,16 @@ public final class PresetStore {
   }
 }
 
+extension Preset {
+  /// The preset with the size of a new `GenerationParameters`: a preset does not keep one.
+  fileprivate func withoutSize() -> Preset {
+    var copy = self
+    copy.parameters.width = GenerationParameters.default.width
+    copy.parameters.height = GenerationParameters.default.height
+    return copy
+  }
+}
+
 /// One element of the file, decoded on its own: a damaged preset does not take the others.
 private struct LossyPreset: Decodable {
   let preset: Preset?
```

```diff
diff --git a/Packages/Sources/HubKit/Generation/Preset.swift b/Packages/Sources/HubKit/Generation/Preset.swift
index 1a719af..03b8f62 100644
--- a/Packages/Sources/HubKit/Generation/Preset.swift
+++ b/Packages/Sources/HubKit/Generation/Preset.swift
@@ -1,24 +1,31 @@
 import Foundation
 
-/// A named recipe (spec §6): the model, the parameters (LoRAs and Advanced cards included)
-/// and the negative prompt. Never the prompt itself.
+/// A named recipe (spec §6, and `2026-10-04-preset-pipeline-design.md`): the model, the parameters (LoRAs and
+/// Advanced cards included), the prompt and the negative prompt. The size is not part of a preset: loading one
+/// never changes the canvas.
 public struct Preset: Equatable, Codable, Sendable, Identifiable {
   public var id: UUID
   public var name: String
   /// Empty when the preset names no model: loading it leaves the model as it is.
   public var model: String
+  /// Empty when the preset has none: loading it leaves the tab's prompt as it is.
+  public var prompt: String
   public var negativePrompt: String
   public var parameters: GenerationParameters
+  /// The identifier of the plug-in that added the preset; nil for the user's own.
+  public var origin: String?
 
   public init(
-    id: UUID = UUID(), name: String, model: String = "", negativePrompt: String = "",
-    parameters: GenerationParameters = .default
+    id: UUID = UUID(), name: String, model: String = "", prompt: String = "", negativePrompt: String = "",
+    parameters: GenerationParameters = .default, origin: String? = nil
   ) {
     self.id = id
     self.name = name
     self.model = model
+    self.prompt = prompt
     self.negativePrompt = negativePrompt
     self.parameters = parameters
+    self.origin = origin
   }
 
   /// Lenient, like the other saved formats.
@@ -27,7 +34,9 @@ public struct Preset: Equatable, Codable, Sendable, Identifiable {
     id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
     name = try container.decode(String.self, forKey: .name)
     model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
+    prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
     negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
+    origin = try? container.decodeIfPresent(String.self, forKey: .origin)
     parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
   }
 }
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `445 tests … passed` (5 nuovi: PresetPromptTests); gli altri invariati. L'app compila ancora (`xcodebuild … build`, `BUILD SUCCEEDED`).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A Packages App && git commit -m "feat: il prompt nei preset; le dimensioni escono dai preset

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Il messaggio `presets` e i passaggi con il nome di un preset (HubKit)

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginContribution.swift`, `Packages/Sources/HubKit/Plugin/PluginMessages.swift`, `Packages/Sources/HubKit/Plugin/PluginPresets.swift`, `Packages/Tests/HubKitTests/ContributionContractTests.swift`, `Packages/Tests/HubKitTests/ContributionReviewTests.swift`

**Interfaces:**
- Produces (HubKit, `public`):
  - `PluginMessageType.presets`;
  - `struct PluginPresets: Equatable, Sendable` (`presets: [Preset]`; `init?(message: Data, origin: String)`: nil se non è un oggetto con una lista `presets`; ogni voce ha `name` (senza nome è lasciata fuori), `fields` (le chiavi di `contribute`, `prompt` e `negativePrompt` compresi; larghezza e altezza non contano) e `loras` (pesi limitati); `origin` è quello dato; nessun modello);
  - `PipelineStep` ora è `{title, preset, moodboard, startImage, useOutputAsStart}` (`preset` ripulito dagli spazi, vuoto = nessuno); **`fields`, `loras` e `fields(over:)` non ci sono più**.
- Consumes: `FieldOverlay`, `GenerationFields`, `PluginContribution.loras` (M8b).

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

```diff
diff --git a/Packages/Tests/HubKitTests/ContributionContractTests.swift b/Packages/Tests/HubKitTests/ContributionContractTests.swift
index 248cfa8..2307a8e 100644
--- a/Packages/Tests/HubKitTests/ContributionContractTests.swift
+++ b/Packages/Tests/HubKitTests/ContributionContractTests.swift
@@ -60,8 +60,8 @@ struct ContributionContractTests {
        "moodboard":[{"path":"/tmp/a.png","name":"Sphere"},{"path":"/tmp/b.png"},{"name":"no path"}],
        "startImage":{"path":"/tmp/s.png"},
        "pipeline":{"name":"Match","steps":[
-         {"title":"Overcast","fields":{"steps":4},"loras":[]},
-         {"fields":{"guidanceScale":1},"moodboard":[{"path":"/tmp/a.png"}],"useOutputAsStart":true},
+         {"title":"Overcast","preset":" Sample · Overcast "},
+         {"preset":"Sample · Match","moodboard":[{"path":"/tmp/a.png"}],"useOutputAsStart":true},
          "junk"]}}
       """.utf8)
     let contribution = try #require(PluginContribution(message: message))
@@ -74,9 +74,9 @@ struct ContributionContractTests {
     #expect(pipeline.name == "Match")
     #expect(pipeline.steps.count == 2)
     #expect(pipeline.steps[0].title == "Overcast")
-    #expect(pipeline.steps[0].loras == [])
-    #expect(pipeline.steps[0].useOutputAsStart == false)
-    #expect(pipeline.steps[1].loras == nil)
+    #expect(pipeline.steps[0].preset == "Sample · Overcast")
+    #expect(pipeline.steps[0].useOutputAsStart == false && pipeline.steps[0].moodboard == nil)
+    #expect(pipeline.steps[1].preset == "Sample · Match")
     #expect(pipeline.steps[1].moodboard?.count == 1)
     #expect(pipeline.steps[1].useOutputAsStart)
   }
@@ -95,22 +95,26 @@ struct ContributionContractTests {
   }
 }
 
-struct PipelineStepTests {
-  @Test func aPassPutsItsChangesOnTheTabsFields() {
-    var base = GenerationFields(prompt: "tab prompt")
-    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
-    base.parameters.steps = 20
-    let step = PipelineStep(fields: FieldOverlay([.steps: .int(4), .prompt: .text("pass prompt")]))
-    let result = step.fields(over: base)
-    #expect(result.parameters.steps == 4)
-    #expect(result.prompt == "pass prompt")
-    #expect(result.parameters.loras.map(\.file) == ["tab.ckpt"])
+struct PluginPresetsTests {
+  @Test func presetsAreReadWithTheirFieldsAndLoRAsAndMarkedAsThePlugins() throws {
+    let message = Data(
+      """
+      {"type":"presets","presets":[
+        {"name":" Sample · Match ","fields":{"prompt":"match the light","negativePrompt":"blur","steps":4,"width":512,"model":"x.ckpt"},
+         "loras":[{"file":"sun.ckpt","weight":0.6}]},
+        {"name":"  "}, {"fields":{"steps":2}}, "junk"]}
+      """.utf8)
+    let presets = try #require(PluginPresets(message: message, origin: "com.x")).presets
+    #expect(presets.count == 1)
+    let preset = presets[0]
+    #expect(preset.name == "Sample · Match" && preset.origin == "com.x" && preset.model.isEmpty)
+    #expect(preset.prompt == "match the light" && preset.negativePrompt == "blur")
+    #expect(preset.parameters.steps == 4 && preset.parameters.loras.map(\.file) == ["sun.ckpt"])
   }
 
-  @Test func aPassWithLoRAsReplacesTheListAndAnEmptyListClearsIt() {
-    var base = GenerationFields()
-    base.parameters.loras = [LoRASelection(file: "tab.ckpt")]
-    #expect(PipelineStep(loras: [LoRASelection(file: "sun.ckpt", weight: 0.6)]).fields(over: base).parameters.loras.map(\.file) == ["sun.ckpt"])
-    #expect(PipelineStep(loras: []).fields(over: base).parameters.loras.isEmpty)
+  @Test func aMessageWithoutAPresetsListIsRefused() {
+    #expect(PluginPresets(message: Data(#"{"type":"presets"}"#.utf8), origin: "a") == nil)
+    #expect(PluginPresets(message: Data("[1]".utf8), origin: "a") == nil)
+    #expect(PluginPresets(message: Data(#"{"presets":[]}"#.utf8), origin: "a")?.presets.isEmpty == true)
   }
 }
```

```diff
diff --git a/Packages/Tests/HubKitTests/ContributionReviewTests.swift b/Packages/Tests/HubKitTests/ContributionReviewTests.swift
index 143ab7f..f1641ee 100644
--- a/Packages/Tests/HubKitTests/ContributionReviewTests.swift
+++ b/Packages/Tests/HubKitTests/ContributionReviewTests.swift
@@ -5,9 +5,8 @@ import Testing
 
 struct ContributionReviewTests {
   @Test func aLoRAWeightFromAPluginIsLimitedLikeTheCardLimitsIt() throws {
-    let message = Data(#"{"loras":[{"file":"a.ckpt","weight":50},{"file":"b.ckpt","weight":-9}],"pipeline":{"steps":[{"loras":[{"file":"c.ckpt","weight":99}]}]}}"#.utf8)
+    let message = Data(#"{"loras":[{"file":"a.ckpt","weight":50},{"file":"b.ckpt","weight":-9}]}"#.utf8)
     let contribution = try #require(PluginContribution(message: message))
     #expect(contribution.loras.map(\.weight) == [LoRASelection.weightRange.upperBound, LoRASelection.weightRange.lowerBound])
-    #expect(contribution.pipeline?.steps.first?.loras?.first?.weight == LoRASelection.weightRange.upperBound)
   }
 }
```

Run: `cd "<repo>/Packages" && swift test --filter "PluginPresetsTests|ContributionContractTests" 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'PluginPresets' in scope`.

- [ ] **Step 2: Implementare**

```diff
diff --git a/Packages/Sources/HubKit/Plugin/PluginContribution.swift b/Packages/Sources/HubKit/Plugin/PluginContribution.swift
index 55c1839..ede06a2 100644
--- a/Packages/Sources/HubKit/Plugin/PluginContribution.swift
+++ b/Packages/Sources/HubKit/Plugin/PluginContribution.swift
@@ -21,25 +21,24 @@ public struct PluginImageRef: Equatable, Sendable {
   }
 }
 
-/// One pass of a pipeline: changes to the configuration, the inputs, and whether the picture the previous
-/// pass made becomes the start image (plug-in design §7).
+/// One pass of a pipeline (`2026-10-04-preset-pipeline-design.md` §4): a preset to run, by name, and the inputs a
+/// preset does not hold. The preset's values are the user's to see and change in the Preset menu.
 public struct PipelineStep: Equatable, Sendable {
   public var title: String
-  public var fields: FieldOverlay
-  /// The LoRAs of this pass; nil keeps the ones on the tab.
-  public var loras: [LoRASelection]?
+  /// The preset to run; empty runs the tab's fields as they are.
+  public var preset: String
   /// The Moodboard of this pass; nil keeps the one on the tab.
   public var moodboard: [PluginImageRef]?
   public var startImage: PluginImageRef?
+  /// The picture the previous pass made becomes the start image of this one.
   public var useOutputAsStart: Bool
 
   public init(
-    title: String = "", fields: FieldOverlay = FieldOverlay(), loras: [LoRASelection]? = nil,
-    moodboard: [PluginImageRef]? = nil, startImage: PluginImageRef? = nil, useOutputAsStart: Bool = false
+    title: String = "", preset: String = "", moodboard: [PluginImageRef]? = nil, startImage: PluginImageRef? = nil,
+    useOutputAsStart: Bool = false
   ) {
     self.title = title
-    self.fields = fields
-    self.loras = loras
+    self.preset = preset
     self.moodboard = moodboard
     self.startImage = startImage
     self.useOutputAsStart = useOutputAsStart
@@ -48,24 +47,13 @@ public struct PipelineStep: Equatable, Sendable {
   init(_ object: [String: JSONValue]) {
     var title = ""
     if case .string(let text)? = object["title"] { title = text }
-    var fields = FieldOverlay()
-    if case .object(let json)? = object["fields"] { fields = FieldOverlay(json: json) }
+    var preset = ""
+    if case .string(let text)? = object["preset"] { preset = text.trimmingCharacters(in: .whitespacesAndNewlines) }
     var useOutput = false
     if case .bool(let flag)? = object["useOutputAsStart"] { useOutput = flag }
     self.init(
-      title: title, fields: fields, loras: PluginContribution.loras(object["loras"]),
-      moodboard: PluginContribution.images(object["moodboard"]), startImage: PluginImageRef(object["startImage"]),
-      useOutputAsStart: useOutput)
-  }
-}
-
-extension PipelineStep {
-  /// What this pass runs with: the tab's fields with the pass's changes on top, and its own LoRAs when it
-  /// has some (an empty list means no LoRA at all).
-  public func fields(over base: GenerationFields) -> GenerationFields {
-    var result = fields.applied(to: base)
-    if let loras { result.parameters.loras = loras }
-    return result
+      title: title, preset: preset, moodboard: PluginContribution.images(object["moodboard"]),
+      startImage: PluginImageRef(object["startImage"]), useOutputAsStart: useOutput)
   }
 }
 
```

```diff
diff --git a/Packages/Sources/HubKit/Plugin/PluginMessages.swift b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
index af9dc35..223f6ff 100644
--- a/Packages/Sources/HubKit/Plugin/PluginMessages.swift
+++ b/Packages/Sources/HubKit/Plugin/PluginMessages.swift
@@ -9,6 +9,8 @@ public enum PluginMessageType {
   public static let notice = "notice"
   /// Plug-in → app: values, LoRAs, pictures, a pipeline (`PluginContribution`).
   public static let contribute = "contribute"
+  /// Plug-in → app: presets to add to the Preset menu (`PluginPresets`).
+  public static let presets = "presets"
   /// Plug-in → app: a question for the language model; the answer is `{"type":"llm","text":…}`.
   public static let llm = "llm"
   /// The answer to a message the app could not use: `{"type":"error","text":…}`.
```

**`Packages/Sources/HubKit/Plugin/PluginPresets.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation

/// The `presets` message (plug-in → app): presets for the Preset menu, each a name, `fields` (the keys of
/// `contribute`, the prompt and the negative prompt among them; a width or height is ignored: a preset has
/// no size) and `loras`. What a preset does not say is the default. A plug-in never names a model.
public struct PluginPresets: Equatable, Sendable {
  public var presets: [Preset]

  /// Nil when the data is not a JSON object with a `presets` list. An entry without a name is left out.
  /// Every preset is marked as the plug-in's (`origin`).
  public init?(message: Data, origin: String) {
    guard let root = try? JSONDecoder().decode(JSONValue.self, from: message), case .object(let object) = root,
      case .array(let list)? = object["presets"]
    else { return nil }
    presets = list.compactMap { value in
      guard case .object(let entry) = value, case .string(let raw)? = entry["name"] else { return nil }
      let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty else { return nil }
      var overlay = FieldOverlay()
      if case .object(let json)? = entry["fields"] { overlay = FieldOverlay(json: json) }
      var fields = overlay.applied(to: GenerationFields())
      fields.parameters.loras = PluginContribution.loras(entry["loras"]) ?? []
      return Preset(
        name: name, prompt: fields.prompt, negativePrompt: fields.negativePrompt, parameters: fields.parameters,
        origin: origin)
    }
  }
}
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `93 tests … passed` (due test di `PipelineStep` tolti, due di `PluginPresets` aggiunti), HubCore invariato (`445`). L'app **non** compila più fino al Task 4.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A Packages && git commit -m "feat: messaggio presets; i passaggi della pipeline nominano un preset

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Aggiungere i preset dei plug-in e applicarli ai passaggi (HubCore)

**Files:**
- Modify: `Packages/Sources/HubCore/Plugins/PipelinePresets.swift`, `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `Packages/Sources/HubCore/Presets/PresetStore.swift`, `Packages/Tests/HubCoreTests/PluginPresetsTests.swift`

**Interfaces:**
- Produces (HubCore, `public`):
  - `PresetStore.add(fromPlugin: [Preset]) -> (added: Int, existing: Int)`: un nome già occupato (senza badare a maiuscole e accenti) non si tocca; i nuovi prendono un `id` nuovo, il nome ripulito e le dimensioni predefinite; salva solo se ha aggiunto;
  - `enum PipelinePresets` (`@MainActor`): `missing(in: PluginPipeline, store: PresetStore) -> [String]` (i nomi che mancano, una volta, in ordine, quelli vuoti no); `fields(for: PipelineStep, over: GenerationFields, store:, catalog:) -> GenerationFields` (il preset sul tab con `PresetLoad.of`: parametri, prompt e negativo se non vuoti, **non il modello né le dimensioni**; senza preset, o con un preset che non c'è più, i campi del tab);
  - `PluginRegistry.presetStore: PresetStore?`; `presets` da un plug-in attivo → `{"type":"ok","added":n,"existing":m}`; non attivo, senza lista o senza store → `error`.
- Consumes: `PluginPresets`, `PipelineStep.preset` (Task 2), `PresetLoad` (Task 1), `isActive` del registro (M8b).

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

**`Packages/Tests/HubCoreTests/PluginPresetsTests.swift`** (file nuovo o riscritto per intero):

```swift
import Foundation
import HubKit
import Testing

@testable import HubCore

@MainActor
struct PluginPresetsTests {
  let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)
  let store = PresetStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsTests-\(UUID())/presets.json"))

  func plugin(_ name: String, steps: Int = 4, prompt: String = "") -> Preset {
    Preset(name: name, prompt: prompt, parameters: GenerationParameters(steps: steps), origin: "com.x")
  }

  @Test func newPresetsAreAddedAndKeepTheirOrigin() {
    let result = store.add(fromPlugin: [plugin("A"), plugin("B")])
    #expect(result.added == 2 && result.existing == 0)
    #expect(store.preset(named: "a")?.origin == "com.x")
  }

  @Test func aTakenNameIsNeverTouchedNotEvenByTheSamePlugin() {
    store.save(Preset(name: "A", parameters: GenerationParameters(steps: 30)))
    store.add(fromPlugin: [plugin("B", steps: 4)])
    store.save(Preset(name: "B", prompt: "edited", parameters: GenerationParameters(steps: 9), origin: "com.x"))
    let result = store.add(fromPlugin: [plugin("a", steps: 4), plugin("B", steps: 4)])
    #expect(result.added == 0 && result.existing == 2)
    #expect(store.preset(named: "A")?.parameters.steps == 30 && store.preset(named: "A")?.origin == nil)
    #expect(store.preset(named: "B")?.parameters.steps == 9 && store.preset(named: "B")?.prompt == "edited")
  }

  @Test func theUsersEditToAPluginsPresetKeepsItsOrigin() {
    store.add(fromPlugin: [plugin("B")])
    var edited = store.preset(named: "B")!
    edited.parameters.steps = 12
    store.save(edited)
    #expect(store.preset(named: "B")?.origin == "com.x" && store.preset(named: "B")?.parameters.steps == 12)
  }

  @Test func theMissingPresetsOfAPipelineAreNamedOnceInOrder() {
    store.add(fromPlugin: [plugin("A")])
    let pipeline = PluginPipeline(steps: [
      PipelineStep(preset: "B"), PipelineStep(preset: "A"), PipelineStep(preset: "C"), PipelineStep(), PipelineStep(preset: "B"),
    ])
    #expect(PipelinePresets.missing(in: pipeline, store: store) == ["B", "C"])
  }

  @Test func aPassRunsThePresetOnTheTabWithoutItsModelOrSize() {
    var preset = Preset(name: "Match", model: "other.ckpt", prompt: "match the light", parameters: GenerationParameters(width: 2048, height: 256, steps: 4))
    preset.parameters.loras = [LoRASelection(file: "sun.ckpt", weight: 0.6)]
    store.save(preset)
    var tab = GenerationFields(prompt: "tab prompt", negativePrompt: "tab negative")
    tab.parameters.width = 768
    tab.parameters.height = 1280
    tab.parameters.steps = 30
    let used = PipelinePresets.fields(for: PipelineStep(preset: "match"), over: tab, store: store, catalog: catalog)
    #expect(used.prompt == "match the light" && used.negativePrompt == "tab negative")
    #expect(used.parameters.steps == 4 && used.parameters.loras.map(\.file) == ["sun.ckpt"])
    #expect(used.parameters.width == 768 && used.parameters.height == 1280)
  }

  @Test func aPassWithoutAPresetRunsTheTabAsItIs() {
    let tab = GenerationFields(prompt: "tab prompt")
    #expect(PipelinePresets.fields(for: PipelineStep(), over: tab, store: store, catalog: catalog) == tab)
    #expect(PipelinePresets.fields(for: PipelineStep(preset: "gone"), over: tab, store: store, catalog: catalog) == tab)
  }
}

@MainActor
struct PluginPresetsRoutingTests {
  let root = PluginFixture.folder()
  let presets = PresetStore(
    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsRouting-\(UUID())/presets.json"))

  func started() throws -> (PluginRegistry, FakeLoader) {
    try PluginFixture.bundle(in: root, id: "a", name: "A")
    let settings = PluginSettingsStore(fileURL: root.deletingLastPathComponent().appendingPathComponent("presets-\(root.lastPathComponent).json"))
    settings.save(["a"])
    let loader = FakeLoader()
    let registry = PluginRegistry(folder: PluginFolder(root: root), settings: settings, loader: loader, tempFolder: root)
    registry.presetStore = presets
    registry.start()
    return (registry, loader)
  }

  func send(_ json: String, _ loader: FakeLoader) async throws -> [String: Any] {
    let reply = await (try #require(loader.host)).receive(Data(json.utf8), from: "a")
    return try #require(try JSONSerialization.jsonObject(with: reply) as? [String: Any])
  }

  @Test func anActivePluginAddsItsPresetsAndTheAnswerCountsThem() async throws {
    let (_, loader) = try started()
    let message = #"{"type":"presets","presets":[{"name":"One","fields":{"steps":4,"prompt":"hi"}},{"name":"Two"}]}"#
    let first = try await send(message, loader)
    #expect(first["type"] as? String == "ok" && first["added"] as? Int == 2 && first["existing"] as? Int == 0)
    #expect(presets.preset(named: "One")?.prompt == "hi" && presets.preset(named: "One")?.origin == "a")
    let again = try await send(message, loader)
    #expect(again["added"] as? Int == 0 && again["existing"] as? Int == 2)
  }

  @Test func anInactivePluginOrABadMessageAddsNothing() async throws {
    let (registry, loader) = try started()
    #expect(try await send(#"{"type":"presets"}"#, loader)["type"] as? String == "error")
    registry.setActive("a", false)
    #expect(try await send(#"{"type":"presets","presets":[{"name":"One"}]}"#, loader)["type"] as? String == "error")
    #expect(presets.presets.isEmpty)
  }
}
```

Run: `cd "<repo>/Packages" && swift test --filter "PluginPresetsTests|PluginPresetsRoutingTests" 2>&1 | grep -E "error:" | head -2`
Expected: `value of type 'PresetStore' has no member 'add'`.

- [ ] **Step 2: Implementare**

**`Packages/Sources/HubCore/Plugins/PipelinePresets.swift`** (file nuovo o riscritto per intero):

```swift
import HubKit

/// The presets a plug-in's pipeline names (`2026-10-04-preset-pipeline-design.md` §4).
@MainActor
public enum PipelinePresets {
  /// The names the pipeline asks for that the Preset menu does not have, once each, in order.
  public static func missing(in pipeline: PluginPipeline, store: PresetStore) -> [String] {
    var result: [String] = []
    for step in pipeline.steps where !step.preset.isEmpty {
      if store.preset(named: step.preset) == nil, !result.contains(step.preset) { result.append(step.preset) }
    }
    return result
  }

  /// What a pass runs with: the tab's fields with the pass's preset on them (its parameters, and its prompt
  /// and negative prompt when it has them), but not its model nor a size. A pass without a preset, or whose
  /// preset is gone, runs the tab's fields as they are.
  public static func fields(for step: PipelineStep, over tab: GenerationFields, store: PresetStore, catalog: ModelCatalog)
    -> GenerationFields
  {
    guard !step.preset.isEmpty, let preset = store.preset(named: step.preset) else { return tab }
    let load = PresetLoad.of(preset, current: tab, catalog: catalog)
    return GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters)
  }
}
```

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
index 17760ea..1467bc6 100644
--- a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
+++ b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
@@ -62,6 +62,8 @@ public final class PluginRegistry: PluginHosting {
 
   /// What the active plug-ins contributed (teal fields, conflicts, the pipeline); the app sets its `target`.
   public let contributions = ContributionStore()
+  /// The Preset menu's store, where the presets a plug-in brings go; set by the app.
+  @ObservationIgnored public var presetStore: PresetStore?
   /// Answers a plug-in's question to the language model (`llm` message); nil = no language model.
   @ObservationIgnored public var askLanguageModel: (@MainActor (_ prompt: String, _ images: [URL]) async throws -> String)?
 
@@ -286,6 +288,8 @@ public final class PluginRegistry: PluginHosting {
     switch PluginMessageType.of(message) {
     case PluginMessageType.contribute:
       return contribute(message, from: pluginID)
+    case PluginMessageType.presets:
+      return addPresets(message, from: pluginID)
     case PluginMessageType.llm:
       return await askModel(message, from: pluginID)
     case PluginMessageType.notice:
@@ -318,6 +322,18 @@ public final class PluginRegistry: PluginHosting {
     return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
   }
 
+  /// Presets for the Preset menu; a name already there is left alone. `{"type":"ok","added":n,"existing":m}`.
+  private func addPresets(_ message: Data, from pluginID: String) -> Data {
+    guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
+    guard let store = presetStore else { return PluginMessageType.failure("There is no preset store.") }
+    guard let parsed = PluginPresets(message: message, origin: pluginID) else {
+      return PluginMessageType.failure("The message has no presets list.")
+    }
+    let result = store.add(fromPlugin: parsed.presets)
+    let answer: [String: Any] = ["type": PluginMessageType.ok, "added": result.added, "existing": result.existing]
+    return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
+  }
+
   /// `{"type":"llm","prompt":…,"images":[paths]}` → `{"type":"llm","text":…}`.
   private func askModel(_ message: Data, from pluginID: String) async -> Data {
     guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
```

```diff
diff --git a/Packages/Sources/HubCore/Presets/PresetStore.swift b/Packages/Sources/HubCore/Presets/PresetStore.swift
index 5fe26eb..fec3896 100644
--- a/Packages/Sources/HubCore/Presets/PresetStore.swift
+++ b/Packages/Sources/HubCore/Presets/PresetStore.swift
@@ -81,6 +81,29 @@ public final class PresetStore {
     commit()
   }
 
+  /// Adds the presets a plug-in brought (each already marked with its `origin`). A name that is taken, by the
+  /// user's own preset or by an earlier one of the plug-in, is never touched: the user may have changed it.
+  /// Returns how many were added and how many were there already.
+  @discardableResult
+  public func add(fromPlugin newPresets: [Preset]) -> (added: Int, existing: Int) {
+    var added = 0
+    var existing = 0
+    for preset in newPresets {
+      let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
+      if name.isEmpty || presets.contains(where: { Self.same($0.name, name) }) {
+        existing += 1
+        continue
+      }
+      var copy = preset.withoutSize()
+      copy.name = name
+      copy.id = UUID()
+      presets.append(copy)
+      added += 1
+    }
+    if added > 0 { commit() }
+    return (added, existing)
+  }
+
   private func commit() {
     presets = Self.sorted(presets)
     do {
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubCore `453 tests … passed` (8 nuovi).

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A Packages && git commit -m "feat: i preset dei plug-in nel menu; applicazione di un preset a un passaggio

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: L'app — la pipeline usa i preset, il menu li segna, l'avviso

**Files:**
- Modify: `App/DTHubApp.swift`, `App/Generation/GenerationController.swift`, `App/Generation/Presets/PresetBar.swift`, `App/Localizable.xcstrings`, `App/Plugins/ContributionText.swift`
- Test: nessuno nuovo — `LocalizationCatalogTests` (esistente) controlla il catalogo; `run(with:)` e `runPipeline` si provano col Task 6.

**Interfaces:**
- Consumes: `PipelinePresets`, `PluginRegistry.presetStore` (Task 3), `PipelineStep.preset` (Task 2).
- Produces: `GenerationController.run(with:)`: se la pipeline nomina preset che non ci sono, `session.fail(with: .generationFailed("Preset non trovato: A, B"))` e ritorna `true` (la finestra Risultati si apre e lo mostra) senza partire; `runPipeline` usa `PipelinePresets.fields(for:over:store:catalog:)` al posto di `fields(over:)`; `DTHubApp` dà `plugins.presetStore = generation.presets`; il menu Preset scrive «Nome · da <plug-in>» per i preset con `origin`; il suggerimento del pulsante Run elenca per ogni passaggio titolo, « — preset» e «← dal risultato precedente».

- [ ] **Step 1: Applicare le modifiche**

```diff
diff --git a/App/DTHubApp.swift b/App/DTHubApp.swift
index 5f92037..f840956 100644
--- a/App/DTHubApp.swift
+++ b/App/DTHubApp.swift
@@ -44,6 +44,7 @@ struct DTHubApp: App {
       tempFolder: FileManager.default.temporaryDirectory.appendingPathComponent("DTHub-plugins", isDirectory: true))
     // Contributions land on the Generation tab; a plug-in's question goes to the language model.
     generation.attach(plugins.contributions)
+    plugins.presetStore = generation.presets
     plugins.askLanguageModel = { prompt, images in try await languageModel.respond(to: prompt, images: images) }
     plugins.start(skipping: NSEvent.modifierFlags.contains(.option))
     _plugins = State(initialValue: plugins)
```

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index 0bb9f26..a38f46e 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -182,6 +182,15 @@ final class GenerationController {
   @discardableResult
   func run(with connection: DrawThingsConnection) -> Bool {
     guard canRun(with: connection) else { return false }
+    // A pipeline whose presets are not all in the Preset menu does not start.
+    if let pipeline = contributions?.pipeline?.pipeline {
+      let missing = PipelinePresets.missing(in: pipeline, store: presets)
+      if !missing.isEmpty {
+        session.fail(
+          with: .generationFailed(String(format: String(localized: "pipeline.missingPreset"), missing.joined(separator: ", "))))
+        return true
+      }
+    }
     isPreparing = true
     let passes = contributions?.pipeline?.pipeline.steps
     preparation = Task {
@@ -201,8 +210,8 @@ final class GenerationController {
     return true
   }
 
-  /// The passes of a pipeline, one after the other (plug-in design §7). Each pass runs the tab's fields with
-  /// its own changes on top; the picture a pass makes can be the next one's start image. A failed or stopped
+  /// The passes of a pipeline, one after the other (plug-in design §7, preset design §4). Each pass runs the
+  /// tab's fields with its preset on them; the picture a pass makes can be the next one's start image. A failed or stopped
   /// pass ends the pipeline; the pictures already made stay in the strip.
   private func runPipeline(_ passes: [PipelineStep], with connection: DrawThingsConnection) async {
     defer {
@@ -214,7 +223,8 @@ final class GenerationController {
     for (index, pass) in passes.enumerated() {
       guard !Task.isCancelled else { return }
       pipelinePass = (index + 1, passes.count)
-      let used = pass.fields(over: fields)
+      let used = PipelinePresets.fields(
+        for: pass, over: fields, store: presets, catalog: connection.monitor.catalog)
       guard let base = await renderInputs(in: connection, parameters: used.parameters) else { return }
       guard !Task.isCancelled, let backend = connection.monitor.backend, let model = connection.selection.selectedFile,
         RunAvailability.blocker(
```

```diff
diff --git a/App/Generation/Presets/PresetBar.swift b/App/Generation/Presets/PresetBar.swift
index d7a3491..818b962 100644
--- a/App/Generation/Presets/PresetBar.swift
+++ b/App/Generation/Presets/PresetBar.swift
@@ -13,6 +13,7 @@ struct PresetBar: View {
   @State private var managing = false
   @State private var editingJSON = false
   @State private var importMessage: String?
+  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
 
   var body: some View {
     HStack(spacing: DS.controlGap) {
@@ -24,7 +25,7 @@ struct PresetBar: View {
           Button {
             controller.load(preset, with: connection)
           } label: {
-            Text(verbatim: preset.name)
+            Text(verbatim: title(of: preset))
           }
         }
         Divider()
@@ -85,6 +86,13 @@ struct PresetBar: View {
     }
   }
 
+  /// The name, and "da <plug-in>" for a preset a plug-in brought.
+  private func title(of preset: Preset) -> String {
+    guard let origin = preset.origin else { return preset.name }
+    let plugin = plugins?.entries.first { $0.id == origin }?.name ?? origin
+    return preset.name + " · " + String(format: String(localized: "control.source.plugin"), plugin)
+  }
+
   /// Asks for a file with a list of presets; the result is told in the bar.
   private func importFile() {
     let panel = NSOpenPanel()
```

```diff
diff --git a/App/Localizable.xcstrings b/App/Localizable.xcstrings
index 883dff9..cc31650 100644
--- a/App/Localizable.xcstrings
+++ b/App/Localizable.xcstrings
@@ -1701,6 +1701,23 @@
         }
       }
     },
+    "contribution.fromPrevious": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "from the previous result"
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "dal risultato precedente"
+          }
+        }
+      }
+    },
     "contribution.off": {
       "extractionState": "manual",
       "localizations": {
@@ -3724,6 +3741,23 @@
         }
       }
     },
+    "pipeline.missingPreset": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Preset not found: %@"
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Preset non trovato: %@"
+          }
+        }
+      }
+    },
     "plugin.error.contract": {
       "extractionState": "manual",
       "localizations": {
```

```diff
diff --git a/App/Plugins/ContributionText.swift b/App/Plugins/ContributionText.swift
index 335f461..37f6b10 100644
--- a/App/Plugins/ContributionText.swift
+++ b/App/Plugins/ContributionText.swift
@@ -67,7 +67,10 @@ enum ContributionText {
   static func pipelineHelp(_ contribution: PipelineContribution, plugins: PluginRegistry) -> String {
     let plugin = plugins.entries.first { $0.id == contribution.pluginID }?.name ?? contribution.pluginID
     let list = contribution.pipeline.steps.enumerated().map { index, step in
-      "\(index + 1). " + (step.title.isEmpty ? String(format: String(localized: "contribution.pass"), index + 1) : step.title)
+      var line = "\(index + 1). " + (step.title.isEmpty ? String(format: String(localized: "contribution.pass"), index + 1) : step.title)
+      if !step.preset.isEmpty { line += " — " + step.preset }
+      if step.useOutputAsStart { line += " ← " + String(localized: "contribution.fromPrevious") }
+      return line
     }
     return ([plugin + (contribution.pipeline.name.isEmpty ? "" : " · " + contribution.pipeline.name)] + list).joined(separator: "\n")
   }
```

- [ ] **Step 2: Compilare e provare**

Run: `cd "<repo>" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/p-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: gli stessi conteggi del Task 3 (Catalog 6 verdi).

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add -A App && git commit -m "feat: la pipeline esegue i preset; il menu Preset segna quelli dei plug-in; avviso del preset mancante

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: PluginKit e il plug-in di esempio 1.3

**Files:**
- Modify: `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift`, `PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift`, `PluginKit/README.md`, `PluginKit/Scripts/build-sample.sh`, `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift`

**Interfaces:**
- Produces: `DTHubHost.registerPresets(_ presets: [[String: Any]]) async -> [String: Any]?`; il Sample 1.3 manda `presets` quando riceve `activate` e prima di ogni pipeline («<nome> · Overcast» e «<nome> · Match the sun», il secondo con il LoRA sun-direction a 0,6), la pipeline nomina i preset (il secondo passaggio ha la sfera nel Moodboard e `useOutputAsStart` se c'è l'Overcast), lo slider del peso non c'è più, `press` ha il bottone `presets`; `build-sample.sh` costruisce la versione 1.3.

- [ ] **Step 1: Scrivere il test e verificare che fallisca**

```diff
diff --git a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
index 5cfeed1..dbf0def 100644
--- a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
+++ b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
@@ -122,6 +122,15 @@ struct BundlePluginLoaderTests {
     let piped = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
     let pipeline = try #require(PluginContribution(message: piped.message)?.pipeline)
     #expect(pipeline.steps.count == 1 && pipeline.steps[0].moodboard?.count == 1 && pipeline.steps[0].useOutputAsStart == false)
+    #expect(pipeline.steps[0].preset == "Sample · Match the sun")
+
+    // The presets the pipeline names are offered before the pipeline (and on request).
+    _ = await plugin.send(Data(#"{"type":"press","button":"presets"}"#.utf8))
+    let offered = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.presets })
+    let list = try #require(PluginPresets(message: offered.message, origin: "x")).presets
+    #expect(list.map(\.name) == ["Sample · Overcast", "Sample · Match the sun"])
+    #expect(list[1].parameters.loras.first?.weight == 0.6 && list[0].parameters.loras.isEmpty)
+    #expect(list[1].prompt.hasPrefix("match light direction"))
 
     _ = await plugin.send(Data(#"{"type":"press","button":"ask"}"#.utf8))
     #expect(host.received.contains { PluginMessageType.of($0.message) == PluginMessageType.llm })
```

Run: `cd "<repo>/Packages" && swift test --filter BundlePluginLoaderTests 2>&1 | grep -E "recorded an issue" | head -2`
Expected: un'aspettativa fallita sul nome del preset del primo passaggio (`pipeline.steps[0].preset == "Sample · Match the sun"`).

- [ ] **Step 2: Implementare**

```diff
diff --git a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
index d30dcb1..4614df8 100644
--- a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
+++ b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
@@ -30,7 +30,6 @@ final class SampleState: ObservableObject {
   @Published var model = "—"
   @Published var active = false
   @Published var azimuth = 45.0
-  @Published var loraWeight = 60.0
   @Published var overcast = false
   @Published var answer = ""
   @Published var status = ""
@@ -40,7 +39,7 @@ final class SampleState: ObservableObject {
 
 @MainActor
 final class SamplePlugin: DTHubPlugin {
-  let manifest = DTHubManifest(id: Variant.id, name: Variant.name, version: "1.2", symbol: Variant.symbol)
+  let manifest = DTHubManifest(id: Variant.id, name: Variant.name, version: "1.3", symbol: Variant.symbol)
   private let state = SampleState()
   private var host: DTHubHost?
 
@@ -68,6 +67,8 @@ final class SamplePlugin: DTHubPlugin {
       return nil
     case "activate":
       state.active = true
+      // The app only listens to a plug-in that is on: the presets are offered now.
+      Task { await registerPresets() }
       return nil
     case "deactivate":
       state.active = false
@@ -78,6 +79,7 @@ final class SamplePlugin: DTHubPlugin {
       switch button {
       case "plain": await sendPlain()
       case "pipeline": await sendPipeline()
+      case "presets": await registerPresets()
       case "startImage": await sendStartImage()
       case "ask": await askModel()
       default: return DTHubMessage.bare("unsupported")
@@ -98,7 +100,7 @@ final class SamplePlugin: DTHubPlugin {
     return (try? data.write(to: URL(fileURLWithPath: path))) == nil ? nil : path
   }
 
-  /// The settings of the sun-direction pass of the Light Direction companion script.
+  /// The settings of the sun-direction passes of the Light Direction companion script.
   private func sunFields(prompt: String) -> [String: Any] {
     [
       "prompt": prompt, "steps": Variant.steps, "guidanceScale": Variant.guidance, "shift": 3, "sampler": 16,
@@ -106,7 +108,20 @@ final class SamplePlugin: DTHubPlugin {
     ]
   }
 
-  private var sunLora: [String: Any] { ["file": Variant.lora, "weight": state.loraWeight / 100] }
+  private var sunLora: [String: Any] { ["file": Variant.lora, "weight": 0.6] }
+
+  private var overcastPreset: String { "\(Variant.name) · Overcast" }
+  private var matchPreset: String { "\(Variant.name) · Match the sun" }
+
+  /// The two presets of the pipeline, in the app's Preset menu: the user sees them, changes them (the LoRA
+  /// weight, the steps…) and saves them under the same name. The app never overwrites a name it has.
+  func registerPresets() async {
+    let answer = await host?.registerPresets([
+      ["name": overcastPreset, "fields": sunFields(prompt: "make it an overcast day, remove the shadows")],
+      ["name": matchPreset, "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora]],
+    ])
+    if let answer, answer["type"] as? String == "error" { state.status = answer["text"] as? String ?? "Error" }
+  }
 
   /// A prompt, parameters, a LoRA and a picture for the Moodboard.
   func sendPlain() async {
@@ -118,18 +133,16 @@ final class SamplePlugin: DTHubPlugin {
     report(answer)
   }
 
-  /// The two passes of the script: flatten the shadows (optional), then match the sun.
+  /// The two passes of the script, as presets: flatten the shadows (optional), then match the sun with the
+  /// sphere in the Moodboard and the first pass's picture as the start image.
   func sendPipeline() async {
     guard let sphere = spherePath() else { return state.status = "No picture folder yet: switch the plug-in on first." }
+    await registerPresets()
     var steps: [[String: Any]] = []
-    if state.overcast {
-      steps.append([
-        "title": "Overcast", "fields": sunFields(prompt: "make it an overcast day, remove the shadows"), "loras": [[String: Any]](),
-      ])
-    }
+    if state.overcast { steps.append(["title": "Overcast", "preset": overcastPreset]) }
     steps.append([
-      "title": "Match the sun", "fields": sunFields(prompt: Variant.prompt), "loras": [sunLora],
-      "moodboard": [["name": "Sphere light", "path": sphere]], "useOutputAsStart": state.overcast,
+      "title": "Match the sun", "preset": matchPreset, "moodboard": [["name": "Sphere light", "path": sphere]],
+      "useOutputAsStart": state.overcast,
     ])
     report(await host?.contribute(["pipeline": ["name": "Sun direction", "steps": steps]]))
   }
@@ -166,7 +179,7 @@ struct SampleView: View {
 
   var body: some View {
     VStack(alignment: .leading, spacing: 12) {
-      Text("\(Variant.name) plug-in 1.2").font(.title2)
+      Text("\(Variant.name) plug-in 1.3").font(.title2)
       Text("Model: \(state.model)")
       Text(state.active ? "active" : "not active").foregroundStyle(.secondary)
       Divider()
@@ -175,11 +188,6 @@ struct SampleView: View {
         Slider(value: $state.azimuth, in: 0...360)
         Text("\(Int(state.azimuth))°").monospacedDigit().frame(width: 44, alignment: .trailing)
       }
-      HStack {
-        Text("LoRA weight")
-        Slider(value: $state.loraWeight, in: -100...100)
-        Text("\(Int(state.loraWeight))").monospacedDigit().frame(width: 44, alignment: .trailing)
-      }
       Toggle("Overcast shadows (adds a pass)", isOn: $state.overcast)
       HStack {
         Button("Send prompt, parameters and sphere") { Task { await sendPlain() } }
```

```diff
diff --git a/PluginKit/README.md b/PluginKit/README.md
index 3b86908..8a4c79a 100644
--- a/PluginKit/README.md
+++ b/PluginKit/README.md
@@ -44,12 +44,17 @@ JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.
   - `moodboard`: `[{"path", "name"}]`, files in the `tempFolder`, added to the Moodboard. Sending them again replaces
     the ones this plug-in sent before.
   - `startImage`: `{"path", "name"}`, the start image of the Control tab.
-  - `pipeline`: `{"name", "steps": [...]}`; each step may have `title`, `fields` (as above), `loras` (replaces the list
-    for the pass; `[]` = none), `moodboard` (replaces the Moodboard for the pass), `startImage`, and
-    `useOutputAsStart` (the picture the previous pass made becomes the start image). RUN then runs the passes one
-    after the other.
+  - `pipeline`: `{"name", "steps": [...]}`; each step is `{"title", "preset", "moodboard", "startImage",
+    "useOutputAsStart"}`: the name of a preset in the app's Preset menu (its parameters, prompt and negative
+    prompt are applied on the tab's fields, but not its model nor a size), the Moodboard for the pass (replaces the
+    tab's), a start image, and whether the picture the previous pass made becomes the start image. RUN then runs
+    the passes one after the other; if a preset is not in the menu it says so and runs nothing.
   The fields a plug-in filled turn teal; the user can always change them. If two plug-ins fill the same field, or
   both propose a start image or a pipeline, the user chooses in a pop-up.
+- `presets` — `{"presets": [{"name", "fields", "loras"}]}`: presets for the Preset menu (shown as «da <plug-in>»);
+  `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size, no model. A
+  name the menu has already is never touched (the user may have changed it), so register them whenever you like.
+  The answer is `{"type":"ok","added":n,"existing":m}`.
 - `llm` — `{"prompt", "images": [paths]}`: a question for the language model. The answer is
   `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`.
 
```

```diff
diff --git a/PluginKit/Scripts/build-sample.sh b/PluginKit/Scripts/build-sample.sh
index e2d1a48..aaf99d7 100755
--- a/PluginKit/Scripts/build-sample.sh
+++ b/PluginKit/Scripts/build-sample.sh
@@ -2,7 +2,7 @@
 # build-sample.sh OUT_FOLDER [b]
 # Builds the sample plug-in of Examples/Sample into OUT_FOLDER/Sample.dthubplugin; with `b`, the second sample
 # (identifier com.example.dthub.sample.b, other module and class) into OUT_FOLDER/SampleB.dthubplugin.
-# Version 1.2. Needs the Swift toolchain; run from anywhere.
+# Version 1.3. Needs the Swift toolchain; run from anywhere.
 set -e
 HERE="${0:A:h}"
 OUT="${1:?usage: build-sample.sh OUT_FOLDER [b]}"
@@ -11,10 +11,10 @@ SCRATCH="$(mktemp -d)"
 trap 'rm -rf "$SCRATCH"' EXIT
 if [[ "$2" == "b" ]]; then
   SAMPLE_B=1 swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
-  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePluginB.dylib | head -1)" "$OUT/SampleB.dthubplugin" com.example.dthub.sample.b SampleB 1.2 SampleBEntry
+  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePluginB.dylib | head -1)" "$OUT/SampleB.dthubplugin" com.example.dthub.sample.b SampleB 1.3 SampleBEntry
   echo "$OUT/SampleB.dthubplugin"
 else
   swift build --package-path "$HERE/../Examples/Sample" --scratch-path "$SCRATCH" >/dev/null
-  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePlugin.dylib | head -1)" "$OUT/Sample.dthubplugin" com.example.dthub.sample Sample 1.2 SampleEntry
+  "$HERE/make-bundle.sh" "$(find "$SCRATCH" -name libSamplePlugin.dylib | head -1)" "$OUT/Sample.dthubplugin" com.example.dthub.sample Sample 1.3 SampleEntry
   echo "$OUT/Sample.dthubplugin"
 fi
```

```diff
diff --git a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
index 8afffea..5ca3ec5 100644
--- a/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
+++ b/PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift
@@ -78,6 +78,13 @@ public final class DTHubHost {
     await sendJSON(body.merging(["type": "contribute"]) { _, new in new })
   }
 
+  /// Sends a `presets` message: presets for the app's Preset menu, each `{"name", "fields", "loras"}` (the keys of
+  /// `contribute`; the prompt and the negative prompt go in `fields`; a preset has no size and no model). A
+  /// name that is in the menu already is never touched. The answer is `{"type":"ok","added":n,"existing":m}`.
+  public func registerPresets(_ presets: [[String: Any]]) async -> [String: Any]? {
+    await sendJSON(["type": "presets", "presets": presets])
+  }
+
   /// Asks the app's language model, which answers in its own time (it may have to load first). Nil when
   /// there is no answer: no model chosen, the plug-in not active, a timeout.
   public func askLanguageModel(_ prompt: String, images: [String] = []) async -> String? {
```

```bash
cd "<repo>" && chmod +x PluginKit/Scripts/build-sample.sh
```

- [ ] **Step 3: Verificare**

Run: `cd "<repo>/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit 93, HubCore 453, DTBridge 66, Catalog 6, LLMBridge 6, PluginHost 6 (totale **630**).

Run: `cd "<repo>" && PluginKit/Scripts/build-sample.sh /tmp/p-bundles && PluginKit/Scripts/build-sample.sh /tmp/p-bundles b`
Expected: i percorsi dei due bundle.

- [ ] **Step 4: Commit**

```bash
cd "<repo>" && git add -A PluginKit Packages && git commit -m "feat: DTHubPluginKit registerPresets; plug-in di esempio 1.3 con i suoi preset

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Prova nell'app e documenti

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-preset-pipeline-design.md`, `docs/superpowers/specs/2026-09-29-dt-hub-core-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare nell'app vera con il server vero, in una cartella dati a parte**

Servono: il server gestito di DT Hub (nelle preferenze dell'utente), FLUX.2 klein 9B e il LoRA `flux_2_sun_direction_lora_v1_lora_f16.ckpt`. **Le preferenze sono quelle dell'utente anche con `CFFIXED_USER_HOME`**: annotare `defaults read com.exiztenz.DTHub drawThings.selectedModel` e `workspace.selectedTab`, e rimetterli alla fine.

```bash
cd "<repo>"
defaults read com.exiztenz.DTHub drawThings.selectedModel    # annotare
xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/p-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
H=/tmp/phome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins"
cp -R /tmp/p-bundles/Sample.dthubplugin "$AS/Plug-ins/com.example.dthub.sample.dthubplugin"
echo '{"enabled":["com.example.dthub.sample"]}' > "$AS/plugins.json"
defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt
(CFFIXED_USER_HOME=$H nohup "/tmp/p-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/p-app.log 2>&1 &)
```

Il file dei preset di prova è `$AS/presets.json`; le immagini vanno in `$H/Pictures/DT Hub/`.

Checklist:
1. Poco dopo l'avvio `$AS/presets.json` ha «Sample · Overcast» e «Sample · Match the sun», con `origin` = `com.example.dthub.sample`, `model` vuoto e larghezza/altezza 1024. Il menu **Preset** li elenca con «· da Sample».
2. Scrivere un prompt nella Generazione, **Salva come preset…** «Prova» (il testo della scheda dice che salva il prompt e non le dimensioni), cambiare prompt e dimensioni, caricare «Prova»: il prompt torna quello salvato e **il canvas non cambia**. Un preset senza prompt (salvarne uno, «Senza», a campo prompt vuoto) lascia invece il prompt del tab quando lo si carica.
3. Tab Sample › **Send pipeline** con «Overcast shadows» spuntato: il pulsante dice **«Run · 2 passaggi»** e il suggerimento elenca «1. Overcast — Sample · Overcast» e «2. Match the sun — Sample · Match the sun ← dal risultato precedente».
4. Aprire «Sample · Match the sun» dal menu Preset, cambiare gli step a 2 e **salvarlo con lo stesso nome**; premere Run: nella finestra Risultati compaiono due immagini; la seconda parte dalla prima; il PNG della seconda (il JSON del job nei metadati) ha 2 step e il LoRA a 0,6; le dimensioni sono quelle del tab. Il preset resta «da Sample».
5. Cancellare «Sample · Overcast» dal menu **Gestisci preset…** e premere Run (la pipeline è ancora sul pulsante): la finestra Risultati mostra **«Preset non trovato: Sample · Overcast»** e non parte nulla. «Send pipeline» lo ricrea (messaggio `presets` prima della pipeline).
6. «Togli la pipeline» (clic destro sul pulsante) lo riporta a «Run».

Alla fine: chiudere l'app di prova (`pkill -f p-dd`), fermare il server gestito se è rimasto (`pkill -f gRPCServerCLI`), rimettere il modello e la scheda annotati, togliere `/tmp/phome`.

- [ ] **Step 2: Aggiornare spec e backlog**

```bash
cd "<repo>" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-04-preset-pipeline-design.md'
s = open(p).read()
s = s.replace("Stato: da approvare", "Stato: realizzata (P1 e P2)")
open(p, 'w').write(s)
p = 'docs/superpowers/specs/2026-09-29-dt-hub-core-design.md'
s = open(p).read()
s = s.replace("**Preset:**", "**Preset** (aggiornato il 4 ottobre 2026: il preset contiene anche il prompt e non ha più le dimensioni; `2026-10-04-preset-pipeline-design.md`):", 1)
open(p, 'w').write(s)
p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi di prompt nei preset e pipeline di preset

- **Passaggi con valori propri** (per esempio uno slider del plug-in per il peso del LoRA): per scelta no; l'utente cambia il preset.
- **Il menu «Gestisci preset…» non segna i preset dei plug-in** (lo fa solo il menu a tendina).
- **I preset di fabbrica di un plug-in non si ripristinano da soli**: per riaverli si cancella il preset e il plug-in lo ricrea al prossimo messaggio `presets`.
- **`run(with:)` e `runPipeline` non hanno test automatici** (vedi M8b): estrarre il ciclo in HubCore con un backend finto.
- **Il peso dei LoRA o altri valori di un passaggio non si vedono nel pulsante Run**: il suggerimento mostra solo i nomi dei preset.
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat docs | tail -1
```

Expected: statistica su tre file.

- [ ] **Step 3: Commit**

```bash
cd "<repo>" && git add docs && git commit -m "docs: prompt nei preset e pipeline di preset realizzati; rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine di questa tappa

Esito atteso sul branch `m8b-plugin` (con l'M8b già dentro):
- **630 test verdi**, build Xcode pulita;
- un preset salva e carica il prompt e non tocca il canvas; un plug-in aggiunge i suoi preset al menu; la pipeline del Sample esegue i due preset e segue le modifiche che l'utente ci fa;
- il preset mancante ferma il Run con un avviso.

Poi: revisione indipendente di tutto il branch (M8b compresa è già rivista: la revisione guarda le due tappe nuove), correzioni, prove dell'utente (**lasciare l'app aperta**), **un solo merge** di M8b e di questa tappa.

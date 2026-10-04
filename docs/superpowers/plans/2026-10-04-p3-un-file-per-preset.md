# Un file per preset (P3) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** I preset non stanno più in un unico `presets.json` ma in una cartella `Presets/`, **un file `<nome>.json` per preset**. Il nome del preset è il nome del file; l'elenco si ricava dai nomi dei file e il contenuto si legge solo quando serve (caricando un preset, o al Run per i soli preset che la pipeline nomina). La provenienza di un preset di un plug-in sta nel nome (un acronimo del plug-in: «SMP · Overcast»), senza campo `origin` e senza «· da <plug-in>» nel menu.

**Architecture:**
- **HubKit**: `Preset` perde `id` e `origin`; il nome non è nel JSON; `PluginPresets(message:)` non ha più l'origine.
- **HubCore**: `PresetStore` è uno strato sopra la cartella (`names`, `refresh()`, `load(named:)`, `save`, `rename`, `delete(named:)`, `add(imported:)`, `add(fromPlugin:)`, `PresetError`); `PipelinePresets.load` legge i soli preset della pipeline e `fields(for:over:presets:catalog:)` li applica; il registro risponde con `rejected`.
- **L'app**: menu e schede dei preset sul nuovo store, l'elenco si rilegge quando la finestra torna attiva, messaggi per i nomi non validi e i preset illeggibili, il Run legge i preset della pipeline una volta.
- **PluginKit**: il Sample chiama i suoi preset «SMP · …» / «SMB · …»; il README scrive la convenzione.

**Tech Stack:** Swift 6, SwiftUI/AppKit, macOS 26, Xcode 27, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-04-preset-pipeline-design.md` §8 (e §2–§5). Parte dal piano `2026-10-04-prompt-preset-pipeline.md`, sullo stesso branch `m8b-plugin`.

## Global Constraints

- **Repository e dipendenze:** radice `/Users/existenz/Software developement/DT Hub` (percorsi tra virgolette); **si lavora sul branch `m8b-plugin`** già esistente, senza crearne altri; macOS 26, Swift 6, Xcode 27; solo DTBridge importa DrawThings-Swift, solo LLMBridge importa MLX.
- **Nessuna migrazione:** l'app non è uscita; `presets.json` non si legge più (decisione dell'utente). La cartella è `~/Library/Application Support/DT Hub/Presets/`.
- **Il nome è il file:** `<nome>.json`; nel JSON non ci sono `name`, `id`, `origin`. Un nome **non può essere vuoto, contenere `/` o `:`, né cominciare con un punto**; maiuscole e accenti non distinguono due nomi (lo stesso preset); salvare con un nome già presente sostituisce quel file (con la sua scrittura delle maiuscole). Le dimensioni non si salvano (`withoutSize`). Un import da Draw Things cambia `/` e `:` in `-`.
- **Letture:** l'elenco viene dai nomi dei file (`refresh()` all'avvio, dopo ogni scrittura dell'app, quando la finestra torna attiva e prima di leggere un preset); il contenuto si legge solo al bisogno. Un file che non si decodifica compare nell'elenco e dà `unreadable` quando lo si carica; non rovina gli altri. File non `.json` e file nascosti non sono preset.
- **Pipeline:** al Run si leggono **solo i preset nominati**, una volta, e restano in memoria per tutto il Run; se uno manca («Preset non trovato: …») o non si legge («Preset non leggibile: …») non parte nessun passaggio. Un preset cambiato o cancellato durante il Run non cambia nulla.
- **Plug-in:** `presets` aggiunge solo i nomi non presenti (anche dell'utente); un nome non valido è **rifiutato** e contato in `rejected`; risposta `{"type":"ok","added","existing","rejected"}`. L'app non impone l'acronimo.
- **Stringhe:** ogni testo visibile in `App/Localizable.xcstrings` (en + it), senza riformattare il catalogo.
- **I blocchi `diff`** sono le modifiche ai file che esistono già; si salvano in un file e si applicano dalla radice con `git apply --whitespace=nowarn <file>`. I blocchi di codice dei file nuovi si salvano così come sono.
- **Commit:** indentazione a 2 spazi; ogni commit termina con `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- **Compilazione dell'app:** il Task 1 cambia l'API dei preset e lascia l'app senza compilare fino al Task 2. Il gate del Task 1 è `swift test`.
- **L'app di prova** condivide le preferenze con quella dell'utente (i file no) e i suoi processi hanno lo stesso identificatore: **se l'app dell'utente è aperta, non pilotare le finestre con gli strumenti di controllo** (agirebbero sulla sua): per la prova dal vivo del Task 4 attendere che sia chiusa, o chiedere.
- **Fuori:** migrazione; controllo della cartella mentre l'app è aperta; cache dell'elenco; una provenienza visibile nel menu.

## Review Focus

- **Un file rotto non perde gli altri e non viene riscritto da altri:** file illeggibile nell'elenco, caricamento con errore, un plug-in che aggiunge preset non lo tocca (test `aDamagedFileIsListedFailsWhenLoadedAndDoesNotTakeTheOthers`, `aTakenNameIsNeverTouchedAndABadNameIsRefused`, Task 1).
- **Nomi e file system:** maiuscole, accenti, `/`, `:`, punto iniziale, nome identico a meno di maiuscole al rinomina e al salvataggio (test `savingUnderAnExistingNameReplacesTheFileEvenIfOnlyTheCapitalsDiffer`, `namesTheFileSystemDoesNotTakeAreRefused`, `renamesAndDeletesTheFile`, Task 1). Il rinomina passa da un nome temporaneo `.renaming-<uuid>.json`: se si interrompe a metà resta un file nascosto (ignorato dall'elenco).
- **Modifiche a mano** visibili senza riavvio (test `aFileAddedOrEditedByHandIsSeenWithoutARestart`), ma l'elenco nel menu si aggiorna quando la finestra torna attiva: **il menu è una vista e non ha test**.
- **`run(with:)` non ha test automatici:** la lettura dei preset al Run, i messaggi «non trovato»/«non leggibile», il `return true` dopo `session.fail`. Il revisore li legga.
- **Il caricamento di un preset dall'interfaccia** (`loadPreset(named:)`, il messaggio in barra) e le schede salva/gestisci non hanno test.

---

### Task 1: Un file per preset (pacchetti)

**Files:**
- Modify: `Packages/Sources/HubCore/Plugins/PipelinePresets.swift`, `Packages/Sources/HubCore/Plugins/PluginRegistry.swift`, `Packages/Sources/HubCore/Presets/PresetStore.swift`, `Packages/Sources/HubKit/Generation/Preset.swift`, `Packages/Sources/HubKit/Plugin/PluginPresets.swift`, `Packages/Tests/HubCoreTests/PluginPresetsTests.swift`, `Packages/Tests/HubCoreTests/PresetPromptTests.swift`, `Packages/Tests/HubCoreTests/PresetTests.swift`, `Packages/Tests/HubKitTests/ContributionContractTests.swift`, `Packages/Tests/HubKitTests/GenerationParametersTests.swift`, `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift`

**Interfaces:**
- Produces (`public`):
  - `Preset` (HubKit): `name` (non nel JSON), `model`, `prompt`, `negativePrompt`, `parameters`; `Identifiable` con `id` = `name`; la lettura è permissiva e lascia `name` vuoto (lo imposta chi legge il file);
  - `enum PresetError: Error, Equatable, Sendable` (HubCore): `invalidName`, `nameTaken`, `notFound(String)`, `unreadable(String)`, `cannotWrite(String)`;
  - `PresetStore` (`@MainActor @Observable`): `init(folder: URL)`, `defaultFolder`, `names: [String]` (ordinati), `refresh()`, `static isValidName(_:)`, `existingName(for:)`, `contains(_:)`, `load(named:) throws(PresetError) -> Preset`, `preset(named:) -> Preset?`, `save(_:) throws(PresetError)`, `delete(named:)`, `rename(_:to:) throws(PresetError)`, `add(imported:)`, `add(fromPlugin:) -> (added: Int, existing: Int, rejected: Int)`;
  - `PipelinePresets` (HubCore): `struct Problem: Error, Equatable` (`missing`, `unreadable`), `load(_ pipeline: PluginPipeline, from: PresetStore) -> Result<[String: Preset], Problem>`, `fields(for:over:presets:catalog:)`;
  - `PluginPresets.init?(message: Data)` (senza origine); il registro risponde a `presets` con `rejected`.

- [ ] **Step 1: Scrivere i test e verificare che falliscano**

```diff
diff --git a/Packages/Tests/HubCoreTests/PluginPresetsTests.swift b/Packages/Tests/HubCoreTests/PluginPresetsTests.swift
index 4baaeb4..04615f1 100644
--- a/Packages/Tests/HubCoreTests/PluginPresetsTests.swift
+++ b/Packages/Tests/HubCoreTests/PluginPresetsTests.swift
@@ -7,54 +7,63 @@ import Testing
 @MainActor
 struct PluginPresetsTests {
   let catalog = ModelCatalog(models: [], loras: [], fileCount: 0)
-  let store = PresetStore(
-    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsTests-\(UUID())/presets.json"))
+  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsTests-\(UUID())", isDirectory: true)
+  var store: PresetStore { PresetStore(folder: folder) }
 
   func plugin(_ name: String, steps: Int = 4, prompt: String = "") -> Preset {
-    Preset(name: name, prompt: prompt, parameters: GenerationParameters(steps: steps), origin: "com.x")
+    Preset(name: name, prompt: prompt, parameters: GenerationParameters(steps: steps))
   }
 
-  @Test func newPresetsAreAddedAndKeepTheirOrigin() {
-    let result = store.add(fromPlugin: [plugin("A"), plugin("B")])
-    #expect(result.added == 2 && result.existing == 0)
-    #expect(store.preset(named: "a")?.origin == "com.x")
+  @Test func newPresetsAreAddedAsFiles() {
+    let result = store.add(fromPlugin: [plugin("SMP · A"), plugin("SMP · B")])
+    #expect(result.added == 2 && result.existing == 0 && result.rejected == 0)
+    #expect(store.names == ["SMP · A", "SMP · B"])
   }
 
-  @Test func aTakenNameIsNeverTouchedNotEvenByTheSamePlugin() {
-    store.save(Preset(name: "A", parameters: GenerationParameters(steps: 30)))
-    store.add(fromPlugin: [plugin("B", steps: 4)])
-    store.save(Preset(name: "B", prompt: "edited", parameters: GenerationParameters(steps: 9), origin: "com.x"))
-    let result = store.add(fromPlugin: [plugin("a", steps: 4), plugin("B", steps: 4)])
-    #expect(result.added == 0 && result.existing == 2)
-    #expect(store.preset(named: "A")?.parameters.steps == 30 && store.preset(named: "A")?.origin == nil)
-    #expect(store.preset(named: "B")?.parameters.steps == 9 && store.preset(named: "B")?.prompt == "edited")
+  @Test func aTakenNameIsNeverTouchedAndABadNameIsRefused() throws {
+    let store = self.store
+    try store.save(Preset(name: "SMP · A", parameters: GenerationParameters(steps: 30)))
+    try store.save(Preset(name: "SMP · B", prompt: "edited", parameters: GenerationParameters(steps: 9)))
+    let result = store.add(fromPlugin: [plugin("smp · a", steps: 4), plugin("SMP · B", steps: 4), plugin("SMP/C"), plugin("SMP: D"), plugin("SMP · E")])
+    #expect(result.added == 1 && result.existing == 2 && result.rejected == 2)
+    #expect(store.preset(named: "SMP · A")?.parameters.steps == 30)
+    #expect(store.preset(named: "SMP · B")?.parameters.steps == 9 && store.preset(named: "SMP · B")?.prompt == "edited")
+    #expect(store.names == ["SMP · A", "SMP · B", "SMP · E"])
   }
 
-  @Test func theUsersEditToAPluginsPresetKeepsItsOrigin() {
-    store.add(fromPlugin: [plugin("B")])
-    var edited = store.preset(named: "B")!
-    edited.parameters.steps = 12
-    store.save(edited)
-    #expect(store.preset(named: "B")?.origin == "com.x" && store.preset(named: "B")?.parameters.steps == 12)
+  @Test func thePipelineReadsOnlyThePresetsItNamesOnceEach() throws {
+    let store = self.store
+    try store.save(plugin("A"))
+    try store.save(plugin("B"))
+    try store.save(plugin("Unused"))
+    let pipeline = PluginPipeline(steps: [PipelineStep(preset: "A"), PipelineStep(), PipelineStep(preset: "a"), PipelineStep(preset: "B")])
+    guard case .success(let loaded) = PipelinePresets.load(pipeline, from: store) else { Issue.record("expected success"); return }
+    #expect(Set(loaded.keys) == ["A", "a", "B"])
+    #expect(loaded["a"]?.name == "A")
   }
 
-  @Test func theMissingPresetsOfAPipelineAreNamedOnceInOrder() {
-    store.add(fromPlugin: [plugin("A")])
+  @Test func aPipelineWithMissingOrUnreadablePresetsFailsNamingThemOnceInOrder() throws {
+    let store = self.store
+    try store.save(plugin("A"))
+    try Data("garbage".utf8).write(to: folder.appendingPathComponent("Bad.json"))
     let pipeline = PluginPipeline(steps: [
-      PipelineStep(preset: "B"), PipelineStep(preset: "A"), PipelineStep(preset: "C"), PipelineStep(), PipelineStep(preset: "B"),
+      PipelineStep(preset: "B"), PipelineStep(preset: "A"), PipelineStep(preset: "C"), PipelineStep(preset: "Bad"),
+      PipelineStep(), PipelineStep(preset: "B"),
     ])
-    #expect(PipelinePresets.missing(in: pipeline, store: store) == ["B", "C"])
+    guard case .failure(let problem) = PipelinePresets.load(pipeline, from: store) else { Issue.record("expected failure"); return }
+    #expect(problem.missing == ["B", "C"] && problem.unreadable == ["Bad"])
   }
 
-  @Test func aPassRunsThePresetOnTheTabWithoutItsModelOrSize() {
+  @Test func aPassRunsThePresetOnTheTabWithoutItsModelOrSize() throws {
     var preset = Preset(name: "Match", model: "other.ckpt", prompt: "match the light", parameters: GenerationParameters(width: 2048, height: 256, steps: 4))
     preset.parameters.loras = [LoRASelection(file: "sun.ckpt", weight: 0.6)]
-    store.save(preset)
+    let store = self.store
+    try store.save(preset)
     var tab = GenerationFields(prompt: "tab prompt", negativePrompt: "tab negative")
     tab.parameters.width = 768
     tab.parameters.height = 1280
     tab.parameters.steps = 30
-    let used = PipelinePresets.fields(for: PipelineStep(preset: "match"), over: tab, store: store, catalog: catalog)
+    let used = PipelinePresets.fields(for: PipelineStep(preset: "Match"), over: tab, presets: ["Match": try store.load(named: "match")], catalog: catalog)
     #expect(used.prompt == "match the light" && used.negativePrompt == "tab negative")
     #expect(used.parameters.steps == 4 && used.parameters.loras.map(\.file) == ["sun.ckpt"])
     #expect(used.parameters.width == 768 && used.parameters.height == 1280)
@@ -62,8 +71,8 @@ struct PluginPresetsTests {
 
   @Test func aPassWithoutAPresetRunsTheTabAsItIs() {
     let tab = GenerationFields(prompt: "tab prompt")
-    #expect(PipelinePresets.fields(for: PipelineStep(), over: tab, store: store, catalog: catalog) == tab)
-    #expect(PipelinePresets.fields(for: PipelineStep(preset: "gone"), over: tab, store: store, catalog: catalog) == tab)
+    #expect(PipelinePresets.fields(for: PipelineStep(), over: tab, presets: [:], catalog: catalog) == tab)
+    #expect(PipelinePresets.fields(for: PipelineStep(preset: "gone"), over: tab, presets: [:], catalog: catalog) == tab)
   }
 }
 
@@ -71,7 +80,7 @@ struct PluginPresetsTests {
 struct PluginPresetsRoutingTests {
   let root = PluginFixture.folder()
   let presets = PresetStore(
-    fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsRouting-\(UUID())/presets.json"))
+    folder: FileManager.default.temporaryDirectory.appendingPathComponent("PluginPresetsRouting-\(UUID())", isDirectory: true))
 
   func started() throws -> (PluginRegistry, FakeLoader) {
     try PluginFixture.bundle(in: root, id: "a", name: "A")
@@ -94,9 +103,11 @@ struct PluginPresetsRoutingTests {
     let message = #"{"type":"presets","presets":[{"name":"One","fields":{"steps":4,"prompt":"hi"}},{"name":"Two"}]}"#
     let first = try await send(message, loader)
     #expect(first["type"] as? String == "ok" && first["added"] as? Int == 2 && first["existing"] as? Int == 0)
-    #expect(presets.preset(named: "One")?.prompt == "hi" && presets.preset(named: "One")?.origin == "a")
+    #expect(presets.preset(named: "One")?.prompt == "hi" && presets.names == ["One", "Two"])
     let again = try await send(message, loader)
-    #expect(again["added"] as? Int == 0 && again["existing"] as? Int == 2)
+    #expect(again["added"] as? Int == 0 && again["existing"] as? Int == 2 && again["rejected"] as? Int == 0)
+    let bad = try await send(#"{"type":"presets","presets":[{"name":"A/B"}]}"#, loader)
+    #expect(bad["rejected"] as? Int == 1)
   }
 
   @Test func anInactivePluginOrABadMessageAddsNothing() async throws {
@@ -104,6 +115,6 @@ struct PluginPresetsRoutingTests {
     #expect(try await send(#"{"type":"presets"}"#, loader)["type"] as? String == "error")
     registry.setActive("a", false)
     #expect(try await send(#"{"type":"presets","presets":[{"name":"One"}]}"#, loader)["type"] as? String == "error")
-    #expect(presets.presets.isEmpty)
+    #expect(presets.names.isEmpty)
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PresetPromptTests.swift b/Packages/Tests/HubCoreTests/PresetPromptTests.swift
index 87b3f4a..3866ade 100644
--- a/Packages/Tests/HubCoreTests/PresetPromptTests.swift
+++ b/Packages/Tests/HubCoreTests/PresetPromptTests.swift
@@ -43,60 +43,14 @@ struct PresetPromptTests {
     #expect(PresetLoad.of(tiled, current: tab, catalog: catalog).parameters.width == 4096)
   }
 
-  @Test func theSavedPresetKeepsPromptAndOriginButNoSize() {
-    let file = tempFile()
-    let store = PresetStore(fileURL: file)
-    store.save(Preset(name: "P", prompt: "a cat", parameters: GenerationParameters(width: 512, height: 1536), origin: "com.x"))
-    let again = PresetStore(fileURL: file).preset(named: "p")
-    #expect(again?.prompt == "a cat" && again?.origin == "com.x")
-    #expect(again?.parameters.width == GenerationParameters.default.width)
-    #expect(again?.parameters.height == GenerationParameters.default.height)
-  }
-
-  @Test func aFileSavedBeforeHasNoPromptAndNoOrigin() throws {
-    let file = tempFile()
-    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
-    try Data(#"[{"name":"old","model":"m.ckpt","negativePrompt":"blur","parameters":{"steps":9,"width":512}}]"#.utf8).write(to: file)
-    let old = try #require(PresetStore(fileURL: file).preset(named: "old"))
-    #expect(old.prompt.isEmpty && old.origin == nil && old.parameters.steps == 9)
-  }
-}
-
-@MainActor
-struct PresetReviewTests {
-  func tempFile() -> URL {
-    FileManager.default.temporaryDirectory
-      .appendingPathComponent("PresetReviewTests-\(UUID())", isDirectory: true).appendingPathComponent("presets.json")
-  }
-
-  @Test func savingOverAPluginsPresetWithoutAnOriginKeepsItsOrigin() {
-    let store = PresetStore(fileURL: tempFile())
-    store.add(fromPlugin: [Preset(name: "Match", parameters: GenerationParameters(steps: 4), origin: "com.x")])
-    // What the Save sheet does: a new Preset with the same name and no origin.
-    store.save(Preset(name: "match", parameters: GenerationParameters(steps: 9)))
-    #expect(store.preset(named: "Match")?.origin == "com.x" && store.preset(named: "Match")?.parameters.steps == 9)
-    // A user's own preset stays the user's.
-    store.save(Preset(name: "Mine"))
-    store.save(Preset(name: "Mine", parameters: GenerationParameters(steps: 3)))
-    #expect(store.preset(named: "Mine")?.origin == nil)
-  }
-
-  @Test func anUnreadablePresetFileIsKeptAsideNotOverwrittenByThePluginsPresets() throws {
-    let file = tempFile()
-    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
-    try Data("this is {not json".utf8).write(to: file)
-    let store = PresetStore(fileURL: file)
-    #expect(store.presets.isEmpty)
-    store.add(fromPlugin: [Preset(name: "One", origin: "com.x")])
-    let aside = file.deletingLastPathComponent().appendingPathComponent("presets.unreadable.json")
-    #expect(try String(contentsOf: aside, encoding: .utf8) == "this is {not json")
-    #expect(PresetStore(fileURL: file).presets.map(\.name) == ["One"])
-  }
-
-  @Test func aReadableFileIsNotMovedAside() throws {
-    let file = tempFile()
-    PresetStore(fileURL: file).save(Preset(name: "A"))
-    _ = PresetStore(fileURL: file)
-    #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().appendingPathComponent("presets.unreadable.json").path))
+  @Test func aSavedPresetKeepsItsPromptAndAFileWithoutOneHasNone() throws {
+    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PresetPromptTests-\(UUID())", isDirectory: true)
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "P", prompt: "a cat"))
+    try Data(#"{"model":"m.ckpt","negativePrompt":"blur","parameters":{"steps":9,"width":512}}"#.utf8)
+      .write(to: folder.appendingPathComponent("Old.json"))
+    #expect(store.preset(named: "p")?.prompt == "a cat")
+    let old = try #require(store.preset(named: "old"))
+    #expect(old.prompt.isEmpty && old.parameters.steps == 9 && old.name == "Old")
   }
 }
```

```diff
diff --git a/Packages/Tests/HubCoreTests/PresetTests.swift b/Packages/Tests/HubCoreTests/PresetTests.swift
index 825fbad..763da56 100644
--- a/Packages/Tests/HubCoreTests/PresetTests.swift
+++ b/Packages/Tests/HubCoreTests/PresetTests.swift
@@ -23,78 +23,115 @@ struct FakeCodec: ConfigurationCodec {
 
 @MainActor
 struct PresetStoreTests {
-  func tempFile() -> URL {
-    FileManager.default.temporaryDirectory
-      .appendingPathComponent("PresetStoreTests-\(UUID())", isDirectory: true)
-      .appendingPathComponent("presets.json")
+  func tempFolder() -> URL {
+    FileManager.default.temporaryDirectory.appendingPathComponent("PresetStoreTests-\(UUID())", isDirectory: true)
   }
 
-  @Test func startsEmptyWithoutAFile() {
-    #expect(PresetStore(fileURL: tempFile()).presets.isEmpty)
+  func files(_ folder: URL) -> [String] {
+    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
   }
 
-  @Test func remembersPresetsAcrossLaunchesByName() {
-    let file = tempFile()
-    let store = PresetStore(fileURL: file)
-    store.save(Preset(name: "Zeta", model: "m.ckpt", negativePrompt: "blurry", parameters: GenerationParameters(steps: 20)))
-    store.save(Preset(name: "alpha"))
-    let again = PresetStore(fileURL: file)
-    #expect(again.presets.map(\.name) == ["alpha", "Zeta"])
+  @Test func startsEmptyWithoutAFolder() {
+    #expect(PresetStore(folder: tempFolder()).names.isEmpty)
+  }
+
+  @Test func eachPresetIsAFileNamedAfterItAndTheNameIsNotInTheJSON() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "Zeta", model: "m.ckpt", negativePrompt: "blurry", parameters: GenerationParameters(steps: 20)))
+    try store.save(Preset(name: "alpha"))
+    #expect(files(folder) == ["Zeta.json", "alpha.json"])
+    #expect(store.names == ["alpha", "Zeta"])
+    #expect(!(try String(contentsOf: folder.appendingPathComponent("Zeta.json"), encoding: .utf8)).contains("\"name\""))
+    let again = PresetStore(folder: folder)
     #expect(again.preset(named: "zeta")?.parameters.steps == 20)
     #expect(again.preset(named: "ZETA")?.negativePrompt == "blurry")
+    #expect(again.preset(named: "zeta")?.name == "Zeta")
+  }
+
+  @Test func savingUnderAnExistingNameReplacesTheFileEvenIfOnlyTheCapitalsDiffer() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "Fast", parameters: GenerationParameters(steps: 4)))
+    try store.save(Preset(name: "fast", parameters: GenerationParameters(steps: 8)))
+    #expect(files(folder) == ["Fast.json"] && store.names == ["Fast"])
+    #expect(store.preset(named: "Fast")?.parameters.steps == 8)
+  }
+
+  @Test func namesTheFileSystemDoesNotTakeAreRefused() {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    for bad in ["   ", "a/b", "a:b", ".hidden"] {
+      #expect(throws: PresetError.invalidName) { try store.save(Preset(name: bad)) }
+    }
+    #expect(store.names.isEmpty && files(folder).isEmpty)
+    #expect(PresetStore.isValidName("SMP · Overcast") && !PresetStore.isValidName("a:b"))
   }
 
-  @Test func savingUnderAnExistingNameReplacesIt() {
-    let store = PresetStore(fileURL: tempFile())
-    store.save(Preset(name: "Fast", parameters: GenerationParameters(steps: 4)))
-    let id = store.presets[0].id
-    store.save(Preset(name: "fast", parameters: GenerationParameters(steps: 8)))
-    #expect(store.presets.count == 1)
-    #expect(store.presets[0].id == id)
-    #expect(store.presets[0].parameters.steps == 8)
-  }
-
-  @Test func anEmptyNameIsRefused() {
-    let store = PresetStore(fileURL: tempFile())
-    #expect(!store.save(Preset(name: "   ")))
-    #expect(store.presets.isEmpty)
-  }
-
-  @Test func renamesAndDeletes() {
-    let store = PresetStore(fileURL: tempFile())
-    store.save(Preset(name: "A"))
-    store.save(Preset(name: "B"))
-    let a = store.preset(named: "A")!.id
-    #expect(!store.rename(a, to: "b"))
-    #expect(!store.rename(a, to: " "))
-    #expect(store.rename(a, to: "C"))
-    #expect(store.presets.map(\.name) == ["B", "C"])
-    store.delete(a)
-    #expect(store.presets.map(\.name) == ["B"])
-  }
-
-  @Test func importedPresetsNeverReplaceSavedOnes() {
-    let store = PresetStore(fileURL: tempFile())
-    store.save(Preset(name: "Qwen Image 2.1", parameters: GenerationParameters(steps: 99)))
-    store.add(imported: [Preset(name: "Qwen Image 2.1"), Preset(name: "Qwen Image 2.1"), Preset(name: "Flux")])
-    #expect(store.presets.map(\.name) == ["Flux", "Qwen Image 2.1", "Qwen Image 2.1 (2)", "Qwen Image 2.1 (3)"])
+  @Test func theSizeIsNotKeptInTheFile() throws {
+    let store = PresetStore(folder: tempFolder())
+    try store.save(Preset(name: "P", parameters: GenerationParameters(width: 512, height: 1536)))
+    #expect(store.preset(named: "P")?.parameters.width == GenerationParameters.default.width)
+    #expect(store.preset(named: "P")?.parameters.height == GenerationParameters.default.height)
+  }
+
+  @Test func renamesAndDeletesTheFile() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "A"))
+    try store.save(Preset(name: "B"))
+    #expect(throws: PresetError.nameTaken) { try store.rename("A", to: "b") }
+    #expect(throws: PresetError.invalidName) { try store.rename("A", to: " ") }
+    #expect(throws: PresetError.notFound("Z")) { try store.rename("Z", to: "Y") }
+    try store.rename("A", to: "C")
+    #expect(store.names == ["B", "C"] && files(folder) == ["B.json", "C.json"])
+    try store.rename("C", to: "c")
+    #expect(store.names == ["B", "c"])
+    store.delete(named: "B")
+    #expect(store.names == ["c"] && files(folder) == ["c.json"])
+  }
+
+  @Test func importedPresetsNeverReplaceSavedOnesAndTheirNamesBecomeValid() throws {
+    let store = PresetStore(folder: tempFolder())
+    try store.save(Preset(name: "Qwen Image 2.1", parameters: GenerationParameters(steps: 99)))
+    store.add(imported: [Preset(name: "Qwen Image 2.1"), Preset(name: "Qwen Image 2.1"), Preset(name: "Flux 1/2: fast")])
+    #expect(store.names == ["Flux 1-2- fast", "Qwen Image 2.1", "Qwen Image 2.1 (2)", "Qwen Image 2.1 (3)"])
     #expect(store.preset(named: "Qwen Image 2.1")?.parameters.steps == 99)
   }
 
-  @Test func aDamagedPresetDoesNotTakeTheOthers() throws {
-    let file = tempFile()
-    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
-    try Data(#"[{"name": "Good", "parameters": {"steps": 5}}, {"model": "no name"}, 7]"#.utf8).write(to: file)
-    let store = PresetStore(fileURL: file)
-    #expect(store.presets.map(\.name) == ["Good"])
-    #expect(store.presets[0].parameters.steps == 5)
+  @Test func aDamagedFileIsListedFailsWhenLoadedAndDoesNotTakeTheOthers() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "Good", parameters: GenerationParameters(steps: 5)))
+    try Data("garbage".utf8).write(to: folder.appendingPathComponent("Bad.json"))
+    store.refresh()
+    #expect(store.names == ["Bad", "Good"])
+    #expect(throws: PresetError.unreadable("Bad")) { try store.load(named: "bad") }
+    #expect(store.preset(named: "Bad") == nil)
+    #expect(store.preset(named: "Good")?.parameters.steps == 5)
+  }
+
+  @Test func aFileAddedOrEditedByHandIsSeenWithoutARestart() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "A", parameters: GenerationParameters(steps: 4)))
+    try Data(#"{"parameters":{"steps":7},"prompt":"by hand"}"#.utf8).write(to: folder.appendingPathComponent("Hand.json"))
+    var edited = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("A.json"))) as! [String: Any]
+    edited["prompt"] = "edited"
+    try JSONSerialization.data(withJSONObject: edited).write(to: folder.appendingPathComponent("A.json"))
+    #expect(store.preset(named: "Hand")?.parameters.steps == 7 && store.preset(named: "Hand")?.prompt == "by hand")
+    #expect(store.preset(named: "A")?.prompt == "edited")
+    #expect(store.names == ["A", "Hand"])
   }
 
-  @Test func anUnreadableFileMeansNoPresets() throws {
-    let file = tempFile()
-    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
-    try Data("garbage".utf8).write(to: file)
-    #expect(PresetStore(fileURL: file).presets.isEmpty)
+  @Test func filesThatAreNotJSONOrAreHiddenAreNotPresets() throws {
+    let folder = tempFolder()
+    let store = PresetStore(folder: folder)
+    try store.save(Preset(name: "A"))
+    try Data("x".utf8).write(to: folder.appendingPathComponent("notes.txt"))
+    try Data("{}".utf8).write(to: folder.appendingPathComponent(".hidden.json"))
+    store.refresh()
+    #expect(store.names == ["A"])
   }
 }
 
```

```diff
diff --git a/Packages/Tests/HubKitTests/ContributionContractTests.swift b/Packages/Tests/HubKitTests/ContributionContractTests.swift
index 2307a8e..c1f89a4 100644
--- a/Packages/Tests/HubKitTests/ContributionContractTests.swift
+++ b/Packages/Tests/HubKitTests/ContributionContractTests.swift
@@ -96,7 +96,7 @@ struct ContributionContractTests {
 }
 
 struct PluginPresetsTests {
-  @Test func presetsAreReadWithTheirFieldsAndLoRAsAndMarkedAsThePlugins() throws {
+  @Test func presetsAreReadWithTheirFieldsAndLoRAs() throws {
     let message = Data(
       """
       {"type":"presets","presets":[
@@ -104,17 +104,17 @@ struct PluginPresetsTests {
          "loras":[{"file":"sun.ckpt","weight":0.6}]},
         {"name":"  "}, {"fields":{"steps":2}}, "junk"]}
       """.utf8)
-    let presets = try #require(PluginPresets(message: message, origin: "com.x")).presets
+    let presets = try #require(PluginPresets(message: message)).presets
     #expect(presets.count == 1)
     let preset = presets[0]
-    #expect(preset.name == "Sample · Match" && preset.origin == "com.x" && preset.model.isEmpty)
+    #expect(preset.name == "Sample · Match" && preset.model.isEmpty)
     #expect(preset.prompt == "match the light" && preset.negativePrompt == "blur")
     #expect(preset.parameters.steps == 4 && preset.parameters.loras.map(\.file) == ["sun.ckpt"])
   }
 
   @Test func aMessageWithoutAPresetsListIsRefused() {
-    #expect(PluginPresets(message: Data(#"{"type":"presets"}"#.utf8), origin: "a") == nil)
-    #expect(PluginPresets(message: Data("[1]".utf8), origin: "a") == nil)
-    #expect(PluginPresets(message: Data(#"{"presets":[]}"#.utf8), origin: "a")?.presets.isEmpty == true)
+    #expect(PluginPresets(message: Data(#"{"type":"presets"}"#.utf8)) == nil)
+    #expect(PluginPresets(message: Data("[1]".utf8)) == nil)
+    #expect(PluginPresets(message: Data(#"{"presets":[]}"#.utf8))?.presets.isEmpty == true)
   }
 }
```

```diff
diff --git a/Packages/Tests/HubKitTests/GenerationParametersTests.swift b/Packages/Tests/HubKitTests/GenerationParametersTests.swift
index 7156046..fbb2187 100644
--- a/Packages/Tests/HubKitTests/GenerationParametersTests.swift
+++ b/Packages/Tests/HubKitTests/GenerationParametersTests.swift
@@ -259,9 +259,9 @@ struct JSONValueTests {
   }
 
   @Test func aPresetLoadsLeniently() throws {
-    let preset = try JSONDecoder().decode(Preset.self, from: Data(#"{"name": "Fast"}"#.utf8))
-    #expect(preset.name == "Fast")
-    #expect(preset.model == "" && preset.negativePrompt == "")
+    let preset = try JSONDecoder().decode(Preset.self, from: Data(#"{"model": 3, "steps": "x"}"#.utf8))
+    #expect(preset.name.isEmpty, "the name is the file's, not the JSON's")
+    #expect(preset.model == "" && preset.prompt == "" && preset.negativePrompt == "")
     #expect(preset.parameters == .default)
   }
 }
```

```diff
diff --git a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
index dbf0def..60005fb 100644
--- a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
+++ b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
@@ -127,7 +127,7 @@ struct BundlePluginLoaderTests {
     // The presets the pipeline names are offered before the pipeline (and on request).
     _ = await plugin.send(Data(#"{"type":"press","button":"presets"}"#.utf8))
     let offered = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.presets })
-    let list = try #require(PluginPresets(message: offered.message, origin: "x")).presets
+    let list = try #require(PluginPresets(message: offered.message)).presets
     #expect(list.map(\.name) == ["Sample · Overcast", "Sample · Match the sun"])
     #expect(list[1].parameters.loras.first?.weight == 0.6 && list[0].parameters.loras.isEmpty)
     #expect(list[1].prompt.hasPrefix("match light direction"))
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter "PresetStoreTests|PluginPresetsTests" 2>&1 | grep -E "error:" | head -2`
Expected: un errore di compilazione (`extra argument 'folder'`/`PresetError` non esiste: lo store a cartella non c'è ancora).

- [ ] **Step 2: Implementare**

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PipelinePresets.swift b/Packages/Sources/HubCore/Plugins/PipelinePresets.swift
index e95f204..df9aefb 100644
--- a/Packages/Sources/HubCore/Plugins/PipelinePresets.swift
+++ b/Packages/Sources/HubCore/Plugins/PipelinePresets.swift
@@ -1,24 +1,40 @@
 import HubKit
 
-/// The presets a plug-in's pipeline names (`2026-10-04-preset-pipeline-design.md` §4).
+/// The presets a plug-in's pipeline names (`2026-10-04-preset-pipeline-design.md` §4, §8).
 @MainActor
 public enum PipelinePresets {
-  /// The names the pipeline asks for that the Preset menu does not have, once each, in order.
-  public static func missing(in pipeline: PluginPipeline, store: PresetStore) -> [String] {
-    var result: [String] = []
-    for step in pipeline.steps where !step.preset.isEmpty {
-      if store.preset(named: step.preset) == nil, !result.contains(step.preset) { result.append(step.preset) }
+  /// What stops a pipeline before its first pass: the names the Preset menu does not have, and those whose
+  /// file is not a preset.
+  public struct Problem: Error, Equatable, Sendable {
+    public var missing: [String]
+    public var unreadable: [String]
+  }
+
+  /// Reads, once each, only the presets the pipeline names. They stay in memory for the whole Run, so a preset
+  /// changed or deleted meanwhile changes nothing. The result is keyed by the name as the step wrote it.
+  public static func load(_ pipeline: PluginPipeline, from store: PresetStore) -> Result<[String: Preset], Problem> {
+    var loaded: [String: Preset] = [:]
+    var problem = Problem(missing: [], unreadable: [])
+    for step in pipeline.steps where !step.preset.isEmpty && loaded[step.preset] == nil {
+      do {
+        loaded[step.preset] = try store.load(named: step.preset)
+      } catch {
+        switch error {
+        case .unreadable: if !problem.unreadable.contains(step.preset) { problem.unreadable.append(step.preset) }
+        default: if !problem.missing.contains(step.preset) { problem.missing.append(step.preset) }
+        }
+      }
     }
-    return result
+    return problem.missing.isEmpty && problem.unreadable.isEmpty ? .success(loaded) : .failure(problem)
   }
 
   /// What a pass runs with: the tab's fields with the pass's preset on them (its parameters, and its prompt
-  /// and negative prompt when it has them), but not its model nor a size. A pass without a preset, or whose
-  /// preset is gone, runs the tab's fields as they are.
-  public static func fields(for step: PipelineStep, over tab: GenerationFields, store: PresetStore, catalog: ModelCatalog)
-    -> GenerationFields
-  {
-    guard !step.preset.isEmpty, let preset = store.preset(named: step.preset) else { return tab }
+  /// and negative prompt when it has them), but not its model nor a size. A pass without a preset runs the
+  /// tab's fields as they are.
+  public static func fields(
+    for step: PipelineStep, over tab: GenerationFields, presets: [String: Preset], catalog: ModelCatalog
+  ) -> GenerationFields {
+    guard !step.preset.isEmpty, let preset = presets[step.preset] else { return tab }
     let load = PresetLoad.of(preset, current: tab, catalog: catalog)
     return GenerationFields(prompt: load.prompt, negativePrompt: load.negativePrompt, parameters: load.parameters)
   }
```

```diff
diff --git a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
index 1467bc6..ec3bcfb 100644
--- a/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
+++ b/Packages/Sources/HubCore/Plugins/PluginRegistry.swift
@@ -322,15 +322,18 @@ public final class PluginRegistry: PluginHosting {
     return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
   }
 
-  /// Presets for the Preset menu; a name already there is left alone. `{"type":"ok","added":n,"existing":m}`.
+  /// Presets for the Preset menu; a name already there is left alone, a name the file system does not take is
+  /// refused. `{"type":"ok","added":n,"existing":m,"rejected":k}`.
   private func addPresets(_ message: Data, from pluginID: String) -> Data {
     guard isActive(pluginID) else { return PluginMessageType.failure("The plug-in is not active.") }
     guard let store = presetStore else { return PluginMessageType.failure("There is no preset store.") }
-    guard let parsed = PluginPresets(message: message, origin: pluginID) else {
+    guard let parsed = PluginPresets(message: message) else {
       return PluginMessageType.failure("The message has no presets list.")
     }
     let result = store.add(fromPlugin: parsed.presets)
-    let answer: [String: Any] = ["type": PluginMessageType.ok, "added": result.added, "existing": result.existing]
+    let answer: [String: Any] = [
+      "type": PluginMessageType.ok, "added": result.added, "existing": result.existing, "rejected": result.rejected,
+    ]
     return (try? JSONSerialization.data(withJSONObject: answer)) ?? PluginMessageType.bare(PluginMessageType.ok)
   }
 
```

```diff
diff --git a/Packages/Sources/HubCore/Presets/PresetStore.swift b/Packages/Sources/HubCore/Presets/PresetStore.swift
index 4939a7c..7f72ab9 100644
--- a/Packages/Sources/HubCore/Presets/PresetStore.swift
+++ b/Packages/Sources/HubCore/Presets/PresetStore.swift
@@ -2,137 +2,167 @@ import Foundation
 import HubKit
 import Observation
 
-/// The saved presets (spec §6), kept in a JSON file in the app's support folder (spec §11).
-/// Names are unique, compared without regard to case.
+/// Why a preset could not be read or written.
+public enum PresetError: Error, Equatable, Sendable {
+  /// Empty, with a "/" or a ":", or starting with a dot: not a name the file system takes.
+  case invalidName
+  case nameTaken
+  case notFound(String)
+  /// The file is there and is not a preset.
+  case unreadable(String)
+  case cannotWrite(String)
+}
+
+/// The saved presets (spec §6, and `2026-10-04-preset-pipeline-design.md` §8): a folder with one `<name>.json`
+/// per preset. The list is the names of the files; a file is read only when its preset is needed. Names follow
+/// the file system's rules: no "/" or ":", and capitals and accents do not tell two names apart.
 @MainActor
 @Observable
 public final class PresetStore {
-  /// By name.
-  public private(set) var presets: [Preset]
-  @ObservationIgnored private let fileURL: URL
-
-  public init(fileURL: URL) {
-    self.fileURL = fileURL
-    let data = try? Data(contentsOf: fileURL)
-    let decoded = data.flatMap { try? JSONDecoder().decode([LossyPreset].self, from: $0) }
-    if data != nil, decoded == nil {
-      // A file that is not a list of presets (edited by hand, damaged) is kept beside, not overwritten by the
-      // next save or by the presets a plug-in adds.
-      let aside = fileURL.deletingLastPathComponent().appendingPathComponent("presets.unreadable.json")
-      try? FileManager.default.removeItem(at: aside)
-      try? FileManager.default.moveItem(at: fileURL, to: aside)
-    }
-    presets = (decoded ?? []).compactMap(\.preset)
-    presets = Self.sorted(presets)
+  /// The names of the presets, sorted; read from the folder by `refresh()`.
+  public private(set) var names: [String] = []
+  @ObservationIgnored private let folder: URL
+
+  public init(folder: URL) {
+    self.folder = folder
+    refresh()
   }
 
-  /// ~/Library/Application Support/DT Hub/presets.json.
-  public static var defaultFileURL: URL {
+  /// ~/Library/Application Support/DT Hub/Presets.
+  public static var defaultFolder: URL {
     FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
       .appendingPathComponent("DT Hub", isDirectory: true)
-      .appendingPathComponent("presets.json")
+      .appendingPathComponent("Presets", isDirectory: true)
   }
 
-  public func preset(named name: String) -> Preset? {
-    presets.first { Self.same($0.name, name) }
+  /// Reads the folder again (a file added, changed or removed by hand shows up).
+  public func refresh() {
+    let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
+    let list = files
+      .filter { $0.pathExtension.lowercased() == "json" && !$0.lastPathComponent.hasPrefix(".") }
+      .map { $0.deletingPathExtension().lastPathComponent }
+      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
+    if list != names { names = list }
   }
 
-  /// Saves under `preset.name`, replacing the preset of the same name. An empty name is refused.
-  @discardableResult
-  public func save(_ preset: Preset) -> Bool {
-    var preset = preset.withoutSize()
-    preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
-    guard !preset.name.isEmpty else { return false }
-    if let index = presets.firstIndex(where: { Self.same($0.name, preset.name) }) {
-      preset.id = presets[index].id
-      // A plug-in's preset the user saves again under its name stays the plug-in's.
-      preset.origin = preset.origin ?? presets[index].origin
-      presets[index] = preset
-    } else {
-      presets.append(preset)
-    }
-    commit()
-    return true
+  /// A name the file system takes: not empty once trimmed, no "/" or ":", not starting with a dot.
+  public static func isValidName(_ raw: String) -> Bool {
+    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
+    return !name.isEmpty && name.count <= 120 && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
   }
 
-  public func delete(_ id: Preset.ID) {
-    presets.removeAll { $0.id == id }
-    commit()
+  /// The name as it is written in the folder, if a preset has this name (capitals and accents aside).
+  public func existingName(for name: String) -> String? {
+    refresh()
+    let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
+    return names.first { Self.same($0, wanted) }
   }
 
-  /// False when the new name is empty or taken by another preset.
-  @discardableResult
-  public func rename(_ id: Preset.ID, to newName: String) -> Bool {
+  public func contains(_ name: String) -> Bool { existingName(for: name) != nil }
+
+  /// Reads the file of a preset, now.
+  public func load(named name: String) throws(PresetError) -> Preset {
+    guard let actual = existingName(for: name) else { throw .notFound(name) }
+    guard let data = try? Data(contentsOf: url(actual)), var preset = try? JSONDecoder().decode(Preset.self, from: data)
+    else { throw .unreadable(actual) }
+    preset.name = actual
+    return preset
+  }
+
+  /// The preset, or nil when there is none or its file cannot be read.
+  public func preset(named name: String) -> Preset? { try? load(named: name) }
+
+  /// Saves under `preset.name`, replacing the file of the same name. The size is not kept.
+  public func save(_ preset: Preset) throws(PresetError) {
+    let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
+    guard Self.isValidName(name) else { throw .invalidName }
+    try write(preset.withoutSize(), as: existingName(for: name) ?? name)
+  }
+
+  public func delete(named name: String) {
+    guard let actual = existingName(for: name) else { return }
+    try? FileManager.default.removeItem(at: url(actual))
+    refresh()
+  }
+
+  /// Renames the file. Changing only the capitals of a name is allowed.
+  public func rename(_ old: String, to newName: String) throws(PresetError) {
     let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
-    guard !name.isEmpty, let index = presets.firstIndex(where: { $0.id == id }),
-      !presets.contains(where: { $0.id != id && Self.same($0.name, name) })
-    else { return false }
-    presets[index].name = name
-    commit()
-    return true
+    guard Self.isValidName(name) else { throw .invalidName }
+    guard let actual = existingName(for: old) else { throw .notFound(old) }
+    if let other = existingName(for: name), !Self.same(other, actual) { throw .nameTaken }
+    guard actual != name else { return }
+    do {
+      // Two steps: on a file system that ignores capitals a one-step move to a name that differs only by them can fail.
+      let temporary = folder.appendingPathComponent(".renaming-\(UUID().uuidString).json")
+      try FileManager.default.moveItem(at: url(actual), to: temporary)
+      try FileManager.default.moveItem(at: temporary, to: url(name))
+    } catch {
+      throw .cannotWrite(error.localizedDescription)
+    }
+    refresh()
   }
 
-  /// Adds imported presets, each under a free name ("Name", "Name (2)", …): nothing the
-  /// user saved is replaced.
+  /// Adds imported presets, each under a free name ("Name", "Name (2)", …); a "/" or ":" in a name becomes "-".
+  /// Nothing the user saved is replaced.
   public func add(imported: [Preset]) {
     for var preset in imported {
-      let base = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
+      let base = preset.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
+        .trimmingCharacters(in: .whitespacesAndNewlines)
+      guard Self.isValidName(base) else { continue }
       var name = base
       var number = 2
-      while presets.contains(where: { Self.same($0.name, name) }) {
+      while contains(name) {
         name = "\(base) (\(number))"
         number += 1
       }
       preset.name = name
-      preset.id = UUID()
-      presets.append(preset)
+      try? write(preset.withoutSize(), as: name)
     }
-    commit()
   }
 
-  /// Adds the presets a plug-in brought (each already marked with its `origin`). A name that is taken, by the
-  /// user's own preset or by an earlier one of the plug-in, is never touched: the user may have changed it.
-  /// Returns how many were added and how many were there already.
+  /// Adds the presets a plug-in brought. A name that is taken, by the user's own preset or by an earlier one of
+  /// the plug-in, is never touched (the user may have changed it); a name the file system does not take is left
+  /// out. Returns how many were added, were there already, and were refused.
   @discardableResult
-  public func add(fromPlugin newPresets: [Preset]) -> (added: Int, existing: Int) {
+  public func add(fromPlugin newPresets: [Preset]) -> (added: Int, existing: Int, rejected: Int) {
     var added = 0
     var existing = 0
+    var rejected = 0
     for preset in newPresets {
       let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
-      if name.isEmpty || presets.contains(where: { Self.same($0.name, name) }) {
+      guard Self.isValidName(name) else {
+        rejected += 1
+        continue
+      }
+      if contains(name) {
         existing += 1
         continue
       }
-      var copy = preset.withoutSize()
-      copy.name = name
-      copy.id = UUID()
-      presets.append(copy)
-      added += 1
+      if (try? write(preset.withoutSize(), as: name)) != nil { added += 1 } else { rejected += 1 }
     }
-    if added > 0 { commit() }
-    return (added, existing)
+    return (added, existing, rejected)
   }
 
-  private func commit() {
-    presets = Self.sorted(presets)
+  // MARK: Private
+
+  private func url(_ name: String) -> URL { folder.appendingPathComponent(name + ".json") }
+
+  private func write(_ preset: Preset, as name: String) throws(PresetError) {
     do {
-      try FileManager.default.createDirectory(
-        at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
+      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
       let encoder = JSONEncoder()
       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
-      try encoder.encode(presets).write(to: fileURL, options: .atomic)
+      try encoder.encode(preset).write(to: url(name), options: .atomic)
     } catch {
-      // A write failure only loses the memory of the change.
+      throw .cannotWrite(error.localizedDescription)
     }
+    refresh()
   }
 
   private static func same(_ a: String, _ b: String) -> Bool {
     a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
   }
-
-  private static func sorted(_ presets: [Preset]) -> [Preset] {
-    presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
-  }
 }
 
 extension Preset {
@@ -144,12 +174,3 @@ extension Preset {
     return copy
   }
 }
-
-/// One element of the file, decoded on its own: a damaged preset does not take the others.
-private struct LossyPreset: Decodable {
-  let preset: Preset?
-
-  init(from decoder: any Decoder) throws {
-    preset = try? Preset(from: decoder)
-  }
-}
```

```diff
diff --git a/Packages/Sources/HubKit/Generation/Preset.swift b/Packages/Sources/HubKit/Generation/Preset.swift
index 03b8f62..0169da8 100644
--- a/Packages/Sources/HubKit/Generation/Preset.swift
+++ b/Packages/Sources/HubKit/Generation/Preset.swift
@@ -3,40 +3,41 @@ import Foundation
 /// A named recipe (spec §6, and `2026-10-04-preset-pipeline-design.md`): the model, the parameters (LoRAs and
 /// Advanced cards included), the prompt and the negative prompt. The size is not part of a preset: loading one
 /// never changes the canvas.
+///
+/// A preset is a file, `<name>.json`, in the Presets folder: the name is the file's name and is not in the JSON.
 public struct Preset: Equatable, Codable, Sendable, Identifiable {
-  public var id: UUID
   public var name: String
+  public var id: String { name }
   /// Empty when the preset names no model: loading it leaves the model as it is.
   public var model: String
   /// Empty when the preset has none: loading it leaves the tab's prompt as it is.
   public var prompt: String
   public var negativePrompt: String
   public var parameters: GenerationParameters
-  /// The identifier of the plug-in that added the preset; nil for the user's own.
-  public var origin: String?
 
   public init(
-    id: UUID = UUID(), name: String, model: String = "", prompt: String = "", negativePrompt: String = "",
-    parameters: GenerationParameters = .default, origin: String? = nil
+    name: String, model: String = "", prompt: String = "", negativePrompt: String = "",
+    parameters: GenerationParameters = .default
   ) {
-    self.id = id
     self.name = name
     self.model = model
     self.prompt = prompt
     self.negativePrompt = negativePrompt
     self.parameters = parameters
-    self.origin = origin
   }
 
-  /// Lenient, like the other saved formats.
+  /// The name is not part of the JSON.
+  private enum CodingKeys: String, CodingKey {
+    case model, prompt, negativePrompt, parameters
+  }
+
+  /// Lenient, like the other saved formats; the name is set by whoever read the file.
   public init(from decoder: any Decoder) throws {
     let container = try decoder.container(keyedBy: CodingKeys.self)
-    id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
-    name = try container.decode(String.self, forKey: .name)
+    name = ""
     model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? ""
     prompt = (try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
     negativePrompt = (try? container.decodeIfPresent(String.self, forKey: .negativePrompt)) ?? ""
-    origin = try? container.decodeIfPresent(String.self, forKey: .origin)
     parameters = (try? container.decodeIfPresent(GenerationParameters.self, forKey: .parameters)) ?? .default
   }
 }
```

```diff
diff --git a/Packages/Sources/HubKit/Plugin/PluginPresets.swift b/Packages/Sources/HubKit/Plugin/PluginPresets.swift
index b6ed821..91409af 100644
--- a/Packages/Sources/HubKit/Plugin/PluginPresets.swift
+++ b/Packages/Sources/HubKit/Plugin/PluginPresets.swift
@@ -7,8 +7,8 @@ public struct PluginPresets: Equatable, Sendable {
   public var presets: [Preset]
 
   /// Nil when the data is not a JSON object with a `presets` list. An entry without a name is left out.
-  /// Every preset is marked as the plug-in's (`origin`).
-  public init?(message: Data, origin: String) {
+  /// The name carries the plug-in's acronym (e.g. "SMP · Overcast"): the app adds nothing to say where it comes from.
+  public init?(message: Data) {
     guard let root = try? JSONDecoder().decode(JSONValue.self, from: message), case .object(let object) = root,
       case .array(let list)? = object["presets"]
     else { return nil }
@@ -21,8 +21,7 @@ public struct PluginPresets: Equatable, Sendable {
       var fields = overlay.applied(to: GenerationFields())
       fields.parameters.loras = PluginContribution.loras(entry["loras"]) ?? []
       return Preset(
-        name: name, prompt: fields.prompt, negativePrompt: fields.negativePrompt, parameters: fields.parameters,
-        origin: origin)
+        name: name, prompt: fields.prompt, negativePrompt: fields.negativePrompt, parameters: fields.parameters)
     }
   }
 }
```

- [ ] **Step 3: Verificare che passino**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: HubKit `93 tests … passed`, HubCore `454`, DTBridge 66, Catalog 6, LLMBridge 6, PluginHost 6.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A Packages && git commit -m "feat: un file per preset (cartella Presets), letti al bisogno; i preset dei plug-in senza origine

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: L'app sul nuovo store

**Files:**
- Modify: `App/Generation/GenerationController.swift`, `App/Generation/Presets/PresetBar.swift`, `App/Generation/Presets/PresetSheets.swift`, `App/Localizable.xcstrings`
- Test: nessuno nuovo — `LocalizationCatalogTests` (esistente) controlla il catalogo; le viste e `run(with:)` si provano col Task 4.

**Interfaces:**
- Consumes: `PresetStore`, `PresetError`, `PipelinePresets` (Task 1).
- Produces: `GenerationController.presets` su `PresetStore.defaultFolder`; `savePreset(named:with:) throws(PresetError)`; `loadPreset(named:with:) -> PresetError?` (legge il file in quel momento); `run(with:)` legge i preset della pipeline una volta (`PipelinePresets.load`) e, se non va, `session.fail` con «Preset non trovato: …» e/o «Preset non leggibile: …» e ritorna `true`; `runPipeline(_:presets:with:)`; il menu Preset elenca `names` e si rilegge all'apparire e quando la finestra torna attiva; la scheda di salvataggio dice subito se il nome non è valido e blocca il pulsante; «Gestisci preset…» rinomina/cancella per nome con il messaggio dell'errore; nuove stringhe `preset.save.invalidName`, `preset.load.unreadable`, `pipeline.unreadablePreset`.

- [ ] **Step 1: Applicare le modifiche**

```diff
diff --git a/App/Generation/GenerationController.swift b/App/Generation/GenerationController.swift
index a38f46e..ffbcf06 100644
--- a/App/Generation/GenerationController.swift
+++ b/App/Generation/GenerationController.swift
@@ -84,7 +84,7 @@ final class GenerationController {
   }
 
   /// The saved presets (spec §6).
-  let presets = PresetStore(fileURL: PresetStore.defaultFileURL)
+  let presets = PresetStore(folder: PresetStore.defaultFolder)
   /// Reads and writes the Draw Things configuration JSON (spec §6, level 3).
   @ObservationIgnored let codec: any ConfigurationCodec = DrawThingsConfigurationCodec()
 
@@ -109,10 +109,10 @@ final class GenerationController {
   }
 
   /// Saves the tab as a preset (parameters but not the size, model, prompt and negative prompt). Whoever does
-  /// not want the prompt in it empties the field first. False when the name is empty.
-  @discardableResult
-  func savePreset(named name: String, with connection: DrawThingsConnection) -> Bool {
-    presets.save(
+  /// not want the prompt in it empties the field first. Throws `invalidName` for a name the file system does
+  /// not take (empty, "/", ":").
+  func savePreset(named name: String, with connection: DrawThingsConnection) throws(PresetError) {
+    try presets.save(
       Preset(
         name: name, model: connection.selection.selectedFile ?? "", prompt: prompt, negativePrompt: negativePrompt,
         parameters: parameters))
@@ -120,7 +120,17 @@ final class GenerationController {
 
   /// Puts a preset on the tab: its parameters (the canvas size stays), its prompt and negative prompt when it
   /// has them, its model when it names one.
-  func load(_ preset: Preset, with connection: DrawThingsConnection) {
+  /// The preset's file is read now; nil when it was loaded, the reason when it was not.
+  func loadPreset(named name: String, with connection: DrawThingsConnection) -> PresetError? {
+    do {
+      load(try presets.load(named: name), with: connection)
+      return nil
+    } catch {
+      return error
+    }
+  }
+
+  private func load(_ preset: Preset, with connection: DrawThingsConnection) {
     let load = PresetLoad.of(preset, current: fields, catalog: connection.monitor.catalog)
     parameters = load.parameters
     prompt = load.prompt
@@ -182,23 +192,33 @@ final class GenerationController {
   @discardableResult
   func run(with connection: DrawThingsConnection) -> Bool {
     guard canRun(with: connection) else { return false }
-    // A pipeline whose presets are not all in the Preset menu does not start.
+    // A pipeline reads the presets it names now, once; if one is missing or is not a preset, nothing starts.
+    var passes: [PipelineStep]?
+    var loadedPresets: [String: Preset] = [:]
     if let pipeline = contributions?.pipeline?.pipeline {
-      let missing = PipelinePresets.missing(in: pipeline, store: presets)
-      if !missing.isEmpty {
-        session.fail(
-          with: .generationFailed(String(format: String(localized: "pipeline.missingPreset"), missing.joined(separator: ", "))))
+      switch PipelinePresets.load(pipeline, from: presets) {
+      case .success(let loaded):
+        loadedPresets = loaded
+        passes = pipeline.steps
+      case .failure(let problem):
+        var lines: [String] = []
+        if !problem.missing.isEmpty {
+          lines.append(String(format: String(localized: "pipeline.missingPreset"), problem.missing.joined(separator: ", ")))
+        }
+        if !problem.unreadable.isEmpty {
+          lines.append(String(format: String(localized: "pipeline.unreadablePreset"), problem.unreadable.joined(separator: ", ")))
+        }
+        session.fail(with: .generationFailed(lines.joined(separator: "\n")))
         return true
       }
     }
     isPreparing = true
-    let passes = contributions?.pipeline?.pipeline.steps
     preparation = Task {
       // Memory first: the language model leaves, a server parked for it comes back.
       await languageModel.prepareForRun()
       await connection.ensureServerForRun()
       if let passes {
-        await runPipeline(passes, with: connection)
+        await runPipeline(passes, presets: loadedPresets, with: connection)
         return
       }
       let inputs = await renderInputs(in: connection, parameters: parameters)
@@ -213,7 +233,9 @@ final class GenerationController {
   /// The passes of a pipeline, one after the other (plug-in design §7, preset design §4). Each pass runs the
   /// tab's fields with its preset on them; the picture a pass makes can be the next one's start image. A failed or stopped
   /// pass ends the pipeline; the pictures already made stay in the strip.
-  private func runPipeline(_ passes: [PipelineStep], with connection: DrawThingsConnection) async {
+  private func runPipeline(
+    _ passes: [PipelineStep], presets loaded: [String: Preset], with connection: DrawThingsConnection
+  ) async {
     defer {
       isPreparing = false
       pipelinePass = nil
@@ -223,8 +245,7 @@ final class GenerationController {
     for (index, pass) in passes.enumerated() {
       guard !Task.isCancelled else { return }
       pipelinePass = (index + 1, passes.count)
-      let used = PipelinePresets.fields(
-        for: pass, over: fields, store: presets, catalog: connection.monitor.catalog)
+      let used = PipelinePresets.fields(for: pass, over: fields, presets: loaded, catalog: connection.monitor.catalog)
       guard let base = await renderInputs(in: connection, parameters: used.parameters) else { return }
       guard !Task.isCancelled, let backend = connection.monitor.backend, let model = connection.selection.selectedFile,
         RunAvailability.blocker(
```

```diff
diff --git a/App/Generation/Presets/PresetBar.swift b/App/Generation/Presets/PresetBar.swift
index 818b962..478073a 100644
--- a/App/Generation/Presets/PresetBar.swift
+++ b/App/Generation/Presets/PresetBar.swift
@@ -13,19 +13,22 @@ struct PresetBar: View {
   @State private var managing = false
   @State private var editingJSON = false
   @State private var importMessage: String?
-  @Environment(PluginRegistry.self) private var plugins: PluginRegistry?
 
   var body: some View {
     HStack(spacing: DS.controlGap) {
       Menu {
-        if controller.presets.presets.isEmpty {
+        if controller.presets.names.isEmpty {
           Text("preset.none")
         }
-        ForEach(controller.presets.presets) { preset in
+        ForEach(controller.presets.names, id: \.self) { name in
           Button {
-            controller.load(preset, with: connection)
+            if let error = controller.loadPreset(named: name, with: connection) {
+              importMessage = Self.text(of: error)
+            } else {
+              importMessage = nil
+            }
           } label: {
-            Text(verbatim: title(of: preset))
+            Text(verbatim: name)
           }
         }
         Divider()
@@ -39,7 +42,7 @@ struct PresetBar: View {
         } label: {
           Text("preset.manage")
         }
-        .disabled(controller.presets.presets.isEmpty)
+        .disabled(controller.presets.names.isEmpty)
         Button {
           importFile()
         } label: {
@@ -75,6 +78,11 @@ struct PresetBar: View {
       }
       Spacer(minLength: 0)
     }
+    // The list is the folder's: files added or changed by hand show up when the window comes back.
+    .onAppear { controller.presets.refresh() }
+    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
+      controller.presets.refresh()
+    }
     .sheet(isPresented: $saving) {
       SavePresetSheet(controller: controller, connection: connection)
     }
@@ -86,11 +94,15 @@ struct PresetBar: View {
     }
   }
 
-  /// The name, and "da <plug-in>" for a preset a plug-in brought.
-  private func title(of preset: Preset) -> String {
-    guard let origin = preset.origin else { return preset.name }
-    let plugin = plugins?.entries.first { $0.id == origin }?.name ?? origin
-    return preset.name + " · " + String(format: String(localized: "control.source.plugin"), plugin)
+  /// What went wrong loading a preset.
+  static func text(of error: PresetError) -> String {
+    switch error {
+    case .unreadable(let name): String(format: String(localized: "preset.load.unreadable"), name)
+    case .notFound(let name): String(format: String(localized: "pipeline.missingPreset"), name)
+    case .invalidName: String(localized: "preset.save.invalidName")
+    case .nameTaken: String(localized: "preset.rename.taken")
+    case .cannotWrite(let reason): reason
+    }
   }
 
   /// Asks for a file with a list of presets; the result is told in the bar.
```

```diff
diff --git a/App/Generation/Presets/PresetSheets.swift b/App/Generation/Presets/PresetSheets.swift
index be2ea5a..8512256 100644
--- a/App/Generation/Presets/PresetSheets.swift
+++ b/App/Generation/Presets/PresetSheets.swift
@@ -10,9 +10,10 @@ struct SavePresetSheet: View {
   @Environment(\.dismiss) private var dismiss
   @State private var name = ""
 
-  private var replaces: Bool {
-    controller.presets.preset(named: name.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
-  }
+  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
+  private var replaces: Bool { controller.presets.contains(trimmed) }
+  /// A name the file system does not take: shown as soon as it is typed.
+  private var invalid: Bool { !trimmed.isEmpty && !PresetStore.isValidName(trimmed) }
 
   var body: some View {
     VStack(alignment: .leading, spacing: DS.rowGap) {
@@ -24,7 +25,11 @@ struct SavePresetSheet: View {
       Text("preset.save.contents")
         .font(.caption)
         .foregroundStyle(.secondary)
-      if replaces {
+      if invalid {
+        Text("preset.save.invalidName")
+          .font(.caption)
+          .foregroundStyle(DS.remove)
+      } else if replaces {
         Text("preset.save.replaces")
           .font(.caption)
           .foregroundStyle(DS.remove)
@@ -43,7 +48,7 @@ struct SavePresetSheet: View {
         }
         .buttonStyle(DSPillButtonStyle(prominent: true))
         .keyboardShortcut(.defaultAction)
-        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
+        .disabled(trimmed.isEmpty || invalid)
       }
     }
     .padding(20)
@@ -53,7 +58,7 @@ struct SavePresetSheet: View {
   }
 
   private func save() {
-    if controller.savePreset(named: name, with: connection) { dismiss() }
+    if (try? controller.savePreset(named: name, with: connection)) != nil { dismiss() }
   }
 }
 
@@ -66,14 +71,14 @@ struct ManagePresetsSheet: View {
     VStack(alignment: .leading, spacing: DS.rowGap) {
       Text("preset.manage.title")
         .font(.headline)
-      if controller.presets.presets.isEmpty {
+      if controller.presets.names.isEmpty {
         Text("preset.none")
           .foregroundStyle(.secondary)
       }
       ScrollView {
         VStack(spacing: DS.controlGap) {
-          ForEach(controller.presets.presets) { preset in
-            PresetRow(preset: preset, store: controller.presets)
+          ForEach(controller.presets.names, id: \.self) { name in
+            PresetRow(presetName: name, store: controller.presets)
           }
         }
       }
@@ -97,10 +102,11 @@ struct ManagePresetsSheet: View {
 }
 
 private struct PresetRow: View {
-  let preset: Preset
+  let presetName: String
   let store: PresetStore
   @State private var name = ""
-  @State private var taken = false
+  @State private var model = ""
+  @State private var problem: String?
 
   var body: some View {
     HStack(spacing: DS.controlGap) {
@@ -108,12 +114,12 @@ private struct PresetRow: View {
         TextField(String(localized: "preset.save.name"), text: $name)
           .textFieldStyle(.roundedBorder)
           .onSubmit(rename)
-        if taken {
-          Text("preset.rename.taken")
+        if let problem {
+          Text(verbatim: problem)
             .font(.caption)
             .foregroundStyle(DS.remove)
-        } else if !preset.model.isEmpty {
-          Text(verbatim: preset.model)
+        } else if !model.isEmpty {
+          Text(verbatim: model)
             .font(.caption)
             .foregroundStyle(.secondary)
             .lineLimit(1)
@@ -121,7 +127,7 @@ private struct PresetRow: View {
         }
       }
       Button {
-        store.delete(preset.id)
+        store.delete(named: presetName)
       } label: {
         Image(systemName: "trash")
           .foregroundStyle(DS.remove)
@@ -130,11 +136,19 @@ private struct PresetRow: View {
       .help(String(localized: "preset.delete"))
       .accessibilityLabel(String(localized: "preset.delete"))
     }
-    .onAppear { name = preset.name }
+    .onAppear {
+      name = presetName
+      model = store.preset(named: presetName)?.model ?? ""
+    }
   }
 
   private func rename() {
-    taken = !store.rename(preset.id, to: name)
-    if taken { name = preset.name }
+    do {
+      try store.rename(presetName, to: name)
+      problem = nil
+    } catch {
+      problem = PresetBar.text(of: error)
+      name = presetName
+    }
   }
 }
```

```diff
diff --git a/App/Localizable.xcstrings b/App/Localizable.xcstrings
index cc31650..01484ae 100644
--- a/App/Localizable.xcstrings
+++ b/App/Localizable.xcstrings
@@ -3758,6 +3758,23 @@
         }
       }
     },
+    "pipeline.unreadablePreset": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Preset not readable: %@"
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Preset non leggibile: %@"
+          }
+        }
+      }
+    },
     "plugin.error.contract": {
       "extractionState": "manual",
       "localizations": {
@@ -5339,6 +5356,23 @@
         }
       }
     },
+    "preset.load.unreadable": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "The preset “%@” cannot be read."
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Il preset «%@» non si può leggere."
+          }
+        }
+      }
+    },
     "preset.manage": {
       "extractionState": "manual",
       "localizations": {
@@ -5458,6 +5492,23 @@
         }
       }
     },
+    "preset.save.invalidName": {
+      "extractionState": "manual",
+      "localizations": {
+        "en": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "A preset name cannot be empty or contain “/” or “:”."
+          }
+        },
+        "it": {
+          "stringUnit": {
+            "state": "translated",
+            "value": "Il nome di un preset non può essere vuoto né contenere «/» o «:»."
+          }
+        }
+      }
+    },
     "preset.save.name": {
       "extractionState": "manual",
       "localizations": {
```

- [ ] **Step 2: Compilare e provare**

Run: `cd "/Users/existenz/Software developement/DT Hub" && xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/q-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`.

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: gli stessi conteggi del Task 1 (Catalog 6 verdi).

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A App && git commit -m "feat: i preset nell'app sono i file della cartella; messaggi per nomi non validi e preset illeggibili

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Il Sample con l'acronimo e il README

**Files:**
- Modify: `Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift`, `PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift`, `PluginKit/README.md`

**Interfaces:**
- Produces: il Sample chiama i suoi preset «SMP · Overcast» e «SMP · Match the sun» (la variante B «SMB · …», `Variant.acronym`); il README spiega la convenzione dell'acronimo, i nomi non validi e `rejected`.

- [ ] **Step 1: Scrivere il test e verificare che fallisca**

```diff
diff --git a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
index 60005fb..2984337 100644
--- a/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
+++ b/Packages/Tests/PluginHostTests/BundlePluginLoaderTests.swift
@@ -122,13 +122,13 @@ struct BundlePluginLoaderTests {
     let piped = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.contribute })
     let pipeline = try #require(PluginContribution(message: piped.message)?.pipeline)
     #expect(pipeline.steps.count == 1 && pipeline.steps[0].moodboard?.count == 1 && pipeline.steps[0].useOutputAsStart == false)
-    #expect(pipeline.steps[0].preset == "Sample · Match the sun")
+    #expect(pipeline.steps[0].preset == "SMP · Match the sun")
 
     // The presets the pipeline names are offered before the pipeline (and on request).
     _ = await plugin.send(Data(#"{"type":"press","button":"presets"}"#.utf8))
     let offered = try #require(host.received.last { PluginMessageType.of($0.message) == PluginMessageType.presets })
     let list = try #require(PluginPresets(message: offered.message)).presets
-    #expect(list.map(\.name) == ["Sample · Overcast", "Sample · Match the sun"])
+    #expect(list.map(\.name) == ["SMP · Overcast", "SMP · Match the sun"])
     #expect(list[1].parameters.loras.first?.weight == 0.6 && list[0].parameters.loras.isEmpty)
     #expect(list[1].prompt.hasPrefix("match light direction"))
 
```

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test --filter BundlePluginLoaderTests 2>&1 | grep -E "recorded an issue" | head -2`
Expected: aspettative fallite sul nome del preset («SMP · Match the sun»).

- [ ] **Step 2: Implementare**

```diff
diff --git a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
index 4614df8..07c1804 100644
--- a/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
+++ b/PluginKit/Examples/Sample/Sources/SamplePlugin/SamplePlugin.swift
@@ -7,6 +7,8 @@ import SwiftUI
   private enum Variant {
     static let id = "com.example.dthub.sample.b"
     static let name = "Sample B"
+    /// The prefix of the names of its presets (2–4 letters): the Preset menu shows nothing else about where a preset comes from.
+    static let acronym = "SMB"
     static let symbol = "star.fill"
     static let prompt = "a lighthouse in a storm, dramatic light"
     static let steps = 8
@@ -17,6 +19,8 @@ import SwiftUI
   private enum Variant {
     static let id = "com.example.dthub.sample"
     static let name = "Sample"
+    /// The prefix of the names of its presets (2–4 letters): the Preset menu shows nothing else about where a preset comes from.
+    static let acronym = "SMP"
     static let symbol = "star"
     static let prompt = "match light direction, colors and intensity from the reference image 2"
     static let steps = 4
@@ -110,8 +114,8 @@ final class SamplePlugin: DTHubPlugin {
 
   private var sunLora: [String: Any] { ["file": Variant.lora, "weight": 0.6] }
 
-  private var overcastPreset: String { "\(Variant.name) · Overcast" }
-  private var matchPreset: String { "\(Variant.name) · Match the sun" }
+  private var overcastPreset: String { "\(Variant.acronym) · Overcast" }
+  private var matchPreset: String { "\(Variant.acronym) · Match the sun" }
 
   /// The two presets of the pipeline, in the app's Preset menu: the user sees them, changes them (the LoRA
   /// weight, the steps…) and saves them under the same name. The app never overwrites a name it has.
```

```diff
diff --git a/PluginKit/README.md b/PluginKit/README.md
index 8a4c79a..9df224a 100644
--- a/PluginKit/README.md
+++ b/PluginKit/README.md
@@ -51,10 +51,13 @@ JSON objects with a `type`. An unknown type gets `{"type":"unsupported"}`.
     the passes one after the other; if a preset is not in the menu it says so and runs nothing.
   The fields a plug-in filled turn teal; the user can always change them. If two plug-ins fill the same field, or
   both propose a start image or a pipeline, the user chooses in a pop-up.
-- `presets` — `{"presets": [{"name", "fields", "loras"}]}`: presets for the Preset menu (shown as «da <plug-in>»);
-  `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size, no model. A
-  name the menu has already is never touched (the user may have changed it), so register them whenever you like.
-  The answer is `{"type":"ok","added":n,"existing":m}`.
+- `presets` — `{"presets": [{"name", "fields", "loras"}]}`: presets for the Preset menu. Each is a
+  file in the app's Presets folder, named after the preset. **Name them with your own acronym** (2–4 letters), a
+  middle dot and the name — `SMP · Overcast`, `SLR · Match the sun` — because that is the only sign of where a
+  preset comes from. A name cannot contain `/` or `:` (file system rules); capitals and accents do not tell two
+  names apart. `fields` has the keys of `contribute` above, the prompt and the negative prompt included; no size,
+  no model. A name the menu has already is never touched (the user may have changed it), so register them
+  whenever you like. The answer is `{"type":"ok","added":n,"existing":m,"rejected":k}`.
 - `llm` — `{"prompt", "images": [paths]}`: a question for the language model. The answer is
   `{"type":"llm","text":…}` (it can take a while: the model may have to load) or an `error`.
 
```

- [ ] **Step 3: Verificare**

Run: `cd "/Users/existenz/Software developement/DT Hub/Packages" && swift test 2>&1 | grep -E "✘ Test [a-zA-Z]+\(|Test run with|error:" | grep -v "started\|reportsFailures"`
Expected: gli stessi conteggi del Task 1 (totale **631**).

Run: `cd "/Users/existenz/Software developement/DT Hub" && PluginKit/Scripts/build-sample.sh /tmp/q-bundles && PluginKit/Scripts/build-sample.sh /tmp/q-bundles b`
Expected: i percorsi dei due bundle.

- [ ] **Step 4: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add -A PluginKit Packages && git commit -m "feat: i preset del Sample portano l'acronimo del plug-in; convenzione nel README

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Prova nell'app e documenti

**Files:**
- Modify: `docs/superpowers/specs/2026-10-04-preset-pipeline-design.md`, `docs/superpowers/backlog.md`

- [ ] **Step 1: Provare nell'app vera con il server vero, in una cartella dati a parte**

**Prima: l'app dell'utente deve essere chiusa** (`ps aux | grep "[D]T Hub.app"` vuoto), altrimenti gli strumenti per pilotare le finestre agirebbero sulla sua. Servono: il server gestito di DT Hub (nelle preferenze dell'utente), FLUX.2 klein 9B, il LoRA `flux_2_sun_direction_lora_v1_lora_f16.ckpt` e un'immagine di partenza (il ritratto del test: `/Users/existenz/Desktop/0______high_level_description____a_fine_art_portrait_of_an_asian_girl_…_4027213388.png`, 896×1152). **Le preferenze sono quelle dell'utente**: annotare e rimettere `drawThings.selectedModel` e `workspace.selectedTab`.

```bash
cd "/Users/existenz/Software developement/DT Hub"
defaults read com.exiztenz.DTHub drawThings.selectedModel    # annotare
xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath /tmp/q-dd CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
PluginKit/Scripts/build-sample.sh /tmp/q-bundles
H=/tmp/qhome; rm -rf $H; AS="$H/Library/Application Support/DT Hub"; mkdir -p "$AS/Plug-ins" "$AS/Control"
cp -R /tmp/q-bundles/Sample.dthubplugin "$AS/Plug-ins/com.example.dthub.sample.dthubplugin"
echo '{"enabled":["com.example.dthub.sample"]}' > "$AS/plugins.json"
defaults write com.exiztenz.DTHub drawThings.selectedModel flux_2_klein_9b_f16.ckpt
(CFFIXED_USER_HOME=$H nohup "/tmp/q-dd/Build/Products/Debug/DT Hub.app/Contents/MacOS/DT Hub" > /tmp/q-app.log 2>&1 &)
```

Per dare l'immagine di partenza senza il pannello di apertura (che gli strumenti non pilotano): con l'app chiusa, copiare il PNG in `$AS/Control/<uuid>.png` e scrivere in `$AS/control.json` `"image":{"id":"<uuid>","name":"portrait.png","pixelWidth":896,"pixelHeight":1152,"source":{"result":{}},"fileName":"<uuid>.png"}`, e in `$AS/session.json` larghezza 896 e altezza 1152; poi avviare.

Checklist:
1. Dopo l'avvio `$AS/Presets/` contiene `SMP · Match the sun.json` e `SMP · Overcast.json`, senza `name`, `id` né `origin` nel JSON; il menu **Preset** li elenca come «SMP · Match the sun» e «SMP · Overcast», senza altro.
2. Tab Sample › «Overcast shadows», **Send pipeline**: «Run · 2 passaggi». Run: due immagini, la seconda parte dalla prima.
3. **Con l'app aperta**, modificare a mano `SMP · Match the sun.json` (`parameters.steps` a 2) e premere di nuovo Run: nei metadati del PNG del secondo passaggio gli step sono 2, **senza riavviare**.
4. Cancellare con `rm` il file `SMP · Overcast.json` e premere Run (la pipeline è sul pulsante): la finestra Risultati mostra **«Preset non trovato: SMP · Overcast»** e non parte nulla. Scrivere in un file di preset del testo che non è JSON: «Preset non leggibile: …».
5. «Send pipeline» ricrea il preset cancellato. Riportando la finestra in primo piano il menu Preset mostra l'elenco aggiornato.
6. Salva come preset… con il nome «a/b»: il messaggio «Il nome di un preset non può essere vuoto né contenere «/» o «:»» e il pulsante Salva spento. Rinominare un preset da Gestisci preset… cambia il nome del file.
7. «Togli la pipeline» (clic destro sul pulsante Run) lo riporta a «Run».

Alla fine: chiudere l'app di prova (`pkill -f q-dd`), fermare il server gestito se è rimasto (`pkill -f gRPCServerCLI`), rimettere il modello e la scheda annotati, togliere `/tmp/qhome`.

- [ ] **Step 2: Aggiornare spec e backlog**

```bash
cd "/Users/existenz/Software developement/DT Hub" && python3 - <<'PY'
p = 'docs/superpowers/specs/2026-10-04-preset-pipeline-design.md'
s = open(p).read()
s = s.replace("Stato: P1 e P2 realizzate, P3 (un file per preset) da fare", "Stato: P1, P2 e P3 realizzate")
open(p, 'w').write(s)
p = 'docs/superpowers/backlog.md'
s = open(p).read().rstrip() + """

## Rimandi di P3 (un file per preset)

- **Il menu Preset si aggiorna quando la finestra torna attiva e all'apparire della barra**, non ogni volta che si apre il menu (SwiftUI non dà l'evento): un file aggiunto a mano mentre la finestra è già in primo piano compare al giro successivo.
- **Un rinomina interrotto a metà** lascia un file nascosto `.renaming-<uuid>.json` (ignorato dall'elenco, da togliere a mano).
- **Nessuna cache dell'elenco:** con migliaia di preset ogni lettura scansiona la cartella.
- **«Gestisci preset…» legge il modello di ogni preset** all'apertura della riga (un file per riga).
"""
open(p, 'w').write(s + "\n")
PY
git diff --stat docs | tail -1
```

Expected: statistica su due file.

- [ ] **Step 3: Commit**

```bash
cd "/Users/existenz/Software developement/DT Hub" && git add docs && git commit -m "docs: un file per preset realizzato; rimandi nel backlog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Fine di P3

Esito atteso sul branch `m8b-plugin` (con M8b, prompt nei preset e pipeline di preset già dentro):
- **631 test verdi**, build Xcode pulita;
- i preset sono file in `Presets/`, il nome è il file, l'elenco viene dai nomi, il contenuto si legge al bisogno, un file rotto non rovina gli altri;
- il Run della pipeline legge solo i preset che nomina e dice cosa manca o non si legge;
- i preset di un plug-in portano l'acronimo nel nome e nient'altro.

Poi: revisione indipendente di P3, correzioni, la prova dell'utente (**lasciare l'app aperta**) e **un solo merge** di tutto (M8b, prompt nei preset, pipeline di preset, un file per preset).

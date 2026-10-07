# Migliora Prompt e Genera Prompt — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** due tasti dell'app che usano l'LLM locale: «Migliora Prompt» (card Prompt) e «Genera Prompt» (card Immagine del tab Control); il risultato va nel campo prompt (e nel negativo dove la famiglia lo usa).

**Architettura:** logica pura e stato in HubCore (`PromptGuides`, `PromptBrief`, `PromptAssistant`), testata con `swift test`; l'app ha solo un collegamento sottile nel `GenerationController` e due tasti. I master prompt semplificati («Model notes» + regola generica) sono copiati nell'app una volta sola da `master-prompts.json` del plug-in Prompt Master e poi vivono per conto loro.

**Tecnologie:** Swift 6.2, Swift Testing (`import Testing`, `@Test`, `#expect`), SwiftUI/AppKit, `LanguageModelManager.respond` esistente. Python 3 per lo script di estrazione.

**Spec:** `docs/superpowers/specs/2026-10-07-llm-prompt-tools-design.md` (leggerla prima: i testi esatti dei messaggi sono lì, al §3.2).

## Vincoli globali

- Si lavora in un ramo nuovo da `main` (es. `llm-prompt-tools`). **Non si unisce in `main` e non si fa push/release senza un «unisci» / via libera esplicito dell'utente.**
- Si aggiungono i file **per nome** (`git add <file>`): mai `git add -A` né `git add docs`; `docs/`, `.serena/`, `Screenshot/` e il briefing sono esclusi da git in locale.
- Tutti i test dell'app stanno in `Packages/Tests/HubCoreTests/`. Test: `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|error:"`.
- I test che toccano `@MainActor` (`PromptAssistant`, `@Observable`) vanno marcati `@MainActor`; niente `UserDefaults` nei test.
- L'app va compilata con `xcodebuild`, non solo `swift test` (il target app non è nel pacchetto): `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build`.
- Testi dell'interfaccia in italiano e inglese (`Localizable.xcstrings`, `extractionState: manual`, entrambe le lingue `translated`). Il codice e i prompt per l'LLM sono in inglese; i commenti nel codice in inglese come nel resto di HubCore.
- Nei testi pubblici (README) non si dice che DT Hub «sostituisce» l'interfaccia di Draw Things.
- Dopo l'unione in `main` (solo con «unisci»): ricompilare l'app dell'utente con il comando `xcodebuild` sopra e dirgli di riavviarla.

## Review Focus

Casi che la spec implica e nessun test «felice» esercita; ognuno ha il suo test nel task indicato.

1. Prompt vuoto o di soli spazi premendo «Migliora Prompt»: nessuna chiamata all'LLM, errore chiaro (Task 4).
2. Il modello risponde con testo attorno al JSON («Here is the prompt: {…}») o con JSON malformato: il prompt non deve restare vuoto né contenere le parentesi (Task 3).
3. Modello che ragiona e non chiude `<think>`: la risposta è vuota, non il ragionamento (Task 3).
4. Famiglia sconosciuta o `nil` (catalogo non ancora caricato): i tasti funzionano con la sola regola generica, in prosa (Task 2, Task 4).
5. Il campo cambia mentre l'LLM risponde, o si preme il tasto due volte: una sola operazione alla volta; «Annulla» riporta il testo passato alla chiamata, non quello digitato dopo (Task 4).

---

## Struttura dei file

| File | Responsabilità |
|---|---|
| `Scripts/make-prompt-guides.py` (nuovo) | estrae le «Model notes» e il flag negativo da `master-prompts.json` e scrive `PromptGuides.swift`; si usa una volta |
| `Packages/Sources/HubCore/PromptAssist/PromptGuides.swift` (nuovo, generato poi a mano) | dati: famiglia → `PromptGuide` |
| `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift` (nuovo) | `PromptPair`, `PromptRequest`, messaggi per l'LLM e parser della risposta |
| `Packages/Sources/HubCore/PromptAssist/PromptAssistant.swift` (nuovo) | stato (`working`, `failure`, annulla) e le operazioni `enhance` / `describe` |
| `Packages/Tests/HubCoreTests/PromptGuidesTests.swift`, `PromptBriefTests.swift`, `PromptAnswerParserTests.swift`, `PromptAssistantTests.swift` (nuovi) | test |
| `App/Generation/GenerationController.swift` (modifica) | `assistant`, `enhancePrompt(in:)`, `promptFromImage(in:)` |
| `App/Generation/Cards/PromptCard.swift`, `App/Control/ImageCard.swift` (modifica) | i due tasti, spinner, «Annulla», riga d'errore |
| `App/Preferences/LanguagePreferencesView.swift` (modifica) | testi per i tre errori nuovi, accanto a `LanguageModelErrorText` |
| `App/Localizable.xcstrings` (modifica) | testi IT/EN |

---

### Task 1: Dati — `PromptGuides` e script di estrazione

**Files:**
- Create: `Scripts/make-prompt-guides.py`
- Create (generato): `Packages/Sources/HubCore/PromptAssist/PromptGuides.swift`
- Test: `Packages/Tests/HubCoreTests/PromptGuidesTests.swift`

**Interfaces:**
- Consumes: `Plugins/PromptMaster/Data/master-prompts.json` (`families.<key>.{label, negative, system}`; in `system` il blocco inizia con una riga `Model notes:` e arriva fino alla fine).
- Produces (usato dai Task 2 e 4):
  ```swift
  public struct PromptGuide: Equatable, Sendable { public let label: String; public let usesNegative: Bool; public let notes: String }
  public enum PromptGuides {
    public static let all: [String: PromptGuide]
    public static func guide(for family: String?) -> PromptGuide?
  }
  ```

- [ ] **Step 1: Scrivere il test che fallisce** (`PromptGuidesTests`, struct con `@Test`):
  - `hasTheThirteenFamilies`: `Set(PromptGuides.all.keys) == ["flux1","flux2","flux2_9b","flux2_4b","krea_2","qwen_image","qwen_image_2.1","z_image","sdxl_base_v0.9","v1","ernie_image","hidream_i1","cosmos2.5_2b"]`.
  - `negativeFlagMatchesThePluginData`: `usesNegative == true` esattamente per `["krea_2","qwen_image","ernie_image","cosmos2.5_2b","sdxl_base_v0.9","v1"]`, false per le altre sette.
  - `notesAreClean`: per ogni guida `!notes.isEmpty`, `notes.hasPrefix("- ")`, e `notes` non contiene `"Model notes:"`, `"Provisional master prompt"`, `"Tag mode is ON"`.
  - `labelsAreReadable`: `PromptGuides.all["flux2_9b"]?.label == "FLUX.2 [klein] 9B"` e `PromptGuides.all["v1"]?.label == "Stable Diffusion 1.5"`.
  - `unknownOrMissingFamilyHasNoGuide`: `PromptGuides.guide(for: nil) == nil`, `PromptGuides.guide(for: "mystery_model") == nil`, `PromptGuides.guide(for: "flux1")?.label == "FLUX.1"`.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `cd Packages && swift test --filter PromptGuidesTests 2>&1 | grep -E "Test run with|error:"` → errore di compilazione (`PromptGuides` non esiste).

- [ ] **Step 3: Scrivere `Scripts/make-prompt-guides.py`**. Argomenti `--source <master-prompts.json>` (obbligatorio, nessun percorso personale come default) e `--out <file.swift>`. Per ogni famiglia di `families`, nell'ordine del JSON: `notes` = testo di `system` dopo la riga `Model notes:` (tagliato agli estremi); se `system` ha già in coda righe che non iniziano con `- ` dopo le note, tenerle fuori scartando tutto ciò che segue l'ultima riga di elenco continua. Scrivere un file Swift con intestazione `// Generated once by Scripts/make-prompt-guides.py from Prompt Master's master-prompts.json; edit by hand from here on.`, `import Foundation`, e `PromptGuides.all` come dizionario letterale di `PromptGuide(label:usesNegative:notes:)`; le note come stringhe multilinea raw `#"""` … `"""#` (le note contengono virgolette e backslash). `guide(for:)` = `family.flatMap { all[$0] }`. Lo script esce con errore se una famiglia non ha `Model notes:`.

- [ ] **Step 4: Generare il file** — `python3 Scripts/make-prompt-guides.py --source Plugins/PromptMaster/Data/master-prompts.json --out Packages/Sources/HubCore/PromptAssist/PromptGuides.swift`. Aprire il file e controllare a occhio: 13 voci; `qwen_image_2.1` finisce con «There is no negative prompt (guidance 1): turn "avoid" terms into positive description.» e **non** con «(Provisional master prompt…)»; `sdxl_base_v0.9` finisce con la riga «A negative prompt is recommended…» e non contiene «Tag mode is ON».

- [ ] **Step 5: Lanciare i test** — stesso comando dello Step 2 → tutti verdi.

- [ ] **Step 6: Commit**
  ```bash
  git add Scripts/make-prompt-guides.py Packages/Sources/HubCore/PromptAssist/PromptGuides.swift Packages/Tests/HubCoreTests/PromptGuidesTests.swift
  git commit -m "feat(prompt-assist): guide dei modelli, note estratte dai master prompt"
  ```

---

### Task 2: Messaggi per l'LLM — `PromptBrief.system / enhance / describe`

**Files:**
- Create: `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`
- Test: `Packages/Tests/HubCoreTests/PromptBriefTests.swift`

**Interfaces:**
- Consumes: `PromptGuides.guide(for:)` (Task 1), `LanguageModelOptions` (HubKit, init con `system:`, `maxTokens:`, `thinking:`).
- Produces (usato dai Task 3 e 4):
  ```swift
  public struct PromptPair: Equatable, Sendable { public var prompt: String; public var negative: String; public init(prompt: String, negative: String) }
  public struct PromptRequest: Equatable, Sendable { public let prompt: String; public let images: [URL]; public let options: LanguageModelOptions }
  public enum PromptBrief {
    public static func system(family: String?) -> String
    public static func enhance(_ current: PromptPair, family: String?) -> PromptRequest
    public static func describe(imageAt url: URL, family: String?) -> PromptRequest
  }
  ```

- [ ] **Step 1: Scrivere i test che falliscono** (`PromptBriefTests`; i testi esatti sono nel §3.2 della spec — copiarli verbatim nelle asserzioni):
  - `systemForAFamilyWithoutNegative`: `PromptBrief.system(family: "flux2_9b")` inizia con `You write prompts for the image model "FLUX.2 [klein] 9B".`, contiene `exclusively in English`, `Reply with the prompt only`, **non** contiene `JSON`, e finisce con `"\n\nModel notes:\n" + PromptGuides.all["flux2_9b"]!.notes`.
  - `systemForAFamilyWithNegativeAsksForJSON`: per `"v1"` contiene `{"prompt": "...", "negative": "..."}` e `Both values are in English`, non contiene `Reply with the prompt only`.
  - `systemForAnUnknownFamilyIsGenericProse`: per `"mystery"` e per `nil`: inizia con `You write prompts for an image-generation model.`, contiene `Reply with the prompt only`, non contiene `Model notes:`.
  - `enhanceRequestText`: per `PromptPair(prompt: "un gatto sul tetto", negative: "")` e `"flux2"`: `prompt == "Improve the prompt below for this model. Keep every element it describes and never contradict it; add concrete visual detail as the model notes ask. The prompt may be in any language.\n\nPrompt:\nun gatto sul tetto"`, `images.isEmpty`, `options == LanguageModelOptions(system: PromptBrief.system(family: "flux2"), maxTokens: 2048, thinking: false)`.
  - `enhanceAddsTheNegativeOnlyWhenTheFamilyUsesItAndItIsNotEmpty`: con `"v1"` e negativo `"blurry"` il prompt termina con `"\n\nNegative prompt:\nblurry"`; con `"v1"` e negativo `""` non contiene `Negative prompt:`; con `"flux2"` e negativo `"blurry"` non contiene `Negative prompt:`.
  - `describeRequest`: `PromptBrief.describe(imageAt: URL(fileURLWithPath: "/tmp/a.png"), family: "krea_2")` ha `prompt == "Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story."`, `images == [URL(fileURLWithPath: "/tmp/a.png")]`, `options.system == PromptBrief.system(family: "krea_2")`, `maxTokens == 2048`, `thinking == false`.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter PromptBriefTests` → errore di compilazione.

- [ ] **Step 3: Implementare in `PromptBrief.swift`** i tipi e le tre funzioni con le firme sopra. `system` assembla: riga 1 (con `label` o testo generico), riga vuota, regola generica (variante JSON solo se `guide?.usesNegative == true`), e se c'è la guida `"\n\nModel notes:\n" + notes`. Una costante privata `options(system:)` evita di ripetere `maxTokens: 2048, thinking: false` (commento: un modello che ragiona di default consumerebbe i token nel ragionamento).

- [ ] **Step 4: Lanciare i test** → verdi.

- [ ] **Step 5: Commit**
  ```bash
  git add Packages/Sources/HubCore/PromptAssist/PromptBrief.swift Packages/Tests/HubCoreTests/PromptBriefTests.swift
  git commit -m "feat(prompt-assist): messaggi per Migliora e Genera Prompt"
  ```

---

### Task 3: Parser della risposta — `PromptBrief.parse`

**Files:**
- Modify: `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`
- Test: `Packages/Tests/HubCoreTests/PromptAnswerParserTests.swift`

**Interfaces:**
- Consumes: `PromptPair` (Task 2). Riferimento da seguire: `Plugins/PromptMaster/Sources/PromptMaster/AnswerParser.swift` (stessa logica, **copiata** — il plug-in non può dipendere da HubCore — senza il campo `ratio`).
- Produces (usato dal Task 4): `public static func parse(_ raw: String) -> PromptPair?` — `negative` è `""` quando la risposta non ne ha. Nessun parametro `family`: l'assistente decide dopo se usare il negativo.

- [ ] **Step 1: Scrivere i test che falliscono** (`PromptAnswerParserTests`):
  - `plainProse`: `parse("  A cat on a roof at dusk.\n") == PromptPair(prompt: "A cat on a roof at dusk.", negative: "")`.
  - `oneQuotePairIsRemoved`: `parse("\"A cat\"")?.prompt == "A cat"`; `parse("“A cat”")?.prompt == "A cat"`; `parse("\"A\" and \"B\"")?.prompt == "\"A\" and \"B\""` (due coppie: non si toglie nulla).
  - `fencedJSON`: `parse("```json\n{\"prompt\": \"a, b\", \"negative\": \"blurry\"}\n```") == PromptPair(prompt: "a, b", negative: "blurry")`.
  - `jsonAliases`: `{"rewritten_prompt":"x","negative_prompt":"y"}` → `PromptPair(prompt: "x", negative: "y")`.
  - `jsonSurroundedByChatter` (Review Focus 2): `parse("Here is the prompt: {\"prompt\": \"a cat\", \"negative\": \"dog\"} Hope it helps!") == PromptPair(prompt: "a cat", negative: "dog")`.
  - `malformedJSONIsTakenAsTheText`: `parse("{\"prompt\": \"a cat\"")?.prompt == "{\"prompt\": \"a cat\""` (nessun crash, il testo resta).
  - `thinkingBlockIsRemoved`: `parse("<think>hmm</think>A cat")?.prompt == "A cat"`.
  - `unclosedThinkingGivesNil` (Review Focus 3): `parse("<think>I should describe a cat and")` è `nil`.
  - `emptyGivesNil`: `parse("")`, `parse("   \n")`, `parse("```\n```")` sono `nil`.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter PromptAnswerParserTests` → errore di compilazione (`parse` non esiste).

- [ ] **Step 3: Implementare `parse`** in `PromptBrief.swift` con helper privati (`withoutThinking`, `withoutFences`, `unquoted`, `clean`) uguali a quelli di `AnswerParser.swift`: togliere `<think>…</think>` (anche non chiuso), la recinzione ```, poi cercare un oggetto JSON tra la prima `{` e l'ultima `}` e leggerne `prompt`/`rewritten_prompt`/`positive_prompt` e `negative`/`negative_prompt`; altrimenti tutto il testo, senza una sola coppia di virgolette; `nil` se non resta nulla. Il test `jsonSurroundedByChatter` passa già con questa logica; il malformato cade nel ramo «tutto il testo».

- [ ] **Step 4: Lanciare i test** → verdi.

- [ ] **Step 5: Commit**
  ```bash
  git add Packages/Sources/HubCore/PromptAssist/PromptBrief.swift Packages/Tests/HubCoreTests/PromptAnswerParserTests.swift
  git commit -m "feat(prompt-assist): parser della risposta (prosa e JSON con negativo)"
  ```

---

### Task 4: Stato e operazioni — `PromptAssistant`

**Files:**
- Create: `Packages/Sources/HubCore/PromptAssist/PromptAssistant.swift`
- Test: `Packages/Tests/HubCoreTests/PromptAssistantTests.swift`

**Interfaces:**
- Consumes: `PromptBrief.enhance/describe/parse`, `PromptGuides.guide(for:)`, `PromptPair`, `PromptRequest` (Task 1–3); `LanguageModelError`, `LanguageModelOptions` (HubKit).
- Produces (usato dal Task 5):
  ```swift
  @MainActor @Observable public final class PromptAssistant {
    public enum Kind: Equatable, Sendable { case enhance, describe }
    public enum Failure: Equatable, Sendable { case emptyPrompt, noImage, emptyAnswer, model(LanguageModelError) }
    public typealias Respond = @MainActor (String, [URL], LanguageModelOptions) async throws(LanguageModelError) -> String
    public init(respond: @escaping Respond)
    public private(set) var working: Kind?
    public private(set) var failure: Failure?
    public func enhance(_ current: PromptPair, family: String?) async -> PromptPair?
    public func describe(imageAt url: URL?, current: PromptPair, family: String?) async -> PromptPair?
    public func undoOffer(current: PromptPair) -> PromptPair?
    public func clearUndo()
  }
  ```

- [ ] **Step 1: Scrivere i test che falliscono** (`PromptAssistantTests`, struct `@MainActor`; un piccolo helper locale `final class Recorder` che registra `(prompt, images, options)` delle chiamate e restituisce una risposta o lancia un errore configurabili, passato come closure `Respond`):
  - `enhanceWritesTheAnswerAndKeepsTheNegativeWhenTheFamilyHasNone`: risposta `"A cat, detailed."`, famiglia `"flux2"`, corrente `PromptPair("gatto","old neg")` → ritorna `PromptPair(prompt: "A cat, detailed.", negative: "old neg")`; la chiamata ha ricevuto `PromptBrief.enhance(corrente, family: "flux2")` (`prompt`, `images`, `options` uguali).
  - `enhanceFillsTheNegativeForAFamilyThatUsesIt`: famiglia `"v1"`, risposta `{"prompt":"a cat","negative":"blurry"}` → `PromptPair("a cat","blurry")`.
  - `aNegativeFamilyWhoseAnswerHasNoNegativeKeepsTheOldOne`: `"v1"`, risposta `"a cat"`, corrente negativo `"old"` → negativo `"old"`.
  - `emptyPromptDoesNotCallTheModel` (Review Focus 1): corrente `PromptPair("   \n","x")` → `nil`, `failure == .emptyPrompt`, zero chiamate.
  - `unknownFamilyWorksInProse` (Review Focus 4): famiglia `nil` e `"mystery"`, risposta `"A cat"` → `PromptPair("A cat", <negativo corrente>)`; `options.system` della chiamata == `PromptBrief.system(family: nil)`.
  - `describeNeedsAnImage`: `describe(imageAt: nil, …)` → `nil`, `failure == .noImage`, zero chiamate.
  - `describeSendsTheImage`: URL `/tmp/a.png`, famiglia `"krea_2"`, risposta JSON con negativo → la chiamata ha `images == [url]` e il risultato ha prompt e negativo della risposta.
  - `serviceErrorsAreReported`: il closure lancia `.noModelSelected` → ritorna `nil`, `failure == .model(.noModelSelected)`, `working == nil` dopo.
  - `emptyAnswerIsReported`: risposta `"<think>x"` → `nil`, `failure == .emptyAnswer`.
  - `oneOperationAtATime` (Review Focus 5): il closure sospende su un `CheckedContinuation`; mentre la prima `enhance` è in corso (`working == .enhance`) una seconda `enhance` ritorna `nil` subito e il closure è stato chiamato una sola volta; dopo aver ripreso la prima `working == nil`.
  - `aNewOperationClearsTheFailure`: dopo un errore, una chiamata riuscita porta `failure` a `nil`.
  - `undoOfferedUntilTheFieldsChange` (Review Focus 5): dopo un `enhance` riuscito da `PromptPair("gatto","")` che dà `PromptPair("A cat","")`: `undoOffer(current: PromptPair("A cat",""))` è `PromptPair("gatto","")`; `undoOffer(current: PromptPair("A cat!",""))` è `nil`; dopo `clearUndo()` anche il primo è `nil`. Il «prima» è il valore passato alla chiamata, anche se nel frattempo il campo è cambiato.
  - `aFailedOperationKeepsThePreviousUndo`: dopo un successo e poi un errore, `undoOffer` per il risultato scritto del successo resta valido.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter PromptAssistantTests` → errore di compilazione.

- [ ] **Step 3: Implementare `PromptAssistant`** con le firme sopra. Un metodo privato `run(kind:request:current:family:) async -> PromptPair?` condivide il flusso: se `working != nil` ritorna nil; imposta `working = kind` e `failure = nil`; `defer { working = nil }`; chiama `respond` (errore → `.model`); `PromptBrief.parse` (nil → `.emptyAnswer`); compone il risultato (negativo della risposta solo se `PromptGuides.guide(for: family)?.usesNegative == true` **e** non vuoto, altrimenti `current.negative`); memorizza `(before: current, written: result)` per `undoOffer`. `enhance` controlla il prompt vuoto (`trimmingCharacters(in: .whitespacesAndNewlines).isEmpty`) e `describe` l'URL nil **prima** di toccare `working`.

- [ ] **Step 4: Lanciare i test** → verdi. Poi tutta la suite di HubCore: `swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento.

- [ ] **Step 5: Commit**
  ```bash
  git add Packages/Sources/HubCore/PromptAssist/PromptAssistant.swift Packages/Tests/HubCoreTests/PromptAssistantTests.swift
  git commit -m "feat(prompt-assist): stato e operazioni Migliora/Genera Prompt, con annulla"
  ```

---

### Task 5: App — collegamento, tasti e testi

**Files:**
- Modify: `App/Generation/GenerationController.swift` (proprietà vicino a `languageModel`, `init`, metodi dopo `traits(in:)`)
- Modify: `App/Generation/Cards/PromptCard.swift`
- Modify: `App/Control/ImageCard.swift` (riga dei pulsanti, dentro `loaded(_:)`)
- Modify: `App/Preferences/LanguagePreferencesView.swift` (accanto a `LanguageModelErrorText`)
- Modify: `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PromptAssistant` (Task 4); `controller.family(in:)`, `control.inputs.image`, `control.copyURL(of:)` (esistenti); `LanguageModelErrorText.message(_:)`; `DSPillButtonStyle`, `DS.*`.
- Produces: nulla per altri task.

L'app non ha test di UI: la verifica è la compilazione (Step 4) e la prova a mano (Task 6).

- [ ] **Step 1: `GenerationController`**. Aggiungere `@ObservationIgnored let assistant: PromptAssistant`, assegnato in `init` **prima** del ripristino della sessione, con `PromptAssistant(respond: { prompt, images, options in try await languageModel.respond(to: prompt, images: images, options: options) })`. Aggiungere:
  - `func enhancePrompt(in connection: DrawThingsConnection) async` — `if let result = await assistant.enhance(PromptPair(prompt: prompt, negative: negativePrompt), family: family(in: connection)) { prompt = result.prompt; negativePrompt = result.negative }`.
  - `func promptFromImage(in connection: DrawThingsConnection) async` — URL = `control.inputs.image.flatMap { control.copyURL(of: $0) }`; stesso schema con `assistant.describe(imageAt:current:family:)`.
  - Nota: `assistant` è `@Observable`, ma il controller lo tiene `@ObservationIgnored`; le view leggono `controller.assistant.working` direttamente (la proprietà osservata è quella dell'assistente).

- [ ] **Step 2: Testi**. In `LanguagePreferencesView.swift` aggiungere un'estensione/funzione `PromptAssistantText.message(_ failure: PromptAssistant.Failure) -> String`: `.model(let e)` → `LanguageModelErrorText.message(e)`; `.emptyPrompt` → `prompt.assist.error.empty`; `.noImage` → `prompt.assist.error.noImage`; `.emptyAnswer` → `prompt.assist.error.noAnswer`. In `Localizable.xcstrings` aggiungere (it / en):
  | chiave | it | en |
  |---|---|---|
  | `prompt.enhance` | Migliora Prompt | Enhance Prompt |
  | `prompt.enhance.help` | Riscrive il prompt con l'LLM, secondo le regole del modello scelto | Rewrites the prompt with the LLM, following the rules of the selected model |
  | `prompt.undo` | Annulla | Undo |
  | `prompt.assist.error.empty` | Scrivi prima un prompt da migliorare. | Write a prompt to enhance first. |
  | `prompt.assist.error.noImage` | Nessuna immagine da descrivere. | No image to describe. |
  | `prompt.assist.error.noAnswer` | L'LLM non ha dato una risposta utilizzabile. | The LLM gave no usable answer. |
  | `control.image.describe` | Genera Prompt | Generate Prompt |
  | `control.image.describe.help` | Descrive l'immagine con l'LLM e scrive il prompt, secondo le regole del modello scelto | Describes the image with the LLM and writes the prompt, following the rules of the selected model |

- [ ] **Step 3: UI**.
  - `PromptCard`: sotto l'ultimo campo, una `HStack(spacing: DS.controlGap)` con: `Button("prompt.enhance")` (`DSPillButtonStyle()`, `Label` con `Image(systemName: "wand.and.stars")`, `.help(String(localized: "prompt.enhance.help"))`, `.disabled(controller.assistant.working != nil)`, azione `Task { await controller.enhancePrompt(in: connection) }`); un `ProgressView().controlSize(.small)` se `working == .enhance`; a destra, se `controller.assistant.undoOffer(current: PromptPair(prompt: controller.prompt, negative: controller.negativePrompt))` non è nil, un `Button("prompt.undo")` in stile `.plain`, `.caption.weight(.semibold)`, `DS.accent` (come «Auto» nel `strengthRow` di `ImageCard`) che riassegna prompt e negativo e chiama `clearUndo()`. Sotto, se `failure != nil`, `Text(PromptAssistantText.message(failure))` in `.caption`, `DS.remove`.
  - `ImageCard`: nella `HStack` dei pulsanti di `loaded(_:)` aggiungere `Button("control.image.describe")` con lo stesso trattamento (icona `text.viewfinder`, spinner se `working == .describe`, `.disabled(working != nil)`, azione `Task { await generation.promptFromImage(in: connection) }`), e sotto la riga d'errore e il link «Annulla» come sopra. L'`HStack` dei pulsanti può andare a capo: usare `ViewThatFits` o spostare il tasto su una seconda riga se a 340 pt non entra.
  - Il tasto di `PromptCard` non è nascosto per famiglie senza guida (decisione 3).

- [ ] **Step 4: Compilare** — `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | tail -20` → `BUILD SUCCEEDED`. Se compare `unable to spawn process '…/metal'`: `cd Packages && swift package clean` e rilanciare.

- [ ] **Step 5: Commit**
  ```bash
  git add App/Generation/GenerationController.swift App/Generation/Cards/PromptCard.swift App/Control/ImageCard.swift App/Preferences/LanguagePreferencesView.swift App/Localizable.xcstrings
  git commit -m "feat(app): tasti Migliora Prompt e Genera Prompt"
  ```

---

### Task 6: Chiusura — suite completa, prova dal vivo, documentazione

**Files:**
- Modify: `README.md` (sezione «What DT Hub adds», una riga, in inglese)
- Modify (solo sul disco, non in git): `docs/superpowers/backlog.md` se contiene voci su queste funzioni

- [ ] **Step 1: Suite completa** — `cd Packages && swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento (prima del lavoro: 488 test dell'app + gli altri target).
- [ ] **Step 2: Prova dal vivo** — con DT Hub (build Debug) e un modello MLX (es. Qwen3-VL 8B 4bit): i quattro punti del §8 della spec. **L'utente ha la sua copia dell'app aperta: dargli le prove a mano, non pilotare l'interfaccia.**
- [ ] **Step 3: README** — aggiungere in «What DT Hub adds» una riga: «**Prompt tools** — *Enhance Prompt* rewrites your prompt for the selected model's family and *Generate Prompt* writes one from the start image, both with the local language model.» Se il README ha uno screenshot di queste card, segnalarlo all'utente (gli screenshot pubblicati si cambiano con una commit, con suo via libera).
- [ ] **Step 4: Commit**
  ```bash
  git add README.md
  git commit -m "docs: README, Prompt tools"
  ```
- [ ] **Step 5: Messaggio finale all'utente**, nel formato del briefing §6: cosa è stato fatto e cosa provare; «Decisioni che ho preso» (con il costo se sbagliate); «Rinviati» (Stop dell'LLM, negativo da solo, interruttore booru, ridimensionamento delle immagini grandi, con il file del backlog); richiesta esplicita di via libera prima di unire in `main` e prima di ogni push/release.

---

## Autorevisione

- **Copertura della spec:** §3.1 → Task 1; §3.2 (system, enhance, describe) → Task 2; parser → Task 3; §3.3 → Task 4; §3.4, testi, errori → Task 5; §6 test → Task 1–4; §8 prove a mano → Task 6.
- **Coerenza dei tipi:** `PromptPair`/`PromptRequest` nascono nel Task 2; `parse(_:)` (Task 3) non ha `family` (spec §3.2 allineata): la scelta del negativo sta nell'assistente (Task 4).
- **Proporzione:** nessun corpo di funzione è scritto nel piano tranne le stringhe fissate dalla spec.
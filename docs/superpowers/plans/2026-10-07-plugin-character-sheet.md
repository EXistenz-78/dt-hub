# Plug-in Character Sheet — Piano di implementazione

> **Per chi esegue:** SOTTO-SKILL OBBLIGATORIA: `superpowers:subagent-driven-development` (consigliata) oppure `superpowers:executing-plans`. I passi usano la sintassi a caselle (`- [ ]`).

**Obiettivo:** un plug-in di DT Hub che, da una sola immagine di un personaggio, prepara in Generazione un foglio di design per Qwen Image 2.1: immagine nel Moodboard, canvas 2304×1536 e prompt (statico, oppure scritto da un LLM locale).

**Architettura:** un pacchetto come Sphere Light (`Plugins/CharacterSheet/`, libreria dinamica con alias di modulo). La logica sta in tipi puri testati con `swift test` (`CSTemplates`, `CSBrief`, `CSAnswer`, `CSMessages`, `CSRunner` con closure, `CSState`); il tab SwiftUI e il plug-in sono un guscio sottile. Il testo del master prompt e del prompt statico sta in **due file fuori dal repo**, estratti dal JSON di ComfyUI da uno script.

**Tecnologie:** Swift 6.2, Swift Testing (`import Testing`), SwiftUI/AppKit, `DTHubPluginKit` e `DTHubDesign` (PluginKit del repo). Python 3 per lo script di estrazione.

**Spec:** `docs/superpowers/specs/2026-10-07-plugin-character-sheet-design.md` (leggerla prima: i valori esatti delle richieste e delle opzioni sono lì, §3.2).

## Vincoli globali

- Si lavora sul ramo `character-sheet` (già creato da `main`, con la spec). **Non si unisce in `main` e non si fa push/release senza un «unisci» / via libera esplicito dell'utente.**
- Si aggiungono i file **per nome** (`git add <file>`): mai `git add -A` né `git add docs`; `.serena/`, `Screenshot/` e il briefing sono esclusi da git in locale. `docicon.psd` non si tocca.
- **Nel repo non entra nessun testo del master prompt o del prompt statico dell'autore del workflow** (nemmeno nei test: i test usano testi inventati). Neppure nei commenti, nel README o negli esempi.
- Piattaforma: macOS 26, Swift 6.2, Apple Silicon. Il pacchetto del plug-in dipende solo da `PluginKit` (`../../PluginKit`); nessuna modifica all'app né a `PluginKit`.
- Id `com.exiztenz.dthub.charactersheet`, nome «Character Sheet», `families: ["qwen_image_2.1"]`, simbolo SF `person.text.rectangle`, classe di ingresso `CharacterSheetEntry`.
- Testi dell'interfaccia in italiano e inglese nella tabella `L` (nessun `.strings`: un bundle di plug-in ha solo la libreria). Codice, commenti e prompt per l'LLM in inglese. README del plug-in in inglese.
- Test: `cd Plugins/CharacterSheet && swift test 2>&1 | grep -E "Test run with|error:"`. I test che toccano `@MainActor` vanno marcati `@MainActor`; niente `UserDefaults` nei test (la memoria della scelta è un file in una cartella temporanea).
- `DTHubLanguageModel` e `DTHubContext` hanno solo `Decodable` (nessun init pubblico): nei test si creano decodificando un JSON.
- Nei testi pubblici (README) non si dice che DT Hub «sostituisce» l'interfaccia di Draw Things.

## Review Focus

Casi che la spec implica e nessun test «felice» esercita; ognuno ha il suo test nel task indicato.

1. Nome del personaggio vuoto, di soli spazi, con virgolette, oppure uguale a `{{name}}`: mai un segnaposto nel prompt, mai una sostituzione ricorsiva (Task 1).
2. Il PE I2I risponde con un JSON che non ha il prompt (solo `ratio_follow` o `wh_ratio`): il campo prompt non deve ricevere il JSON (Task 3).
3. `system_prompt.txt` del PE presente ma vuoto o di soli spazi: conta come mancante (Task 2).
4. Immagine con percorso con spazi, estensione insolita, o già copiata prima: la copia sovrascrive, il Moodboard riceve sempre il percorso copiato (Task 5).
5. «Prepara» premuto due volte, o senza modello con visione, o prima del primo `context` (nessuna cartella temporanea): nessuna doppia richiesta, riga chiara, nessun `contribute` (Task 5, Task 6).

---

## Struttura dei file

| File | Responsabilità |
|---|---|
| `Plugins/CharacterSheet/Package.swift` (nuovo) | pacchetto, alias dei moduli del kit e del design system |
| `Sources/CharacterSheet/CSTemplates.swift` (nuovo) | cartella dei due file, lettura, segnaposto `{{name}}` |
| `Sources/CharacterSheet/CSBrief.swift` (nuovo) | la richiesta all'LLM (forma generica e forma PE I2I) e le impostazioni |
| `Sources/CharacterSheet/CSAnswer.swift` (nuovo) | legge la risposta (testo o JSON) |
| `Sources/CharacterSheet/CSMessages.swift` (nuovo) | i corpi di `contribute` |
| `Sources/CharacterSheet/Strings.swift` (nuovo) | tabella `L`, italiano e inglese |
| `Sources/CharacterSheet/CSRunner.swift` (nuovo) | la sequenza di «Prepara», con closure |
| `Sources/CharacterSheet/CSState.swift` (nuovo) | stato osservato del tab e memoria della scelta |
| `Sources/CharacterSheet/CharacterSheetPlugin.swift`, `CharacterSheetView.swift` (nuovi) | plug-in e tab |
| `Tests/CharacterSheetTests/*.swift` (nuovi) | un file di test per ogni file di logica |
| `Plugins/CharacterSheet/Scripts/build.sh`, `Scripts/extract-from-workflow.py` (nuovi) | bundle e estrazione dei due testi |
| `Plugins/CharacterSheet/README.md`, `Plugins/README.md` (nuovo/modifica) | documentazione in inglese |

---

### Task 1: Pacchetto e file di testo — `CSTemplates`

**Files:**
- Create: `Plugins/CharacterSheet/Package.swift`
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSTemplates.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSTemplatesTests.swift`

**Interfaces:**
- Consumes: nulla.
- Produces (usato dai Task 5, 6, 8):
  ```swift
  enum CSTemplateFile: String, CaseIterable { case master = "master-prompt.txt", staticPrompt = "static-prompt.txt" }
  enum CSTemplateError: Error, Equatable { case missing(CSTemplateFile), empty(CSTemplateFile) }
  enum CSTemplates {
    static let fallbackName = "CHARACTER"
    static var defaultFolder: URL   // ~/Library/Application Support/DT Hub/Data/CharacterSheet
    static func load(_ file: CSTemplateFile, from folder: URL) -> Result<String, CSTemplateError>
    static func fill(_ text: String, name: String) -> String
  }
  ```

- [ ] **Step 1: Scrivere il pacchetto.** `Package.swift` copiato da `Plugins/SphereLight/Package.swift` con nome, prodotto e target `CharacterSheet`, alias `CharacterSheetKit` e `CharacterSheetDesign`, e `testTarget(name: "CharacterSheetTests", dependencies: ["CharacterSheet"])`. Il commento in testa rimanda alla spec.

- [ ] **Step 2: Scrivere i test che falliscono** (`CSTemplatesTests`, cartelle in `FileManager.default.temporaryDirectory` con `UUID`, rimosse con `defer`):
  - `loadReturnsTheTextWithoutOuterWhitespace`: file `master-prompt.txt` con `"\n  Role text.  \n"` ⇒ `.success("Role text.")`.
  - `loadOfAMissingFileSaysWhich`: cartella vuota, `.staticPrompt` ⇒ `.failure(.missing(.staticPrompt))`.
  - `loadOfAWhitespaceOnlyFileIsEmpty`: file di soli spazi e a capo ⇒ `.failure(.empty(.master))`.
  - `fillReplacesEveryPlaceholder`: `fill("A {{name}} and {{name}}", name: "Ayaka") == "A Ayaka and Ayaka"`.
  - `fillTrimsTheName`: `fill("{{name}}", name: "  Ayaka \n") == "Ayaka"`.
  - `anEmptyOrBlankNameBecomesCHARACTER` (Review Focus 1): `fill("{{name}}", name: "")` e `name: "   "` ⇒ `"CHARACTER"`.
  - `aNameThatLooksLikeThePlaceholderIsInsertedOnce` (Review Focus 1): `fill("x {{name}} y", name: "{{name}}") == "x {{name}} y"` (una sola passata: nessuna ricorsione).
  - `aNameWithQuotesIsInsertedAsIs` (Review Focus 1): `fill("Title \"{{name}}\"", name: "Ayaka \"the\" Kamisato") == "Title \"Ayaka \"the\" Kamisato\""`.
  - `textWithoutAPlaceholderIsUnchanged`: `fill("No placeholder", name: "Ayaka") == "No placeholder"`.
  - `defaultFolderEndsWithTheDataPath`: `defaultFolder.path.hasSuffix("DT Hub/Data/CharacterSheet")`.

- [ ] **Step 3: Lanciare e vedere il fallimento** — `cd Plugins/CharacterSheet && swift test --filter CSTemplatesTests 2>&1 | grep -E "Test run with|error:"` → errore di compilazione (i tipi non esistono). La prima volta il pacchetto scarica/compila `PluginKit`: può volerci qualche minuto.

- [ ] **Step 4: Implementare `CSTemplates`** nel file indicato con le firme sopra. `fill` fa una sola passata (`replacingOccurrences(of:with:)` sul testo originale, non sul risultato). `load` legge con `String(contentsOf:encoding: .utf8)`; qualunque errore di lettura ⇒ `.missing`.

- [ ] **Step 5: Lanciare i test** → tutti verdi.

- [ ] **Step 6: Commit**
  ```bash
  git add Plugins/CharacterSheet/Package.swift Plugins/CharacterSheet/Sources/CharacterSheet/CSTemplates.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSTemplatesTests.swift
  git commit -m "feat(character-sheet): pacchetto e file di testo del plug-in"
  ```

---

### Task 2: La richiesta all'LLM — `CSBrief`

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSBrief.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSBriefTests.swift`

**Interfaces:**
- Consumes: `DTHubLLMOptions` (DTHubPluginKit: `temperature, topP, topK, presencePenalty, maxTokens, thinking, timeout`, tutti opzionali).
- Produces (usato dal Task 5):
  ```swift
  struct CSRequest: Equatable { let model: String; let prompt: String; let images: [String]; let system: String; let options: DTHubLLMOptions }
  enum CSBrief {
    static let peSystemFileNames = ["system_prompt.txt", "system_prompt_i2i.txt"]
    static func isPEI2I(_ modelName: String) -> Bool
    static func peSystem(inFolder folder: URL, read: (URL) -> String?) -> String?
    static func generic(model: String, image: String, name: String, master: String) -> CSRequest
    static func peI2I(model: String, image: String, name: String, master: String, peSystem: String) -> CSRequest
  }
  ```

- [ ] **Step 1: Scrivere i test che falliscono** (`CSBriefTests`; i valori vengono dalla spec §3.2):
  - `peDetectionReadsTheModelName`: `isPEI2I` vero per `"Qwen-Image-2.1-PE-I2I-MLX-4bit"` e `"qwen3.5_9b_qwen_image_2.1_pe_i2i"`; falso per `"Qwen-Image-2.1-PE-T2I-MLX-4bit"`, `"Qwen3-VL-8B-Instruct-4bit"` e `""`.
  - `genericRequest`: `generic(model: "Qwen3-VL-8B-Instruct-4bit", image: "/t/ref.png", name: "Ayaka", master: "MASTER")` ⇒ `model` uguale, `system == "MASTER"`, `prompt == "Entity name: Ayaka"`, `images == ["/t/ref.png"]`, `options == DTHubLLMOptions(temperature: 0.9, topP: 0.95, topK: 20, maxTokens: 16384, thinking: true, timeout: 900)`.
  - `genericRequestWithAnEmptyNameUsesCHARACTER`: nome `"  "` ⇒ `prompt == "Entity name: CHARACTER"`.
  - `peRequest`: `peI2I(model: "Qwen-Image-2.1-PE-I2I-MLX-4bit", image: "/t/ref.png", name: "Ayaka", master: "MASTER", peSystem: "PE SYSTEM")` ⇒ `system == "PE SYSTEM"`, `prompt == "MASTER\n\nEntity name: Ayaka"`, `images == ["/t/ref.png"]`, `options == DTHubLLMOptions(temperature: 1.0, topP: 0.95, topK: 20, presencePenalty: 0, maxTokens: 24000, thinking: true, timeout: 1800)`.
  - `peSystemTakesTheFirstNonEmptyFile`: la lettura finta restituisce per `system_prompt.txt` il valore `"  \n"` e per `system_prompt_i2i.txt` `"Text\n"` ⇒ `"Text"`.
  - `peSystemWithNoUsableFileIsNil` (Review Focus 3): ambedue vuoti o di soli spazi ⇒ `nil`; ambedue assenti ⇒ `nil`.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter CSBriefTests` → errore di compilazione.

- [ ] **Step 3: Implementare `CSBrief.swift`.** `isPEI2I`: nome in minuscolo con `-` e `.` letti come `_` (come `PEPlanner.normalized` di Prompt Master), contiene `qwen_image_2_1_pe_i2i`. Il nome vuoto o di soli spazi diventa `CSTemplates.fallbackName` (nome tagliato agli estremi). `peSystem` prova i file nell'ordine di `peSystemFileNames`, tagliati agli estremi, e prende il primo non vuoto. Due costanti private per le opzioni, con un commento sul perché (impostazioni dell'autore del workflow e di Qwen).

- [ ] **Step 4: Lanciare i test** → verdi.

- [ ] **Step 5: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/CSBrief.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSBriefTests.swift
  git commit -m "feat(character-sheet): richieste all'LLM, forma generica e forma PE I2I"
  ```

---

### Task 3: La risposta — `CSAnswer`

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSAnswer.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSAnswerTests.swift`

**Interfaces:**
- Consumes: nulla. Riferimento da seguire: `Plugins/PromptMaster/Sources/PromptMaster/AnswerParser.swift` (stessa logica, **copiata**: il plug-in è un pacchetto separato), senza `negative` e `ratio`.
- Produces (usato dal Task 5): `enum CSAnswer { static func parse(_ raw: String) -> String? }`.

- [ ] **Step 1: Scrivere i test che falliscono** (`CSAnswerTests`):
  - `plainProse`: `parse("  Ten sections.\n")` ⇒ `"Ten sections."`.
  - `blankLinesBetweenParagraphsStay`: `parse("1. A\n\n2. B")` ⇒ `"1. A\n\n2. B"`.
  - `oneQuotePairIsRemoved`: `parse("\"A\"")` ⇒ `"A"`; `parse("“A”")` ⇒ `"A"`; `parse("\"A\" and \"B\"")` resta uguale.
  - `rewrittenPromptOfTheEnhancer`: `parse("{\"rewritten_prompt\": \"Make a sheet.\", \"wh_ratio\": \"3:2\", \"ratio_follow\": \"\"}")` ⇒ `"Make a sheet."`.
  - `promptAliases`: `{"prompt":"x"}` e `{"positive_prompt":"x"}` ⇒ `"x"`.
  - `fencedJSON`: ```` ```json\n{"rewritten_prompt": "x"}\n``` ```` ⇒ `"x"`.
  - `jsonSurroundedByChatter`: `parse("Here: {\"rewritten_prompt\": \"x\"} Done.")` ⇒ `"x"`.
  - `thinkingBlockIsRemoved`: `parse("<think>hmm</think>Sheet")` ⇒ `"Sheet"`.
  - `unclosedThinkingGivesNil`: `parse("<think>I should")` ⇒ `nil`.
  - `emptyGivesNil`: `""`, `"   \n"`, ```` "```\n```" ```` ⇒ `nil`.
  - `jsonWithoutAPromptGivesNil` (Review Focus 2): `parse("{\"ratio_follow\": \"<image1>\"}")` ⇒ `nil` e `parse("{\"wh_ratio\": \"3:2\", \"rewritten_prompt\": \"\"}")` ⇒ `nil` (diversamente da `AnswerParser`, qui un oggetto JSON valido senza prompt non è mai il prompt).
  - `malformedJSONIsTakenAsTheText`: `parse("{\"rewritten_prompt\": \"x\"")` ⇒ lo stesso testo.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter CSAnswerTests` → errore di compilazione.

- [ ] **Step 3: Implementare `parse`** con helper privati (`withoutThinking`, `withoutFences`, `unquoted`, `clean`) uguali a quelli di `AnswerParser.swift`. L'unica differenza: se il testo (dopo fence e `<think>`) contiene un oggetto JSON tra la prima `{` e l'ultima `}` che si legge come JSON ma non ha nessuna chiave di prompt non vuota (`rewritten_prompt`, `prompt`, `positive_prompt`), il risultato è `nil`. JSON non leggibile ⇒ si tratta come testo.

- [ ] **Step 4: Lanciare i test** → verdi.

- [ ] **Step 5: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/CSAnswer.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSAnswerTests.swift
  git commit -m "feat(character-sheet): lettura della risposta dell'LLM"
  ```

---

### Task 4: I messaggi — `CSMessages`

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSMessages.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSMessagesTests.swift`

**Interfaces:**
- Consumes: nulla.
- Produces (usato dal Task 5):
  ```swift
  enum CSMessages {
    static let width = 2304, height = 1536
    static let referenceFileStem = "com.exiztenz.dthub.charactersheet-reference"
    static func moodboard(imagePath: String) -> [String: Any]
    static func size() -> [String: Any]
    static func prompt(_ text: String) -> [String: Any]
  }
  ```
  Forme (contratto 1, `PluginKit/README.md`): `{"moodboard": [{"path": imagePath, "name": "Character reference"}]}`; `{"fields": {"width": 2304, "height": 1536}}`; `{"fields": {"prompt": text}}`.

- [ ] **Step 1: Scrivere i test che falliscono** (`CSMessagesTests`; i corpi si confrontano passando per `JSONSerialization` e rileggendo, perché sono `[String: Any]`):
  - `moodboardBody`: un solo elemento con `path` e `name == "Character reference"`; nessun'altra chiave in cima.
  - `sizeBody`: `fields.width == 2304`, `fields.height == 1536`, nessuna altra chiave in `fields`.
  - `promptBody`: `fields.prompt` uguale al testo, anche con virgolette, a capo e caratteri non ASCII; nessuna altra chiave in `fields`.
  - `sizeIsThreeToTwoAndMultipleOf64`: `width * 2 == height * 3`, `width % 64 == 0`, `height % 64 == 0`.
  - `allBodiesSerialize`: `JSONSerialization.isValidJSONObject` vero per i tre.

- [ ] **Step 2: Lanciare e vedere il fallimento**, **Step 3: Implementare** `CSMessages.swift`, **Step 4: Lanciare i test** → verdi (`swift test --filter CSMessagesTests`).

- [ ] **Step 5: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/CSMessages.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSMessagesTests.swift
  git commit -m "feat(character-sheet): messaggi di contribute (Moodboard, dimensioni, prompt)"
  ```

---

### Task 5: Testi e sequenza — `L` e `CSRunner`

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/Strings.swift`
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSRunner.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSRunnerTests.swift`

**Interfaces:**
- Consumes: `CSTemplates`, `CSTemplateFile`, `CSTemplateError` (Task 1); `CSBrief`, `CSRequest` (Task 2); `CSAnswer.parse` (Task 3); `CSMessages` (Task 4); `DTHubLanguageModel` (`name`, `path`, `supportsImages`), `DTHubLLMAnswer` (`.text(String)`, `.failure(String)`).
- Produces (usato dai Task 6 e 8):
  ```swift
  enum L { enum Key: CaseIterable {…}; static func text(_:italian:) / format(_:_:italian:) / isDefined(_:italian:); static var systemIsItalian: Bool }
  struct CSJob: Equatable { var imagePath: String?; var name: String; var useStatic: Bool; var model: DTHubLanguageModel?; var tempFolder: String? }
  struct CSOutcome: Equatable { var line: String; var succeeded: Bool }
  @MainActor struct CSRunner {
    var contribute: @MainActor ([String: Any]) async -> [String: Any]?
    var ask: @MainActor (CSRequest) async -> DTHubLLMAnswer
    var copyImage: (_ source: String, _ tempFolder: String) throws -> String
    var readTemplate: (CSTemplateFile) -> Result<String, CSTemplateError>
    var readPESystem: (DTHubLanguageModel) -> String?
    var now: () -> Date
    var templatesFolder: String      // per i messaggi d'errore
    var italian: Bool
    func prepare(_ job: CSJob, progress: (String) -> Void) async -> CSOutcome
    static func copyIntoFolder(_ source: String, _ tempFolder: String) throws -> String   // l'implementazione vera di copyImage
  }
  ```

**Testi (`L.Key`), inglese ⇒ italiano** (i test controllano che ogni chiave sia definita in entrambe le lingue; quelle con `%@`/`%d` si riempiono con `format`):
`needImage` «Choose an image first.» / «Prima scegli un'immagine.»; `noFolder` «No picture folder yet: switch the plug-in on first.» / «La cartella delle immagini non c'è ancora: prima accendi il plug-in.»; `templateMissing` «%@ is missing in %@.» / «Manca %@ in %@.»; `templateEmpty` «%@ is empty.» / «%@ è vuoto.»; `noVisionModel` «No language model with vision: use the static prompt, or add one to the models folder.» / «Nessun modello con visione: usa il prompt statico, oppure aggiungine uno alla cartella dei modelli.»; `peSystemMissing` «%@ needs its system_prompt.txt next to the weights.» / «%@ ha bisogno del suo system_prompt.txt accanto ai pesi.»; `sendingImage` «Sending the image to the Moodboard…» / «Mando l'immagine al Moodboard…»; `writingBrief` «The model is writing the brief…» / «Il modello scrive il brief…»; `doneStatic` «Static prompt written. Image in the Moodboard, canvas 2304×1536.» / «Prompt statico scritto. Immagine nel Moodboard, canvas 2304×1536.»; `doneLLM` «Prompt written: %d words in %d s.» / «Prompt scritto: %d parole in %d s.»; `emptyAnswer` «The model gave no usable answer.» / «Il modello non ha dato una risposta utilizzabile.»; `llmFailed` «The model did not answer: %@» / «Il modello non ha risposto: %@»; `notAnswered` «No answer from the app.» / «Nessuna risposta dall'app.»; `copyFailed` «Could not copy the image.» / «Non si è potuta copiare l'immagine.»; e per il tab (usati nel Task 8) `chooseImage` «Choose…» / «Scegli…», `characterName` «Character name» / «Nome del personaggio», `staticPrompt` «Static prompt» / «Prompt statico», `llmModel` «Language model» / «Modello LLM», `prepare` «Prepare» / «Prepara», `openFolder` «Open folder» / «Apri cartella», `dropImage` «Drop an image here» / «Trascina qui un'immagine», `noModelsShown` «No model with vision» / «Nessun modello con visione», `active` «active» / «attivo» e `inactive` «not active» / «non attivo».

- [ ] **Step 1: Scrivere i test che falliscono** (`CSRunnerTests`, `@MainActor`; un `final class Spy` come in `SphereSenderTests` registra i corpi di `contribute`, le richieste `ask` e i messaggi di avanzamento, e risponde con valori configurabili; un helper decodifica `DTHubLanguageModel` da JSON `{"name","path","supportsImages"}`; la cartella temporanea e un'immagine finta stanno in una cartella con `UUID`):
  - `everyWordIsInBothLanguages`: ogni `L.Key` è definita in italiano e in inglese.
  - `staticModeWritesTheStaticPromptWithoutAskingTheModel`: `readTemplate(.staticPrompt)` ⇒ `"Sheet for {{name}}"`, nome `"Ayaka"` ⇒ `contribute` riceve in ordine Moodboard, dimensioni, `{"fields":{"prompt":"Sheet for Ayaka"}}`; `ask` mai chiamata; `outcome.succeeded`; riga `doneStatic`.
  - `genericModelRequestUsesTheMasterAsSystem`: modello `Qwen3-VL-8B-Instruct-4bit`, `readTemplate(.master)` ⇒ `"MASTER"`, risposta `.text("Ten sections")` ⇒ la richiesta passata a `ask` è esattamente `CSBrief.generic(model:image:name:master:)` con `image` = il percorso **copiato**; il prompt scritto è `"Ten sections"`; riga `doneLLM` con 2 parole.
  - `peModelUsesItsOwnSystemAndTheMasterAsInstruction`: modello `Qwen-Image-2.1-PE-I2I-MLX-4bit`, `readPESystem` ⇒ `"PE SYSTEM"`, risposta `{"rewritten_prompt":"Sheet"}` ⇒ richiesta uguale a `CSBrief.peI2I(…)`; prompt scritto `"Sheet"`.
  - `aPEWithoutItsSystemPromptStopsBeforeAsking` (Review Focus 3): `readPESystem` ⇒ `nil` ⇒ errore `peSystemMissing` col nome del modello, `ask` mai chiamata e **nessun** `contribute` in assoluto (tutti i controlli che non toccano l'app, il `system_prompt.txt` del PE compreso, vengono prima della copia e del Moodboard).
  - `aMissingTemplateStopsBeforeTouchingTheApp`: `readTemplate` ⇒ `.failure(.missing(.master))` ⇒ riga `templateMissing` con `master-prompt.txt` e `templatesFolder`; zero `contribute`, zero `ask`. Lo stesso per `.empty` e per il file statico in modalità statica.
  - `noImageStopsEverything`: `imagePath: nil` ⇒ `needImage`, zero chiamate.
  - `noTempFolderStopsEverything` (Review Focus 5): `tempFolder: nil` ⇒ `noFolder`, zero chiamate.
  - `llmModeWithoutAModelStopsEverything` (Review Focus 5): `useStatic: false`, `model: nil` ⇒ `noVisionModel`, zero chiamate.
  - `anEmptyAnswerLeavesThePromptAlone`: risposta `.text("<think>x")` ⇒ riga `emptyAnswer`, `outcome.succeeded == false`; `contribute` ha ricevuto Moodboard e dimensioni ma **non** il prompt.
  - `aFailureOfTheAppIsReported`: `ask` ⇒ `.failure("no model chosen")` ⇒ riga `llmFailed` con quel motivo; nessun prompt scritto.
  - `aContributeErrorStopsTheSequence`: la prima risposta è `["type": "error", "text": "boom"]` ⇒ la riga contiene `boom`; nessuna chiamata successiva a `contribute` né a `ask`; con risposta `nil` ⇒ `notAnswered`.
  - `progressLinesFollowTheSteps`: in modalità LLM `progress` riceve `sendingImage` poi `writingBrief`.
  - `theLineShowsWordsAndSeconds`: `now` restituisce due istanti a 38 s di distanza; prompt di 1.420 parole ⇒ `Prompt written: 1420 words in 38 s.`
  - `copyIntoFolderCopiesAndOverwrites` (Review Focus 4): immagine `my ref.PNG` (spazio nel nome, estensione maiuscola) copiata come `com.exiztenz.dthub.charactersheet-reference.PNG` nella cartella; una seconda copia di un altro file con la stessa estensione sovrascrive senza errore e il contenuto è quello nuovo; un'origine inesistente lancia.

- [ ] **Step 2: Lanciare e vedere il fallimento** — `swift test --filter CSRunnerTests` → errore di compilazione.

- [ ] **Step 3: Implementare `Strings.swift`** sul modello di `Plugins/SphereLight/Sources/SphereLight/Strings.swift` (stessa struttura `L`, tabelle `en`/`it`) con le chiavi sopra.

- [ ] **Step 4: Implementare `CSRunner.swift`.** `prepare` esegue, nell'ordine della spec §3.5: controlli senza effetti (immagine, cartella temporanea, modello se non statico, file di testo, `system_prompt.txt` del PE) ⇒ copia ⇒ `contribute(moodboard)` ⇒ `contribute(size)` ⇒ statico: `contribute(prompt(fill(...)))` / LLM: `progress(writingBrief)`, richiesta, `CSAnswer.parse`, `contribute(prompt)`. Una risposta di `contribute` con `type == "error"` ferma con il suo `text`; `nil` ferma con `notAnswered`. Il modello è PE se `CSBrief.isPEI2I(model.name)`. `copyIntoFolder` crea la cartella se manca, rimuove una copia precedente e copia il file; nome `CSMessages.referenceFileStem + "." + estensione dell'origine`.

- [ ] **Step 5: Lanciare i test** → verdi; poi tutta la suite del plug-in: `swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento.

- [ ] **Step 6: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/Strings.swift Plugins/CharacterSheet/Sources/CharacterSheet/CSRunner.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSRunnerTests.swift
  git commit -m "feat(character-sheet): sequenza di Prepara e testi italiano/inglese"
  ```

---

### Task 6: Stato del tab e memoria — `CSState`

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CSState.swift`
- Test: `Plugins/CharacterSheet/Tests/CharacterSheetTests/CSStateTests.swift`

**Interfaces:**
- Consumes: `DTHubContext`, `DTHubLanguageModel` (DTHubPluginKit); `CSTemplates.defaultFolder` (Task 1).
- Produces (usato dal Task 8):
  ```swift
  struct CSSettings: Codable, Equatable { var useStatic: Bool; var model: String? }
  struct CSSettingsStore { var folder: URL; func load() -> CSSettings; func save(_ settings: CSSettings) }   // folder/settings.json
  @MainActor final class CSState: ObservableObject {
    @Published var active: Bool
    @Published var imagePath: String?
    @Published var name: String
    @Published var useStatic: Bool        // salva a ogni cambio
    @Published var selectedModel: String? // salva a ogni cambio
    @Published var status: String
    @Published private(set) var busy: Bool
    private(set) var tempFolder: String?
    private(set) var family: String?
    private(set) var languageModels: [DTHubLanguageModel]
    init(store: CSSettingsStore)
    var visionModels: [DTHubLanguageModel] { get }
    var resolvedModel: DTHubLanguageModel? { get }      // quello scelto se c'è tra i visionModels, altrimenti il primo, altrimenti nil
    func update(from context: DTHubContext)
    func beginPrepare() -> Bool                          // false se già busy; altrimenti busy = true
    func endPrepare(status: String)
    var job: CSJob { get }                               // con resolvedModel e tempFolder
  }
  ```

- [ ] **Step 1: Scrivere i test che falliscono** (`CSStateTests`, `@MainActor`; cartella temporanea; il contesto si decodifica da JSON `{"family":"qwen_image_2.1","tempFolder":"/t","languageModels":[…]}`):
  - `visionModelsKeepsOnlyThoseWithImages`: tre modelli, uno senza visione ⇒ due, nell'ordine dell'app.
  - `theSavedChoiceIsUsedWhenItExists`: `selectedModel` salvato = secondo modello con visione ⇒ `resolvedModel` è il secondo.
  - `aMissingSavedModelFallsBackToTheFirstWithVision`: modello salvato che non c'è più ⇒ il primo.
  - `noVisionModelGivesNil`: solo modelli senza visione, o `languageModels` assente nel contesto ⇒ `resolvedModel == nil`.
  - `choicesSurviveARestart`: cambiare `useStatic` e `selectedModel`, creare un nuovo `CSState` con lo stesso store ⇒ stessi valori; immagine e nome ripartono vuoti.
  - `firstRunDefaults`: store senza file ⇒ `useStatic == false`, `selectedModel == nil`.
  - `aCorruptSettingsFileFallsBackToDefaults`: `settings.json` con testo non JSON ⇒ valori di default, nessun crash.
  - `contextFillsTheFolderAndTheFamily`: `update(from:)` imposta `tempFolder` e `family`; un contesto senza `languageModels` svuota l'elenco.
  - `onlyOnePrepareAtATime` (Review Focus 5): `beginPrepare()` vero, poi falso finché non arriva `endPrepare(status:)`; dopo di essa di nuovo vero e `status` aggiornato.
  - `jobCarriesWhatTheTabHolds`: `job` ha immagine, nome, interruttore, `resolvedModel` e `tempFolder` correnti.

- [ ] **Step 2: Lanciare e vedere il fallimento**, **Step 3: Implementare** `CSState.swift` (`ObservableObject` come `SLRState` di Sphere Light; `didSet` di `useStatic` e `selectedModel` salvano con lo store; `CSSettingsStore` scrive `settings.json` in modo atomico e crea la cartella; lettura leniente con `try?`), **Step 4: Lanciare i test** → verdi (`swift test --filter CSStateTests`, poi tutta la suite).

- [ ] **Step 5: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/CSState.swift Plugins/CharacterSheet/Tests/CharacterSheetTests/CSStateTests.swift
  git commit -m "feat(character-sheet): stato del tab e memoria della scelta"
  ```

---

### Task 7: Script di estrazione — `extract-from-workflow.py`

**Files:**
- Create: `Plugins/CharacterSheet/Scripts/extract-from-workflow.py`

**Interfaces:**
- Consumes: il JSON di ComfyUI del workflow (formato con `definitions.subgraphs[]`, ciascuno con `name` e `nodes[]`; i nodi hanno `type`, `title`, `widgets_values`).
- Produces: `master-prompt.txt` e `static-prompt.txt` in `--out` (usati dal Task 5 tramite `CSTemplates`).

- [ ] **Step 1: Scrivere lo script.** Argomenti `--source <workflow.json>` (obbligatorio, nessun percorso personale come default) e `--out <cartella>` (default `~/Library/Application Support/DT Hub/Data/CharacterSheet`). Cerca il sotto-grafo di nome `Character Sheet Prompt Maker`; il **master** è il `widgets_values[0]` del nodo `PrimitiveStringMultiline` con titolo `Prompt Template (Important)`; lo **statico** è il `widgets_values[0]` dell'altro nodo `PrimitiveStringMultiline` del sotto-grafo. Nel statico sostituisce la frase `Extract character name (or use "CHARACTER")` con `Character name "{{name}}"` (esce con errore se la frase non c'è: l'autore potrebbe cambiare il testo). Esce con messaggio e codice ≠ 0 se manca il sotto-grafo, uno dei due nodi, o un testo è vuoto. Crea la cartella; non sovrascrive file esistenti senza `--force`. Stampa i due percorsi e le lunghezze in caratteri.

- [ ] **Step 2: Provarlo su una cartella di prova** — `python3 Plugins/CharacterSheet/Scripts/extract-from-workflow.py --source ~/Downloads/QwenImage21Character_qwenImage21V30/Character_Sheet_Production.json --out "$TMPDIR/cs-files"`. Atteso: due righe con i percorsi e lunghezze (circa 9.500 e 2.500 caratteri); `grep -c "{{name}}" "$TMPDIR/cs-files/static-prompt.txt"` ⇒ `1`; `grep -c "{{name}}" "$TMPDIR/cs-files/master-prompt.txt"` ⇒ `0`; rilanciato senza `--force` rifiuta di sovrascrivere; con una `--source` che non è un workflow esce con errore.

- [ ] **Step 3: Commit** (i file estratti **non** vanno aggiunti: stanno in `$TMPDIR`)
  ```bash
  git add Plugins/CharacterSheet/Scripts/extract-from-workflow.py
  git commit -m "feat(character-sheet): script che estrae master prompt e prompt statico dal workflow"
  ```

---

### Task 8: Plug-in, tab, bundle e documentazione

**Files:**
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CharacterSheetPlugin.swift`
- Create: `Plugins/CharacterSheet/Sources/CharacterSheet/CharacterSheetView.swift`
- Create: `Plugins/CharacterSheet/Scripts/build.sh`
- Create: `Plugins/CharacterSheet/README.md`
- Modify: `Plugins/README.md` (tabella: una riga per Character Sheet; la frase «Three plug-ins ship…» diventa «Four»; nessun link di scaricamento finché non c'è una release)

**Interfaces:**
- Consumes: tutto quanto sopra; `DTHubPlugin`, `DTHubHost` (`contribute`, `askLanguageModelAnswer(_:images:system:model:options:)`), `DTHubPluginEntry`; design system (`DS`, `DSGroupHeader`, `DSPillButtonStyle`, `dsPanel`).
- Produces: il bundle `CharacterSheet.dthubplugin`. Nulla per altri task.

L'interfaccia non ha test: la verifica è la compilazione, il bundle firmato e la prova a mano (Task 9).

- [ ] **Step 1: `CharacterSheetPlugin.swift`**, sul modello di `SphereLightPlugin.swift`: `manifest` come nei vincoli globali (versione «1.0»), `CSState(store: CSSettingsStore(folder: CSTemplates.defaultFolder))`; `handle`: `context` ⇒ `state.update(from:)`, `activate`/`deactivate` ⇒ `state.active`, il resto ⇒ `unsupported`. Un metodo `prepare()` privato: `guard state.beginPrepare()`, costruisce `CSRunner` con le closure vere (`contribute: host.contribute`; `ask`: `host.askLanguageModelAnswer(request.prompt, images: request.images, system: request.system, model: request.model, options: request.options)`; `copyImage: CSRunner.copyIntoFolder`; `readTemplate: { CSTemplates.load($0, from: CSTemplates.defaultFolder) }`; `readPESystem: { CSBrief.peSystem(inFolder: URL(fileURLWithPath: $0.path), read: { try? String(contentsOf: $0, encoding: .utf8) }) }`; `now: Date.init`; `templatesFolder: CSTemplates.defaultFolder.path`; `italian: L.systemIsItalian`), lancia un `Task` che chiama `runner.prepare(state.job, progress: { state.status = $0 })` e poi `state.endPrepare(status: outcome.line)`. Classe di ingresso `@objc(CharacterSheetEntry) public final class CharacterSheetEntry: DTHubPluginEntry`.

- [ ] **Step 2: `CharacterSheetView.swift`** (`@ObservedObject var state: CSState`, closure `prepare` e `openFolder`): una colonna con `DSGroupHeader`; miniatura dell'immagine (`NSImage(contentsOfFile:)`, riquadro con `L.dropImage` se manca) con il pulsante `L.chooseImage` (`NSOpenPanel`, solo immagini) e il trascinamento (`onDrop` con `public.file-url`); `TextField` per il nome (`L.characterName`); `Toggle` `L.staticPrompt` legato a `state.useStatic`; `Picker` `L.llmModel` sui `state.visionModels` (per nome), disattivato con lo statico, con il testo `L.noModelsShown` se l'elenco è vuoto; pulsante `L.prepare` (`DSPillButtonStyle(prominent: true)`, disattivato senza immagine o con `busy`); pulsante `L.openFolder` (crea la cartella se manca e la apre con `NSWorkspace`); riga di stato `.caption` con spinner mentre `busy`.

- [ ] **Step 3: Compilare e provare** — `cd Plugins/CharacterSheet && swift build 2>&1 | tail -5` → `Build complete!`; poi tutta la suite: `swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento.

- [ ] **Step 4: `Scripts/build.sh`** copiato da `Plugins/SphereLight/Scripts/build.sh` con `CharacterSheet`, id `com.exiztenz.dthub.charactersheet`, `CharacterSheetEntry`, versione `1.0`. Poi: `Plugins/CharacterSheet/Scripts/build.sh "$TMPDIR/cs-plugin"` → stampa il percorso del bundle; `codesign --verify --deep --strict "$TMPDIR/cs-plugin/CharacterSheet.dthubplugin" && echo OK` → `OK`; `ls "$TMPDIR/cs-plugin/CharacterSheet.dthubplugin/Contents"` → c'è `Info.plist` e la libreria.

- [ ] **Step 5: Documentazione.** `Plugins/CharacterSheet/README.md` in inglese, sul modello di quello di Sphere Light: riga «Works with» (Qwen Image 2.1), cosa fa, il tab, come funzionano le due modalità e i due modelli, **dove stanno i due file di testo e come ottenerli con lo script** (`--source` è il workflow JSON dell'utente; il repo non contiene il testo dell'autore), l'avvertenza «inspired by a community ComfyUI workflow for Qwen Image 2.1 character sheets; its prompt texts are not included», come si costruisce e si prova. Riga nella tabella di `Plugins/README.md` (famiglia: **Qwen Image 2.1** only).

- [ ] **Step 6: Commit**
  ```bash
  git add Plugins/CharacterSheet/Sources/CharacterSheet/CharacterSheetPlugin.swift Plugins/CharacterSheet/Sources/CharacterSheet/CharacterSheetView.swift Plugins/CharacterSheet/Scripts/build.sh Plugins/CharacterSheet/README.md Plugins/README.md
  git commit -m "feat(character-sheet): plug-in, tab, bundle e documentazione"
  ```

---

### Task 9: Chiusura — installazione e prove a mano

**Files:** nessuno nel repo (salvo correzioni emerse dai test).

- [ ] **Step 1: Suite del plug-in e dell'app** — `cd Plugins/CharacterSheet && swift test 2>&1 | grep -E "Test run with|error:"` e `cd Packages && swift test 2>&1 | grep -E "Test run with|error:"` → nessun fallimento (l'app non è toccata: i 523 test dell'app restano).
- [ ] **Step 2: Preparare i due file di testo** per l'utente: `python3 Plugins/CharacterSheet/Scripts/extract-from-workflow.py --source ~/Downloads/QwenImage21Character_qwenImage21V30/Character_Sheet_Production.json` (scrive in `~/Library/Application Support/DT Hub/Data/CharacterSheet/`; è la cartella dei dati dell'utente, fuori dal repo). Verificare con `ls -l` che i due file ci siano e non siano vuoti.
- [ ] **Step 3: Installare il plug-in nell'app dell'utente** con il bundle del Task 8 Step 4: **DT Hub chiuso**, poi
  ```bash
  D="$HOME/Library/Application Support/DT Hub/Plug-ins/com.exiztenz.dthub.charactersheet.dthubplugin"
  rm -rf "$D" && cp -R "$TMPDIR/cs-plugin/CharacterSheet.dthubplugin" "$D" && ls "$D"
  ```
  Da dare all'utente in un blocco `bash` a sé (l'app è aperta: non la si pilota). Il plug-in va anche acceso in Preferences › Plug-ins (l'elenco si legge all'avvio).
- [ ] **Step 4: Messaggio finale all'utente**, nel formato del briefing §6, con le **prove a mano** della spec §7: (1) statico + Moodboard + 2304×1536 su Qwen Image 2.1 ⇒ l'identità del foglio; (2) Qwen3-VL 8B con il master prompt (segue o ripete?); (3) Qwen PE I2I con il master come richiesta (lo applica, lo riassume, lo riscrive?); (4) tempi e memoria; (5) artefatti a griglia. «Decisioni che ho preso» (con il costo se sbagliate), «Rinviati» (opzione C, modo A, annullare l'LLM, `VAEDeGrid`; file del backlog), e la richiesta esplicita di via libera prima di unire in `main` e prima di ogni push/release. Ricordare che nel repo non c'è testo dell'autore del workflow, quindi una pubblicazione del plug-in non lo include.

---

## Autorevisione

- **Copertura della spec:** §1–2 → Task 5/8 (comportamento), §3 architettura → Task 1–8, §3.1 → Task 1 e 7, §3.2 → Task 2, §3.3 → Task 3, §3.4 → Task 4, §3.5 → Task 5, §3.6 → Task 6 e 8, §4 errori → Task 5, §5 test → Task 1–6, §7 prove a mano → Task 9.
- **Coerenza dei tipi:** `CSRequest` nasce nel Task 2 e lo consuma `CSRunner` (Task 5); `CSJob` nasce nel Task 5 e lo produce `CSState.job` (Task 6); `CSTemplateFile`/`CSTemplateError` nascono nel Task 1; `L.Key` del tab sono nel Task 5 e li usa il Task 8.
- **Proporzione:** nessun corpo di funzione è scritto nel piano; solo firme, nomi dei test, asserzioni e i valori fissati dalla spec.

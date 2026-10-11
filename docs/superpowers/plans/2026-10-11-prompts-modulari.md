# Prompt modulari — fase 1 (DT Hub) — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** I testi che guidano l'LLM in Migliora/Genera Prompt escono dal codice e diventano file Markdown in `~/Library/Application Support/DT Hub/Data/DTHub/` (Rules per compito + Family per famiglia + livello utente in `custom/`), uniti solo all'invio; il testo inviato all'LLM resta identico a quello di oggi.

**Architecture:** Un lettore di file con intestazione (`PromptFile`) e una `PromptLibrary` in HubCore che legge i file a ogni richiesta (disco se valido, altrimenti la copia incorporata), assembla Rules + Family + custom e riscrive i file di base all'avvio. `PromptBrief`, `PromptAssistant` e il menu delle famiglie passano dalla libreria; `PromptGuides.swift` sparisce. Il contesto dei plug-in riceve in più il Family prompt (aggiunta facoltativa al contratto 1) e il kit dei plug-in ha la sua copia del lettore, per la fase 2.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI (Preferenze), pacchetti `HubCore` / `HubKit`, `PluginKit`.

**Spec:** `docs/superpowers/specs/2026-10-11-prompts-modulari-design.md` (fasi 2 e 3 — Prompt Master, Character Sheet, I4, AI Assistant — avranno piani a parte).

## Global Constraints

- Formato sempre **Markdown**; cartella `~/Library/Application Support/DT Hub/Data/DTHub/` con `family/`, `rules/`, `custom/`.
- File con intestazione `---` / righe `chiave: valore` / `---` e corpo. Family: `label`, `version`, `negative`, `words`, `maxWords`. Rules: `version`. Custom: `mode: append` (predefinito) o `replace`.
- Segnaposto riconosciuti **solo** `{label}`, `{words}`, `{maxWords}`; ogni altra graffa resta com'è (la regola JSON contiene `{"prompt": …}`).
- Ordine di assemblaggio: Rules, Family, livello utente (sempre ultimo, ciascun pezzo preceduto da «In case of conflict, the instructions below take precedence over those above.»; un pezzo `replace` occupa il posto del livello che sostituisce, senza quella riga).
- I file si **rileggono a ogni richiesta**; file mancante, illeggibile o con `version` più bassa di quella incorporata → copia incorporata + avviso in `problems()`.
- All'avvio: un file di base mancante o con `version` più bassa dell'incorporata viene riscritto (il vecchio in `<nome>.md.bak`); `custom/` creata; `custom/families.txt` riscritto sempre.
- Famiglia sconosciuta: prompt generico di oggi («You write prompts for an image-generation model.» + regola di sola prosa).
- LLM con system prompt proprio: il suo system prompt resta com'è; si accoda solo `custom/<compito>.md` se esiste (sempre in aggiunta).
- Il testo assemblato per le 13 famiglie e per il caso senza famiglia è **uguale** a `PromptBrief.system(family:)` di oggi. Nessun cambio ai messaggi utente di Migliora/Genera.
- Risposte all'utente e commenti nel codice in italiano/inglese come il resto del progetto; testi dell'interfaccia in `Localizable.xcstrings` (en + it); `git add` per nome; mai unire o pubblicare senza via libera.

## Review Focus

1. **Intestazione assente o rotta** in un file di base (`---` non chiuso, riga senza `:`, BOM, fine riga CRLF): si usa la copia incorporata e `problems()` lo dice; non si invia mai il testo dell'intestazione all'LLM.
2. **File `custom/` vuoto o di soli spazi**: ignorato, senza la riga di precedenza da sola.
3. **Segnaposto**: `{words}` con `words` mancante nell'intestazione resta com'è e `problems()` lo segnala; le graffe del JSON della regola non si toccano.
4. **Cartella non scrivibile** (permessi, disco di sola lettura): `install()` non fallisce, l'app lavora dalle copie incorporate.
5. **Famiglia del catalogo senza Family prompt**: il menu LLM la mostra per chiave come oggi e Migliora usa il prompt generico.

---

### Task 1: Fotografia dei system prompt di oggi

**Files:**
- Create: `Packages/Tests/HubCoreTests/Fixtures/LegacySystemPrompts.swift`
- Create (temporaneo, non committare): `Packages/Tests/HubCoreTests/TmpDumpLegacyTests.swift`

**Interfaces:**
- Produces: `enum LegacySystemPrompts { static let byFamily: [String: String]; static let generic: String }` — le chiavi sono le 13 famiglie di `PromptGuides.all`; `generic` è `PromptBrief.system(family: nil)`.

- [ ] **Step 1: Scrivere un test temporaneo `TmpDumpLegacyTests.dump()`** che, per ogni chiave di `PromptGuides.all` e per `nil`, chiama `PromptBrief.system(family:)` e scrive su `Packages/Tests/HubCoreTests/Fixtures/LegacySystemPrompts.swift` un `enum` con due dizionari/stringhe letterali raw (`#"""` … `"""#`).
- [ ] **Step 2: Eseguirlo** — `cd Packages && swift test --filter TmpDumpLegacyTests` — atteso: il file esiste e contiene 13 voci + `generic`.
- [ ] **Step 3: Cancellare `TmpDumpLegacyTests.swift`**, ricompilare i test (`swift test --filter PromptBriefTests`: verdi).
- [ ] **Step 4: Commit** — `git add Packages/Tests/HubCoreTests/Fixtures/LegacySystemPrompts.swift`; messaggio `test(prompt): fotografia dei system prompt di Migliora/Genera`.

### Task 2: Lettore dei file (`PromptFile`)

**Files:**
- Create: `Packages/Sources/HubCore/Prompts/PromptFile.swift`
- Test: `Packages/Tests/HubCoreTests/PromptFileTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct PromptFile: Equatable, Sendable {
    public var header: [String: String]
    public var body: String
    public var isValid: Bool            // false se l'intestazione è aperta e non chiusa o ha righe senza ":"
    public var version: Int             // Int(header["version"]) ?? 0
    public init(header: [String: String] = [:], body: String, isValid: Bool = true)
    public static func parse(_ text: String) -> PromptFile
    public func resolved(_ values: [String: String]) -> String   // sostituisce solo i nomi presenti in `values`
    public func serialized() -> String   // "---\nchiave: valore\n…\n---\n" + body; chiavi in ordine alfabetico
  }
  ```

- [ ] **Step 1: Test** `PromptFileTests`: `headerAndBodyAreSplit` (`"---\nlabel: A\nversion: 3\n---\nTesto"` → header `["label":"A","version":"3"]`, body `"Testo"`, version 3), `noHeaderMeansTheWholeTextIsTheBody`, `crlfAndBomAreAccepted`, `anUnclosedHeaderIsInvalid` (`isValid == false`, `header` vuoto, body = testo intero), `aHeaderLineWithoutColonIsInvalid`, `valuesKeepTheirColons` (`label: A: B` → `"A: B"`), `resolvedReplacesOnlyTheNamedPlaceholders` (`{"prompt": "x"} {words}` con `["words": "300-450"]` → `{"prompt": "x"} 300-450`), `serializedParsesBackToTheSame`.
- [ ] **Step 2: Eseguire** `swift test --filter PromptFileTests` — atteso: FAIL (tipo non definito).
- [ ] **Step 3: Implementare** `PromptFile` come da firma; intestazione solo se la prima riga (dopo BOM) è `---`; chiave = tutto fino al primo `:`, valore troncato dagli spazi.
- [ ] **Step 4: Eseguire** gli stessi test — atteso: PASS.
- [ ] **Step 5: Commit** — `git add Packages/Sources/HubCore/Prompts/PromptFile.swift Packages/Tests/HubCoreTests/PromptFileTests.swift`; `feat(prompt): lettore dei file MD con intestazione`.

### Task 3: Copie incorporate delle Rules e dei Family prompt

**Files:**
- Create: `Scripts/make-embedded-prompts.py` (una tantum, resta nel repository)
- Create (generato): `Packages/Sources/HubCore/Prompts/EmbeddedPrompts.swift`
- Test: `Packages/Tests/HubCoreTests/EmbeddedPromptsTests.swift`

**Interfaces:**
- Consumes: `PromptFile` (Task 2), `LegacySystemPrompts` (Task 1).
- Produces: `enum EmbeddedPrompts { static let families: [String: String]` (id → testo MD completo con intestazione) `; static let rules: [String: String]` (`"enhance"`, `"describe"`) `; static let genericFamily: String }`.

Forma dei file incorporati: **Rules** (`enhance`, `describe`, identiche; `version: 1`) = `You write prompts for the image model "{label}".` **Family** = intestazione (`label`, `version: 1`, `negative`, `words`, `maxWords`) + corpo `<regola di risposta di oggi, prosa o JSON>\n\nModel notes:\n<note di oggi>` dove nelle note «aim for X words» → «aim for {words} words» e «never beyond Y words» → «never beyond {maxWords} words». `words` e `maxWords` vengono da `families.<id>.words`/`maxWords` di `master-prompts.json` di Prompt Master (embedded in `Plugins/PromptMaster/Sources/PromptMaster/Embedded/EmbeddedData.swift`).

- [ ] **Step 1: Test** `EmbeddedPromptsTests`: `thirteenFamiliesAllParseAsValid` (13 chiavi, `PromptFile.parse(...).isValid`, `label`/`negative`/`words`/`maxWords` presenti); `eachFamilyAssemblesToTheSystemPromptOfToday` — per ogni id: `Rules(enhance).resolved(["label": label]) + "\n\n" + Family.resolved(["label":…, "words":…, "maxWords":…])` è uguale a `LegacySystemPrompts.byFamily[id]`; `theGenericOneEqualsToday` (`EmbeddedPrompts.genericFamily` parse → `"You write prompts for an image-generation model.\n\n" + corpo == LegacySystemPrompts.generic`); `enhanceAndDescribeRulesAreValid`.
- [ ] **Step 2: Eseguire** — atteso: FAIL (tipo non definito).
- [ ] **Step 3: Scrivere lo script** `Scripts/make-embedded-prompts.py`: legge `PromptGuides.swift` e `master-prompts.json`, produce `EmbeddedPrompts.swift` con letterali raw; **fallisce** se, risolti i segnaposto, il testo di una famiglia non coincide con quello di oggi. Eseguirlo.
- [ ] **Step 4: Eseguire** `swift test --filter EmbeddedPromptsTests` — atteso: PASS.
- [ ] **Step 5: Commit** — `git add Scripts/make-embedded-prompts.py Packages/Sources/HubCore/Prompts/EmbeddedPrompts.swift Packages/Tests/HubCoreTests/EmbeddedPromptsTests.swift`; `feat(prompt): Rules e Family prompt incorporati (MD)`.

### Task 4: `PromptLibrary` — lettura e assemblaggio

**Files:**
- Create: `Packages/Sources/HubCore/Prompts/PromptLibrary.swift`
- Test: `Packages/Tests/HubCoreTests/PromptLibraryTests.swift`

**Interfaces:**
- Consumes: `PromptFile`, `EmbeddedPrompts`.
- Produces:
  ```swift
  public enum PromptTask: String, Sendable { case enhance, describe }
  public struct FamilyPrompt: Equatable, Sendable {
    public let id: String; public let label: String; public let negative: Bool
    public let words: String; public let maxWords: String
    public let body: String            // con segnaposto risolti
    public let notes: String           // la parte dopo "Model notes:\n" (o tutto il corpo se manca)
    public let isCustomized: Bool      // esiste custom/family-<id>.md
  }
  public struct PromptLibrary: Sendable {
    public init(folder: URL)
    public static var live: PromptLibrary { get }           // …/Application Support/DT Hub/Data/DTHub
    public static let priorityLine: String                  // "In case of conflict, the instructions below take precedence over those above."
    public func families() -> [FamilyPrompt]                // sempre le famiglie incorporate, ordinate per label
    public func family(_ id: String?) -> FamilyPrompt?
    public func system(task: PromptTask, family: String?) -> String
    public func ownSystemAddition(task: PromptTask) -> String?   // custom/<task>.md (append)
    public func problems() -> [String]
  }
  ```
  Regole: file su disco valido (`isValid`, `version ≥` incorporata, `label` presente) altrimenti la copia incorporata; `{label}` risolto nelle Rules e nel Family; custom `mode: replace` come da Global Constraints.

- [ ] **Step 1: Test** (cartella temporanea): `emptyFolderGivesTheSystemPromptOfToday` (13 famiglie + `nil`, tutte uguali a `LegacySystemPrompts`); `aValidFileOnDiskWins` (file `family/qwen_image_2.1.md` con corpo diverso e `version: 1`); `aLowerVersionFallsBackAndIsReported`; `aBrokenHeaderFallsBackAndIsReported`; `missingWordsKeepsThePlaceholderAndIsReported`; `theJSONBracesOfTheRuleAreUntouched` (famiglia con negativo: `{"prompt": "..."}` presente nel risultato); `customAppendsAfterFamilyWithThePriorityLine` (ordine Rules, Family, `custom/enhance.md`, `custom/family-<id>.md`, ciascuno dopo la riga); `customReplaceTakesTheSlot` (`mode: replace` in `custom/enhance.md` sostituisce le Rules, senza riga; idem `family-<id>.md` per Family); `emptyCustomIsIgnored` (solo spazi); `ownSystemAdditionIsNilWithoutFile`; `familiesFlagCustomized`; `unknownFamilyIsGeneric` (uguale a `LegacySystemPrompts.generic`); `editsAreReadAtEveryCall` (scrivo, leggo, riscrivo, rileggo).
- [ ] **Step 2: Eseguire** `swift test --filter PromptLibraryTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** `PromptLibrary` (nessuna cache; `live` calcola la cartella con `applicationSupportDirectory`). `family(_:)` e `system(...)` non lanciano mai.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** — `git add Packages/Sources/HubCore/Prompts/PromptLibrary.swift Packages/Tests/HubCoreTests/PromptLibraryTests.swift`; `feat(prompt): libreria dei prompt (Rules + Family + custom)`.

### Task 5: Installazione dei file di base, `custom/` e `families.txt`

**Files:**
- Modify: `Packages/Sources/HubCore/Prompts/PromptLibrary.swift`
- Test: `Packages/Tests/HubCoreTests/PromptLibraryInstallTests.swift`

**Interfaces:**
- Consumes: `PromptLibrary` (Task 4).
- Produces: `public func install()` (non lancia: gli errori di scrittura si ignorano) e `public var familiesListURL: URL` (`custom/families.txt`); `public var folderURL: URL`.

Formato di `families.txt`: righe di intestazione che spiegano l'uso (`custom/family-<id>.md`, `enhance.md`, `describe.md`, `mode: append|replace`), poi una riga per famiglia `Qwen Image 2.1 = qwen_image_2.1 (no negative prompt)` / `(negative prompt)`, ordinate per nome.

- [ ] **Step 1: Test**: `installWritesEveryBaseFileAndCustom` (13 famiglie + 2 Rules + `custom/` + `families.txt`); `installKeepsAFileWithTheSameOrHigherVersion` (contenuto invariato, nessun `.bak`); `installRewritesALowerVersionAndKeepsABackup` (`<nome>.md.bak` con il vecchio testo); `installRewritesABrokenFile`; `familiesListIsAlwaysRewritten`; `installOnAReadOnlyFolderDoesNotThrow` (cartella con permessi 0o500: nessuna eccezione, `system(...)` funziona); `afterInstallTheSystemPromptIsStillTheOneOfToday`.
- [ ] **Step 2: Eseguire** `swift test --filter PromptLibraryInstallTests` — atteso: FAIL.
- [ ] **Step 3: Implementare** `install()`: per ogni file incorporato, scrive se manca / illeggibile / `version` più bassa (copia prima il vecchio in `.md.bak`); crea `custom/`; riscrive `families.txt`.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** — `git add Packages/Sources/HubCore/Prompts/PromptLibrary.swift Packages/Tests/HubCoreTests/PromptLibraryInstallTests.swift`; `feat(prompt): installazione dei file di base, custom e families.txt`.

### Task 6: Migliora/Genera passano dalla libreria; sparisce `PromptGuides`

**Files:**
- Modify: `Packages/Sources/HubCore/PromptAssist/PromptBrief.swift`, `PromptAssistant.swift`, `Packages/Sources/HubCore/Language/LanguageModelFamilyOptions.swift`, `App/DTHubApp.swift`, `App/Generation/GenerationController.swift`
- Delete: `Packages/Sources/HubCore/PromptAssist/PromptGuides.swift`, `Packages/Tests/HubCoreTests/PromptGuidesTests.swift`
- Test: `Packages/Tests/HubCoreTests/PromptBriefTests.swift`, `PromptAssistantTests.swift`, `LanguageModelFamilyOptionsTests.swift` (aggiornare), `PromptLibraryTests.swift` (aggiungere i test dell'ex `PromptGuidesTests`: le 13 famiglie, le 6 con negativo, etichette leggibili, famiglia sconosciuta)

**Interfaces:**
- Consumes: `PromptLibrary` (Task 4–5).
- Produces (firme cambiate): `PromptBrief.system(family: String?, library: PromptLibrary = .live) -> String` (= `library.system(task: .enhance, family:)`); `PromptBrief.enhance(_:family:images:library:)`, `PromptBrief.describe(imageAt:family:library:)`; le due varianti `ownSystem:` accodano `library.ownSystemAddition(task:)` al system prompt proprio; `PromptAssistant.init(resolve:respond:library: PromptLibrary = .live)`; `LanguageModelFamilyOptions.list(catalogFamilies:library: PromptLibrary = .live)`. `PromptAssistant` usa `library.family(family)?.negative` al posto di `PromptGuides.guide(for:)?.usesNegative`.

- [ ] **Step 1: Test** (aggiornare quelli esistenti perché usino una `PromptLibrary` su cartella temporanea): `enhanceUsesTheLibrarySystem` (file di famiglia modificato → il system della richiesta cambia); `describeUsesTheDescribeRules`; `ownSystemGetsTheCustomAdditionOnly` (con `custom/enhance.md` il system proprio + testo; senza file, invariato); `negativeFollowsTheFamilyFile` (famiglia con `negative: true` nel file → il negativo della risposta JSON viene applicato); `familyMenuListsTheLibraryFamiliesAndTheUnknownCatalogOnes`.
- [ ] **Step 2: Eseguire** `swift test --filter "PromptBrief|PromptAssistant|LanguageModelFamilyOptions|PromptLibrary"` — atteso: FAIL.
- [ ] **Step 3: Implementare** le firme sopra; in `DTHubApp.swift` chiamare `PromptLibrary.live.install()` prima di creare il controller; `promptGuide` dei plug-in costruito da `PromptLibrary.live.family(...)` (`label`, `negative`, `notes`) — il contenuto non cambia; eliminare `PromptGuides.swift` e il suo test.
- [ ] **Step 4: Eseguire** tutta la suite — `cd Packages && swift test` — atteso: PASS (stesso numero di test di oggi, più i nuovi) — e la build Debug: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build` → `BUILD SUCCEEDED`.
- [ ] **Step 5: Commit** — `git add` dei file elencati (`git rm` per i due eliminati); `refactor(prompt): Migliora e Genera leggono i prompt dalla libreria`.

### Task 7: Il contesto dei plug-in porta il Family prompt; copia del lettore nel kit

**Files:**
- Modify: `Packages/Sources/HubKit/Plugin/PluginMessages.swift` (`PluginPromptGuide`), `PluginKit/Sources/DTHubPluginKit/DTHubPlugin.swift` (`DTHubPromptGuide`), `App/DTHubApp.swift`, `PluginKit/README.md`
- Create: `PluginKit/Sources/DTHubPluginKit/DTHubPromptFile.swift`
- Test: `Packages/Tests/HubKitTests/PluginContractTests.swift`, `PluginKit/Tests/DTHubPluginKitTests/DTHubPromptFileTests.swift`

**Interfaces:**
- Consumes: `FamilyPrompt` (Task 4).
- Produces: `PluginPromptGuide` e `DTHubPromptGuide` guadagnano `familyPrompt: String?` (corpo risolto: protocollo + note), `words: String?`, `maxWords: String?` (tutti facoltativi; `notes`, `label`, `usesNegative` restano com'erano). `DTHubPromptFile` ha la stessa API di `PromptFile` (`parse`, `resolved`, `version`, `isValid`, `header`, `body`) — il kit è un pacchetto a parte, quindi il codice è copiato (come `AnswerParser`).

- [ ] **Step 1: Test**: in `PluginContractTests` il messaggio `context` con `promptGuide` completo si decodifica con i tre campi nuovi, e uno vecchio (senza) si decodifica con `nil`; in `DTHubPromptFileTests` gli stessi casi di `PromptFileTests` (intestazione, CRLF/BOM, intestazione aperta, segnaposto).
- [ ] **Step 2: Eseguire** — atteso: FAIL.
- [ ] **Step 3: Implementare** i campi e la copia del lettore; `DTHubApp.swift` riempie `familyPrompt`, `words`, `maxWords` da `FamilyPrompt`; il README del kit descrive i tre campi (aggiunta facoltativa al contratto 1).
- [ ] **Step 4: Eseguire** `swift test` in `Packages` e in `PluginKit` — atteso: PASS; i plug-in esistenti (AI Assistant) compilano e passano i loro test (`swift test` in `Plugins/AIAssistant`).
- [ ] **Step 5: Commit** — `git add` per nome; `feat(plug-in): il contesto porta il Family prompt; lettore MD nel kit`.

### Task 8: Preferenze › LLM — cartella, indicatore «Personalizzato», anteprima «Prompt finale»

**Files:**
- Modify: `App/Preferences/LanguagePreferencesView.swift`, `App/Localizable.xcstrings`
- Create: `App/Preferences/PromptLibrarySection.swift`

**Interfaces:**
- Consumes: `PromptLibrary.live` (`families()`, `system(task:family:)`, `problems()`, `folderURL`), `FamilyPrompt.isCustomized`.
- Produces: `struct PromptLibrarySection: View` — pulsante **Apri cartella dei prompt** (`NSWorkspace.shared.open(folderURL)`), un Picker di famiglia + compito (Migliora / Descrivi), l'anteprima in sola lettura (`system(task:family:)`, testo selezionabile, monospazio), l'etichetta **Personalizzato** accanto alla famiglia con `isCustomized`, e le righe di `problems()` in rosso.

- [ ] **Step 1: Test** — logica pura già coperta (Task 4–5); qui non si aggiungono test di vista. Aggiungere a `LocalizationCatalogTests` nulla: il test esistente controlla che ogni chiave abbia en + it.
- [ ] **Step 2: Implementare** la sezione e inserirla in `LanguagePreferencesView`; chiavi `prefs.prompts.title`, `prefs.prompts.open`, `prefs.prompts.family`, `prefs.prompts.task.enhance`, `prefs.prompts.task.describe`, `prefs.prompts.custom`, `prefs.prompts.preview`, `prefs.prompts.note` (la nota avverte che le Family rules non vanno modificate e dice dove stanno i file e `custom/`) in en e it.
- [ ] **Step 3: Eseguire** la build Debug e `cd Packages && swift test --filter LocalizationCatalogTests` — atteso: `BUILD SUCCEEDED`, test verdi.
- [ ] **Step 4: Commit** — `git add App/Preferences/PromptLibrarySection.swift App/Preferences/LanguagePreferencesView.swift App/Localizable.xcstrings`; `feat(preferenze): cartella dei prompt, indicatore Personalizzato e anteprima`.

### Task 9: Documentazione e prove finali

**Files:**
- Modify: `README.md` (sezione sui prompt), `docs/superpowers/briefing-prossima-sessione.md` (locale, non committato)

- [ ] **Step 1: README** — una sezione breve: dove stanno i file (`Data/DTHub/{family,rules,custom}`), a cosa servono Rules/Family/custom, `mode: append|replace`, `families.txt`, la nota «le Family rules sono in <percorso>, è sconsigliato modificarle», e che i file si rileggono a ogni richiesta.
- [ ] **Step 2: Suite completa** — `cd Packages && swift test`; `cd PluginKit && swift test`; `swift test` in `Plugins/AIAssistant` — atteso: tutto verde.
- [ ] **Step 3: Prove a mano (le fa l'utente)**: con l'app avviata esistono i file in `Data/DTHub/`; **Migliora Prompt** e **Genera Prompt** su **Qwen Image 2.1**, **FLUX.2 [klein] 9B** (prosa) e **Krea 2** (negativo e JSON): stessi risultati di prima; un `custom/enhance.md` con una riga cambia il comportamento al tentativo successivo senza riavvio; un file di famiglia rotto fa comparire l'avviso nell'anteprima e l'app continua; l'anteprima «Prompt finale» mostra il testo che riceve l'LLM.
- [ ] **Step 4: Commit** — `git add README.md`; `docs: i prompt modulari nel README`.

---

## Self-review

- **Copertura della spec (fase 1):** §1–§2 → Task 3–4; §3 (cartelle, `families.txt`) → Task 5; §4 (formato, segnaposto) → Task 2–3; §5 (assemblaggio, LLM con system proprio, rilettura) → Task 4 e 6; §6 (contesto ai plug-in, lettore nel kit) → Task 7; §7 (cartella, «Personalizzato», anteprima, avvisi) → Task 8; §8 (installazione, `.bak`) → Task 5; §10 (confronto su tutte le famiglie, prove con LLM su Qwen 2.1 / FLUX.2 klein 9B / Krea 2) → Task 1, 3, 9. Le prove di Ideogram 4 e la migrazione di Character Sheet / Prompt Master / I4 / AI Assistant sono delle fasi 2 e 3 (piani a parte).
- **Tipi coerenti:** `PromptFile` (Task 2) → `PromptLibrary`/`FamilyPrompt` (Task 4) → firme di Task 6–8; `DTHubPromptFile` (Task 7) ha la stessa API di `PromptFile`.
- **Proporzione:** nove task, firme e test nominati, nessun corpo di funzione tranne dove la spec fissa il testo.

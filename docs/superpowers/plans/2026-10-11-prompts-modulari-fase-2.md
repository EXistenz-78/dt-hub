# Prompt modulari — fase 2 (Prompt Master) — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (esecuzione nativa, scelta dell'utente) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prompt Master smette di avere i suoi master per famiglia: usa il Family prompt che DT Hub manda nel contesto, le sue Rules in MD (`compose.md`, `compose-tags.md`) in `Data/prompt-master/rules/` e un livello utente in `Data/prompt-master/custom/`.

**Architecture:** Un piccolo helper nel kit (`DTHubPromptFolder`) legge i file di base (disco se validi, altrimenti la copia incorporata), li installa con `.bak`, legge `custom/` e assembla. Il plug-in tiene solo i dati che servono a lui (`families.json`: categorie nascoste, regola dei tag «booru», «provvisorio», variante delle Rules). Il system prompt è `Rules + familyPrompt (+ regola booru) + custom`.

**Tech Stack:** Swift 6.2, Swift Testing, `PluginKit` (`DTHubPluginKit`), plug-in `Plugins/PromptMaster`.

**Spec:** `docs/superpowers/specs/2026-10-11-prompts-modulari-design.md` (§2, §3, §5, §6, §8, fase 2 di §11). Fase 1: `docs/superpowers/plans/2026-10-11-prompts-modulari.md`.

## Global Constraints

- Il Family prompt esiste **solo in DT Hub**; il plug-in lo legge da `context.promptGuide.familyPrompt` (con `usesNegative`, `label`). Senza `familyPrompt` (app più vecchia) o senza famiglia il plug-in non scrive (stesso messaggio di «nessun master prompt» di oggi).
- Cartella del plug-in: `~/Library/Application Support/DT Hub/Data/prompt-master/` con `rules/` (`compose.md`, `compose-tags.md`), `custom/` (`compose.md`, facoltativo; `mode: append|replace`) e `families.json`; restano `custom-terms.json` e il database in `Data/`.
- Stessa regola di fase 1: file valido e con `version` non più bassa dell'incorporata, altrimenti copia incorporata; all'avvio un file mancante, illeggibile o più vecchio viene riscritto (vecchio in `.md.bak`); `custom/` creata; riga di precedenza «In case of conflict, the instructions below take precedence over those above.» prima del file utente (`append`); `replace` sostituisce le Rules, senza riga; file utente vuoto ignorato.
- Segnaposto solo `{label}`; le altre graffe restano.
- Ordine del system prompt: Rules, Family prompt, regola «booru» (solo SDXL e SD 1.5 con l'interruttore acceso), poi il livello utente.
- Il testo delle Rules per ogni famiglia è quello di oggi (primo e secondo paragrafo del vecchio `system`): `compose.md` per le 10 famiglie «a frasi», `compose-tags.md` per SDXL, SD 1.5 e Anima.
- Differenze accettate rispetto a oggi (le due Rules non le contengono più): la regola di risposta è quella del Family prompt di DT Hub («whatever the language of the input», e per le famiglie con negativo la formulazione di DT Hub), e la riga «(Provisional master prompt…)» non va all'LLM (il flag `provisional` resta per l'avviso in interfaccia).
- Versione del plug-in 1.4 (`Scripts/build.sh`, manifest, README).

## Review Focus

1. **App senza `familyPrompt`** (contesto da una DT Hub vecchia) o famiglia senza Family prompt: «Write» disattivato come con una famiglia senza master, nessun crash.
2. **`custom/compose.md` vuoto, di soli spazi o con intestazione rotta**: ignorato (rotto = ignorato, il resto funziona).
3. **`families.json` su disco con schema o versione sbagliati** o illeggibile: copia incorporata e avviso nello stato, come per gli altri file di dati.
4. **Interruttore «booru»** con `compose-tags.md`: la regola si accoda al Family prompt, prima del livello utente, e solo per SDXL e SD 1.5.
5. **Cartella non scrivibile**: `install` non fallisce e il plug-in lavora dalle copie incorporate.

---

### Task 1: `DTHubPromptFolder` nel kit

**Files:**
- Create: `PluginKit/Sources/DTHubPluginKit/DTHubPromptFolder.swift`
- Test: `PluginKit/Tests/DTHubPluginKitTests/DTHubPromptFolderTests.swift`

**Interfaces:**
- Consumes: `DTHubPromptFile` (esiste).
- Produces:
  ```swift
  public struct DTHubPromptFolder: Sendable {
    public init(folder: URL)
    public static let priorityLine: String      // "In case of conflict, the instructions below take precedence over those above."
    /// The file at `path` if valid and not older than `embedded`; else the embedded copy (+ reason).
    public func base(_ path: String, embedded: String) -> (file: DTHubPromptFile, problem: String?)
    /// `custom/<name>`: nil when absent or empty.
    public func custom(_ name: String) -> (body: String, replaces: Bool)?
    /// Writes the files (path → embedded text) that are missing/unreadable/older (old one kept as `<name>.bak`); makes `custom/`.
    public func install(_ files: [String: String])
    /// Rules, family text and extras joined by blank lines; the user's file after them (replace swaps the Rules).
    public func assemble(rules: String, family: String, extras: [String], customName: String, label: String) -> String
  }
  ```

- [ ] **Step 1: Test** `DTHubPromptFolderTests` (cartella temporanea): `baseUsesTheFileWhenValidAndNotOlder`, `baseFallsBackWithAReasonForABrokenHeaderOrAnOlderVersion`, `customIsNilWhenAbsentOrEmpty`, `customReadsModeReplace`, `installWritesMissingAndKeepsABackupOfAnOlderFile` (`.bak`), `installKeepsAFileWithTheSameOrHigherVersion`, `installOnAReadOnlyFolderDoesNotThrow`, `assembleJoinsRulesFamilyExtrasAndTheUsersFileLast` (con riga di precedenza), `assembleReplaceSwapsTheRules` (`{label}` risolto nel file utente), `assembleIgnoresAnEmptyUsersFile`.
- [ ] **Step 2: Eseguire** `cd PluginKit && swift test --filter DTHubPromptFolderTests` — atteso: FAIL (tipo non definito).
- [ ] **Step 3: Implementare** come `PromptLibrary` della fase 1 (stessa logica di `load`/`install`/`custom`/assemblaggio), `assemble` taglia gli spazi ai bordi di ogni pezzo.
- [ ] **Step 4: Eseguire** — atteso: PASS.
- [ ] **Step 5: Commit** — `git add` per nome; `feat(kit): DTHubPromptFolder per i file di prompt dei plug-in`.

### Task 2: Dati e Rules di Prompt Master

**Files:**
- Create: `Plugins/PromptMaster/Sources/PromptMaster/Embedded/EmbeddedPrompts.swift` (a mano), `Plugins/PromptMaster/families.json`
- Modify: `Plugins/PromptMaster/Sources/PromptMaster/Models.swift`, `DataSource.swift`, `Embedded/EmbeddedData.swift` (via script), `Plugins/PromptMaster/Scripts/make-prompt-data.py`
- Delete: `Plugins/PromptMaster/master-prompts.json`
- Test: `Plugins/PromptMaster/Tests/PromptMasterTests/DataTests.swift` (aggiornare), `BriefTests.swift` (Task 3)

**Interfaces:**
- Produces:
  ```swift
  struct PMFamily: Codable, Equatable, Sendable {
    var hiddenCategories: [String]
    var booruSystem: String?       // the «Tag mode is ON…» rule (SDXL, SD 1.5)
    var provisional: Bool?
    var tags: Bool?                // true → rules/compose-tags.md
  }
  struct PMFamiliesData: Codable, Equatable, Sendable, VersionedData { var schema: Int; var version: String; var families: [String: PMFamily] }
  enum EmbeddedPrompts { static let families: String; static let compose: String; static let composeTags: String }   // MD con `---\nversion: 1\n---` + «You write prompts for the image model "{label}".\n\n<paragrafo>»
  ```
  `PMData` perde `masters: MasterPrompts` e guadagna `families: PMFamiliesData`; `DataSource.familiesFileName = "families.json"`.

- [ ] **Step 1: Test** (`DataTests`): le 13 famiglie in `families.json` incorporato; `hiddenCategories` come nel vecchio `master-prompts.json` (es. `qwen_image` → `["render_quality"]`, `cosmos2.5_2b` → tre categorie); `booruSystem` presente solo per `sdxl_base_v0.9` e `v1`; `provisional` per flux2, qwen_image_2.1, hidream_i1, cosmos2.5_2b; `tags == true` per SDXL, SD 1.5 e Anima; i test esistenti su `master-prompts.json` (file valido, versione più vecchia, schema sconosciuto, illeggibile) passano a `families.json`.
- [ ] **Step 2: Eseguire** — atteso: FAIL.
- [ ] **Step 3: Generare** `families.json` e `EmbeddedPrompts.swift` con uno script una tantum (python, dai dati del vecchio `master-prompts.json`: i due paragrafi iniziali di `system` diventano `compose.md` e `compose-tags.md` con `{label}` al posto del nome); `make-prompt-data.py` smette di scrivere `master-prompts` e conserva solo `prompt-database` in `EmbeddedData.swift`; aggiornare `Models.swift`/`DataSource.swift`; cancellare `master-prompts.json` e `FamilyPrompt`/`MasterPrompts`.
- [ ] **Step 4: Eseguire** `swift test --filter DataTests` — atteso: PASS (il resto del plug-in può non compilare finché non c'è il Task 3: i due task si completano insieme prima del commit).

### Task 3: Brief, stato e scrittura usano il Family prompt dell'app

**Files:**
- Modify: `Sources/PromptMaster/BriefBuilder.swift`, `PMState.swift`, `PMWriter.swift`, `PromptMasterPlugin.swift`
- Test: `Tests/PromptMasterTests/BriefTests.swift`, `PMWriterTests.swift`, `PMStateTests.swift`, `PEPlannerTests.swift` (aggiornare)

**Interfaces:**
- Consumes: `DTHubPromptFolder` (Task 1), `PMFamiliesData`/`EmbeddedPrompts` (Task 2), `DTHubPromptGuide.familyPrompt/usesNegative/label` (fase 1).
- Produces: `BriefBuilder.make(guide: DTHubPromptGuide, family: String, data: PMFamiliesData, folder: DTHubPromptFolder, description: String, terms: [SelectedTerm], booru: Bool) -> Brief?` (nil se `guide.familyPrompt` è nil o vuoto); `PMState.guide: DTHubPromptGuide?` (dal contesto) al posto di `master`; `PMWriter.Request` ha `guide`, `data`, `folder` al posto di `masters`.

- [ ] **Step 1: Test** `BriefTests`: per ogni famiglia il system assemblato **comincia** con il primo e il secondo paragrafo del vecchio `system` (fotografia in `Tests/PromptMasterTests/Fixtures/LegacyMasterSystems.swift`, dalle 13 voci del vecchio JSON) e **contiene** le note di famiglia di DT Hub; `tagsFamiliesUseTheTagsRules`; `booruRuleComesAfterTheFamilyPromptAndOnlyWhenOn`; `customAppendsWithThePriorityLine`; `customReplaceSwapsTheRules`; `noFamilyPromptMeansNoBrief` (guide senza `familyPrompt`); `theRulesCarryTheLabel`. `PMWriterTests`: la riga negativa si scrive solo se `guide.usesNegative`; `PMStateTests`: `canWrite` richiede `guide?.familyPrompt` non vuoto.
- [ ] **Step 2: Eseguire** — atteso: FAIL.
- [ ] **Step 3: Implementare** le firme sopra. `PromptMasterPlugin` passa `context.promptGuide` a `PMState.update(...)`; la cartella è `DataSource.defaultFolder/prompt-master`; `BriefBuilder.make` assembla con `folder.assemble(rules: …, family: guide.familyPrompt, extras: booru ? [rule] : [], customName: "compose.md", label: guide.label)`.
- [ ] **Step 4: Eseguire** `swift test` nel plug-in — atteso: PASS (tutta la suite).
- [ ] **Step 5: Commit** — `git add` per nome (Task 2 e 3 insieme); `feat(prompt-master): usa il Family prompt dell'app, Rules in MD e custom`.

### Task 4: Installazione, versione, README

**Files:**
- Modify: `Sources/PromptMaster/PromptMasterPlugin.swift`, `Scripts/build.sh` (VERSION 1.4), manifest (versione), `README.md`, `Plugins/README.md` (se riporta la versione)
- Test: `Tests/PromptMasterTests/DataTests.swift` o un file nuovo `InstallTests.swift`

**Interfaces:**
- Consumes: `DTHubPromptFolder.install(_:)`.
- Produces: `DataSource.installPrompts(folder: URL)` — chiama `install` con `rules/compose.md`, `rules/compose-tags.md` e `families.json`? No: `families.json` resta un file di dati come gli altri (non lo riscrive): solo le due Rules.

- [ ] **Step 1: Test** `InstallTests`: `installWritesTheTwoRulesAndCustom` (cartella temporanea), `afterInstallTheBriefIsTheSame`, `readOnlyFolderDoesNotThrow`.
- [ ] **Step 2: Eseguire** — atteso: FAIL.
- [ ] **Step 3: Implementare** `installPrompts` e chiamarlo all'avvio del plug-in (dove oggi carica i dati); aggiornare README (sezione Data: `rules/`, `custom/`, `families.json`, nota «le Rules sono in <percorso>, è sconsigliato modificarle») e la versione 1.4.
- [ ] **Step 4: Eseguire** `swift test` (plug-in, kit, `Packages`) e `Scripts/build.sh $TMPDIR/pm` — atteso: PASS, bundle firmato.
- [ ] **Step 5: Commit** — `git add` per nome; `feat(prompt-master): installazione delle Rules, versione 1.4, README`.

---

## Self-review

- **Copertura della spec:** §2 (Rules + Family, Family solo in DT Hub) → Task 2–3; §3 (cartelle) → Task 2, 4; §5 (assemblaggio) → Task 1, 3; §6 (contesto) → Task 3; §8 (installazione, `.bak`, migrazione) → Task 1, 4; verifiche di §10 → `BriefTests` con la fotografia dei vecchi `system`.
- **Tipi coerenti:** `DTHubPromptFolder` (Task 1) usato in Task 3–4; `PMFamiliesData` (Task 2) in Task 3.
- **Differenze dichiarate** (Global Constraints): wording della regola di risposta e riga «provisional»; la prova con l'LLM la fa l'utente.

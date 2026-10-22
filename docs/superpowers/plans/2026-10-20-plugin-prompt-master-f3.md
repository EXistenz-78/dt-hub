# Prompt Master F3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** costruire il plug-in «Prompt Master F3»: compone il prompt strutturato di FLUX.3 Klein (descrizione, composizione con `<id>`, array JSON dei riquadri), con quattro card e un solo «Scrivi con LLM» che sostituisce i testi e si annulla.

**Architecture:** pacchetto Swift indipendente `Plugins/PromptMasterF3/` sul modello di `Plugins/PromptMasterI4/` (libreria dinamica, kit e design system con alias, contratto 1). La logica è in tipi puri testabili (`F3Composer`, `F3IDParser`, `F3Sync`, `F3DefaultBox`, `F3Brief`, `F3AnswerParser`, `F3Writer`, `F3Snapshot`); le viste li usano. Da I4 si copiano e adattano `BBox`, `CanvasGeometry`, la card del canvas, il campo posizione, lo Shuffler, `DataSource` e `I4Store`.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, macOS 26, Swift Testing (come I4), `DTHubPluginKit`/`DTHubDesign`.

**Spec:** `docs/superpowers/specs/2026-10-20-plugin-prompt-master-f3-design.md` (mockup: `docs/superpowers/mockups/2026-10-20-prompt-master-f3.html`).

## Global Constraints

- Si risponde, si scrive la documentazione e i commenti di progetto in **italiano**; README del plug-in e testi pubblici in **inglese**; testi dell'interfaccia in italiano e inglese (tabella `L`, come I4; il test di catalogo it/en deve passare).
- **Famiglie:** `F3Plugin.families` è un elenco in un solo punto. **Per ora `["flux2_9b", "flux2_4b"]`** (FLUX.2 klein, le stesse di Sphere Light): così il plug-in si prova nell'app fino alla generazione del prompt (il Run con FLUX.3 non si può ancora provare). Quando Draw Things espone FLUX.3 Klein si **aggiunge** il suo id (e si decide se tenere o togliere le famiglie FLUX.2). Nessun'altra parte del codice cita gli id.
- **Scala delle coordinate:** `BBoxScale.grid = 1000` (spec §2); è l'**unico** punto che decide la scala; ordine `[y0, x0, y1, x1]`, `top < bottom`, `left < right`, lato minimo 20.
- Il testo inviato: descrizione, riga vuota, composizione, riga vuota, array JSON indentato di due spazi; negativo svuotato (spec §5).
- «Invia» disattivato con: nessun elemento, `desc` vuota, id ripetuto (spec §5).
- Sincronizzazione degli id ritardata di ~0,8 s o a perdita del fuoco; rinomina riconosciuta; id tolti ricordati per la sessione (spec §7).
- Box di default: lato 180 su 1000 (quadrato in pixel), passo 200, a fila da in alto a sinistra (spec §8).
- LLM: una sola richiesta senza `model`, `thinking` spento, temperatura 0,6, `maxTokens` 4096, attesa 600 s; il controllo degli id è nel codice (spec §9).
- Annulla ripristina **solo l'ultima** scrittura (testi, voci, composizione, `desc`); file in `llm/` accanto a `state.json`.
- Database: `prompt-database.json` condiviso, **senza il gruppo H**; niente dati personali nei file (`/Users/existenz`, mail) nei commit.
- Metodo: test-first (RED poi GREEN), un commit per task, file aggiunti **per nome** (mai `git add -A`).

## Review Focus

1. **Id con spazi, `<>` vuoti o annidati, `<a<b>>`:** non devono creare elementi strani né andare in errore (test al Task 2).
2. **Composizione senza nessun id** o con 20+ id: la griglia dei box di default si riempie e si sfalsa senza uscire dal canvas (Task 3).
3. **`desc` con virgolette, `\`, a capo, emoji:** il JSON inviato deve restare valido (Task 1).
4. **Risposta dell'LLM troncata, con tag di pensiero, con i titoli in disordine o con un id cambiato:** mai perdere i testi dell'utente (Task 6–7).
5. **Cambio di progetto o riavvio con «Annulla» attivo:** la fotografia si ritrova da `state.json` (Task 4 e 7).

---

## Mappa dei file (`Plugins/PromptMasterF3/`)

- `Package.swift`, `Scripts/build.sh`, `Scripts/make-f3-data.py`, `Scripts/make-embedded-prompts.py` (da I4) — Task 0
- `Sources/PromptMasterF3/F3Plugin.swift`, `Strings.swift` — Task 0, 10
- `BBox.swift`, `F3Composer.swift` — Task 1
- `F3IDParser.swift`, `F3Sync.swift` — Task 2
- `F3DefaultBox.swift` — Task 3
- `F3Document.swift`, `F3Snapshot.swift`, `F3Store.swift`, `F3State.swift` — Task 4
- `DataSource.swift`, `F3Catalog.swift`, `F3Shuffler.swift`, `F3Prompts.swift`, `Embedded/EmbeddedData.swift` — Task 5
- `F3Brief.swift`, `F3AnswerParser.swift` — Task 6
- `F3Writer.swift`, `F3WorkFolder.swift` — Task 7 (`F3Snapshot.swift` nasce al Task 4)
- `CanvasGeometry.swift`, `F3CanvasCard.swift` — Task 8
- `F3View.swift`, `F3DescriptionCard.swift`, `F3CompositionCard.swift`, `F3ElementsCard.swift`, `F3Palette.swift` — Task 9
- `README.md`, `Plugins/README.md`, `README.md` principale — Task 11
- Test in `Tests/PromptMasterF3Tests/`, un file per tipo.

---

### Task 0: Scheletro del pacchetto e manifest

**Files:**
- Create: `Plugins/PromptMasterF3/Package.swift`, `Scripts/build.sh`, `Sources/PromptMasterF3/F3Plugin.swift`, `Sources/PromptMasterF3/Strings.swift`
- Test: `Tests/PromptMasterF3Tests/ManifestTests.swift`

**Interfaces:**
- Produces: `final class F3Plugin: DTHubPlugin` con `static let families = ["flux2_9b", "flux2_4b"]` e `manifest` (`id` `com.exiztenz.dthub.promptmasterf3`, `name` «Prompt Master F3», `version` «1.0», `symbol` `curlybraces.square`, `families: families`); `enum L` con `text(_:italian:)`, `format(_:_:italian:)`, `systemIsItalian` (stessa forma di `Strings.swift` di I4).

- [ ] **Step 1:** test `manifest_isForTheFamilyOnly`: `F3Plugin().manifest.families == F3Plugin.families` e `id == "com.exiztenz.dthub.promptmasterf3"`.
- [ ] **Step 2:** `swift test` in `Plugins/PromptMasterF3` — FAIL (target mancante).
- [ ] **Step 3:** copiare `Package.swift` e `Scripts/build.sh` di I4 cambiando nomi, alias moduli (`PromptMasterF3Kit`, `PromptMasterF3Design`), `VERSION=1.0`; `F3Plugin` con `handle` che per `context|project|activate|deactivate` non fa ancora nulla e per altro risponde `DTHubMessage.bare("unsupported")`; `Strings.swift` con la tabella `L` vuota di partenza.
- [ ] **Step 4:** `swift test` — PASS.
- [ ] **Step 5:** commit `feat(f3): scheletro del plug-in` (file per nome).

### Task 1: Riquadro e testo inviato (`F3Composer`)

**Files:** Create `BBox.swift` (copia di I4 con `enum BBoxScale { static let grid = 1000 }` al posto di `BBox.grid`), `F3Composer.swift`; Test `ComposerTests.swift`, `BBoxTests.swift`.

**Interfaces:**
- Produces: `struct F3Element: Codable, Equatable, Identifiable { var id: String; var desc: String; var box: BBox; var colorIndex: Int; var expanded: Bool }`; `enum F3Composer { static func text(description: String, terms: [String], composition: String, elements: [F3Element]) -> String; static func jsonArray(_ elements: [F3Element]) -> String; static func problems(composition: String, elements: [F3Element]) -> [F3Problem] }`; `enum F3Problem: Equatable { case noElements, emptyDescription(id: String), duplicateID(String) }`.

- [ ] **Step 1:** test `BBoxTests` (copiati da I4: `parse`, `normalized`, `resolve`, lato minimo 20) con la nuova scala.
- [ ] **Step 2:** test `ComposerTests`: `text_joinsThreePartsWithBlankLines` (descrizione «A.» + composizione «B <x_1>.» + un elemento → esattamente `"A.\n\nB <x_1>.\n\n[\n  {\n    \"id\": \"x_1\",\n    \"bbox\": [1, 2, 3, 4],\n    \"desc\": \"d\"\n  }\n]"`, con bbox valido); `text_appendsTermsAsSentence` (`terms: ["Neon light","rim light"]` → descrizione termina con `" Neon light, rim light."`); `json_escapesQuotesBackslashNewlineEmoji` (la `desc` `a "b" \ c\nd 😀` ricodificata con `JSONSerialization` torna uguale); `problems_flagsEmptyDescAndDuplicates`; `problems_noElements`.
- [ ] **Step 3:** RED, poi implementare con `JSONEncoder` (`.prettyPrinted`, chiavi in ordine `id`, `bbox`, `desc` con `CodingKeys` e un `encode` esplicito per l'ordine); l'indentazione a due spazi si ottiene con un'unica riga di post-processing documentata o con un encoder a mano (sceglie l'implementatore, il test fissa l'uscita).
- [ ] **Step 4:** GREEN. **Step 5:** commit.

### Task 2: Id nel testo e sincronizzazione (`F3IDParser`, `F3Sync`)

**Files:** Create `F3IDParser.swift`, `F3Sync.swift`; Test `IDParserTests.swift`, `SyncTests.swift`.

**Interfaces:**
- Produces: `enum F3IDParser { static func ids(in text: String) -> [F3IDMatch] }` con `struct F3IDMatch: Equatable { var id: String; var range: Range<String.Index> }` (id = contenuto di `<…>` senza `<`, `>`, a capo, tolti gli spazi ai bordi, 1–40 caratteri; nell'ordine del testo, ripetizioni incluse); `struct F3Sync { var elements: [F3Element]; var removed: [String: F3Element]; mutating func apply(oldText: String, newText: String, makeBox: (Int) -> BBox) -> F3SyncChange }`; `struct F3SyncChange: Equatable { var added: [String]; var removed: [String]; var renamed: [(from: String, to: String)]; var duplicates: [String] }` (Equatable a mano).

- [ ] **Step 1:** test `IDParserTests`: `<a>` → `["a"]`; `< a >` → `["a"]`; `<>` e `< >` ignorati; `<a<b>>` → solo `["b"]`; id di 41 caratteri ignorato; a capo dentro ignorato; ripetizioni mantenute in ordine; `<woman_1>, <woman_1>` due match.
- [ ] **Step 2:** test `SyncTests`: id nuovo → elemento in fondo con `makeBox(indice)`; id tolto → elemento tolto e messo in `removed`, e se **ricompare** torna con `desc` e `box` di prima; **rinomina** (stessa posizione, uno sparisce e uno appare) → stessa scheda, stessa `desc`, stesso box, stesso `colorIndex`; id ripetuto → una sola scheda e `duplicates` lo elenca; `<woman_` (tag aperto, non chiuso) → nessun elemento; il colore è `colorIndex` crescente e non cambia mai.
- [ ] **Step 3:** RED, implementare (la rinomina si rileva confrontando i match vecchi e nuovi per posizione e indice nel testo). **Step 4:** GREEN. **Step 5:** commit.

### Task 3: Box di default (`F3DefaultBox`)

**Files:** Create `F3DefaultBox.swift`; Test `DefaultBoxTests.swift`.

**Interfaces:** `enum F3DefaultBox { static func box(index: Int, aspect: Double, taken: [BBox]) -> BBox }` (`aspect` = larghezza/altezza della generazione).

- [ ] **Step 1:** test: indice 0 → `BBox(y0: 0, x0: 0, …)` con lato in x 180 e in y `180 * aspect` (quadrato in pixel, limitato a 1000); indice 1 → `x0 == 200`; con griglia a 5 colonne l'indice 5 va a capo (`y0` = 200 su canvas quadrato); con `aspect` 1,5 il box è alto 270; **griglia piena** (indice 100) → resta dentro 0–1000 e non coincide con uno di `taken`; nessun box ha lato < 20.
- [ ] **Step 2:** RED, implementare (fila da in alto a sinistra, passo 200, a capo; se piena, sfalsa di 20). **Step 3:** GREEN. **Step 4:** commit.

### Task 4: Documento, stato e persistenza

**Files:** Create `F3Document.swift`, `F3Snapshot.swift` (solo la struct `F3Snapshot` con i suoi campi, §7 aggiunge `restore`), `F3Store.swift` (da `I4Store`), `F3State.swift`; Test `DocumentTests.swift`, `StoreTests.swift`, `StateTests.swift`.

**Interfaces:**
- Produces: `struct F3Document: Codable, Equatable { var description: String; var picks: [String: String]; var mode: PhotoOrArt; var composition: String; var elements: [F3Element]; var snapshot: F3Snapshot? }` (`picks`: categoria → voce `en`); `struct F3Session: Codable { static let currentSchema = 1; var schema: Int; var document: F3Document; var openGroups: [String]; var openCategories: [String] }`; `F3Store` e `FileStorage` come in I4 (`state.json`); `@MainActor @Observable final class F3State` con `document`, `selectedElement: String?`, `canSend: Bool`, `problems: [F3Problem]`, `func compositionChanged(_ text: String)` (debounce 0,8 s, `commitComposition()` immediato alla perdita del fuoco), `func switchProject(folder: URL, adoptLegacy: Bool)`, `func update(generationSize: CGSize?)`, `var status: String`.
- Consumes: `F3Sync`, `F3DefaultBox`, `F3Composer.problems`.

- [ ] **Step 1:** test `StoreTests`: salva/carica; `schema` diverso → sessione vuota; file mancante → vuota.
- [ ] **Step 2:** test `StateTests`: `compositionChanged` non crea elementi prima dei 0,8 s (orologio iniettato) né per `<woman_`; `commitComposition()` li crea con colori e box di default distinti; `canSend` falso nei tre casi di `F3Problem`; cambio di progetto ricarica il documento del nuovo progetto; **riavvio con snapshot**: salva con `snapshot` non nil, ricarica, `snapshot` ancora presente.
- [ ] **Step 3:** RED, implementare; l'orologio del debounce è un parametro iniettabile (`var sleep: (Duration) async -> Void`). **Step 4:** GREEN. **Step 5:** commit.

### Task 5: Dati, catalogo, Shuffle e prompt installato

**Files:** Create `DataSource.swift` (copia di I4, cartella `Data`, `flux3.json`), `F3Catalog.swift`, `F3Shuffler.swift` (da `I4Shuffler`), `F3Prompts.swift` (da `I4Prompts`, cartella `prompt-master-f3`), `Scripts/make-f3-data.py`, `Embedded/EmbeddedData.swift` (generato); Test `DataTests.swift`, `CatalogTests.swift`, `ShufflerTests.swift`, `PromptsTests.swift`.

**Interfaces:**
- Produces: `struct F3Config: Codable, VersionedData { var schema: Int; var version: String; var excludedGroups: [String]; var photoCategories: [String]; var artCategories: [String]; var options: LanguageOptions }`; `struct F3Catalog { init(database: PromptDatabase, config: F3Config); func groups(mode: PhotoOrArt) -> [F3CatalogGroup]; func termSentence(picks: [String: String]) -> [String] }` (`en`, una voce per categoria); `F3Prompts.install(dataFolder:)`, `F3Prompts.system(in:) -> String`.

- [ ] **Step 1:** test `CatalogTests`: nessuna categoria del gruppo H (`render_quality`, `negative_terms`, `typography_text`) in nessun modo; con `mode: .photo` le categorie `photoCategories` e non quelle d'arte (e viceversa); `termSentence` dà le voci `en` nell'ordine delle categorie. `ShufflerTests` (da I4): al massimo 3 categorie, una voce ciascuna. `PromptsTests`: `install` scrive `master-prompt.md` e crea `custom/`; il file più vecchio dell'incorporato viene sostituito.
- [ ] **Step 2:** RED; implementare. L'elenco `photoCategories`/`artCategories` si ricava da `ideogram4.json` di I4 (gruppi A–G, toglie le categorie sugli oggetti che non servono a una scena con riquadri; il dettaglio si controlla guardando il file e si scrive in `make-f3-data.py`). Il master prompt incorporato è la bozza del §10 della spec.
- [ ] **Step 3:** GREEN. **Step 4:** commit.

### Task 6: Messaggio all'LLM e parser della risposta

**Files:** Create `F3Brief.swift`, `F3AnswerParser.swift`; Test `BriefTests.swift`, `AnswerParserTests.swift`.

**Interfaces:**
- Produces: `struct F3Part: Equatable { enum Kind: Equatable { case description, composition, element(id: String) }; var kind: Kind; var text: String; var terms: [String] }`; `enum F3Brief { static func parts(from document: F3Document, catalog: F3Catalog) -> [F3Part]; static func message(_ parts: [F3Part]) -> String }`; `enum F3AnswerParser { static func parse(_ answer: String, requested: [F3Part.Kind]) -> [F3Part.Kind: String] }`.

- [ ] **Step 1:** test `BriefTests`: il messaggio di una scena di esempio coincide con il blocco Markdown del §9 della spec (titoli `## description`, `## composition`, `## element: woman_1`; le voci come righe `Categoria: voce` in inglese sotto la descrizione; posizioni e colori assenti); finisce con la forma da riempire (stessi titoli, stesso ordine); parti vuote non richieste.
- [ ] **Step 2:** test `AnswerParserTests`: risposta pulita; con `<think>…</think>` e recinzioni ``` ; titoli in disordine; titolo mancante → assente dal risultato; testo avvolto da virgolette → ripulito; **risposta troncata a metà** → solo le parti complete; titolo scritto con maiuscole diverse o `element:woman_1` senza spazio.
- [ ] **Step 3:** RED, implementare. **Step 4:** GREEN. **Step 5:** commit.

### Task 7: Scrittura con controllo degli id, Annulla e cartella di lavoro

**Files:** Create `F3Writer.swift`, `F3WorkFolder.swift`; Modify `F3Snapshot.swift` (aggiunge `restore`); Test `WriterTests.swift`, `SnapshotTests.swift`, `WorkFolderTests.swift`.

**Interfaces:**
- Consumes: `F3Brief`, `F3AnswerParser`, `F3IDParser`, `F3Document`.
- Produces: `struct F3Snapshot: Codable, Equatable { var description: String; var picks: [String: String]; var composition: String; var descs: [String: String] }`; `struct F3Writer { var ask: (String, String, LanguageOptions) async -> String?; func write(document: F3Document, catalog: F3Catalog, system: String, options: LanguageOptions) async -> F3WriteResult }`; `struct F3WriteResult { var document: F3Document; var snapshot: F3Snapshot; var status: String; var request: String; var answer: String }`; `enum F3IDCheck { static func preserves(original: String, rewritten: String) -> Bool }` (stessi `<id>`, stesso numero di volte; le parole tra virgolette dell'originale compaiono identiche); `F3WorkFolder(folder:)` con `write(request:answer:before:)` su `llm/request.md`, `answer.md`, `before.md`.

- [ ] **Step 1:** test `WriterTests` (con un `ask` finto): risposta buona → testi sostituiti, voci scelte svuotate, `snapshot` con i testi di prima; **composizione con un id cambiato** → scartata, un nuovo tentativo da sola, poi originale e stato «l'LLM ha cambiato gli id»; id in più o in meno; parole tra virgolette di una `desc` cambiate → `desc` originale; parte mancante → ripiego con la sola parte; `ask` che dà `nil` → documento invariato e stato d'errore; **nessuna parte dell'utente si perde** in nessuno di questi casi.
- [ ] **Step 2:** test `SnapshotTests`: `restore` rimette descrizione, voci, composizione e `desc`; lo snapshot si spegne dopo l'uso; una seconda scrittura sostituisce lo snapshot; con id rinominati nel frattempo, `restore` rimette i testi e il documento si risincronizza.
- [ ] **Step 3:** test `WorkFolderTests`: i tre file esistono dopo una scrittura e si sostituiscono alla successiva.
- [ ] **Step 4:** RED, implementare. **Step 5:** GREEN. **Step 6:** commit.

### Task 8: Canvas

**Files:** Create `CanvasGeometry.swift` (copia di I4 con `CanvasItem { id: String; label: String; colorIndex: Int; box: BBox }`; niente creazione da trascinamento sul vuoto), `F3CanvasCard.swift`; Test `CanvasGeometryTests.swift`.

**Interfaces:** `CanvasMode` senza `.create`; `CanvasGeometry.begin(at:items:selected:) -> CanvasMode` restituisce `.none` sul vuoto; l'etichetta è l'id.

- [ ] **Step 1:** test (da I4, adattati): spostamento e ridimensionamento restano nella griglia e col lato minimo 20; **trascinare sul vuoto non produce nessuna modalità né box**; il clic sull'etichetta seleziona l'elemento; la selezione fa risaltare un solo box.
- [ ] **Step 2:** RED, adattare. **Step 3:** GREEN. **Step 4:** commit.

### Task 9: Le quattro card

**Files:** Create `F3View.swift`, `F3DescriptionCard.swift`, `F3CompositionCard.swift`, `F3ElementsCard.swift`, `F3Palette.swift`; Test `RenderTests.swift` (PNG dei tab con `F3_RENDER_DIR`, come I4), `PaletteTests.swift`.

**Interfaces:** `F3Palette.color(index: Int) -> Color` (otto colori in rotazione, lo stesso per testo, canvas e scheda); `F3CompositionCard` evidenzia gli `<id>` con il colore dell'elemento, mostra solo casella, didascalia «Aggiungi un `<ID>` nel testo per creare un Elemento.» e l'avviso dell'id ripetuto; `F3ElementsCard` ha schede (chip dell'id, descrizione, posizione modificabile con `BBox.resolve`, su/giù, rimuovi) e in fondo **Annulla**, **Scrivi con LLM**, **Invia**, riga di stato.

- [ ] **Step 1:** test `PaletteTests`: `color(index: 8) == color(index: 0)`; i primi otto sono distinti. `RenderTests`: il tab con documento di esempio (cinque elementi, un id ripetuto) produce un PNG non vuoto di larghezza attesa e **la card Composizione ha altezza ≤ quella della card Descrizione**.
- [ ] **Step 2:** costruire le viste dal mockup `2026-10-20-prompt-master-f3.html` (le cose del kit: `DSCard`, `DSButton`…); testi in `L` (it/en), il test di catalogo deve passare. **Step 3:** `swift test` — PASS. **Step 4:** commit.

### Task 10: Collegamento al plug-in

**Files:** Modify `F3Plugin.swift`; Test `PluginTests.swift`.

**Interfaces:** `handle` per `context` (`GenerationSize.read` → `state.update`), `project`, `activate`, `deactivate`; `write()` (usa `host.askLanguageModelAnswer`, `F3Writer`, `F3WorkFolder`, `F3Prompts.system`, opzioni da `F3Config`); `undo()` (`F3Snapshot.restore`); `send()` (`F3Sender` copia di `I4Sender` con `fields: ["prompt": text, "negativePrompt": ""]`).

- [ ] **Step 1:** test `PluginTests` (con un host finto): `send` manda esattamente `F3Composer.text` con il negativo vuoto; non invia con `canSend == false`; `write` non parte con nessun testo e nessuna voce; `undo` ripristina; un messaggio `project` cambia la cartella dello stato.
- [ ] **Step 2:** RED, implementare. **Step 3:** GREEN. **Step 4:** `Plugins/PromptMasterF3/Scripts/build.sh "$TMPDIR/pm-f3"` e controllo `file -b …/Contents/MacOS/PromptMasterF3` («shared library») e `codesign --verify --deep --strict`. **Step 5:** commit.

### Task 11: README e documentazione

**Files:** Create `Plugins/PromptMasterF3/README.md` (inglese); Modify `Plugins/README.md` (riga e link di installazione), `README.md` (elenco dei plug-in: da dieci a undici, solo alla release).

- [ ] **Step 1:** README: famiglia, come si usa (le quattro card), formato del prompt, file dei dati, **nessun LoRA richiesto** (regola dei link ai LoRA: non applicabile), screenshot da fare a mano. **Step 2:** commit del solo `README.md` del plug-in e della riga in `Plugins/README.md` quando il plug-in è pronto per la release (non prima).

### Task 12: Verifiche dal vivo (in due tempi)

**12a — subito, con FLUX.2 klein:** installare il bundle (`rm -rf` della vecchia versione, poi riavvio) e provare nell'app **tutto fino alla generazione del prompt**: le quattro card, `<id>` → box e scheda, canvas, Shuffle, «Scrivi con LLM» con l'LLM vero (master prompt e controllo degli id), Annulla, riavvio con lo stato, «Invia» che mette il testo nel Prompt. Il Run con FLUX.2 non vale: il modello non capisce il formato.

**12b — BLOCCATO finché FLUX.3 Klein non è in Draw Things:**

- [ ] **Step 1:** aggiungere a `F3Plugin.families` l'id vero.
- [ ] **Step 2:** provare a mano un prompt generato: formato delle coordinate nel campo Prompt (0–1000 o 0–1: se 0–1, cambiare **solo** `BBoxScale` e la scrittura nel JSON di `F3Composer`), resa dei riquadri, lunghezza massima del prompt.
- [ ] **Step 3:** prova dell'LLM con il modello vero dell'utente su tre scene (il master prompt: accorciarlo se sbaglia i titoli o gli id), esito nella spec §12–14.
- [ ] **Step 4:** aggiornare spec e briefing con gli esiti; release solo con via libera esplicito (regole del briefing).

---

## Auto-revisione

- **Copertura della spec:** §1–2 formato → T1; §3 famiglia → T0/T12b; §4 dati → T5; §5 testo e Invia → T1, T4, T10; §6 interfaccia → T9; §7 id → T2, T4; §8 canvas → T3, T8; §9 LLM, controllo id, Annulla → T6, T7, T10; §10 master prompt → T5; §11 stato e `llm/` → T4, T7; §12 test → in ogni task; §13 decisioni → nei vincoli globali; §14 rischi → T12.
- **Coerenza dei tipi:** `F3Element` (T1) è usato da T2, T3, T4, T7, T9; `F3Snapshot` nasce in T4 (la struct) e T7 aggiunge `restore`. `F3Problem` (T1) è usato da `F3State.problems` (T4) e dalla card (T9).
- **Ordine:** T0–T11 e 12a non dipendono da FLUX.3 (si usano le famiglie FLUX.2 klein); solo 12b è bloccato.

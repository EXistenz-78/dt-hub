# Selettore dei modelli con DT+ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Con DT+ acceso, sostituire il menu dei modelli con un pannello con ricerca e un albero collassabile Official / Community / Uncurated › famiglie, aggiungendo alla lista DT+ i modelli Official.

**Architecture:** Ogni modello del catalogo DT+ porta la sua origine (`ModelSource`); una terza lista (Official) si scarica come le altre due; una logica pura in `HubCore` (`ModelTree`) costruisce albero, filtro e conteggi; la vista nuova sta nell'app e sostituisce il menu solo con DT+ acceso.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`import Testing`, `@Test`), `CachedDownload` (HubKit) per le liste.

**Spec:** `docs/superpowers/specs/2026-10-16-selettore-modelli-dt-plus-design.md` (leggerla prima: decisioni, fonti, misure).

## Global Constraints

- Si risponde in italiano; testi dell'app in italiano **e** inglese (`App/Localizable.xcstrings`; `LocalizationCatalogTests` lo controlla); README in inglese. I nomi «Official», «Community», «Uncurated» restano in inglese in entrambe le lingue.
- Solo `DTBridge` conosce DrawThings-Swift; `HubKit` e `HubCore` no. Con DT+ **spento** non cambia niente: il menu e `modelsByFamily` restano com'erano.
- Liste (nomi corretti): **Official** = `https://kcjerrell.github.io/dt-models/official_models.json` (129 voci, campi in camelCase, 16 `deprecated`); **Community** = `https://models.drawthings.ai/models.json` (253); **Uncurated** = `https://models.drawthings.ai/uncurated_models.json` (384). I **nomi dei file di cache restano** `models-list.json` (Community) e `community-models-list.json` (Uncurated); Official: `official-models-list.json`.
- Origine di un file in più liste: Official > Community > Uncurated.
- Con DT+ acceso: i modelli locali fuori da ogni lista sono **nascosti**; gli Official `deprecated` non installati sono nascosti; i remoti hanno la nuvola (`isRemote`).
- Albero: solo Official aperto di default; Community, Uncurated e famiglie chiuse; stato aperto/chiuso tenuto finché l'app è in esecuzione; cursore nel campo di ricerca all'apertura, Esc chiude; pannello circa 340 × 420 pt.
- Test (Swift Testing, prima il test visto fallire): `cd Packages && swift test --filter <Suite> 2>&1 | grep -E "Test run with|✘|error:"`. In questo worktree la **prima** compilazione dei pacchetti richiede alcuni minuti (mlx).
- Commit per nome di file (mai `git add -A`), sul ramo `feat/model-picker` (worktree `.worktrees/model-picker`); messaggi in inglese con la riga `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Niente push, niente unione in `main` senza via libera dell'utente.
- Catalogo dei testi: `App/Localizable.xcstrings` si modifica con Python `json.load` / `json.dumps(d, ensure_ascii=False, indent=2, separators=(',', ': '))` + riga finale (round-trip identico al file); ogni chiave nuova ha `"extractionState": "manual"` e le localizzazioni `en` e `it`.

## Review Focus

1. **Elenchi non scaricabili e mai salvati** (Official offline): il catalogo si costruisce senza crash; secondo la spec i locali fuori lista restano nascosti (Task 3).
2. **Modello scelto fuori dall'albero** (un locale fuori lista, DT+ appena acceso): il pulsante mostra ancora il nome, il pannello non lo elenca e non crasha (Task 6).
3. **Ricerca di soli spazi o con accenti** («flux  », «Flüx»): i soli spazi valgono ricerca vuota; accenti e maiuscole non contano (Task 5).
4. **Stessa famiglia in due origini** (`flux1` in Community e in Uncurated): sono due gruppi distinti con conteggi propri, e lo stato aperto/chiuso di uno non tocca l'altro (Task 5).
5. **Voci senza `file` o con chiavi già in snake_case** nell'elenco Official: si saltano / non si alterano (Task 2).

---

### Task 1: Origine del modello e raggruppamento in HubKit

**Files:**
- Create: `Packages/Sources/HubKit/Catalog/ModelSource.swift`
- Modify: `Packages/Sources/HubKit/Catalog/ModelCatalog.swift` (`CatalogModel` riga ~2-22; `ModelCatalog.modelsByFamily` riga ~85)
- Test: `Packages/Tests/HubKitTests/ModelCatalogTests.swift`

**Interfaces:**
- Produces:
  - `public enum ModelSource: Int, CaseIterable, Comparable, Sendable { case official, community, uncurated }` (ordine di visualizzazione = ordine dei case).
  - `CatalogModel.source: ModelSource?` (`let`); `CatalogModel.init(file:name:family:capabilities:isRemote:source:)` con `source: ModelSource? = nil` come ultimo parametro; `public func with(source: ModelSource?, isRemote: Bool) -> CatalogModel`.
  - `public struct ModelSourceGroup: Identifiable, Equatable, Sendable { public var id: ModelSource { source }; public let source: ModelSource; public let families: [ModelFamilyGroup]; public var count: Int }`.
  - `ModelCatalog.modelsBySource: [ModelSourceGroup]`: un gruppo per ogni origine che ha modelli, nell'ordine di `ModelSource.allCases`; dentro le famiglie ordinate come `modelsByFamily`; i modelli con `source == nil` non compaiono.

- [ ] **Step 1: Test** in `ModelCatalogTests`: `modelsBySourceGroupsInTheFixedOrder` (modelli: community `flux2_9b`, official `flux1`, uncurated `flux1`, uno senza origine → `modelsBySource.map(\.source) == [.official, .community, .uncurated]`, il modello senza origine non è in nessun gruppo); `theSameFamilyIsASeparateGroupInEachSource` (`flux1` in community e uncurated → due gruppi con conteggi propri); `anEmptySourceHasNoGroup`; `settingTheSourceKeepsTheRest` (`with(source: .official, isRemote: true)` conserva file, nome, famiglia, capacità).
- [ ] **Step 2: Fallisce** (`--filter ModelCatalogTests`): «cannot find type 'ModelSource'».
- [ ] **Step 3: Implementare** i tipi sopra; `modelsBySource` riusa la logica di ordinamento di `modelsByFamily` (estrarre una funzione privata che raggruppa un `[CatalogModel]` in `[ModelFamilyGroup]`).
- [ ] **Step 4: Verde**, poi tutta `HubKitTests` (nessuna regressione).
- [ ] **Step 5: Commit** `feat: model source and grouping by source in the catalog`.

---

### Task 2: La lista Official e i nomi corretti (DTBridge)

**Files:**
- Modify: `Packages/Sources/DTBridge/LiveModelList.swift`; `Packages/Sources/DTBridge/DrawThingsBackend.swift` (solo i nomi, vedi sotto)
- Test: `Packages/Tests/DTBridgeTests/LiveModelListTests.swift`, `DTPlusTests.swift`

**Interfaces:**
- Consumes: `CachedDownload` (HubKit).
- Produces:
  - `LiveModelList.shared` → rinominato **`LiveModelList.community`** (Community, `models.json`, cache `models-list.json`); `LiveModelList.community` → rinominato **`LiveModelList.uncurated`** (cache `community-models-list.json`, `uncuratedAddress` al posto di `communityAddress`); nuovo **`LiveModelList.official`** (`officialAddress`, cache `official-models-list.json`). I commenti dei tre (e di `DrawThingsBackend`) dicono Official / Community / Uncurated.
  - `LiveModelList.init(cacheURL:address:download:now:)` gets `parser: @escaping @Sendable (Data) -> [String: Data] = LiveModelList.parse` (l'Official passa `LiveModelList.parseOfficial`).
  - `static func parseOfficial(_ data: Data) -> [String: Data]`: come `parse` ma ogni chiave con maiuscole è convertita in snake_case (`defaultScale` → `default_scale`, `textEncoder` → `text_encoder`), le chiavi già in snake_case restano, `deprecated` non entra nella specifica; voci senza `file` saltate.
  - `static func deprecatedFiles(_ data: Data) -> Set<String>` e `public func deprecated() async -> Set<String>` (i file con `"deprecated": true`; vuoto se la lista non c'è).

- [ ] **Step 1: Test:** `officialEntriesBecomeSpecsInSnakeCase` (`{"file":"a.ckpt","name":"A","version":"flux1","defaultScale":16,"textEncoder":"t5.ckpt","deprecated":true}` → JSON della specifica con `default_scale == 16`, `text_encoder`, `version`, senza `deprecated`); `snakeCaseKeysAreLeftAlone`; `officialEntriesWithoutAFileAreSkipped` (**Review Focus 5**); `theDeprecatedFilesAreListedApart`; `theOfficialListHasItsOwnAddressAndCache` (`officialAddress.absoluteString == "https://kcjerrell.github.io/dt-models/official_models.json"`); `withoutTheNetworkTheSavedOfficialListIsUsed` (come il test esistente per Community); aggiornare `DTPlusTests` (`communityAddress` → `uncuratedAddress`).
- [ ] **Step 2: Fallisce** (`--filter "LiveModelListTests|DTPlusTests"`).
- [ ] **Step 3: Implementare** come sopra; cercare con `grep -rn "LiveModelList\.\(shared\|community\)\|communityAddress" Packages App` tutti gli usi e aggiornarli (`DrawThingsBackend.init` passa `liveModels: .community`, `communityModels: .uncurated` per ora; i campi si rinominano nel Task 3).
- [ ] **Step 4: Verde** (`--filter "LiveModelListTests|DTPlusTests"`), poi tutta `DTBridgeTests`.
- [ ] **Step 5: Commit** `feat: the Official model list, and the lists named as Draw Things names them`.

---

### Task 3: Catalogo DT+ con origine, Official e filtro dei locali

**Files:**
- Modify: `Packages/Sources/DTBridge/CatalogBuilder.swift` (`addingRemoteModels` riga ~43, `cloudCatalog` riga ~60); `Packages/Sources/DTBridge/DrawThingsBackend.swift` (campi, `init`, `fetchCatalog`, `registerRemoteSpec`)
- Test: `Packages/Tests/DTBridgeTests/DTPlusTests.swift` (`RemoteModelsTests`, `CloudCatalogTests`)

**Interfaces:**
- Consumes: `ModelSource`, `CatalogModel.with(source:isRemote:)` (Task 1); `LiveModelList.official/.community/.uncurated`, `deprecated()` (Task 2).
- Produces:
  - `CatalogBuilder.addingRemoteModels(to:live:sources:)` con `sources: [String: ModelSource] = [:]`: i modelli aggiunti ricevono `source` da `sources[file]`.
  - `CatalogBuilder.cloudCatalog(local:specs:sources:deprecated:cloudFiles:cloudLoRAs:)` con `sources: [String: ModelSource]` e `deprecated: Set<String>`: modelli = **locali** con `cloudFiles.contains(file) && sources[file] != nil`, ricostruiti con `with(source: sources[file], isRemote: false)`, **più remoti** (file in `specs`, nel cloud, non locali, non in `deprecated`), `isRemote: true`, `source` da `sources`. I LoRA restano come oggi.
  - `DrawThingsBackend`: campi `officialModels`, `communityModels` (ex `liveModels`), `uncuratedModels` (ex `communityModels`); l'`init` interno prende `officialModels: LiveModelList? = nil` accanto agli altri; `fetchCatalog` con DT+ unisce le specifiche con priorità Official > Community > Uncurated, costruisce `sources` (stessa priorità) e `deprecated`; `registerRemoteSpec` cerca la specifica in Official, poi Community, poi Uncurated.

- [ ] **Step 1: Test** (aggiornare `CloudCatalogTests`: `catalog` passa `sources`, `deprecated: []`; i locali del test stanno in `sources`): `theOriginOfAModelIsTheFirstListThatHasIt` (file in Official e Community → `.official`); `anInstalledModelNotInAnyListIsHidden` (**spec §2**: locale nel cloud ma assente da `sources` → fuori dal catalogo); `anInstalledListedModelKeepsTheServerDescriptionAndGetsItsSource`; `aDeprecatedOfficialModelIsHiddenUnlessInstalled` (deprecato non installato → assente; deprecato installato → presente); `withoutAnyListEverythingLocalIsHidden` (**Review Focus 1**: `sources` vuoto → nessun modello e nessun crash); `addingRemoteModelsSetsTheSourceWhenGiven` (e senza `sources` il comportamento di oggi: i test esistenti restano verdi).
- [ ] **Step 2: Fallisce** (`--filter "RemoteModelsTests|CloudCatalogTests"`).
- [ ] **Step 3: Implementare** i builder e il backend come sopra (il test di `DrawThingsBackendTests` che costruisce il backend con le liste va aggiornato per i nomi).
- [ ] **Step 4: Verde**, poi tutte le suite: `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"`.
- [ ] **Step 5: Commit** `feat: DT+ catalog with the source of each model, Official included`.

---

### Task 4: Punto di controllo con l'utente (prova dell'Official non scaricato)

Nessun codice. Serve per sapere, prima di costruire l'interfaccia, se gli Official girano dal solo elenco (spec §8, fase 2; §9).

**Files:** nessuno.

- [ ] **Step 1: Compilare l'app dal worktree:** dalla cartella del worktree, `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"`. Atteso: `BUILD SUCCEEDED`. L'app è in `.worktrees/model-picker/build/Build/Products/Debug/DT Hub.app` (ha lo stesso identificatore dell'app dell'utente: va aperta solo da lui, a copie chiuse).
- [ ] **Step 2: Chiedere all'utente la prova:** con DT+ acceso, nel menu (ancora quello lungo) scegliere un Official non scaricato (per esempio «FLUX.1 [schnell]») e lanciare un RUN breve (pochi passi); riferire se genera, e il messaggio se non genera. Gli Official non scaricati ora compaiono nell'elenco con la nuvola.
- [ ] **Step 3: Esito:** se genera, proseguire. **Se non genera, fermarsi** e decidere con l'utente come completare i dati del modello (spec §9) prima del Task 5; registrare l'esito nella spec §11.
- [ ] **Step 4: Commit** (solo se la spec cambia) `docs: outcome of the Official-model probe`.

---

### Task 5: La logica dell'albero in HubCore

**Files:**
- Create: `Packages/Sources/HubCore/ModelPicker/ModelTree.swift`
- Test: `Packages/Tests/HubCoreTests/ModelTreeTests.swift`

**Interfaces:**
- Consumes: `ModelCatalog.modelsBySource`, `ModelSource`, `CatalogModel` (Task 1).
- Produces (tutti `public`, `Equatable`, `Sendable`):
  - `struct ModelTreeFamilyID: Hashable { source: ModelSource; family: String? }`.
  - `struct ModelTreeState { var expandedSources: Set<ModelSource> = [.official]; var expandedFamilies: Set<ModelTreeFamilyID> = []; mutating func toggle(_ source: ModelSource); mutating func toggle(_ family: ModelTreeFamilyID) }`.
  - `struct ModelTreeFamily: Identifiable { var id: ModelTreeFamilyID; family: String?; count: Int; isExpanded: Bool; models: [CatalogModel] }`.
  - `struct ModelTreeSection: Identifiable { var id: ModelSource; source: ModelSource; count: Int; isExpanded: Bool; families: [ModelTreeFamily] }`.
  - `enum ModelTree { static func sections(for catalog: ModelCatalog, query: String, state: ModelTreeState) -> [ModelTreeSection] }`: senza ricerca (`query` vuota o di soli spazi) le sezioni sono tutte quelle con modelli, `isExpanded` dallo stato, `count` = tutti i modelli del gruppo; con ricerca solo i modelli che combaciano (`localizedStandardContains` su nome, file e famiglia, senza maiuscole/accenti), solo i gruppi con risultati, `isExpanded == true` a ogni livello, `count` = i risultati.

- [ ] **Step 1: Test** (con `@MainActor` se il compilatore lo chiede per i tipi di HubCore): `theInitialStateOpensOnlyOfficial` (sezioni nell'ordine Official/Community/Uncurated; `isExpanded` solo la prima; nessuna famiglia aperta); `countsAreTheModelsOfEachGroup`; `togglingASourceOrAFamilyChangesOnlyIt` (**Review Focus 4**: `flux1` in Community e Uncurated; aprire quella di Community non apre quella di Uncurated); `searchMatchesNameFileAndFamily`; `searchIgnoresCaseAndAccents` (**Review Focus 3**: «FLÜX» trova «flux»); `onlySpacesIsNoSearch`; `searchOpensEveryGroupWithResultsAndHidesTheRest`; `clearingTheSearchGoesBackToTheState` (stesso `state`, query vuota → come prima); `noResultsGivesNoSections`; `aSourceWithoutModelsIsOmitted`.
- [ ] **Step 2: Fallisce** (`--filter ModelTreeTests`).
- [ ] **Step 3: Implementare** `ModelTree.sections` e i `toggle`.
- [ ] **Step 4: Verde**, poi tutta `HubCoreTests`.
- [ ] **Step 5: Commit** `feat: model tree: groups, search and open/closed state`.

---

### Task 6: Pannello, collegamento nell'header e testi

**Files:**
- Create: `App/MainWindow/ModelPickerView.swift`
- Modify: `App/MainWindow/HeaderBar.swift` (`modelMenu`, riga ~132), `App/Localizable.xcstrings`
- Test: nessun test di vista; `LocalizationCatalogTests` e la compilazione.

**Interfaces:**
- Consumes: `ModelTree`, `ModelTreeState`, `ModelTreeSection` (Task 5); `generation.chooseModel(_:in:)`, `connection.dtPlus`, `connection.canUseDTPlus`, `monitor.catalog`, `selection.selectedFile`.
- Produces: `struct ModelPickerView: View` con `catalog: ModelCatalog`, `selectedFile: String?`, `state: Binding<ModelTreeState>`, `onSelect: (CatalogModel) -> Void`; in `HeaderBar` un `@State private var modelTree = ModelTreeState()` e `modelMenu` che con `connection.dtPlus && connection.canUseDTPlus` mostra un `Button` con la stessa etichetta (`DSMenuLabel`) e un `.popover` con `ModelPickerView`, altrimenti il menu di oggi **invariato**.

- [ ] **Step 1: Chiavi di testo** (en / it): `header.model.search` («Search models» / «Cerca un modello»), `header.model.noResults` («No models» / «Nessun modello»), `modelpicker.row.cloud` («in the cloud» / «in cloud»), `modelpicker.row.selected` («selected» / «scelto»). Aggiornare il catalogo con lo script Python descritto nei vincoli; `swift test --filter CatalogTests` verde.
- [ ] **Step 2: `ModelPickerView`:** campo di ricerca in alto (`@FocusState`, a fuoco all'apertura; Esc chiude con `.onExitCommand`); sotto uno `ScrollView` con `LazyVStack` delle sezioni da `ModelTree.sections(for:query:state:)`: intestazione di sezione come bottone (chevron, «Official · 107»), famiglie come intestazioni di livello 2 con conteggio, righe con nome, nuvola per `isRemote` e spunta per il `selectedFile`; clic su una riga = `onSelect` e chiusura. Dimensioni 340 × 420 pt massimo; etichette per VoiceOver (nome, «in cloud», «scelto»); con catalogo vuoto o non collegato, gli stessi messaggi del menu di oggi (`header.model.unavailable`, `connection.noModelsText`, `header.model.empty`). Il modello scelto fuori dall'albero (**Review Focus 2**) non è elencato e non dà errore; il pulsante continua a mostrare `modelTitle`.
- [ ] **Step 3: Collegare `HeaderBar.modelMenu`** come descritto; il menu con DT+ spento resta identico (nessuna modifica a `modelMenuContent`).
- [ ] **Step 4: Compilare:** `xcodebuild -project DTHub.xcodeproj -scheme DTHub -destination 'platform=macOS' -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"` → `BUILD SUCCEEDED`; poi `cd Packages && swift test` verde (compresi i test dei testi).
- [ ] **Step 5: Commit** `feat: model picker with search and collapsible groups for DT+`.

---

### Task 7: Chiusura: documentazione, revisione, prove a mano

**Files:**
- Modify: `README.md` (una frase in inglese nella voce DT+: tre liste, ricerca, albero); `docs/superpowers/briefing-prossima-sessione.md` e nota Obsidian `DT Hub` (locali, non in git)

- [ ] **Step 1: Suite completa:** `cd Packages && swift test 2>&1 | grep -E "Test run with|✘|error:"` verde.
- [ ] **Step 2: Controllo dati personali** nei file nuovi, con il comando del briefing (release, punto 2): nessun risultato.
- [ ] **Step 3: Revisione dell'intero ramo** (un giro, a un revisore indipendente con il pacchetto di `review-package`): coerenza dei nomi tra i task, ogni punto della spec §2–§6 coperto, i cinque casi del Review Focus testati.
- [ ] **Step 4: Prove a mano per l'utente** (nel messaggio finale): DT+ spento = menu di sempre; DT+ acceso = pannello, solo Official aperto, ricerca (accenti, famiglia), conteggi, scelta di un modello, un Official non scaricato in lista, riapertura che conserva lo stato.
- [ ] **Step 5: Commit** `docs: model picker in the README`. **Poi fermarsi:** niente unione in `main`, niente push, niente release senza il via libera esplicito dell'utente (dopo l'unione: ricompilare l'app Debug e dirgli di riavviarla).

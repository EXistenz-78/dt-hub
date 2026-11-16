# Tab in finestra separata Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ogni tab della finestra principale (Control, Generazione, plug-in) si può staccare in una finestra propria e torna nella barra chiudendola.

**Architecture:** `WorkspaceState` (HubCore) sa quali tab sono staccati e applica le regole di selezione. Una scena SwiftUI per valore (`WindowGroup(id:for: String.self)`) mostra il contenuto di un tab; la stessa vista `WorkspaceTabContent` serve la finestra principale e quella staccata. La barra dei tab stacca prima lo stato e poi apre la finestra, così il controller di un plug-in non sta mai in due finestre.

**Tech Stack:** Swift 6, SwiftUI (macOS 26), Swift Testing, pacchetto `Packages` (HubCore), app Xcode `DTHub.xcodeproj`.

**Spec:** `docs/superpowers/specs/2026-11-16-tab-in-finestra-separata-design.md`

## Global Constraints

- I plug-in (`Plugins/`, `PluginKit/`) non si toccano: nessuna modifica al contratto né a `DSTabButtonStyle`.
- Nessun ripristino al riavvio: `detachedTabIDs` non si salva; la scena usa `.restorationBehavior(.disabled)`.
- Finestra nuda: niente `HeaderBar`, coda o banner nella finestra del tab.
- Arancione di sistema: `Color.orange`.
- Stringhe in `App/Localizable.xcstrings`, inglese (sorgente) e italiano, `extractionState: manual`.
- Commenti nel codice in inglese, nello stile dei file esistenti. Lavoro su un ramo `feat/tab-finestra`, mai su `main`.

## Review Focus

- Plug-in staccato che viene spento (o diventa incompatibile col modello): la finestra si chiude, nessun tab fantasma arancione. → test in Task 1, verifica dal vivo in Task 4.
- Tutti i tab staccati: la finestra principale mostra la riga di nota, non crasha; ⌃Pag↑/↓ non fa nulla. → test in Task 1.
- Clic ripetuto / Option-clic su un tab già staccato: una sola finestra, portata avanti. → verifica dal vivo in Task 4 (`openWindow(id:value:)` lo garantisce).
- Chiusura della finestra di un tab mentre un altro è aperto nella principale: il tab chiuso diventa quello aperto. → test in Task 1.
- Passaggio del controller del plug-in tra le due finestre nei due versi: contenuto visibile e funzionante. → verifica dal vivo in Task 4.

---

### Task 1: Tab staccati in `WorkspaceState`

**Files:**
- Modify: `Packages/Sources/HubCore/Workspace/WorkspaceState.swift`
- Test: `Packages/Tests/HubCoreTests/WorkspaceStateTests.swift`

**Interfaces:**
- Produces:
  - `public private(set) var detachedTabIDs: Set<WorkspaceTab.ID>`
  - `public private(set) var selectedTabID: WorkspaceTab.ID?` (era non opzionale; `nil` = tutti staccati)
  - `public func isDetached(_ id: WorkspaceTab.ID) -> Bool`
  - `public func detach(_ id: WorkspaceTab.ID)`
  - `public func attach(_ id: WorkspaceTab.ID)`

- [ ] **Step 1: Scrivere i test che falliscono** (in `WorkspaceStateTests`, con gli helper già presenti)

```swift
@Test func detachingTheOpenTabOpensGeneration() {
  let state = state()
  state.setPluginTabs([promptMaster])
  state.select(promptMaster.id)
  state.detach(promptMaster.id)
  #expect(state.isDetached(promptMaster.id))
  #expect(state.tabs.contains(promptMaster))
  #expect(state.selectedTabID == WorkspaceTab.generationID)
}

@Test func detachingGenerationOpensControlThenTheFirstTabLeft() {
  let state = state()
  state.setPluginTabs([promptMaster])
  state.detach(WorkspaceTab.generationID)
  #expect(state.selectedTabID == WorkspaceTab.controlID)
  state.detach(WorkspaceTab.controlID)
  #expect(state.selectedTabID == promptMaster.id)
  state.detach(promptMaster.id)
  #expect(state.selectedTabID == nil)
}

@Test func detachingAnotherTabKeepsTheOpenOne() {
  let state = state()
  state.detach(WorkspaceTab.controlID)
  #expect(state.selectedTabID == WorkspaceTab.generationID)
}

@Test func aDetachedTabCannotBeSelected() {
  let state = state()
  state.detach(WorkspaceTab.controlID)
  state.select(WorkspaceTab.controlID)
  #expect(state.selectedTabID == WorkspaceTab.generationID)
}

@Test func attachingOpensTheTab() {
  let state = state()
  state.detach(WorkspaceTab.controlID)
  state.attach(WorkspaceTab.controlID)
  #expect(!state.isDetached(WorkspaceTab.controlID))
  #expect(state.selectedTabID == WorkspaceTab.controlID)
}

@Test func nextAndPreviousSkipDetachedTabs() {
  let state = state()
  state.setPluginTabs([promptMaster, sphereLight])   // promptMaster, sphereLight, control, generation
  state.detach(WorkspaceTab.controlID)
  state.selectPrevious()
  #expect(state.selectedTabID == sphereLight.id)
  state.selectNext()
  #expect(state.selectedTabID == WorkspaceTab.generationID)
}

@Test func nextDoesNothingWhenEveryTabIsDetached() {
  let state = state()
  state.detach(WorkspaceTab.generationID)
  state.detach(WorkspaceTab.controlID)
  state.selectNext()
  #expect(state.selectedTabID == nil)
}

@Test func aPluginTabThatGoesIsNoLongerDetached() {
  let state = state()
  state.setPluginTabs([promptMaster])
  state.detach(promptMaster.id)
  state.setPluginTabs([])
  #expect(!state.isDetached(promptMaster.id))
  state.attach(promptMaster.id)   // the window closing afterwards
  #expect(state.selectedTabID == WorkspaceTab.generationID)
}

@Test func detachingAnUnknownTabIsIgnored() {
  let state = state()
  state.detach("nope")
  #expect(state.detachedTabIDs.isEmpty)
}

@Test func detachingDoesNotChangeTheRememberedTab() {
  let defaults = UserDefaults(suiteName: "WorkspaceStateTests-\(UUID())")!
  let state = state(defaults)
  state.select(WorkspaceTab.controlID)
  state.detach(WorkspaceTab.controlID)
  #expect(defaults.string(forKey: WorkspaceState.selectedTabKey) == WorkspaceTab.controlID)
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test --package-path Packages --filter WorkspaceStateTests`
Expected: errore di compilazione («no member 'detach'»).

- [ ] **Step 3: Implementare in `WorkspaceState.swift`**

- `detach`: ignora un id non in `tabs`; inserisce; se era `selectedTabID`, imposta il sostituto senza scrivere nelle preferenze: Generazione, poi Control, poi il primo di `tabs` non staccato, altrimenti `nil`.
- `attach`: rimuove l'id; se il tab è in `tabs` chiama `select(id)`.
- `select(_:)`: ignora anche un id staccato.
- `select(offset:)`: lavora su `tabs.filter { !isDetached($0.id) }`; senza tab aperto non fa nulla.
- `setPluginTabs`: `detachedTabIDs` si interseca con gli id di `tabs`; se il tab aperto è sparito usa lo stesso sostituto di `detach`.

- [ ] **Step 4: Verificare che passino**

Run: `swift test --package-path Packages --filter WorkspaceStateTests`
Expected: 22 test passati (12 esistenti + 10 nuovi).

- [ ] **Step 5: Commit** — `git commit -m "Workspace: tabs can be detached from the main window"`

### Task 2: Finestra del tab e contenuto condiviso

**Files:**
- Create: `App/MainWindow/TabWindow.swift`
- Modify: `App/MainWindow/MainWindowView.swift` (righe 40 e 74-89), `App/DTHubApp.swift` (scene, dopo la finestra del Canvas), `DTHub.xcodeproj/project.pbxproj` solo se il progetto non usa cartelle sincronizzate, `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1 (`detach`, `attach`, `isDetached`, `selectedTabID: String?`).
- Produces:
  - `enum TabWindow { static let id = "tab" }`
  - `struct WorkspaceTabContent: View` con `init(tabID: WorkspaceTab.ID, workspace: WorkspaceState, generation: GenerationController, connection: DrawThingsConnection, plugins: PluginRegistry)`
  - `struct TabWindowView: View` con gli stessi parametri (`tabID` è il valore della scena)

- [ ] **Step 1: `WorkspaceTabContent`** in `TabWindow.swift`: l'`if/else` oggi in `MainWindowView.tabContent`, sul `tabID` ricevuto (il `PluginTabView` conserva `.id(tabID)`). `openControl` del tab Generazione chiama una closure d'ambiente/parametro `showTab: (WorkspaceTab.ID) -> Void` fornita dal chiamante (vedi Step 3).

- [ ] **Step 2: `MainWindowView`** usa `WorkspaceTabContent` per `workspace.selectedTabID`; con `nil` mostra `Text("tabs.allDetached")` in `.callout`, `.secondary`, centrato. L'`onChange(of: workspace.selectedTabID)` resta.

- [ ] **Step 3: `TabWindowView`**
  - corpo: `WorkspaceTabContent` in `Color.clear.overlay { }`, `.padding(20)`, `.frame(minWidth: 520, idealWidth: 900, minHeight: 420, idealHeight: 760)`, `.background(DSBackground())`, `.background(DSWindowConfigurator())`, `.tint(DS.accent)`, `.environment(plugins)`, `.environment(plugins.contributions)`, `.navigationTitle(titolo del tab)`;
  - `.background(WindowFrameKeeper(key: "tabWindow.frame.\(tabID)", minSize: CGSize(width: 520, height: 420)))`;
  - `.onAppear { workspace.detach(tabID); plugins.refreshContext() }`, `.onDisappear { workspace.attach(tabID) }`;
  - `.onChange(of: workspace.isDetached(tabID), initial: true)`: se il tab non è in `workspace.tabs`, oppure non è più staccato dopo la comparsa, `dismissWindow(id: TabWindow.id, value: tabID)`;
  - «mostra un tab» (usato da `openControl`, in entrambe le finestre): se staccato `openWindow(id: TabWindow.id, value: id)`, altrimenti `workspace.select(id)` e la finestra principale non viene portata avanti.

- [ ] **Step 4: scena in `DTHubApp.body`**

```swift
WindowGroup(id: TabWindow.id, for: String.self) { $tabID in
  if let tabID {
    TabWindowView(tabID: tabID, workspace: workspace, generation: generation, connection: connection, plugins: plugins)
      .environment(canvasWindow)
      .environment(remote)
  }
}
.windowResizability(.contentMinSize)
.restorationBehavior(.disabled)
.commandsRemoved()
```

- [ ] **Step 5: stringa** `tabs.allDetached`: en «All tabs are in separate windows», it «Tutti i tab sono in finestre separate».

- [ ] **Step 6: build**

Run: `xcodebuild -project DTHub.xcodeproj -scheme DTHub -configuration Debug build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit** — `git commit -m "A window that shows one tab; the tab's content in a view of its own"`

### Task 3: Barra dei tab e scorciatoie

**Files:**
- Modify: `App/MainWindow/WorkspaceTabBar.swift`, `App/Localizable.xcstrings`

**Interfaces:**
- Consumes: `TabWindow.id`, `workspace.detach`, `workspace.isDetached`.

- [ ] **Step 1: clic.** L'azione del pulsante: se il tab è staccato, oppure `NSEvent.modifierFlags.contains(.option)`, chiama `workspace.detach(tab.id)` e poi `openWindow(id: TabWindow.id, value: tab.id)`; altrimenti `workspace.select(tab.id)`. L'ordine (prima `detach`, poi `openWindow`) è obbligatorio: il controller del plug-in lascia la finestra principale prima che l'altra lo ospiti.

- [ ] **Step 2: aspetto.** `WorkspaceTabButton` riceve `isDetached: Bool`: l'`Image` usa `.foregroundStyle(Color.orange)` quando è staccato; il nome continua a comparire solo al passaggio del mouse; il pallino di Control resta. `accessibilityValue` = `tabs.detached.value` quando staccato.

- [ ] **Step 3: menù contestuale** sul pulsante: non staccato → `tabs.detach` (stessa azione dell'Option-clic); staccato → `tabs.bringToFront` (`openWindow`) e `tabs.reattach` (`dismissWindow(id: TabWindow.id, value: tab.id)`).

- [ ] **Step 4: stringhe**

| chiave | en | it |
|---|---|---|
| `tabs.detach` | Open in a Separate Window | Apri in una finestra separata |
| `tabs.bringToFront` | Bring Window to Front | Porta la finestra in primo piano |
| `tabs.reattach` | Move Back to the Main Window | Riporta nella finestra principale |
| `tabs.detached.value` | In a separate window | In una finestra separata |

- [ ] **Step 5: build** come in Task 2, Step 6. `TabCommands` non cambia: `selectNext`/`selectPrevious` saltano già gli staccati (Task 1).

- [ ] **Step 6: Commit** — `git commit -m "Tab bar: a tab opens in a window of its own (context menu or Option-click)"`

### Task 4: Verifica

- [ ] **Step 1:** `swift test --package-path Packages` → tutti i test passano.
- [ ] **Step 2:** build Debug come sopra → `** BUILD SUCCEEDED **`.
- [ ] **Step 3: dal vivo**, con la build Debug (non `/Applications`):
  1. Option-clic su Control → finestra «Control», icona arancione, la principale mostra Generazione.
  2. Clic sull'icona arancione → la finestra viene avanti, la principale non cambia tab.
  3. Clic destro su un plug-in → «Apri in una finestra separata»: il plug-in funziona nella finestra (un controllo che cambia stato).
  4. Chiudere la finestra del plug-in → icona normale, il plug-in è il tab aperto nella principale e funziona.
  5. Staccare un plug-in e spegnerlo dal menù Plug-in → la finestra si chiude.
  6. Staccare tutti i tab → riga «Tutti i tab sono in finestre separate»; ⌃Pag↓ non fa nulla.
  7. «Apri Control» dal tab Generazione con Control staccato → la finestra di Control viene avanti.
  8. Uscire e riaprire → nessun tab staccato.
- [ ] **Step 4:** riferire all'utente cosa è stato provato e cosa no.

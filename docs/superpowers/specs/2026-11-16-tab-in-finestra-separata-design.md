# Tab in finestra separata: design

Data: 2026-11-16. Stato: approvato dall'utente.

## Obiettivo

Ogni tab della finestra principale (Control, Generazione e i tab dei plug-in) si può aprire in una finestra propria,
per tenerlo accanto a un altro tab o su un secondo schermo. I plug-in non cambiano e non vanno ricompilati.

## Decisioni prese con l'utente

- **Staccare:** menù contestuale sul tab («Apri in una finestra separata») oppure clic sul tab con Option premuto.
- **Tab staccato:** resta nella barra al suo posto, con l'icona **arancione**. Il clic porta la sua finestra in primo
  piano e non cambia il tab aperto nella finestra principale.
- **Riattaccare:** solo chiudendo la finestra. L'icona torna normale e il tab si apre nella finestra principale.
- **Finestra nuda:** solo il contenuto del tab, senza intestazione, coda o banner.
- **Nessun ripristino:** al riavvio nessun tab è staccato.

## Scelte di chi ha scritto il design (approvate insieme al resto)

- Staccando il tab aperto, la finestra principale passa a Generazione; se Generazione è staccata, a Control; poi al
  primo tab non staccato. Se sono tutti staccati mostra la riga «Tutti i tab sono in finestre separate».
- Un plug-in spento, o non più compatibile col modello, perde il tab: la sua finestra si chiude da sola.
- ⌃Pag↑ e ⌃Pag↓ saltano i tab staccati.
- «Apri Control» dal tab Generazione porta avanti la finestra di Control, se è staccata.
- Dimensione e posizione della finestra sono ricordate per ogni tab (anche se la finestra non si riapre da sola).
- Il menù contestuale di un tab staccato offre «Riporta nella finestra principale», che equivale a chiudere la finestra.
- Il titolo della finestra è il nome del tab. L'arancione è quello di sistema (`Color.orange`).

## Approcci considerati

1. **Spostare il tab in una scena SwiftUI per valore** (scelto). Una `WindowGroup(id:for: String.self)` dà una finestra
   per id di tab; `openWindow(id:value:)` porta avanti quella già aperta. È lo schema del Canvas staccato
   (`CanvasWindow.swift`): lo stato dice chi è staccato, la finestra lo segnala quando compare e quando sparisce.
2. **Duplicare il tab** (finestra in più, tab ancora nella principale). Scartato: un plug-in ha un solo
   `NSViewController`, che può stare in una finestra sola; Control ha monitor di tastiera che in doppia copia
   reagirebbero due volte.
3. **Finestre AppKit fatte a mano** (`NSWindow` + `NSHostingController`). Scartato: rifà ciò che SwiftUI dà già alle
   altre finestre dell'app (ambiente, chiusura, posizione) e aggiunge un secondo modo di fare finestre.

## Architettura

- **`WorkspaceState`** (HubCore) tiene `detachedTabIDs: Set<WorkspaceTab.ID>`, non salvato.
  - `detach(_:)`: ignora un id che non è nella barra; aggiunge l'id; se era il tab aperto sceglie il sostituto.
  - `attach(_:)`: toglie l'id e, se il tab esiste ancora, lo apre (`select`).
  - `select(_:)` ignora un tab staccato (la barra, per quelli, porta avanti la finestra).
  - `selectNext`/`selectPrevious` scorrono solo i tab non staccati.
  - `setPluginTabs` toglie dagli staccati gli id spariti.
  - `selectedTabID` diventa `nil` quando tutti i tab sono staccati; l'ultimo tab salvato nelle preferenze non cambia
    quando la selezione si sposta per uno stacco.
- **Scena nuova** in `DTHubApp`: `WindowGroup(id: TabWindow.id, for: String.self)` con `TabWindowView`, senza ripristino
  (`.restorationBehavior(.disabled)`) e senza voce «Nuova finestra» nel menù.
- **`TabWindowView`** (file nuovo `App/MainWindow/TabWindow.swift`): il contenuto del tab con lo stesso ambiente della
  finestra principale (`plugins`, `contributions`, `canvasWindow`, `remote`), sfondo, tinta, `DSWindowConfigurator` e
  `WindowFrameKeeper` con una chiave per tab. Alla comparsa chiama `detach`, alla scomparsa `attach`. Se l'id non è
  (più) tra i tab, chiude la finestra.
- **Contenuto del tab** in una vista sola, `WorkspaceTabContent(tabID:)`, usata dalla finestra principale e da
  `TabWindowView`: oggi è l'`if/else` di `MainWindowView.tabContent`.
- **`WorkspaceTabBar`**: icona arancione per i tab staccati; clic → `openWindow` se staccato, altrimenti `select`;
  Option-clic e menù contestuale → `openWindow` (lo stacco avviene alla comparsa della finestra).
- Il contesto dei plug-in si rinfresca (`plugins.refreshContext()`) anche quando compare una finestra di tab.

## Fuori dal progetto

- Ricordare i tab staccati al riavvio.
- Strumenti MCP per staccare o riattaccare un tab.
- Intestazione, Run o scelta del modello nella finestra staccata (⌘R resta nel menù).

## Verifica

- Test in `WorkspaceStateTests` per stacco, riattacco, sostituto, scorrimento e plug-in che sparisce.
- Dal vivo: staccare Control, Generazione e un plug-in; chiudere la finestra; spegnere un plug-in staccato; il
  controller del plug-in deve lasciare la finestra principale prima di entrare nell'altra, e viceversa.

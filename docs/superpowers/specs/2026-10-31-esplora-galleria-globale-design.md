# Esplora: galleria globale nella finestra Risultati — disegno

Data: 31 ottobre 2026. Ramo: `feature/risultati-esplora` (da `main`, `9b84020`). Mockup approvato: `docs/superpowers/mockups/esplora-mockup.html`.

## Obiettivo

Nella finestra Risultati, accanto alla vista di oggi, una seconda vista «Esplora»: una griglia con le immagini di tutti i progetti insieme (più cartelle aggiunte a mano), con ricerca sui metadati, preferiti e anteprima con la barra spaziatrice. Serve a ritrovare un'immagine di sempre senza ricordare in che progetto sta.

## Cosa dice l'utente (requisiti)

1. In basso a sinistra, dove ora c'è il seed, **due tab** con la grafica delle tab della toolbar: **Risultati** (la finestra attuale, nessun'altra modifica) ed **Esplora**. Il seed **si toglie**. La riga dei pulsanti a destra (Usa come immagine, Aggiungi al Moodboard, Riprendi parametri, Finder, Cestino) resta invariata.
2. **Esplora** riempie la finestra con una griglia di tutte le immagini di tutti i progetti. In alto a destra resta il pulsante della sidebar metadati.
3. In alto a destra un **campo di ricerca** sui metadati (prompt, modello, LoRA, ogni altro parametro).
4. In alto a sinistra un tasto **+** per aggiungere cartelle, permanenti; accanto un menu **«Cartelle Extra»** che le elenca e permette di eliminarle dalla lista.
5. Le immagini hanno le stesse funzioni della strip: selezione, selezione multipla, menu contestuale.
6. Miniature **50% più grandi** della strip (108 pt contro 72).
7. **Stella** su ogni immagine: un clic la accende e la segna come preferita. Un pulsante **solo stella** (senza testo) filtra le preferite.
8. **Barra spaziatrice**: anteprima grande dell'immagine selezionata; non attiva con selezione multipla.

Scelta dell'utente: i preferiti stanno in un file unico dell'app (non dentro i PNG).

## Fuori ambito

Tag o valutazioni oltre alla stella; ordinamenti diversi dal più recente; cartelle virtuali; modifica dei metadati; ricerca per immagine; la tab Risultati non cambia (salvo il seed tolto).

## Interfaccia

- `ResultsView` ottiene uno stato `tab` (Risultati/Esplora), non persistito (si apre su Risultati). Le tab sono due bottoni nello stile delle tab della toolbar (attiva: riempimento `DS.accent`, testo scuro), nella riga in basso a sinistra. Accanto alle tab restano il testo «N selezionate» (selezione multipla) e gli errori (`useError`, «non salvata»); il seed sparisce dalla riga in entrambe le tab. Dopo il nome «Esplora» il numero totale delle immagini, in piccolo.
- **Risultati**: contenuto identico a oggi (area immagine, riga di stato, strip). La riga dei pulsanti agisce sul risultato scelto come ora.
- **Esplora**: al posto di area immagine, stato e strip, una colonna con barra superiore + griglia. Il pulsante sidebar (`sidebar.trailing`) resta sovrapposto in alto a destra e apre la stessa `ResultInfoSidebar`, riempita dai metadati dell'immagine selezionata (letti dal PNG).
- Barra superiore, da sinistra: `+` (apre `NSOpenPanel` per cartelle), menu «Cartelle Extra ▾» (elenco con percorso e «Elimina»; vuoto: «Nessuna cartella aggiunta»), spazio, pulsante ★ (acceso = solo preferite), campo «Cerca nei metadati…». Il campo lascia libero l'angolo del pulsante sidebar.
- La riga dei pulsanti agisce sulla selezione della griglia: Usa come immagine e Riprendi parametri solo con una immagine (il job si legge dal PNG; se manca, i due pulsanti sono disattivi), Moodboard, Finder e Cestino anche con più immagini.
- Cella: miniatura 108×108, angoli `DS.boxRadius`, bordo `DS.accent` 2 pt se selezionata; stella in alto a sinistra (spenta: velo scuro e stella vuota; accesa: gialla); al passaggio del mouse il nome del progetto in basso. Un video mostra la sua copertina con il badge della durata, come nella strip.
- Griglia pigra (`LazyVGrid`, colonne adattive da 108 pt), dalla più recente. Con zero risultati: «Nessuna immagine corrisponde» (o messaggio di galleria vuota).

## Dati

Tutto in HubCore (testabile), la vista in `App/Results/`.

**Fonti.** (a) Tutti i progetti della cartella di output: le sottocartelle con `.dthub/project.json`, immagini in `yyyy-MM-dd/*.png` (come `ProjectImages.allImages`). (b) Le cartelle extra, scandite in modo ricorsivo per tutti i `.png`. Una cartella extra già dentro la cartella di output non si conta due volte (dedup per percorso).

**`GalleryFolders`** — elenco delle cartelle extra in `~/Library/Application Support/DT Hub/gallery-folders.json` (array di percorsi). L'app non è in sandbox (`ENABLE_APP_SANDBOX = NO`), quindi bastano i percorsi. Un percorso che non esiste più resta in elenco (si può eliminare) e non dà immagini.

**`GalleryEntry`** — `url`, `date` (creazione, poi modifica), `project` (nome del progetto, o della cartella extra), `searchText` (minuscolo, senza accenti: PNG Description + UserComment + nome progetto + nome file), `hasVideo`/durata se esiste l'MP4 accanto. L'id è il percorso.

**`GalleryIndex`** — cache su disco `gallery-index.json` in Application Support (chiave: percorso + data di modifica + dimensione). `refresh()` scandisce le fonti, riusa le voci invariate, rilegge solo i PNG nuovi o cambiati, toglie le voci dei file spariti, e salva. Gira in background (`Task.detached`), parte all'apertura di Esplora e quando arriva un'immagine nuova (`session.results` cambia); la griglia mostra subito l'indice in cache e si aggiorna a fine giro. Un PNG illeggibile entra comunque, con il solo nome file come testo.

**Preferiti** — `GalleryFavorites`: insieme di percorsi in `favorites.json` (Application Support). Se un file viene spostato o rinominato, la stella si perde (limite dichiarato dell'opzione scelta). Quando un'immagine va nel cestino dall'app, il suo percorso esce dai preferiti e dall'indice. Scrittura atomica.

**Ricerca.** Il testo si divide in parole; devono comparire **tutte** nel `searchText` (AND), senza distinguere maiuscole e accenti. Ritardo di 200 ms sulla digitazione. Si combina con il filtro ★. Il filtro agisce sull'elenco già in memoria (nessuna rilettura di file).

**Selezione.** `ResultSelection` oggi è su `UUID`: si generalizza su un id `Hashable & Sendable` (la strip continua a usare `UUID`) e si aggiunge `step` per righe (↑/↓ = ± numero di colonne, con le colonne lette dalla griglia). Si riusano `click` (⌘, ⇧), `selectAll`, `afterRemoval`, `keepOnly`. Con la selezione che sparisce (filtro cambiato) resta solo ciò che è ancora visibile.

**Azioni.** Come nella strip: menu contestuale (Usa come immagine solo con una; Aggiungi al Moodboard; Cestino), trascinamento del file (anche multiplo) verso Control o altre app, ⌫ per il cestino dopo un clic nella griglia, ⌘A, frecce. «Usa come immagine» e Moodboard usano i metodi di `controller.control` con `fileURL` (`source: .result`). Il cestino riusa `PNGImageStore.trash` (e il video accanto). «Riprendi parametri» costruisce il job da `PNGImageStore.job(in:)` e lo passa a `controller.resume`: si verifica nel piano se serve un'estensione per i job che non vengono da una `GeneratedImage`.

**Miniature.** Caricamento asincrono con `PNGImageStore.image(at:maxPixel: 216)`, cache in memoria (`NSCache`, limite di costo), annullamento quando la cella esce dallo schermo.

**Barra spaziatrice.** Quick Look nativo (`QLPreviewPanel`) sul file dell'immagine selezionata. Spazio apre e chiude; Esc chiude. Attivo solo in Esplora, con **una sola** immagine selezionata, finestra in primo piano e senza testo in modifica (non vale mentre si scrive nel campo di ricerca). Con selezione multipla non fa nulla. Monitor AppKit come `ArrowKeyMonitor` (SwiftUI qui non riceve questi tasti). Con la selezione che cambia mentre il pannello è aperto, il pannello segue la nuova immagine.

## Errori e casi limite

- Cartella extra senza permesso di lettura o inesistente: ignorata in silenzio nella scansione, resta in elenco.
- Prima apertura con molte immagini: la griglia si riempie man mano che l'indice si costruisce (stato «Indicizzo…» discreto nella barra superiore).
- Immagine sparita dal disco fra due scansioni: la cella caricata mostra un segnaposto; a fine scansione esce dall'elenco.
- File non creati da DT Hub: si mostrano e si cercano per ciò che hanno (Description/UserComment); Riprendi parametri disattivo se il job non si legge.

## Test

Pacchetti (`swift test` da `Packages`), test-first:
- `GalleryIndex`: indicizza le immagini di più progetti; secondo giro rilegge solo i file cambiati; file tolto esce; PNG illeggibile entra col nome; dedup fra cartella extra e output.
- Ricerca: AND su più parole, senza maiuscole/accenti, su prompt, modello e LoRA presi da un PNG di prova; filtro ★ combinato.
- `GalleryFolders` e `GalleryFavorites`: salvataggio e rilettura, aggiunta/eliminazione, scrittura atomica; la rimozione nel cestino toglie il preferito.
- `ResultSelection` generico: i test attuali restano verdi; passo di riga ↑/↓ con bordi.
A mano nell'app Debug: aspetto delle tab, griglia a 108 pt, stella, menu «Cartelle Extra», barra spaziatrice (una, più immagini, durante la ricerca), trascinamento verso Control, cestino.

## Da decidere nel piano

Dove vivono `ResultsView` in Esplora (nuovo file `App/Results/ExploreView.swift` per non gonfiare `ResultsView`, già di 630 righe); il numero di colonne per ↑/↓; se `GalleryIndex` è un `actor` o un tipo con coda; i testi in italiano e inglese in `Localizable.xcstrings`.

# Panorama 360 — vista a sfera e Cutout — spec

Data: 25 ottobre 2026. Stato: **bozza da far approvare**. Percorso: architetturale (sottosistema nuovo dentro il plug-in + due aggiunte al contratto).
Estende `2026-10-25-plugin-panorama-360-design.md` (versione A, già implementata sul ramo `feat/panorama-360`) e realizza ciò che là era «fuori dalla prima versione» (§1.2, punti 1 e 2). **La correzione della giunzione resta l'ultima funzione e non fa parte di questa spec** (§9).
Mockup: `docs/superpowers/mockups/2026-10-25-panorama-360-sfera.html` (interattivo; il menu «stato simulato» in basso accende i casi).

## 1. Scopo

Guardare il panorama dall'interno (camera al centro della sfera) e poter agire su di esso:
1. **Vista a sfera** del canvas ERP, con gli sticker **modificabili guardando la scena** (sposta, scala, ruota), e del **risultato del RUN**, in sola lettura.
2. **Cutout:** estrarre la vista corrente come immagine piatta e (a) mandarla come immagine di partenza, al Moodboard o su disco, (b) **rimettere il ritaglio modificato** nel panorama: come sticker nel canvas (per rigenerare anche l'intorno) o direttamente **nel panorama risultato** (correzione puntuale, senza altro RUN), che va ai Risultati.

**Successo:** guardo il risultato, giro su un difetto, estraggo la vista, la ritocco con un modello edit, e rimetto il ritocco al suo posto nel panorama (come sticker, o sul risultato) senza uscire dal plug-in.

## 2. Scelte dell'utente (registro)
- Il visore mostra **sia il canvas ERP sia il risultato del RUN**; con il canvas gli sticker si modificano nella sfera (opzione B), col risultato solo vista.
- Interfaccia: **Vista in cima a tutto** (Piano | Sfera). Piano = la card di oggi, senza sorgente (Piano + Risultato non esiste). Sfera: accanto compare **Canvas | Risultato** e l'area diventa **4:3 orizzontale**.
- Il **risultato arriva dall'app** (aggiunta al contratto `lastResult`), non da un drop.
- **Cutout senza riquadro**: si estrae tutto quello che si vede; proporzione sempre 4:3, dimensione in megapixel.
- Quattro azioni sul ritaglio più «rimetti»: partenza, Moodboard, Salva…, **Rimetti come sticker**, **Rimetti nel panorama**.
- Il montaggio (risultato con il ritaglio modificato incollato) **va ai Risultati** (galleria), non all'ERP; non esiste una sorgente «Montaggio»: diventa l'ultimo risultato e la sorgente Risultato lo mostra.
- Pubblicazione solo a lavoro completo (anche con giunzione).

## 3. Architettura

Tutto in `Plugins/Panorama360/`, più due aggiunte facoltative al contratto 1 (§5).

| Unità | Compito | Nuovo/modificato |
|---|---|---|
| `PSCamera` | yaw, pitch (±89°), FOV orizzontale (20…120°); raggio di un pixel; posizione sullo schermo di una direzione (nil se dietro la camera) | nuovo, in `PSProjection` |
| `PSRendering.renderView` | `renderView(source:camera:width:height:)`; `source` = `.layers([PSLayer])` (sticker sul verde) oppure `.panorama(CGImage)` (ERP: longitudine avvolta, latitudine tenuta ai bordi) | nuovo, Metal e CPU (riferimento) |
| `PSRendering.render` (ERP) | accetta un `background: CGImage?` (panorama, al posto del verde) e `PSLayer.feather` (sfumatura del bordo, frazione del lato) | modificato |
| `PSView` (card) | in cima il selettore Vista; in Sfera il selettore Sorgente, il mirino, l'area 4:3, il pannello Cutout | modificato |
| `PSSphereView` | la vista camera: immagine renderizzata + overlay (guide, contorni, maniglie proiettati) + gesti | nuovo |
| `PSStateEditing` | puntatore nella sfera: direzione → (u, v) per **spostare** con `PSInteraction.moved`; scala e rotazione con le maniglie proiettate; selezione dal raggio | modificato |
| `PSCutout` | dimensioni (megapixel, lati multipli di 64, 4:3), estrazione della vista, memoria dell'ultima estrazione | nuovo |
| `PSCutoutActions` | partenza, Moodboard, Salva…, Rimetti come sticker, Rimetti nel panorama | nuovo |
| `PanoState` | nuovi campi con valore predefinito (§4) | modificato, `version` resta 1 |

**Perché i raggi della camera su sticker e panorama** (e non ERP renderizzato e poi ricampionato): con la camera stretta (30°) un ERP 2048×1024 darebbe circa 170 px di larghezza; così gli sticker mantengono la loro risoluzione piena. Per la sorgente Risultato si campiona direttamente l'immagine.

### 3.1 Camera e proiezione
`PSCamera.basis`: forward `(sin y·cos p, sin p, cos y·cos p)`, right `(cos y, 0, −sin y)`, up `forward × right` (stessa convenzione degli sticker, senza rotazione). Per il pixel `(x, y)` di una vista `w × h`: raggio = `normalize(fwd + (2x/w − 1)·tanX·right + (1 − 2y/h)·tanY·up)`, `tanX = tan(FOV/2)`, `tanY = tanX·h/w`. Inversa: per una direzione `d` con `dz = d·fwd > 1e-4`, `sx = (d·right/dz/tanX·0,5 + 0,5)·w`, `sy = (0,5 − d·up/dz/tanY·0,5)·h`. Trascinare nel vuoto: `yaw −= dx·FOV/larghezza`, `pitch += dy·FOV/larghezza` (come trascinare la scena); rotella: FOV ×(1 + delta·0,001).

### 3.2 Rendering
`renderView` ricalca `render`: una passata per layer in Metal (fragment con raggio dalla camera invece che da (u, v)), o campionamento del panorama; riferimento CPU nei test; ripiego automatico su CPU come per l'ERP. In trascinamento si renderizza a metà risoluzione, al rilascio a piena. La vista ha 1024×768 punti interni (4:3).

### 3.3 Sticker nella sfera
- **Selezione/spostamento:** il puntatore → raggio → direzione → `(u, v)` (`PSProjection.point`) → `PSInteraction.grab/moved` (invariati: lavorano in gradi di lon/lat).
- **Scala/rotazione:** le maniglie sono proiettate dalla camera; la distanza dal centro e l'angolo si misurano in punti schermo (nessun problema di giunzione: la camera non ha giunzione). Solo con la sorgente Canvas.
- **Contorni:** gli stessi punti di `PSProjection.outline`, proiettati; le polilinee si tagliano dove un punto sta dietro la camera.
- **Guide in Sfera:** orizzonte (equatore proiettato); niente meridiani.

## 4. Stato (`state.json`, versione 1, file vecchi leggibili)
Nuovi campi con valore predefinito, letti con `decodeIfPresent`: `viewMode` (`plane`|`sphere`, predefinito `plane`), `source` (`canvas`|`result`, predefinito `canvas`), `camera` (`yaw 0, pitch 0, fov 90`), `cutoutMegapixels` (1,0), `lastCutout` (opzionale: `yaw, pitch, fov, size, resultPathAtExtraction, patchPath`). Un file scritto prima di questa spec si legge senza errori e un file nuovo letto da un plug-in vecchio non si rompe (i campi in più si ignorano).

## 5. Contratto 1 — due aggiunte facoltative (app, kit, README; vanno nella stessa release delle due già fatte, dopo la 0.4.3)
1. **`lastResult` nel contesto:** `{"path","name"}` dell'ultimo risultato del progetto (il primo della striscia dei Risultati); assente se non ce ne sono. Fa parte di `PluginContextKey` (`lastResultID`), così il plug-in sente quando ne arriva uno nuovo. Kit: `DTHubContext.lastResult: DTHubLastResult?` (lettura tollerante).
2. **`contribute.result` accettato anche senza pipeline guidata:** oggi solo mentre gira una pipeline guidata (`guidedModelFile`). Senza, l'app lo archivia sotto **il modello scelto nell'header**, senza tempo di generazione; il file deve esistere ed essere un'immagine leggibile. Nessun teal né conflitto, come oggi.
Le due aggiunte già fatte (`presets[]` con `model`/`advanced`, `contribute.preset`) restano: in tutto il contratto 1 ne guadagna quattro per questa release.

## 6. Cutout
- **Dimensione:** `megapixel` (0,25…4, predefinito 1,0): `w = round(√(MP·10⁶·4/3)/64)·64`, `h = round(w·3/4/64)·64` (1,0 MP → 1152 × 896). Il FOV dell'immagine è quello della camera; la proporzione è quella dell'area (4:3).
- **Estrai:** renderizza la vista corrente (con la sorgente scelta: Canvas = sticker su verde; Risultato = il panorama) a `w × h` e la tiene in memoria con la posa della camera. Memoria nello stato: `lastCutout`.
- **Azioni** sul ritaglio estratto (icone con tooltip):
  1. **Usa come immagine di partenza** — `contribute.startImage` (PNG nella `tempFolder`).
  2. **Aggiungi al Moodboard** — `contribute.moodboard`.
  3. **Salva…** — pannello di salvataggio, PNG.
  4. **Rimetti come sticker** — crea uno sticker con l'ultimo risultato (il ritocco) alla posa dell'estrazione (`yaw`, `pitch`, `fov`, `rot 0`), lo seleziona, passa a Piano + canvas.
  5. **Rimetti nel panorama** — compone il ritocco sul panorama risultato (`render` ERP con `background` = il risultato dell'estrazione e il ritocco come layer alla stessa posa, `feather` 3%), alla dimensione del risultato; manda il PNG con `contribute.result` (descrizione «Montaggio · ritaglio rimesso a yaw …° pitch …° FOV …°»). Diventa l'ultimo risultato.
- **Abilitazione di 4 e 5:** c'è un'estrazione in memoria; l'ultimo risultato è **diverso** dal risultato presente all'estrazione (`resultPathAtExtraction`) oppure è il ritocco già usato (`patchPath`, così le due azioni lavorano sullo stesso ritocco anche dopo il montaggio); e la sua proporzione è **4:3 entro il 2%**. Altrimenti spente, con il motivo nel tooltip.
- Al primo «Rimetti» il ritocco usato si fissa in `patchPath` (fino alla prossima estrazione).

## 7. Casi limite e errori
- Nessun risultato: Risultato spento; se era scelto si torna a Canvas. A RUN finito, su Risultato l'immagine si aggiorna da sola.
- File del risultato spostato o illeggibile: avviso nel riquadro del plug-in, la vista mostra Canvas.
- Risultato non 2:1: si tratta come ERP lo stesso (u, v dirette) con un avviso nel riquadro.
- Sorgente Risultato: `+`, cestino, maniglie e tastiera di modifica spenti.
- Rimetti con il ritocco di proporzione diversa: azione spenta (nessun montaggio storto).
- Camera: pitch ±89°, FOV 20…120° sempre.
- Cambio di progetto: camera, vista e sorgente tornano a quelli del progetto; `lastCutout` è per progetto.

## 8. Test
Elencati nel piano: `PSCamera` (raggio↔schermo, dietro la camera, limiti); `renderView` Metal = CPU (sticker e panorama, a cavallo della giunzione, ai poli); `render` con `background` e `feather`; interazioni nella sfera (sposta, scala, ruota, selezione dal raggio, gesto di sguardo); dimensioni del Cutout; abilitazioni di «Rimetti» (diverso, stessa proporzione, `patchPath`); stato (campi vecchi, versione); contratto: `lastResult` (HubKit, `PluginContextKey`, kit) e `contribute.result` senza pipeline guidata (archivio sotto il modello dell'header); PNG di prova della card in entrambe le viste.

## 9. Fuori da questa spec
La **correzione della giunzione** tra i due bordi verticali (ultima funzione): resta come in `…-plugin-panorama-360-design.md` §9. Questa spec ne tiene conto così: `uOffset` esiste già in proiezione e renderer; `renderView` e `render` con `background` si prestano a ruotare un panorama di mezza larghezza; il montaggio è un risultato come gli altri e potrà essere l'ingresso della correzione.

## 10. Fasi (circa 7 task)
1. Contratto: `lastResult` e `contribute.result` senza pipeline guidata (app, kit, test).
2. `PSCamera`, campi di stato nuovi e compatibilità dei file vecchi.
3. Renderer: `renderView` (Metal e CPU) e `render` con `background`/`feather`.
4. Interazione nella sfera: gesti, selezione, sposta/scala/ruota, contorni e maniglie proiettati.
5. Card: selettore Vista, Sorgente, area 4:3, mirino, `lastResult` come sorgente, avvisi.
6. Cutout: estrazione, dimensioni, memoria, le cinque azioni, abilitazioni.
7. Testi it/en, README, prove a mano, nota Obsidian e briefing.
Esecuzione: nativa, una revisione finale con revisore indipendente (come per la versione A). Ramo: `feat/panorama-360` (stesso).

## 11. Rischi
- Metal nei dylib: già verificato con la versione A; il ripiego CPU copre `renderView`.
- Prestazioni della vista a 1024×768 con molti sticker: mezza risoluzione in trascinamento, un renderer per volta (`previewGeneration`).
- I ritocchi con modelli che cambiano l'inquadratura non combaciano: l'azione si spegne solo sulla proporzione; il resto è responsabilità dell'utente (README).
- Poli: vicino a pitch ±89° gli sticker si deformano: è la proiezione, non un errore.

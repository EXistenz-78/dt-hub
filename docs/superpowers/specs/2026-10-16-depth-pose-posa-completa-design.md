# Depth & Pose — posa a figura intera (viso e mani) — Design

Data: 16 ottobre 2026. Stato: disegno approvato in chat dall'utente (DWPose-L, due scaricamenti separati, Vision come ripiego); da rivedere per iscritto prima del piano.
Base: ramo `depth-pose` (plug-in Depth & Pose 1.0, spec madre `2026-10-16-plugin-depth-pose-design.md`, la cui §5.2 questa spec **estende**: la posa con Vision resta, ma solo come ripiego).

## 1. Obiettivo

La posa del plug-in oggi viene da Vision di Apple: solo corpo, e sbaglia gli arti che non si vedono. Si vuole una posa **a figura intera come quella di DWPose**: scheletro del corpo, **viso a puntini bianchi** e **mani a 21 punti**, più robusta con gli arti nascosti (riferimento: `pose-full.jpg` della LoRA schematic di nomadoor).

Successo: con il modello della posa scaricato, «Crea» con Posa spuntata disegna per ogni persona corpo, viso e mani nello stile OpenPose/DWPose, in circa 15 ms per persona; senza il modello, la posa funziona come oggi (solo corpo, Vision).

## 2. Decisioni (dell'utente, 16 ottobre)

1. **Modello: DWPose-L** (`dw-ll_ucoco_384`), non RTMW-x: più piccolo, più veloce, è quello che usano ControlNet e le LoRA di posa.
2. **Conversione nostra in Core ML**, ospitata come **release a parte su GitHub** (`dwpose-l-coreml`, non «latest»).
3. **Due scaricamenti separati**, ognuno col suo tasto che compare solo se il modello manca: depth (200 MB) e posa (64 MB).
4. **Vision resta come ripiego** della posa: senza il modello della posa si ottiene il corpo come oggi.
5. I riquadri delle persone vengono da **Vision** (`VNDetectHumanRectanglesRequest`), senza convertire un rilevatore.

## 3. Cosa ha mostrato lo spike (16 ottobre)

| | DWPose-L | RTMW-x |
|---|---|---|
| ONNX → Core ML F16 | 134 MB → **64 MB** | 229 MB → 110 MB |
| Tempo per persona (Neural Engine) | **15 ms** | 22 ms |
| Scarto da onnxruntime (media / massimo) | 0,1–0,4 px / 4 px | 0,2–0,9 px / 30 px |

- Ingresso: ritaglio RGB **288×384** (larghezza×altezza), valori 0–255 (la normalizzazione media/deviazione è dentro il modello). Uscite: `simcc_x` (1×133×576) e `simcc_y` (1×133×768), mezzo precisione.
- La conversione passa da ONNX a PyTorch (`onnx2torch`) a Core ML; serve un rimedio a due nodi `Clip` (§8). Il pacchetto convertito è `dwpose_l.mlpackage` (tre file, §6).
- Punteggio di un riquadro = **media dei 17 punti del corpo** (indici COCO 0–16): persone con riquadro di Vision 0,53–0,75; illustrazione a tutto fotogramma 0,43; sfondi senza persone 0,10–0,40 (0,40 solo per un ritaglio che conteneva degli stivali). **Soglia: 0,35.**
- Vision trova le persone nelle foto (anche tre insieme) e **nulla nelle illustrazioni**: lì si usa l'immagine intera come riquadro, e DWPose trova il personaggio.

## 4. Pipeline

Per un'immagine (già ridotta a 2048 px sul lato lungo, `DPImage`):

1. **Riquadri.** `VNDetectHumanRectanglesRequest` con `upperBodyOnly = false`; riquadri in pixel con origine in alto a sinistra, ordinati per area decrescente, **al massimo 12**. Se non ne trova, **un solo riquadro: l'immagine intera**.
2. **Ritaglio** di ogni riquadro (`DPCrop`): centro = centro del riquadro; scala = (larghezza, altezza) × **1,25**, poi portata al rapporto 288:384 allargando il lato più corto; la trasformazione è una scala uniforme `288 / scalaLarghezza` con il centro che va in (144, 192), senza rotazione, interpolazione bilineare, **nero fuori dall'immagine**.
3. **Modello**: ritaglio → `simcc_x`, `simcc_y`.
4. **Decodifica** (`DPSimCC`): per ognuno dei 133 punti, posizione = argmax di `simcc_x` e di `simcc_y` (in «bin»), punteggio = media dei due massimi; se il punteggio è ≤ 0 il punto non c'è. Coordinate nell'immagine: `bin / 2 / (288, 384) * scala + centro − scala / 2`.
5. **Mappatura** (`DPWholeBody`) dal formato COCO-WholeBody:
   - **corpo** a 18 punti OpenPose: `naso`←0, `occhio dx`←2, `occhio sx`←1, `orecchio dx`←4, `orecchio sx`←3, `spalla dx`←6, `spalla sx`←5, `gomito dx`←8, `gomito sx`←7, `polso dx`←10, `polso sx`←9, `anca dx`←12, `anca sx`←11, `ginocchio dx`←14, `ginocchio sx`←13, `caviglia dx`←16, `caviglia sx`←15 (destra e sinistra della persona, come in COCO); **collo** = punto medio delle due spalle, punteggio = il minore dei due;
   - **viso**: indici 23–90 (68 punti); **mano sinistra**: 91–111; **mano destra**: 112–132 (21 punti ciascuna, polso = primo); i piedi (17–22) non si disegnano.
6. **Scarto delle figure**: una figura con media dei 17 punti del corpo **< 0,35** non esiste.
7. Le coordinate diventano 0–1 sull'immagine (origine in alto a sinistra) e passano al disegno.

Con il ripiego (nessun modello della posa) la pipeline è quella di Vision di oggi, con figure senza viso né mani.

## 5. Disegno (stile ControlNet/DWPose, sul fondo nero di oggi)

Ordine: ossa del corpo (a 0,6 del colore, come oggi) → punti del corpo → **ossa delle mani** → **punti delle mani** → **punti del viso**.

- **Corpo**: invariato (§5.2 della spec madre).
- **Mani**: 20 ossa tra i 21 punti, `[[0,1],[1,2],[2,3],[3,4],[0,5],[5,6],[6,7],[7,8],[0,9],[9,10],[10,11],[11,12],[0,13],[13,14],[14,15],[15,16],[0,17],[17,18],[18,19],[19,20]]`; l'osso *i* ha il colore HSV (tinta `i / 20`, saturazione 1, valore 1); spessore `max(2, spessore/2)` pixel, dove *spessore* è quello del corpo (`max(3, latoLungo/170)`); i punti sono cerchi **blu pieni** (0, 0, 255) di raggio *spessore*. Un osso c'è solo se i due estremi superano la soglia.
- **Viso**: ogni punto sopra la soglia è un cerchio **bianco pieno** (255, 255, 255) di raggio `max(2, spessore × 0,75)`.
- **Soglia** dei punti: confidenza ≥ **0,3**, la stessa del corpo.
- Una figura si disegna se ha **almeno un osso del corpo**, oppure un viso con almeno 10 punti sopra la soglia, oppure una mano con almeno 5. Senza nessuna figura disegnabile non esce nulla («nessuna persona», come oggi).
- Punti fuori dall'immagine (persona tagliata dal bordo) non si disegnano e non causano errori.

## 6. Modello: file e scaricamento

- Pacchetto `DWPoseL384F16.mlpackage` in `…/DT Hub/Data/DepthPose/`, accanto a quello della depth, con il suo `DWPoseL384F16.mlmodelc` compilato. Stessa procedura della depth: scarica in una cartella temporanea, controlla dimensione e sha256, compila, sposta; un errore o un «Annulla» non lasciano nulla; un pacchetto messo a mano si prende in carico all'avvio.
- File, dalla release `dwpose-l-coreml` di `EXistenz-78/dt-hub` (nomi piatti → percorsi locali):
  - `DWPoseL384F16-Manifest.json` → `…/Manifest.json` — 617 byte, sha256 `65bf603ed9d11c56f9d3209178a6032bff2eeb385a4cb938135d2fefff5ba4be`
  - `DWPoseL384F16-model.mlmodel` → `…/Data/com.apple.CoreML/model.mlmodel` — 139.633 byte, sha256 `f9d97464e6b77682de65fe3bfaba34fab7562d0ac0494c2bde33c9a461c8a7a5`
  - `DWPoseL384F16-weight.bin` → `…/Data/com.apple.CoreML/weights/weight.bin` — 67.199.424 byte, sha256 `64691178575c974d0e5ccb59051a385546a54b78f3d42d63786ccca067d15810`
- Host ammessi: invariati (`github.com` e `githubusercontent.com`).
- La release porta anche un `NOTICE` (§9). Non è «latest».

## 7. Interfaccia e stato

- Sotto le checkbox, la sezione dei modelli mostra **fino a due voci**, ognuna solo se serve: «Scarica il modello della depth (200 MB)» (come oggi) e «Scarica il modello della posa completa (64 MB)», con barra di avanzamento e «Annulla» durante lo scaricamento, e «Scarica di nuovo…» se il modello su disco non si apre.
- I due scaricamenti sono **indipendenti** (si può scaricare l'uno mentre l'altro lavora o si annulla).
- «Crea» con Posa: se il modello della posa è pronto usa DWPose-L; se manca, o se si rivela non apribile, usa Vision (la nota «modello danneggiato» compare e il tasto «Scarica di nuovo» torna).
- `DPState.modelState` resta lo stato del modello della depth; si aggiungono `poseModelState` e le azioni corrispondenti (`downloadModel(.pose)`, `cancelDownload(.pose)`, …). La scelta delle checkbox e il resto non cambiano.

## 8. Conversione (script)

`Plugins/DepthPose/Scripts/convert_pose_model.py PERCORSO.onnx OUT.mlpackage`: carica l'ONNX; **ai nodi `Clip`** il cui minimo o massimo è un nome vuoto, o passa per un `Identity`, assegna una costante esplicita (−3,4e38 / 3,4e38 o il valore dell'inizializzatore); converte con `onnx2torch`; avvolge il modello in un modulo che prende RGB 0–255 e normalizza (media 123,675/116,28/103,53, deviazione 58,395/57,12/57,375); `ct.convert` a `mlprogram`, F16, macOS 15, ingresso immagine (1, 3, 384, 288), uscite `simcc_x` e `simcc_y`. Requisiti in `requirements-convert.txt` (si aggiungono `onnx` e `onnx2torch`; **torch resta 2.7.0**: `onnx2torch` da solo lo porta alla 2.14). Il modello di partenza è `dw-ll_ucoco_384.onnx` di `yzd-v/DWPose` (Hugging Face).

## 9. Rete, licenza, privacy

- Nessuna rete nuova: è lo stesso scaricamento al clic della depth, solo verso `github.com` e `githubusercontent.com`.
- **Licenza: Apache-2.0** (DWPose, IDEA-Research, Zhendong Yang et al.; pesi `yzd-v/DWPose` su Hugging Face, che dichiara Apache-2.0). La release porta la licenza, un NOTICE con attribuzione e «convertito in Core ML (F16, ingresso fisso 288×384, normalizzazione inclusa)». Nessun limite di uso commerciale (a differenza della depth).
- Nulla dell'utente esce dal Mac.

## 10. Test (prima il rosso, poi il verde)

- **`DPSimCC`**: argmax su vettori finti; punteggio = media dei massimi; punteggio ≤ 0 → punto assente; numero di punti dedotto dalla lunghezza.
- **`DPCrop`**: valori di riferimento calcolati con il codice di rtmlib: riquadro (30, 45, 125, 318) → centro (77,5; 181,5), scala (255,9375; 341,25), scala uniforme 1,125275, traslazione (56,791209; −12,237363); riquadro (0, 0, 320, 320) → scala (400; 533,3333), 0,72, traslazione (28,8; 76,8); riquadro (10, 20, 210, 120) → scala (250; 333,3334), 1,152, traslazione (17,28; 111,36); il bin (288, 384) cade nel centro del riquadro; il bin (0, 0) in `centro − scala/2`; il ritaglio sposta un pixel noto nel punto atteso, è nero fuori dall'immagine e misura 288×384.
- **`DPWholeBody`**: ogni indice COCO va al punto OpenPose giusto (destra e sinistra non scambiate); il collo è il punto medio con il punteggio minore; viso 68 punti, mani 21+21; i piedi non entrano.
- **Disegno**: osso della mano *i* col colore HSV atteso (0 → rosso; 10 → ciano); punti della mano blu; punto del viso bianco di raggio atteso; ordine (viso sopra le mani, mani sopra le ossa); figura con solo il viso o solo una mano; punti sotto soglia non disegnati; punti fuori dall'immagine non disegnati; nessuna figura disegnabile → nil; le prove esistenti del corpo restano.
- **`DWPoseDetector`** con rete e cercatore di riquadri finti: più persone → più figure; nessun riquadro → immagine intera; figura con media del corpo < 0,35 scartata (e un'immagine senza persone non dà niente); al massimo 12 persone, le più grandi; il riquadro passato esplicitamente si rispetta.
- **`DPModelStore`**: il manifest della posa (nomi, dimensioni, sha256, URL sotto `dwpose-l-coreml`, host ammesso); `baseURL` per modello.
- **`DPState`**: due modelli indipendenti (scaricamento di uno mentre l'altro è pronto; «Annulla» di uno non tocca l'altro; un pacchetto della posa messo a mano si compila all'avvio); «Crea» sceglie DWPose-L se pronto e Vision se manca o non si apre (con la nota); `canCreate`/`showsPoseDownloadButton`.
- **Vista**: `RenderTests` con il modello della posa mancante, in scaricamento e pronto.
- **Prove con modelli veri** (dietro `DTHUB_LIVE_DEPTH=1`, con `DP_LIVE_POSE_DIR` che indica la cartella del pacchetto): il pacchetto corrisponde al manifest e si compila; su una foto di prova i punti coincidono con quelli di onnxruntime (tolleranza 6 px, riquadri passati a mano); Vision trova il riquadro di una persona vera; una scena senza persone non dà nessuna figura.

## 11. Fuori ambito (rinviati)

RTMW-x (o altri modelli più grandi), un rilevatore di persone convertito (YOLOX) per le illustrazioni con più personaggi, i piedi nel disegno, interruttori «solo corpo / senza viso / senza mani», correzione a mano dello scheletro (idea «Pose Builder»), posa 3D, animali, soglie regolabili dall'utente.

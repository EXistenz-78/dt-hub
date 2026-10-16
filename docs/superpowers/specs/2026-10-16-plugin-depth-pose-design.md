# Plug-in Depth & Pose — Design

Data: 16 ottobre 2026. Stato: disegno approvato in chat dall'utente, sezione per sezione; da rivedere per iscritto prima del piano.
Base: `main` **0.2.3** (`12cfd1b`).

## 1. Obiettivo

Un plug-in che, da **una sola immagine**, produce in pochi istanti una **mappa di profondità** (depth) e/o uno **scheletro di posa**, e li manda al **Moodboard**.

Perché: oggi le stesse mappe si ottengono con LoRA su Flux 2 Klein, cioè con una generazione completa (molti step su un modello da miliardi di parametri) per un'estrazione che è deterministica. Qui si usano modelli dedicati e piccoli, una sola passata: decine di millisecondi per la depth, meno ancora per la posa.

Successo: l'utente trascina un'immagine, sceglie Depth, Pose o Entrambe, preme «Crea» e «Manda al Moodboard»; le mappe compaiono nel Moodboard, pronte come riferimento per un modello o un LoRA che le legge. Nessuna generazione, nessun server.

## 2. Decisioni (dell'utente, 15–16 ottobre)

1. **Origine dell'immagine: file o trascinamento nel plug-in** (non l'immagine di partenza di Control, non il Moodboard).
2. **Uscite della prima versione: depth e posa del corpo.** Mani, viso, posa 3D e altre mappe sono rinviati (§12).
3. **Modello di depth scaricato al primo uso** da Hugging Face. Il tasto «Scarica il modello» compare **solo se il plug-in non trova il modello**.
4. **Un selettore Depth · Pose · Entrambe** decide cosa si crea e cosa si manda.
5. Le mappe vanno nel Moodboard con `contribute.moodboard`, come fa Sphere Light. **Nessuna aggiunta al contratto 1.**

## 3. Il plug-in

- Nome visibile «Depth & Pose» (provvisorio); id `com.exiztenz.dthub.depthpose`; pacchetto `Plugins/DepthPose/` sul modello di Sphere Light (Sources, Tests, `Scripts/build.sh`, `README.md` in inglese); zip `DepthPose.dthubplugin.zip`.
- **Tutte le famiglie** (nessun `families` restrittivo).
- Libreria dinamica caricata nel processo dell'app, come gli altri: nessuna risorsa nel bundle.
- Parti, ognuna con un solo compito:
  - `DepthEstimator`: immagine → immagine in grigi (Core ML). Dietro un protocollo `DepthModel`, per provarlo con un modello finto.
  - `PoseDetector`: immagine → giunti per persona (Vision). Dietro un protocollo, per provarlo con giunti finti.
  - `OpenPoseSkeleton`: giunti Vision → 18 punti OpenPose (conversione pura).
  - `PoseRenderer`: 18 punti → immagine (disegno puro, senza Vision).
  - `ModelStore`: dov'è il modello, scaricamento, compilazione (§6).
  - `DepthPoseStore`: stato (selettore, immagine, mappe, avanzamento), per progetto (`state.json`).
  - `DepthPoseView`: l'interfaccia.
  - `Strings`: tabella `L` in italiano e inglese.
- Dati globali in `~/Library/Application Support/DT Hub/Data/DepthPose/`.

## 4. Interfaccia

Un solo tab, larghezza come Sphere Light.

- **Zona di trascinamento** «Trascina un'immagine» + tasto «Apri…»: accetta file del Finder (PNG, JPEG, HEIC, TIFF; ciò che ImageIO legge) e dati d'immagine trascinati dal browser. Un indirizzo da solo non si segue. Mostra l'anteprima e il nome; trascinare un'altra immagine la sostituisce e cancella le mappe di prima.
- **Selettore** «Depth · Pose · Entrambe» (predefinito: Entrambe; ricordato per progetto).
- **«Crea»**: calcola le mappe scelte e le mostra affiancate in anteprima (etichette «Depth», «Pose»). Disattivato senza immagine, o con «Depth» scelta e modello assente (con «Entrambe» e modello assente crea solo la posa e lo dice).
- **«Manda al Moodboard»**: attivo quando c'è almeno una mappa. Manda in **un solo** messaggio `contribute.moodboard` le mappe del selettore; un nuovo invio sostituisce quelle mandate prima (comportamento del contratto). La risposta dell'app (`conflicts`, `problems`) si mostra come nota.
- **«Scarica il modello (50 MB)»**: compare **solo se il modello non è sul disco** (o è danneggiato: «Riscarica»). Durante lo scaricamento sparisce il tasto e compare una barra di avanzamento con «Annulla». A fine scaricamento il tasto sparisce e «Depth» si attiva da sola.
- Finché il modello manca, **la posa funziona comunque**.
- Testi in italiano e inglese; ogni testo sta nella tabella `L`; un test controlla che esistano in tutte e due le lingue.

## 5. Elaborazione

### 5.1 Depth

- Modello: **Depth Anything V2 Small, F16**, `apple/coreml-depth-anything-v2-small` (Apache-2.0, 24,8M parametri).
- Ingresso `image` (immagine), uscita `depth` (immagine in scala di grigi): lette dai metadati del modello (verificate il 16 ottobre). Il modello vuole il **lato corto a 518 px e il lato lungo multiplo di 14**: `DepthEstimator` ridimensiona l'immagine di conseguenza (mantenendo le proporzioni; il lato lungo si arrotonda al multiplo di 14 più vicino), esegue il modello e riporta il risultato alle dimensioni dell'originale con interpolazione bilineare.
- **Scala**: la mappa si normalizza minimo→0, massimo→255 su ogni immagine, per non dipendere dall'intervallo che dà il modello. **Vicino = chiaro, lontano = scuro** (convenzione dei ControlNet di depth). L'orientamento dell'uscita del modello si **verifica con una prova a mano** (§10) e, se è invertito, `DepthEstimator` inverte; il test sul modello finto fissa la convenzione.
- Lato lungo dell'immagine di ingresso limitato a **2048 px** (si riduce prima del calcolo); le mappe escono alla stessa dimensione.
- Unità di calcolo: `MLModelConfiguration.computeUnits = .all` (il Neural Engine fa il grosso, circa 25–35 ms sui dati della scheda del modello).

### 5.2 Pose

- `VNDetectHumanBodyPoseRequest`: ogni osservazione è una persona; i giunti sono letti con `recognizedPoints` e **l'elenco dei nomi non si presume**: si usano i giunti che la richiesta dà, e un giunto mancante o con **confidenza < 0,3** si salta.
- **Conversione OpenPose a 18 punti** (`OpenPoseSkeleton`), nell'ordine standard: naso, collo, spalla destra, gomito destro, polso destro, spalla sinistra, gomito sinistro, polso sinistro, anca destra, ginocchio destro, caviglia destra, anca sinistra, ginocchio sinistro, caviglia sinistra, occhio destro, occhio sinistro, orecchio destro, orecchio sinistro. «Destra/sinistra» sono quelle **della persona**, come in Vision. Il collo è quello di Vision; se manca ma ci sono le due spalle, è il loro punto medio. Il «root» di Vision non entra nello schema.
- **Disegno** (`PoseRenderer`): fondo nero, dimensioni dell'immagine; per ogni persona, le 17 ossa dello schema OpenPose come linee/ellissi con i **colori standard** (arti e tronco in tinte diverse, testa con occhi e orecchie) e un cerchio pieno su ogni punto. Lo spessore è proporzionale al lato lungo (circa 1/170) e ha un minimo; le ossa con un estremo mancante non si disegnano. I colori sono una tabella fissa nel codice, copiata dalla convenzione di OpenPose; i valori esatti si scrivono nel piano e si provano con un test a pixel.
- Più persone: più scheletri sulla stessa immagine. Nessuna persona: la posa non si crea e una nota lo dice; la depth, se scelta, si crea e si può mandare.

### 5.3 Uscita

- Mappe salvate come PNG in 8 bit (`depth.png`, `pose.png`) nella `tempFolder` del contesto, alla dimensione dell'immagine ridotta (§5.1). Nomi per il Moodboard: «Depth» e «Pose» (il campo `name` di `contribute.moodboard`), senza il nome dell'immagine.
- La `tempFolder` arriva col messaggio `context`; senza, il tasto «Manda al Moodboard» è disattivato e una nota lo dice.

## 6. Modello: dove sta, come si scarica

- Cartella: `…/DT Hub/Data/DepthPose/`.
  - `DepthAnythingV2SmallF16.mlpackage/` = i tre file scaricati;
  - `DepthAnythingV2SmallF16.mlmodelc/` = il modello compilato, usato per le predizioni.
- **File da scaricare** (verificati sull'API di Hugging Face il 16 ottobre), da `https://huggingface.co/apple/coreml-depth-anything-v2-small/resolve/main/`:
  - `DepthAnythingV2SmallF16.mlpackage/Manifest.json` — 617 byte
  - `DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/model.mlmodel` — 399.433 byte
  - `DepthAnythingV2SmallF16.mlpackage/Data/com.apple.CoreML/weights/weight.bin` — 49.419.072 byte (LFS)
- **Procedura**: si scarica in una cartella temporanea dentro `Data/DepthPose/`; si controlla che ogni file abbia la **dimensione attesa** (e, per `weight.bin`, lo **sha256** dell'LFS: `fa60d9b6a155734f59029ebb882fd54e549bfaee3539c1a9cbd2cbbab64a0fed`); si compila con `MLModel.compileModel(at:)`; solo allora si sposta tutto al posto definitivo. Un errore o un «Annulla» cancellano la cartella temporanea e **non lasciano nulla a metà**.
- «Il modello è presente» significa: la cartella compilata esiste **e** si apre con `MLModel(contentsOf:)`. Se non si apre, il tasto torna come «Riscarica».
- Il tasto è l'unico punto in cui il plug-in usa la rete (§9).

## 7. Stato per progetto

`state.json` nella cartella del progetto: il valore del selettore. **L'immagine e le mappe non si ricordano** (sono file temporanei): all'apertura di un progetto il tab riparte vuoto, col selettore come l'utente l'aveva lasciato. Un plug-in che non riceve `project` tiene lo stato globale, come gli altri (`unsupported` → un solo stato).

## 8. Errori

Sempre una nota (`notice`) sopra la finestra, in italiano o inglese:

- immagine illeggibile o non supportata;
- modello assente (Depth scelta): invita a scaricarlo;
- scaricamento fallito, interrotto o incompleto (dimensione o sha256 diversi);
- modello danneggiato o non compilabile;
- nessuna persona trovata (la depth, se scelta, si crea comunque);
- `tempFolder` assente o non scrivibile;
- il Moodboard ha risposto con `problems`: si mostrano.

## 9. Sicurezza e privacy

- **Rete**: solo al clic su «Scarica il modello» e solo verso `huggingface.co` (e il suo CDN di Hugging Face per i file LFS, che reindirizza: si seguono i reindirizzamenti solo verso sottodomini di `huggingface.co` e `hf.co`). È il **secondo** plug-in a usare la rete, dopo LoRA Advisor; va detto nel README e nelle note di release. Non si invia nulla dell'utente: solo richieste GET dei tre file.
- Le immagini dell'utente restano sul disco: depth e posa si calcolano in locale; le mappe vanno solo in `tempFolder`.
- Nessun dato personale nei file del repo (controllo di routine prima della release).

## 10. Test

Prima il rosso, poi il verde (TDD), come negli altri plug-in.

- **`OpenPoseSkeleton`**: giunti finti → 18 punti; collo mancante ricavato dalle spalle; confidenza sotto soglia saltata; destra/sinistra non scambiate; persona con pochi giunti.
- **`PoseRenderer`**: immagine piccola con scheletro noto → pixel attesi (colore di un osso, di un punto, fondo nero); più persone; osso con un estremo mancante non disegnato; spessore proporzionale; nessuna persona → nessuna immagine.
- **`DepthEstimator` con `DepthModel` finto**: ridimensionamento (lato corto 518, lato lungo multiplo di 14), ritorno alle dimensioni originali, normalizzazione 0–255, convenzione «vicino chiaro», limite dei 2048 px, immagine illeggibile.
- **`ModelStore`** con `URLProtocol` finto e cartella temporanea: scaricamento completo, interruzione, file di dimensione sbagliata, sha256 sbagliato, «Annulla», che non resti nulla a metà, «modello presente» e «danneggiato», reindirizzamento verso un host non ammesso rifiutato.
- **`DepthPoseStore`**: selettore → cosa si crea e cosa si manda; il messaggio `contribute.moodboard` contiene solo le mappe scelte e i percorsi in `tempFolder`; salvataggio e lettura dello stato.
- **Interfaccia** (`RenderTests`, PNG come negli altri plug-in): tab vuoto, con anteprima, con modello assente (tasto visibile), con modello presente (tasto assente), in scaricamento; italiano e inglese; `LocalizationCatalogTests`-simile sulla tabella `L`.
- **Prove con modelli veri, fuori sandbox** (`URLSession` va in timeout in sandbox): scaricamento reale dei tre file e controllo dello sha256; una depth vera (orientamento vicino/lontano, scala, tempo); una posa vera con Vision su una foto di persona (un test con foto d'esempio nel repo **solo se sintetica**, nessun ritratto reale).
- **Prove a mano dell'utente**: trascinare un'immagine dal Finder e dal browser; «Crea» con le tre voci; «Manda al Moodboard» e controllo nel Moodboard; scaricamento del modello; uso delle mappe come riferimento con il LoRA/modello che l'utente ha.

## 11. Versioni e rilascio

- Plug-in `1.0`. Nessuna modifica al contratto 1: lavora con l'app attuale **0.2.3** (il campo `moodboard` esiste dalla prima versione del contratto).
- Release: all'uscita di una versione dell'app, o come aggiunta (`DepthPose.dthubplugin.zip` accanto agli altri). Come per ogni release: il via libera dell'utente è esplicito, il README dell'app elenca il plug-in, Obsidian e briefing si aggiornano, nota di release che dice del download e della rete.
- Nota Obsidian nuova `DT Hub - Depth & Pose`, collegata alla nota madre.

## 12. Fuori ambito (rinviati)

Mani e viso (`VNDetectHumanHandPoseRequest`, landmark del viso) per lo scheletro OpenPose completo; posa 3D (`VNDetectHumanBodyPose3DRequest`); altre mappe (canny, normali, segmentazione); modello Depth Base/Large; mandare la mappa come immagine di partenza o come livello Pennello; origine dell'immagine da Control o dal Moodboard; modifica dello scheletro a mano (collegata all'idea «Pose Builder» del backlog); DWPose/RTMPose convertito in Core ML; macOS 15 (il ramo `macos-15` è fermo per scelta dell'utente).

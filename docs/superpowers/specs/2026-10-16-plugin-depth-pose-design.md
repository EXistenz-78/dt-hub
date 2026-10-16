# Plug-in Depth & Pose — Design

Data: 16 ottobre 2026. Stato: disegno approvato in chat dall'utente, sezione per sezione. **Aggiornato il 16 ottobre dopo le prime prove dell'utente: vedi §13, che prevale sulle sezioni precedenti dove le contraddice.**
Base: `main` (`167db50`, app **0.2.3**). Controllato il 16 ottobre: i commit di `main` dopo la 0.2.3 (misuratore CU, selettore dei modelli, intestazione compatta) non toccano `PluginKit`, `Plugins/` né il contratto dei plug-in.

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
- **Solo con modelli edit o in-context** (§13): nessun `families` restrittivo, ma `requiresEditModel: true` nel manifest.
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
- **Due checkbox «Depth» e «Posa»** (predefinito: tutte e due; la scelta si ricorda per progetto). La checkbox «Depth» è disattivata finché il modello manca.
- **«Crea»** (l'ultimo controllo della colonna di sinistra, sotto le checkbox): calcola le mappe scelte e le mostra affiancate in anteprima (etichette «Depth», «Pose»). Disattivato senza immagine, senza nessuna checkbox spuntata, o con solo «Depth» e modello assente (con tutte e due e modello assente crea solo la posa e lo dice).
- **«Manda al Moodboard»**: attivo quando c'è almeno una mappa. Manda in **un solo** messaggio `contribute.moodboard` le mappe del selettore; un nuovo invio sostituisce quelle mandate prima (comportamento del contratto). La risposta dell'app (`conflicts`, `problems`) si mostra come nota.
- **«Scarica il modello (200 MB)»**: compare **solo se il modello non è sul disco** (o è danneggiato: «Riscarica»). Durante lo scaricamento sparisce il tasto e compare una barra di avanzamento con «Annulla». A fine scaricamento il tasto sparisce e «Depth» si attiva da sola.
- Finché il modello manca, **la posa funziona comunque**.
- Testi in italiano e inglese; ogni testo sta nella tabella `L`; un test controlla che esistano in tutte e due le lingue.

## 5. Elaborazione

### 5.1 Depth

- Modello: **Depth Anything V2 Base, F16**, convertito in Core ML per questo plug-in (§13): pacchetto unico con **due funzioni**, `landscape` (ingresso 1036×784) e `portrait` (784×1036), pesi condivisi, circa 205 MB. Uscita `depth` già immagine in grigi a 16 bit mezza precisione, normalizzata 0–1 dentro il modello (vicino = chiaro).
- `DepthEstimator` sceglie la funzione dall'orientamento dell'immagine (le quadrate vanno nella orizzontale), la **adatta nel rettangolo d'ingresso senza deformarla** (`fit`: più grande possibile, centrata, bordi neri), esegue il modello, **ritaglia i bordi** dalla risposta e la porta alla dimensione dell'immagine con interpolazione bilineare; poi normalizza 0–255 sull'immagine.
- Il lato lungo dell'immagine è limitato a **2048 px** prima del calcolo (`DPImage.maxLongSide`).
- Unità di calcolo `.all` (Neural Engine). La **prima predizione per ciascuna funzione** specializza il modello per il Neural Engine e può richiedere fino a mezzo minuto; poi circa 0,5 s di modello (circa 1 s col plug-in).
- (Superato: la versione Small di Apple, 518×392 fisso, 50 MB, circa 30 ms.)

### 5.2 Pose

> **Superato dalla spec `2026-10-16-depth-pose-posa-completa-design.md`:** la posa con Vision qui sotto resta solo come ripiego quando il modello della posa completa (DWPose-L: corpo, viso, mani) non è scaricato.

- `VNDetectHumanBodyPoseRequest`: ogni osservazione è una persona; i giunti sono letti con `recognizedPoints` e **l'elenco dei nomi non si presume**: si usano i giunti che la richiesta dà, e un giunto mancante o con **confidenza < 0,3** si salta.
- **Conversione OpenPose a 18 punti** (`OpenPoseSkeleton`), nell'ordine standard: naso, collo, spalla destra, gomito destro, polso destro, spalla sinistra, gomito sinistro, polso sinistro, anca destra, ginocchio destro, caviglia destra, anca sinistra, ginocchio sinistro, caviglia sinistra, occhio destro, occhio sinistro, orecchio destro, orecchio sinistro. «Destra/sinistra» sono quelle **della persona**, come in Vision. Il collo è quello di Vision; se manca ma ci sono le due spalle, è il loro punto medio. Il «root» di Vision non entra nello schema.
- **Disegno** (`PoseRenderer`): fondo nero, dimensioni dell'immagine; per ogni persona, le 17 ossa dello schema OpenPose come linee/ellissi con i **colori standard** (arti e tronco in tinte diverse, testa con occhi e orecchie) e un cerchio pieno su ogni punto. Lo spessore è proporzionale al lato lungo (circa 1/170) e ha un minimo; le ossa con un estremo mancante non si disegnano. I colori sono una tabella fissa nel codice, copiata dalla convenzione di OpenPose; i valori esatti si scrivono nel piano e si provano con un test a pixel.
- Più persone: più scheletri sulla stessa immagine. Nessuna persona: la posa non si crea e una nota lo dice; la depth, se scelta, si crea e si può mandare.

### 5.3 Uscita

- Mappe salvate come PNG in 8 bit (`depth.png`, `pose.png`) nella `tempFolder` del contesto, alla dimensione dell'immagine ridotta (§5.1). Nomi per il Moodboard: «Depth» e «Pose» (il campo `name` di `contribute.moodboard`), senza il nome dell'immagine.
- La `tempFolder` arriva col messaggio `context`; senza, il tasto «Manda al Moodboard» è disattivato e una nota lo dice.

## 6. Modello: dove sta, come si scarica

- Cartella: `…/DT Hub/Data/DepthPose/`.
  - `DepthAnythingV2BaseF16.mlpackage/` = i tre file scaricati (o messi a mano);
  - `DepthAnythingV2BaseF16.mlmodelc/` = il modello compilato, usato per le predizioni.
- **File da scaricare**, dalla release `depth-anything-v2-base-coreml` di `EXistenz-78/dt-hub` su GitHub (un elenco piatto di file: il nome sul server, `asset`, può differire dal percorso locale, `path`):
  - `DepthAnythingV2BaseF16-Manifest.json` → `…mlpackage/Manifest.json` — 617 byte
  - `DepthAnythingV2BaseF16-model.mlmodel` → `…mlpackage/Data/com.apple.CoreML/model.mlmodel` — 411.200 byte
  - `DepthAnythingV2BaseF16-weight.bin` → `…mlpackage/Data/com.apple.CoreML/weights/weight.bin` — 204.996.928 byte
  - ognuno con il suo sha256 (nel codice, `DPModelManifest`).
- **Procedura**: si scarica in una cartella temporanea dentro `Data/DepthPose/`; si controlla dimensione **e sha256** di ogni file; si compila con `MLModel.compileModel(at:)`; solo allora si sposta tutto al posto definitivo. Un errore o un «Annulla» cancellano la cartella temporanea e **non lasciano nulla a metà**.
- **Pacchetto già presente** (messo a mano, o scaricato altrove): all'avvio, se manca il modello compilato ma tutti i file del pacchetto sono nella cartella, il plug-in li controlla con gli stessi sha256 e li compila (`installLocalPackage`).
- «Il modello è presente» significa: la cartella compilata esiste **e** si apre con `MLModel(contentsOf:)`. Se non si apre, il tasto torna come «Scarica di nuovo il modello».
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

- **Rete**: solo al clic su «Scarica il modello» e solo verso `github.com` (i file di una release sono serviti da un sottodominio di `githubusercontent.com`: si seguono i reindirizzamenti solo verso questi). È il **secondo** plug-in a usare la rete, dopo LoRA Advisor; va detto nel README e nelle note di release. Non si invia nulla dell'utente: solo richieste GET dei tre file. I pesi sono CC BY-NC 4.0 (§13): licenza e attribuzione stanno nella pagina della release.
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

## 13. Revisione del 16 ottobre (dopo le prime prove)

Dopo averlo provato l'utente ha chiesto, e questa sezione prevale sulle precedenti:

1. **Due checkbox** «Depth» e «Posa» al posto del selettore a tre voci; «Crea» sotto di loro. Il vecchio `state.json` (`"mode": depth | pose | both`) si legge ancora.
2. **Attivo solo con modelli edit o in-context.** Il manifest guadagna `requiresEditModel: true` (aggiunta facoltativa al contratto 1: un'app che non la conosce lascia il plug-in acceso). L'app sa già se il modello scelto è edit/in-context (`ModelCapabilities.isEditModel`, dal campo `modifier` della specifica: `kontext`, `kontext_kv`, `qwenimage_edit_plus`, `editing`) e lo passa al registro, che spegne il plug-in e ne nasconde il tab con gli altri modelli; con un modello sconosciuto resta acceso. Serve una versione dell'app che contenga la modifica.
3. **Depth più dettagliata: Depth Anything V2 Base** convertito da noi in Core ML. La versione di Apple (Small) ha un ingresso fisso 518×392; la conversione di Base ha due funzioni (§5.1). Misurato su una foto di prova: la correlazione con PyTorch è 1,0000; il confronto a occhio mostra più separazione tonale e bordi più netti. La quantizzazione a 8 bit è stata provata e scartata (correlazione −0,06).
4. **Ospitato su GitHub** (release di `dt-hub`), non più su Hugging Face. Licenza dei pesi: **CC BY-NC 4.0** (Lihe Yang et al.): il plug-in e DT Hub restano gratuiti; i pesi convertiti non si vendono né si includono in nulla di venduto. La pagina della release porta licenza, attribuzione e «convertito in Core ML (F16, forme fisse, funzioni unite, uscita normalizzata)». Lo script di conversione sta in `Plugins/DepthPose/Scripts/`.
5. **Posa: da migliorare** (prossimo lavoro, da concordare). Vision non capisce gli arti non visibili e non dà viso né mani. Direzione: RTMW / DWPose (133 punti: corpo, mani, viso; Apache-2.0), da convertire in Core ML come si è fatto per la depth, con il disegno OpenPose completo (viso a puntini bianchi, mani a 21 punti) come nel riferimento `pose-full.jpg` della LoRA di nomadoor. `rtmlib-coreml` non serve come modello (è `rtmlib` con il provider Core ML di onnxruntime), ma il suo codice (Apache-2.0) mostra la pre/post-elaborazione e il disegno `openpose134`.
6. **Posa a figura intera (spec `2026-10-16-depth-pose-posa-completa-design.md`).** DWPose-L convertito in Core ML (64 MB, 15 ms per persona), release `dwpose-l-coreml`, Apache-2.0; riquadri da Vision (o l'immagine intera); corpo, viso a puntini e mani; Vision resta come ripiego; i due modelli si scaricano con tasti indipendenti.

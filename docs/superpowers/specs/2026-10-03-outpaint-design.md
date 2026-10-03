# DT Hub — Design dell'outpaint (zoom dell'immagine nel canvas)

Data: 3 ottobre 2026 · Stato: realizzata (M7d) · Estende `2026-10-01-tab-control-design.md` (§5 Inquadratura, §6 Dal tab al RUN)

## 1. Scopo

Poter **allargare** un'immagine (outpaint): la si rimpicciolisce nel canvas, i margini che restano vuoti sono area da rigenerare e Draw Things li riempie in modo coerente con il resto. Lo stesso controllo, in senso opposto, **ingrandisce** l'immagine per usarne solo una porzione come base.

Decisioni dell'utente (3 ottobre 2026):
- l'outpaint si fa **prima** del Tiled Diffusion a 8192 (la spec del tab Control diceva il contrario; il backlog si aggiorna). Lavora entro il limite di oggi, 2048;
- niente modo "Contieni" né scala separata: **uno slider nella card Canvas, da −100 a +100**. 0 è com'è oggi (l'immagine riempie il canvas, ed è il valore all'importazione); i valori negativi rimpiccioliscono l'immagine e lasciano margini; i positivi la ingrandiscono. Il **trascinamento** per spostarla nel canvas resta;
- scatto magnetico dello slider su 0 e sul valore in cui l'immagine sta tutta nel canvas.

Fuori: Tiled Diffusion e canvas oltre 2048; outpaint a passi successivi in automatico; pennello dentro i margini (si rigenerano comunque); riempimento dei margini scelto dall'utente.

## 2. Idea di base

Il ritaglio è già una **finestra** sull'immagine (`FramingMath.cropRect`, in pixel dell'immagine), e Run, maschera, Pennello e schermo la usano. La finestra può **uscire dall'immagine**: la parte fuori è margine. Non c'è una seconda geometria; maschera e Pennello restano in coordinate dell'immagine e vengono tagliati dalla finestra come oggi.

## 3. Modello

`Framing` perde il modo (`fill`, l'unico che c'era) e ottiene lo `zoom`:
- `zoom`: −100…+100, predefinito 0, limitato; la lettura è tollerante e un modo vecchio nel file si ignora;
- `offsetX`, `offsetY`: −1…+1 come oggi.

**Fattore.** `f = 4^(zoom/100)` (+100 ingrandisce 4 volte, −100 riduce a un quarto; la scala è esponenziale così la stessa distanza dello slider dà lo stesso effetto a destra e a sinistra).

**Finestra.** Parte da quella di riempimento `(w0, h0)` (la parte dell'immagine che riempie il canvas, come oggi) e la divide per `f`: `w = w0/f`, `h = h0/f`. La posizione è `x = (iw − w)·(1 + offsetX)/2`, `y = (ih − h)·(1 + offsetY)/2`: con `w` più grande di `iw` la differenza è negativa e `offset` −1 attacca l'immagine al bordo iniziale del canvas, +1 al finale, 0 la centra. La formula è quella di oggi. Lo spostamento è libero su un asse quando la finestra non coincide con l'immagine su quell'asse.

**Margini.** `FramingMath` calcola, dal rettangolo dell'immagine dentro il canvas, quanto margine c'è su ogni lato (in pixel del canvas e in percentuale) e se ce n'è (`hasMargins`).

**Scatti.** Zoom 0, e `zoomContain = 100·log₄(s_contain / s_fill)` (negativo o 0), dove `s` sono i pixel di canvas per pixel di immagine che riempiono (`max`) o contengono (`min`) l'immagine. Lo scatto cattura entro ±3 punti.

Lo zoom e lo spostamento **non fanno parte della storia** (come oggi lo spostamento), ma si salvano in `control.json` e Annulla/Ripeti non li riportano indietro (`keepingSettings`, già in uso). Cambiare il canvas ricalcola tutto al volo; cambiare l'immagine riporta zoom e spostamento a 0.

## 4. Dal tab al RUN

- **Immagine.** Il canvas riceve l'immagine nella sua posizione, scalata; il Pennello va sopra nello stesso taglio. I margini si riempiono con i **pixel del bordo dell'immagine stesi in fuori** (gli angoli con il pixel d'angolo). Provato dal vivo il 3 ottobre 2026 (SD 1.5, 512×512 in un canvas 768×512): con un grigio neutro "Conserva l'originale" lasciava una riga chiara sulla giunzione, con i bordi estesi no.
- **Maschera.** `InputComposer.mask` accetta la maschera dipinta **opzionale**: la maschera inviata è l'unione di margini (rigenerare) e maschera dipinta scalata. Il bordo dei margini passa dalle stesse impostazioni (Sfumatura, Margine, "Conserva l'originale"). Con margini ma senza maschera dipinta il Run manda comunque la maschera e `strength` al 100% (con forza scelta a mano vale la forza scelta).
- **Forza automatica.** 100% se c'è una maschera dipinta **o** un margine, 70% negli altri casi (anche con zoom positivo); modelli Edit 100%. `effectiveStrength` riceve `hasMargins`.
- **`enableInpainting`** e l'invio della maschera si decidono come in M7c (solo con l'immagine, solo per i modelli con `modifier == "inpainting"`).
- **Decodifica.** La dimensione a cui si decodifica l'immagine tiene conto dello zoom (con zoom positivo servono più pixel di oggi).

### 4b. Riempimento dei margini per i LoRA di outpaint (aggiunto il 3 ottobre 2026, dopo la prova dell'utente)

I bordi estesi con la maschera valgono per i modelli inpaint e per Klein senza LoRA (misurato su FLUX.2 klein: continua bene). Sono sbagliati per i **LoRA di outpaint dei modelli Edit**: si istruiscono con il prompt (Qwen: "replace the solid gray areas…", Flux: "fill the green spaces…") e vogliono margini di **un colore pieno** e **nessuna maschera**. Misurato su Qwen Image 2.1 + `q21_outpaint_v2` (576×1024, 25 passi, forza 100%, guida 1): con bordi estesi + maschera il modello **conserva le strisce**; con grigio pieno e senza maschera continua la scena come in Draw Things; con grigio e maschera l'originale torna intatto ma la giunzione si vede come una cornice e il resto non si fonde.

- `MarginFill`: `edges` (bordi estesi, margini nella maschera), `gray`, `green` (colore pieno, margini fuori dalla maschera). `ControlInputs.marginFill` (nil = automatico) si salva e non è un passo della cronologia.
- **Automatico**: se tra i LoRA del job ce n'è uno con "outpaint" nel nome del file o nel trigger → `green` se il trigger parla di "green", altrimenti `gray`; senza → `edges`.
- Una maschera dipinta dall'utente si manda comunque, ma senza i margini.
- La card Canvas mostra, solo quando ci sono margini, il menu "Riempimento margini" (Automatico (…) / Bordi estesi + maschera / Grigio, senza maschera / Verde, senza maschera). In Disegno i margini sono arancio solo se vanno nella maschera, altrimenti del colore del riempimento.
- Crash noto, **non di DT Hub**: il LoRA `flux_outpaint_lora` è per Flux.1; applicato a FLUX.2 klein fa cadere il server (trap in `LoRALoader.mergeLoRA`). Si risolve con un controllo di compatibilità LoRA/modello (backlog).

## 5. Interfaccia (card Canvas)

**Modo Canvas.** Sotto il selettore Canvas/Disegno, lo slider **Zoom** (−100…+100, con il valore a fianco e un pulsante "ripristina" che riporta zoom e spostamento a 0). Lo stage mostra sempre il **canvas** (rapporto fisso), con l'immagine che si muove e scala dentro. Attorno al canvas una **cornice scura** (circa il 12% per lato) mostra la parte che esce, oscurata; i margini sono a scacchi. Il drag sposta l'immagine su entrambi gli assi dove c'è spazio.

**Modo Disegno.** Il canvas come viene inviato; i margini colorati come la maschera. Il pennello e le maschere non dipingono nei margini (la maschera e il disegno hanno la dimensione dell'immagine).

**Didascalia.** Oltre alla dimensione: con margini "margini: sopra e sotto 12%" (solo i lati che ne hanno); con zoom positivo "si usa il 40% dell'immagine"; a 0 e immagine di rapporto diverso la perdita come oggi.

**Avvisi.** L'avviso arancione di ritaglio forte (oltre un terzo) compare solo con zoom ≤ 0: con zoom positivo il ritaglio lo ha scelto l'utente.

**Forza.** La didascalia della card Immagine che spiega "con la maschera la forza è al 100%" vale anche con i margini.

## 6. Moduli toccati

| Modulo | Cambia |
|---|---|
| HubKit | `Framing` (zoom, senza modo), `effectiveStrength(editModel:hasMargins:)` |
| HubCore | `FramingMath` (finestra con zoom, margini, scatti), `InputComposer` (immagine con margini, maschera opzionale), `ControlStore` (`setZoom`, `pendingInputs`, avvisi, `PendingInputs.render`), `CanvasDrawing` e `MaskBitmap` (taglio con finestra fuori dall'immagine) |
| App | `CanvasStage` (slider, stage a canvas con cornice, drag, didascalia), `ImageCard` (forza), `ControlText`, catalogo |
| DTBridge | nessuno (la maschera e la forza passano già) |

## 7. Test e verifiche

**Unitari (HubCore, HubKit):**
- finestra: zoom 0 uguale a oggi, zoom positivo (rettangolo più piccolo, spostamento), zoom negativo (rettangolo che esce, `offset` −1/0/+1 attacca ai bordi), 1:1 in 4:3 e 3:4 in 4:3, `zoomContain` (rapporto uguale → 0);
- margini: lati, percentuali, `hasMargins` (zoom 0 con rapporto uguale: nessuno);
- compositore: pixel reali (immagine nella posizione, margini con il colore del bordo, il Pennello nello stesso taglio); maschera: trasparente nei margini, la dipinta al suo posto, senza maschera dipinta; bordo con Margine/Sfumatura;
- forza automatica con margini, con maschera, senza;
- store: `setZoom` limita, si salva e si ripristina, non entra in Annulla, cambiando immagine torna a 0; avvisi (ritaglio forte solo con zoom ≤ 0);
- lettura tollerante di `control.json` vecchi (con `mode`, senza `zoom`).

**Dal vivo con un server vero** (fatto il 3 ottobre 2026): un'immagine rimpicciolita in un canvas più largo; i margini si rigenerano, l'immagine resta (Conserva l'originale), giunzione senza cucitura visibile con i bordi estesi (con il grigio c'era una riga chiara); forza al 100%.

**Prestazioni:** il trascinamento e lo slider devono restare fluidi: l'immagine si ricompone sullo schermo a ogni evento (da misurare nel prototipo, sullo stage già a strati).

## 8. Rischi aperti

- **Giunzione dei margini:** dipende da Draw Things e dal modello; si misura nel prototipo (riempimento) e con un modello inpainting vero quando ci sarà.
- **Zoom positivo e decodifica:** con foto grandi lo zoom ×4 richiede di decodificare a più risoluzione; il limite di memoria si controlla nel prototipo.
- **Vista dei ritagli forti:** lo stage a canvas non mostra più tutta l'immagine con la parte persa oscurata, ma solo una cornice attorno al canvas; la didascalia dà le percentuali. Si giudica nel prototipo.

## 9. Tappa

**M7d** — Outpaint (slider Zoom, margini come maschera). Poi: Tiled Diffusion fino a 8192, M8 Plug-in, Galleria.

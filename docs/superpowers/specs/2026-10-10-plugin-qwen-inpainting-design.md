# Plug-in «Qwen 2.1 Inpainting» e `contribute.paint` — Design

Data: 10 ottobre 2026. Stato: approvato in chat dall'utente, sezione per sezione; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` 0.1.5 (`5c6bf54`). Indipendente da «LLM Chat»: i due lavori toccano file vicini (`PluginContribution`, `ContributionStore`, README del kit). Chi arriva secondo fa il merge.

## 1. Obiettivo

Un plug-in per **Qwen Image 2.1** che fa ciò che fa il nodo «Sketch» di Pixaroma per ComfyUI, ricreato da zero con l'interfaccia e i comandi di DT Hub (nessun codice copiato):

- si disegnano **segni colorati** sull'immagine di partenza (pennello, rettangoli, ovali, frecce);
- per ogni coppia **colore + strumento** si scrive cosa cambiare lì;
- **Invia** mette il disegno nel livello Pennello di Control e scrive il prompt, direttamente oppure passando dal PE I2I di Qwen.

Al RUN l'app unisce il livello Pennello all'immagine (`InputComposer`): Qwen riceve immagine e segni fusi, legge le istruzioni e toglie i segni.

## 2. Decisioni (dell'utente, 10 ottobre)

- **Niente maschera**: solo disegno e istruzioni.
- **Il disegno va come livello Pennello** di Control (aggiunta `contribute.paint`), non come nuova immagine di partenza.
- **Una card per coppia colore + strumento** (2 rettangoli verdi = 1 card; 1 rettangolo e 1 pennellata verdi = 2 card; 1 rettangolo verde e 1 rosso = 2 card). Il titolo e la frase usano il plurale quando i segni sono più di uno.
- **Frase finale sempre presente**: «Remove all the colored marks and keep everything else the same.» (i segni arrivano fusi all'immagine).
- **PE I2I:** si usa l'LLM assegnato alla famiglia `qwen_image_2.1` con uso I2I, se esiste, con una casella per non usarlo; altrimenti le frasi unite vanno direttamente nel prompt.
- **Modifica dei segni dopo il disegno** (selezione, spostamento, maniglie): **rinviata**. Nella prima versione ci sono Annulla, Ripeti e Cancella tutto.
- **Cambio dell'immagine di partenza:** tutti i segni spariscono.
- **Niente Margine né Sfumatura.**

## 3. Contratto: `contribute.paint`

- **HubKit (`PluginContribution`):** `public var paint: PluginImageRef?`, letto da `contribute.paint` (`{"path","name"}`, file nel `tempFolder`) con lo stesso parser di `startImage`. È incluso in `isEmpty`.
- **`ContributionTarget`:** `func setPaint(_ image: PluginImageRef) throws`.
- **`GenerationController.setPaint`:**
  1. legge il PNG;
  2. lo ridisegna in un `CGContext` RGBA della dimensione esatta di `control.maskSize` (le proporzioni dell'immagine, lato lungo ≤ `MaskBitmap.maxSide`);
  3. costruisce `PaintBitmap(image:)` e chiama `control.commitPaint(_:)`.

  È un passo di Annulla di Control e **sostituisce** il disegno che c'era. Se il PNG non ha le proporzioni dell'immagine, viene stirato; il plug-in manda sempre le proporzioni giuste.
- **`ContributionStore.receive`:** `paint` si applica dopo l'eventuale `startImage` dello stesso messaggio, e solo con un'immagine di partenza (`target.startImageID != nil`). Altrimenti va in `problems` (`"paint: there is no start image."`), così come un file illeggibile (`"<name>: …"`). Niente marchi né conflitti: vince l'ultimo che scrive.
- **README del kit:** la chiave `paint` in `contribute`. Va sopra l'immagine di partenza nel livello Pennello della card Canvas, dove l'utente lo vede e lo modifica; sostituisce il disegno che c'era; al RUN l'app lo unisce all'immagine; serve un'immagine di partenza.

## 4. Il plug-in

### 4.1 Identità

- Nome «Qwen 2.1 Inpainting», id `com.exiztenz.dthub.qweninpainting`, versione 1.0, simbolo `scribble.variable`, `families: ["qwen_image_2.1"]`.
- Cartella `Plugins/QwenInpainting`, bundle `QwenInpainting.dthubplugin`, entry `QwenInpaintingEntry`, alias dei moduli `QwenInpaintingKit` / `QwenInpaintingDesign`. Pacchetto e `Scripts/build.sh` come Batch plus.

### 4.2 Dati

```swift
enum MarkTool: String, Codable, CaseIterable { case sketch, box, circle, arrow }
enum MarkColor: String, Codable, CaseIterable { case yellow, red, blue, cyan, magenta, green, purple, white, black }
struct Mark: Codable, Equatable {
  var tool: MarkTool
  var color: MarkColor
  /// Line width in pixels of the start image.
  var width: Double
  /// Fractions of the start image (0…1). box/circle: two opposite corners; arrow: tail, tip; sketch: the stroke.
  var points: [CGPoint]
}
struct CardKey: Hashable, Codable { var color: MarkColor; var tool: MarkTool }
```

- **Colori puri**, in questo ordine:

  | Colore | RGB |
  |---|---|
  | yellow | 255,255,0 |
  | red | 255,0,0 |
  | blue | 0,0,255 |
  | cyan | 0,255,255 |
  | magenta | 255,0,255 |
  | green | 0,255,0 |
  | purple | 128,0,255 |
  | white | 255,255,255 |
  | black | 0,0,0 |

  Il nome inglese è quello che va nel prompt; il tooltip è in italiano o in inglese.
- **Limiti:** 200 segni, 4 000 punti per pennellata. I punti più vicini di 1 px dello schermo al precedente si scartano.
- **Spessore:** da 4 a 128 px dell'immagine, default 16.

### 4.3 Geometria (una sola fonte per schermo e PNG)

`MarkGeometry.path(for mark: Mark, in size: CGSize) -> (stroke: CGPath, fill: CGPath?)`, nelle coordinate di `size`:

- **box:** rettangolo fra i due angoli, tratto centrato sul bordo.
- **circle:** ellisse inscritta nel rettangolo fra i due angoli.
- **sketch:** curva per i punti medi (ogni punto originale fa da controllo di una quadratica), poi una linea fino all'ultimo punto. Un solo punto dà un tondino.
- **arrow:**
  - asta dalla coda alla base della punta;
  - punta = triangolo pieno (`fill`), lungo `max(width × 4, 12)` ma mai più di 2/3 della freccia, semiapertura 25°.

Il tratto è sempre arrotondato (`lineCap .round`, `lineJoin .round`) e lo spessore vale `width × size.width / imageWidth`.

### 4.4 Interfaccia

- **Barra** (stile della modalità Disegno di Canvas):
  - strumenti con sola icona e nome nel tooltip: Pennello `paintbrush.pointed`, Rettangolo `rectangle`, Ovale `oval`, Freccia `arrow.up.right`;
  - divisore, poi i 9 tondini dei colori (il selezionato ha un anello in `DS.accent`);
  - divisore, poi Cancella tutto (`trash`, `DS.remove`, con conferma), Annulla e Ripeti;
  - sotto, la riga **Spessore** con slider e valore in px.
- **Canvas:**
  - l'immagine di partenza di Control adattata allo spazio (proporzioni conservate), con i segni sopra;
  - il segno in corso si vede mentre si trascina;
  - rettangolo, ovale e freccia: clic e trascina;
  - pennello: mano libera;
  - una pressione che si sposta meno di 3 px dello schermo non crea nulla;
  - senza immagine di partenza: testo «Metti un'immagine di partenza in Control» e strumenti disattivati.
- **Card:**
  - una per coppia `CardKey` presente fra i segni, nell'ordine del **primo** segno di quella coppia;
  - titolo col tondino del colore (§4.5), poi un campo di testo multilinea (da 2 a 6 righe).
- **Riga di invio:**
  - **anteprima** del prompt composto (sola lettura, testo piccolo, selezionabile);
  - casella **«Migliora con <nome>»**, solo se esiste il PE (§4.6);
  - pulsante **Invia** e riga di stato.
  - Invia è attivo con immagine di partenza, almeno un segno e plug-in acceso.
- **Avviso** con il plug-in spento: «Accendi Qwen 2.1 Inpainting dal menu dei plug-in».

### 4.5 Titoli e frasi

Per una coppia con `n` segni (plurale se `n > 1`):

| Strumento | Titolo della card | Frase |
|---|---|---|
| box | `INSIDE red box` / `INSIDE red boxes` | `Inside the red box: <testo>` / `Inside the red boxes: <testo>` |
| circle | `INSIDE red circle(s)` | `Inside the red circle(s): <testo>` |
| sketch | `INSIDE red sketch(es)` | `Inside the red sketch(es): <testo>` |
| arrow | `WHERE red arrow points` / `WHERE red arrows point` | `Where the red arrow points: <testo>` / `Where the red arrows point: <testo>` |

- **Testo:** spazi e a capo ridotti a uno spazio; vuoto → nessuna frase; si aggiunge il punto se non finisce con `.`, `!` o `?`.
- **Prompt composto:**
  - le frasi nell'ordine delle card, separate da uno spazio, poi `Remove all the colored marks and keep everything else the same.`;
  - nessuna frase → prompt composto vuoto: il campo Prompt non si tocca e va solo il disegno.
- **Testi in memoria:** sono salvati per `CardKey` anche quando la card è nascosta (segni tolti con Annulla o Cancella tutto) e ricompaiono con lei.

### 4.6 PE I2I

- **Scelta:** il primo, in ordine di nome, fra i `languageModels` del contesto con `family == "qwen_image_2.1"`, `use == "i2i"` e `supportsImages == true`. Nessuno → niente casella.
- **Casella** «Migliora con <nome>», accesa di default, salvata per progetto.
- **System prompt:** il primo file che esiste nella cartella del modello (`path`) fra `system_prompt_i2i.txt` e `system_prompt.txt`. Altrimenti:

  ```
  You rewrite instructions for Qwen Image 2.1 image editing. The picture has colored marks drawn on it. Rewrite the
  user's instructions as one clear editing prompt in English. Keep every reference to the colored marks (colour and
  shape) and the final instruction to remove them. Answer with the prompt only.
  ```
- **Testo mandato:** il prompt composto, una riga vuota, poi `Keep every reference to the colored marks and the instruction to remove them.`
- **Opzioni:** `maxTokens` 2048, timeout 600 s. Immagine: `fused.png` (§4.7).
- **Risposta:** si tolgono spazi e virgolette esterne. Vuota o errore → si usa il prompt composto e la riga di stato dice «PE non disponibile: inviato il prompt diretto (<motivo>)».

### 4.7 Invia

1. **`paint.png`:**
   - RGBA trasparente, alla dimensione in pixel dell'immagine di partenza (letta dal file, rispettando l'orientamento EXIF come fa l'app);
   - ogni segno disegnato con `MarkGeometry`, antialias acceso, colore pieno;
   - scritto in `tempFolder/qwen-inpainting-<uuid>/paint.png`.
2. **Prompt composto** (§4.5).
3. **PE**, se casella accesa, PE presente e prompt composto non vuoto:
   - `fused.png` = immagine di partenza + `paint.png`, ridotta a lato lungo ≤ 1536, accanto a `paint.png`;
   - poi la chiamata del §4.6.
4. **`host.contribute`** con `{"paint": {"path", "name": "Qwen 2.1 Inpainting"}}`, più `"fields": {"prompt": …}` se il prompt non è vuoto.
5. **Riga di stato:**
   - «Inviato.» o «Inviato. N conflitti in attesa nell'app.»;
   - `problems` in rosso;
   - `error` in rosso col testo dell'app;
   - nessuna risposta → «Nessuna risposta dall'app».
6. **Durante l'invio:** Invia disattivato, stato «Invio…» oppure «PE in corso…».

### 4.8 Stato per progetto

- **`state.json`** nella cartella del progetto (messaggio `project`):

  ```json
  {"startImage": "…", "marks": [...], "texts": {"red:box": "…"}, "tool": "box", "color": "red", "width": 16, "usePE": true}
  ```
- **Scrittura e lettura:** scrittura atomica a ogni cambio (per il testo: alla fine della modifica o dopo 0,5 s di pausa); lettura tollerante, dove un campo mancante prende il default e un segno illeggibile si salta.
- **Prima del primo `project`:** tutto in memoria.
- **Annulla/Ripeti:** fotografie della lista dei segni, al massimo 100, solo in memoria. Si svuotano al cambio di progetto o di immagine.
- **Cambio d'immagine:** il contesto porta `startImage` (percorso). Se è diverso da quello salvato, compreso il passaggio a nessuna immagine:
  - segni e pila di Annulla si svuotano;
  - `texts` resta;
  - si salva il percorso nuovo.

  Il primo contesto dopo un cambio di progetto confronta con il valore di quel progetto.

### 4.9 Testi

Tabella `L` it/en come in Batch plus. I titoli delle card e le frasi sono sempre in inglese: sono il prompt.

## 5. Test

- **HubKitTests:** `contribute.paint` letto (con e senza `name`); `isEmpty` con il solo `paint` è falso.
- **HubCoreTests (`ContributionStore`):** con immagine → `setPaint` chiamato; senza immagine → problema; file che fa fallire `setPaint` → problema col nome; `startImage` + `paint` nello stesso messaggio → nell'ordine.
- **App:** il ridimensionamento alla `maskSize` sta in una funzione pura testabile in HubCore (`PaintBitmap.fitted(from: CGImage, width:height:)`). Test: un PNG 2048×1024 con un pixel rosso in alto a sinistra diventa 1024×512 con quel colore lì.
- **Plug-in:**
  - **card:** raggruppamento e ordine (esempi del §2); testi conservati quando una card si nasconde e ricompare;
  - **frasi:** titoli e frasi al singolare e al plurale per i quattro strumenti; prompt composto (spazi, punto, frase finale, vuoto senza testi);
  - **geometria:** il rettangolo di `box` (100×100, spessore 10) passa per i punti attesi; la punta della freccia mai oltre 2/3; una pennellata di un solo punto dà un tondino;
  - **rasterizzazione:** `paint.png` di 200×100 con un box rosso → pixel del bordo rosso (255,0,0,255), centro trasparente, angolo esterno trasparente;
  - **immagine fusa:** lato lungo ≤ 1536, il pixel del segno è rosso;
  - **scelta del PE**: vale solo `qwen_image_2.1` + `i2i` + visione; il primo per nome;
  - **system prompt:** letto dal file i2i, poi dal generico, poi il testo incorporato;
  - **corpo di `contribute`:** con e senza prompt;
  - **ripiego del PE** in caso di errore;
  - **stato:** salva e ricarica; cambio d'immagine svuota segni e Annulla e tiene i testi; progetti separati;
  - **pila di Annulla:** limite 100; Ripeti si svuota dopo un segno nuovo;
  - **testi** `L` completi.

## 6. Compatibilità

- **App 0.1.5 con il plug-in nuovo:** l'app non conosce `paint` e risponde `ok` senza applicarlo, quindi il plug-in non può accorgersene dalla risposta. Il README del plug-in chiede DT Hub 0.1.6 o successiva.
- **Plug-in vecchi:** nessun cambiamento.

## 7. Da verificare a mano

- Rettangolo rosso e freccia verde, testi nelle due card, Invia senza PE:
  - il livello Pennello in Canvas mostra i segni;
  - il Prompt contiene le due frasi e quella finale;
  - RUN → modifica nelle zone segnate e segni spariti.
- Due rettangoli rossi → una card «INSIDE red boxes».
- Con PE I2I assegnato a «Qwen Image 2.1 · I2I»: la casella compare e il prompt arriva riscritto; spegnendola arriva il prompt diretto.
- Cambio dell'immagine di partenza → segni spariti, testi ritrovati rifacendo un segno uguale.
- Annulla in Control dopo l'Invia → torna il disegno di prima.

## 8. Fuori ambito

- Selezione, spostamento e maniglie dei segni.
- Testo scritto sull'immagine.
- Maschera.
- Zoom e spostamento del canvas.
- Più immagini.
- Plug-in per altre famiglie.

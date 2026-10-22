# Plug-in Flux3 Editing — spec

Data: 22 ottobre 2026. Stato: **bozza da approvare**. Mockup: `docs/superpowers/mockups/2026-10-22-flux3-editing.html` (interattivo; i dettagli visivi sono quelli del mockup).

## 1. Scopo

**Flux3 Editing** costruisce il prompt di *editing con immagini di riferimento* di FLUX.3: una prosa che cita le immagini (`<ref_image_N>`) e gli elementi (`<id>`), seguita da un array JSON `[{id, from, src_bbox, tgt_bbox, desc}]`. L'utente disegna i riquadri su **immagini vere**: sulle immagini del Moodboard per prendere un oggetto, sull'immagine di partenza per dire dove metterlo o cosa tenere, cambiare, spostare o togliere. Il testo finale va nel campo Prompt della Generazione.

Decisioni dell'utente (22 ottobre 2026):
- **Plug-in separato** («Flux3 Editing»; nel briefing «Flux3 Inpainting»). Prompt Master F3 e I4 non si toccano; dal codice di F3 si copia solo ciò che serve (i plug-in sono pacchetti indipendenti).
- **Tre card:** Moodboard, Immagine di partenza, Prompt. Le prime due sono tele con l'immagine di sfondo.
- **FLUX.2 klein fa da segnaposto** finché FLUX.3 Klein non è in Draw Things: il plug-in scrive il prompt finale come se l'obiettivo fosse FLUX.3 (FLUX.2 non legge i riquadri, ma si prova tutto fino al prompt).
- **Numerazione (regola A):** `ref_image_0` = immagine di partenza (badge 1 del tab Control), `ref_image_N` = badge N + 1. Non verificabile finché FLUX.3 non gira in Draw Things: sta in **un solo punto** del codice (§4).
- Il plug-in lavora solo con un'immagine di partenza; le immagini del Moodboard con l'occhio spento non compaiono.
- Come F3: LLM facoltativo (traduce e arricchisce senza toccare gli id), Annulla, stato per progetto.

## 2. Il formato che FLUX.3 legge (modifica con riferimenti)

Fonti: documentazione BFL (`docs.bfl.ai/flux_3/flux3_image_bounding_boxes`, `…/guides/prompting_editing_multi_reference`), raccolte dall'utente (`sintassi dell' l'editing Flux3.md`, `More.md`). Griglia **0–1000**, origine in alto a sinistra, **`[top, left, bottom, right]` = `[y0, x0, y1, x1]`**, `top < bottom`, `left < right`; ogni bbox è normalizzata **sulla propria immagine**. La prima immagine dell'array è quella modificata e dà la dimensione di uscita.

```
Modify <ref_image_0> by adding the lamp <lamp_1> from <ref_image_1> on the sideboard. Keep everything else unchanged.

[
  {"id": "lamp_1", "from": "ref_image_1", "src_bbox": [250, 180, 820, 620], "tgt_bbox": [300, 550, 550, 720], "desc": "…"}
]
```

I cinque casi (colonne del JSON):

| Tipo (menu della mini-card) | `from` | `src_bbox` | `tgt_bbox` | Riquadri disegnati |
|---|---|---|---|---|
| **Da riferimento** (automatico) | `ref_image_N` | sull'immagine del Moodboard | sull'immagine di partenza | uno sul Moodboard + la sua coppia sull'immagine di partenza |
| **Nuovo** | `null` | `null` | il riquadro | uno sull'immagine di partenza |
| **Esistente** (tenere o cambiare: lo decide la `desc`) | `ref_image_0` | il riquadro | lo stesso riquadro | uno |
| **Sposta** | `ref_image_0` | dove sta | dove va | due sull'immagine di partenza, stesso colore |
| **Togli** | `ref_image_0` | il riquadro | `null` | uno (tratteggiato, con una X) |

## 3. Famiglia e manifest

`id` `com.exiztenz.dthub.flux3editing`, nome «Flux3 Editing», versione 1.0, simbolo da scegliere al piano (es. `rectangle.on.rectangle`). `families`: costante unica `Flux3EditingPlugin.families`, oggi `["flux2_9b", "flux2_4b"]` (come F3); quando Draw Things espone FLUX.3 Klein si aggiunge il suo id (sconosciuto: nessuna ipotesi nel codice). Fuori dalla famiglia il tab sparisce (regola del contratto 1). Nessuna aggiunta al contratto: bastano `startImage` e `moodboard` del contesto (§4).

## 4. Le immagini e la numerazione

Il contesto dell'app dà `startImage` (percorso) e `moodboard` (percorsi, **solo le immagini accese, nell'ordine delle miniature**: è `ControlStore.moodboardURLs`). Il plug-in:
- `ref_image_0` = `startImage`; `ref_image_{i + 1}` = `moodboard[i]`. Un'unica funzione (`RefNumbering`) calcola il numero da una posizione, con un solo scarto (`startImageIndex = 0`): se FLUX.3 si rivela diverso (es. la prima immagine del Moodboard è `ref_image_0`) si cambia lì.
- Le proporzioni di ogni canvas sono quelle del file (letto con ImageIO).
- Un riquadro **ricorda l'immagine con il suo percorso** (nome del file della copia nel progetto), non con il numero: se l'utente riordina o spegne un'immagine nel Moodboard, i numeri nel testo si ricalcolano e i riquadri la seguono. Se l'immagine non c'è più (tolta o spenta) i suoi riquadri restano nell'elenco, segnati «immagine non più nel Moodboard», **esclusi dal testo** e dall'Invia finché non si risolve (si elimina il riquadro o si riaccende l'immagine).
- Senza immagine di partenza il tab mostra «Serve un'immagine di partenza» e non c'è niente da fare.
- Se le proporzioni della Generazione (`size` del contesto) non sono quelle dell'immagine di partenza, avviso: *le coordinate di destinazione si riferiscono all'uscita* (la card Immagine mostra il consiglio «Adatta le dimensioni» del tab Control). Non blocca.

## 5. Interfaccia (tre card, come il mockup)

**Moodboard.** Un canvas con l'immagine di sfondo, `‹` `›` ai lati per passare da un'immagine all'altra (disattivati ai bordi; con una sola immagine non servono), sotto il nome del file, `ref_image_N` e «n di m». Ogni immagine mostra **solo i propri riquadri di origine**. Il badge numerico dell'immagine (lo stesso del tab Control) nell'angolo.
**Immagine di partenza.** Un canvas con l'immagine: mostra le destinazioni, i riquadri locali e il badge 1.
**Prompt.** Casella di testo (la prosa), le mini-card in griglia, i pulsanti **Scrivi con LLM**, **Annulla**, **Invia**, la riga di stato. Niente anteprima del JSON nell'interfaccia vera (nel mockup serve a spiegare); si vede il testo finale perché «Scrivi con LLM» lo scrive nei campi.

**Disegno** (come I4, ma sull'immagine): si trascina per creare un riquadro, si trascina il corpo per spostarlo, l'angolo in basso a destra per ridimensionarlo; lato minimo 20 (griglia 0–1000), tenuto dentro l'immagine. Riquadro disegnato sul Moodboard → **Da riferimento**: nasce subito la coppia sull'immagine di partenza (stessa proporzione dell'origine, lato massimo 30% della tela, al centro), liberamente spostabile e ridimensionabile. Riquadro disegnato sull'immagine di partenza → **Nuovo** (locale, senza controparte).

**Colori:** otto, a rotazione (come `F3Palette`), uno per elemento, uguale sulle due tele e nella mini-card; il riquadro di origine è **tratteggiato**, quello di destinazione **pieno**; selezionato = bordo bianco con maniglia.

**Mini-card:** id (campo libero, avviso se ripetuto), menu del tipo, `from: …`, le coordinate, la `desc`, elimina. Il menu cambia il tipo senza perdere il riquadro (**Da riferimento** non è scegliibile a mano, nasce dal disegno sul Moodboard; da «Da riferimento» non si passa a un altro tipo). Passaggi: Nuovo → Esistente = stesso riquadro come origine e destinazione; → Sposta = l'origine resta, la destinazione nasce accanto; → Togli = solo l'origine; Sposta → Nuovo/Esistente tiene la destinazione. Clic su una mini-card o su un riquadro li seleziona entrambi. Le mini-card seguono l'ordine di creazione (frecce su/giù come F3, l'ordine è quello del JSON). Per «Sposta» una freccia dal riquadro `da` a quello `a`.

## 6. Il testo inviato (`EditComposer`)

Funzione pura da documento a stringa; «Invia» lo manda nel Prompt (`contribute.fields.prompt`) e svuota il negativo (FLUX non lo usa):
1. la **prosa** dell'utente così com'è (nel testo si usa `<ref_image_N>` e `<id>`);
2. riga vuota, poi l'**array JSON** nell'ordine delle mini-card, scritto con `JSONEncoder` (indentato di due spazi). I campi come nella tabella di §2; `from` e `src_bbox`/`tgt_bbox` nulli sono scritti come `null` (non omessi).

**Invia è disattivato** (la riga di stato dice perché) se: non c'è l'immagine di partenza; non ci sono elementi; un elemento «Nuovo», «Da riferimento» o «Esistente» ha la `desc` vuota (per «Togli» e «Sposta» è facoltativa); un id è ripetuto; un riquadro punta a un'immagine non più nel Moodboard. **Avvisi non bloccanti:** id non citati nella prosa; `<ref_image_N>` nel testo senza immagine. I riquadri di «Da riferimento» e «Sposta» devono avere le due metà (le crea il plug-in, non si perdono).

## 7. Scrivi con LLM

Come F3: le parti da elaborare (prosa e `desc` di ogni elemento) vanno all'LLM **in Markdown**; il master prompt (`Data/prompt-master-flux3-editing/master-prompt.md`, con `custom/` dell'utente, come I4/F3) spiega il formato e dà un esempio. Ordine tassativo: **non modificare** i testi tra `<…>` (gli id e `<ref_image_N>`), tradurre in inglese e arricchire il resto; la prosa deve citare ogni `<id>` e ogni immagine usata (l'LLM può aggiungerli). Controlli nel codice (riuso di `F3AnswerParser`/`F3Language`): ogni `<…>` dell'originale presente e uguale, nessun id nuovo, l'inglese (un solo nuovo tentativo con promemoria, poi resta l'originale). Il risultato **sostituisce i testi nell'interfaccia**; **Annulla** rimette quelli di prima (solo l'ultima scrittura); richiesta e risposta in `llm/` nella cartella del progetto. Non si mandano le immagini all'LLM (solo i testi).

## 8. Stato e persistenza

Per progetto (messaggio `project` come F3): `state.json` con la prosa, gli elementi (`id`, `kind`, `refFile`, `src`, `tgt`, `desc`, `colorIndex`), l'ultima fotografia per Annulla, e l'indice dell'immagine mostrata sul Moodboard. Le immagini non si copiano: si ricordano per nome del file. Migrazione dallo stato globale come F3 (`adoptLegacy`).

## 9. Codice e test

Pacchetto `Plugins/Flux3Editing/` (stesso schema di F3: `Package.swift`, `Scripts/build.sh`, `Sources/Flux3Editing`, `Tests`, `README.md` in inglese con la riga in `Plugins/README.md`). **Copiato da F3** (ramo `feat/prompt-master-f3`, non unito): `BBox`, `F3Palette`, `F3Language`, `F3AnswerParser`, `F3Writer`, `F3Sender`, `F3WorkFolder`, `F3Store`, il codice del canvas (`CanvasGeometry`, parti di `F3CanvasCard`). **Nuovo:** `EditElement`/`EditKind`, `EditDocument`, `RefNumbering`, `ImageStage` (tela con sfondo, due tele), `EditComposer`, `EditState`, le tre card, le conversioni di tipo (§5). **Test** (test-first, Swift Testing): numerazione (con/senza partenza, riordino, immagini spente), `EditComposer` (i cinque casi, `null`, ordine, JSON con virgolette), regole di Invia e avvisi, conversioni di tipo, coppie (disegno sul Moodboard → destinazione), riquadri orfani, parser e controlli dell'LLM, persistenza e Annulla, manifest, rendering dei tab (PNG come F3).
Nessuna modifica all'app né al contratto.

## 10. Decisioni mie (da correggere se non vanno)

1. Menu a quattro tipi più «Da riferimento» automatico; «Mantieni» e «Modifica» sono lo stesso tipo (**Esistente**).
2. Riquadri che puntano a immagini sparite: restano, esclusi dal testo, Invia bloccato.
3. Niente anteprima del JSON nell'interfaccia vera.
4. Avvisi non bloccanti per id non citati nella prosa (l'LLM li aggiunge).
5. «Da riferimento» non si converte in altri tipi (si cancella e si ridisegna).
6. Destinazione di una coppia: stessa proporzione dell'origine, al massimo 30% della tela, al centro.
7. L'LLM non vede le immagini.

## 11. Rischi aperti

- **Numerazione (regola A)** e **scala** (0–1000 vs 0–1 nel repo di Klein): da verificare con FLUX.3 vero; un punto di codice ciascuna (`RefNumbering`, `BBoxScale`).
- **Tela di uscita ≠ immagine di partenza** (altre proporzioni, ritaglio del tab Control, «Si perde il 2%»): le coordinate di destinazione sono nel canvas di uscita; qui il canvas ha le proporzioni dell'immagine. Si segnala, non si corregge.
- **«Togli» solo con `tgt_bbox: null`:** documentato da BFL, non provato.
- **Riquadri sovrapposti sulla stessa immagine** ammessi (FLUX li ammette); con molte coppie la lettura dei colori peggiora (otto colori, poi ripetono).
- **Dimensione massima** del prompt e **limite di dieci immagini** di FLUX.3: avviso se il Moodboard ne ha più di nove accese (oltre non sono tutte numerabili).
- **Ramo di F3 non unito:** l'implementazione parte da `main` copiando i file da `feat/prompt-master-f3` (nessuna dipendenza di codice fra i due pacchetti). Se F3 si modifica dopo, le copie divergono (accettato, come I4/F3).
- FLUX.2 klein non legge i riquadri: la resa dei box si vede solo con FLUX.3.

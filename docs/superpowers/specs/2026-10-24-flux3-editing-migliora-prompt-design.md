# Flux3 Editing: «Migliora prompt» con il PUP ufficiale (design)

Data: 24 ottobre 2026. Plug-in: `Plugins/Flux3Editing` (ramo `feat/flux3-vision`, non unito). Stato: da approvare.

## 1. Perché

Il banco ninja (23–24 ott, `docs/superpowers/bench/flux3-ninja/`) ha mostrato che:

- il master prompt conta più del resto: il master E (descrizioni statiche, effetti a catena nella prosa, fuoco mai citato) ha dato un ninja integrato anche con lo sfondo sfocato, dove v4/v5/v6 no;
- il modello ufficiale di BFL per questo lavoro, `flux-3-image-klein-pup` (Qwen3.5-9B con visione, `system_prompts.json` con `t2i`, `i2i`, `t2i_bbox`, `i2i_bbox`), lavora proprio sul formato che il plug-in produce (prosa + tabella `{id, from, src_bbox, tgt_bbox, desc}`) e, usato direttamente (probe `pup-probe/`), ha dato un risultato ottimo sulla base sfocata;
- **attenzione all'attribuzione:** nelle prove con «Scrivi con LLM» ha risposto Qwen3-VL-8B-Instruct-4bit (assegnato a «tutte le altre»), non il pup (assegnato alla famiglia Flux3): una richiesta `llm` senza `model` considera solo «tutte le altre». I testi del pup vengono solo dal probe in Python.

## 2. Cosa cambia per l'utente

1. **Niente casella «Manda le immagini all'LLM»:** le immagini partono sempre (se il modello non ha visione: solo testo, con nota).
2. **Il pulsante «Scrivi con LLM» diventa «Migliora prompt»** (inglese «Improve prompt»).
3. **Due modalità, scelte dal plug-in:**
   - **PUP:** se il modello scelto è il pup ufficiale → richiesta unica nel suo formato nativo.
   - **Standard:** per qualsiasi altro LLM → flusso attuale a parti con il master E (diventa il master versione 7).
4. **Righe aggiunte dal pup** (per esempio `person_1`, l'elemento ancora che il modello inserisce): si tengono, in una riga di sola lettura sotto gli elementi, con «Togli» per ognuna. Vanno nel prompt finale.
5. Nota di stato: «Migliorato con <modello> (modalità PUP|standard)».

## 3. Scelta del modello

Il plug-in non sa quale LLM userebbe l'app, ma ha `context.languageModels` (`name`, `path`, `supportsImages`, `family`, `use`). Regola, la stessa dell'app (`LanguageModelRouter`) più il filtro «PUP»:

1. Candidati: i modelli con `family == context.family` (famiglia Flux3, id nelle `families` del plug-in); altrimenti quelli con `family == "*"`. Ordine per nome (`localizedStandardCompare`).
2. Un candidato è **PUP** se la sua cartella (`path`) contiene `system_prompts.json` con la chiave `i2i_bbox`. Il prompt ufficiale si legge da lì (non si incorpora).
3. Se il primo candidato è PUP e `supportsImages` → modalità PUP, richiesta con `model: <nome>`.
4. Altrimenti modalità standard, richiesta senza `model` (decide l'app, come oggi); la nota dice chi ha risposto se noto.
5. Se `languageModels` manca (app vecchia): modalità standard.

## 4. Modalità PUP (da `flux3/pup.py` e `bbox.py` di BFL, Apache-2.0)

**Richiesta** (una sola):

- `system`: `system_prompts.json["i2i_bbox"]` del modello.
- `images`: la base e le reference usate, **grezze** (senza riquadri disegnati), nell'ordine `ref_image_0…N`; preparazione di BFL: alpha su bianco, LANCZOS al budget (1 immagine 1 MP; 2 immagini 724²; 3–10 immagini 512²), lati multipli di 32, JPEG q92; massimo 10.
- `prompt`:
  ```
  Reference images follow in attachment order: ref_image_0, ref_image_1, ...
  User editing instruction: ORIGINAL PROMPT:
  <prosa>

  LOCKED BOUNDING-BOX ANNOTATIONS ([y_min, x_min, y_max, x_max] on a 0-1000 canvas, with (0, 0) at the top-left). This is an authoritative JSON list of dictionaries; preserve every supplied identity, provenance value, null, and coordinate exactly:
  <righe JSON>
  Decide the edit, imagine the target image, and output the annotation record.
  ```
  (le righe sono quelle che il compositore già produce per il prompt finale; testo esatto da `bbox.upsampling_input` e `I2I_SCAFFOLD[True]`).
- `options`: temperatura 0, `topP` 0,95, `topK` 20, `presencePenalty` 0, `maxTokens` 3584, `thinking` false, timeout 600 s.

**Risposta:** «paragrafo [righe]». Si divide al `[` più a destra da cui il resto è un elenco JSON valido (`split`).

**Riconciliazione** (port di `reconcile`): una riga del modello che rimpiazza un nostro riquadro con IoU ≥ 0,9 prende il nostro id (anche nelle citazioni `<id>` del paragrafo); le nostre righe restano identiche (id, from, riquadri) e adottano la `desc` del modello; le righe che il modello aggiunge si tengono se hanno id valido citato nel paragrafo, `desc` non vuota, riquadro valido (0–1000, non tutto ≤ 1) e `from` coerente (`ref_image_N` con `src_bbox`, oppure `target` senza).

**Controlli sul testo intero:** ogni id citato come `<id>` almeno una volta, parole tra virgolette uguali a quelle in ingresso, niente testo italiano (`looksItalian`), nessun segnaposto cambiato. Se qualcosa non va → si riprova una volta con un promemoria; al secondo fallimento si passa alla modalità standard con lo stesso modello; se fallisce anche quella, i testi dell'utente restano com'erano.

**Dove finisce il risultato:** il paragrafo diventa la prosa; le `desc` dei nostri elementi sostituiscono le loro descrizioni; le righe aggiunte vanno in `document.extraRows` (nuovo campo dello stato, facoltativo, `schema` resta 1) e nel prompt finale dopo i nostri elementi.

## 5. Modalità standard

È il flusso di oggi (richiesta a parti, controlli per blocco, ripiego a singola parte, immagini con i riquadri disegnati) con due differenze: il master di base è **E** (`master-e.md`, versione 7) e le immagini partono sempre se il modello le legge. La personalizzazione `custom/master-prompt.md` resta valida. `master-prompt.md` v6 e v5 escono dal plug-in (restano nel git).

## 6. Domande da verificare in implementazione

- Per un elemento nuovo il pup, in `valid_added`, vuole `from: "target"`; il compositore oggi scrive `null`. Verificare sulla scheda del modello che cosa riceve il DiT e allineare (le righe «locked» si mandano com'è il formato finale).
- I limiti reali di `DTHubLLMOptions` (`topK` 0–200, `maxTokens` fino a 32768: tutto nei limiti, nessun problema atteso).
- Tempo di una richiesta (circa 9–15 s su M5 Max con il pup 8 bit) e memoria con il server FLUX acceso.

## 7. Test

Reconcile (rinomina per IoU, riga aggiunta valida/non valida, riga mancante, citazioni), split del testo con parentesi nel testo, scelta della modalità (candidati per famiglia e «tutte le altre», cartella con e senza `system_prompts.json`, senza visione, senza `languageModels`), preparazione delle immagini (dimensioni per numero di immagini, JPEG), richiesta composta (sistema, scaffold, opzioni), controlli sul testo, ripiego PUP → standard, stato con `extraRows` (ricarica, «Togli», invio), checkbox assente, stringhe del pulsante, contenuto del master E (versione 7).

## 8. Fuori da questo lavoro

Id semantici (`ninja_1`) al posto di `el_N` (nel banco non hanno cambiato nulla); rilevamento automatico dello sfondo sfocato; pianificazione dei riquadri da parte del pup (`*_1stage`); modalità `t2i_bbox` per un uso senza immagine di partenza.

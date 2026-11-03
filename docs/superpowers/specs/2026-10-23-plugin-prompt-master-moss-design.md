# DT Hub — Plug-in Prompt Master MOSS (MOSS Image)

Data: 23 ottobre 2026 · Stato: bozza da approvare · Estende `2026-10-06-plugin-prompt-master-i4-design.md` e `2026-10-20-plugin-prompt-master-f3-design.md` (stesso contratto 1, stessi componenti, stesso modo di costruire un plug-in) · Mockup approvato: `docs/superpowers/mockups/2026-10-23-prompt-master-moss.html`.

## 1. Scopo

MOSS Image (OpenMOSS, Apache 2.0) legge, oltre al linguaggio naturale e alle sequenze di tag, **un prompt in JSON con un layout**: una descrizione d'insieme (`summary`) e un elenco piatto di elementi (`items`) con il loro riquadro. **Prompt Master MOSS** costruisce quel JSON: l'utente scrive la descrizione, sceglie voci dal database, disegna i riquadri sul canvas e compila gli elementi; l'LLM locale, facoltativo, riscrive i testi in inglese. Il prompt in linguaggio naturale puro non è di questo plug-in: lo copre il Family prompt `moss_image` dell'app (già in `main`, commit `f1bb27b`).

È una via di mezzo tra **I4** (database completo, palette, tipi di elemento cambiabili dal canvas) e **F3** (un solo «Scrivi con LLM» con «Annulla»). Cambia il **calcolo delle coordinate** (§5) e i **tipi di elemento** (cinque).

Decisioni dell'utente (23 ottobre 2026):
- **Interfaccia come I4**: a sinistra una card con tutto il Summary, a destra Canvas ed Elementi. Il mockup è approvato. Il tipo di un elemento si cambia **sia dal selettore nella scheda sia dall'etichetta del riquadro** (clic → menu).
- **Cinque etichette** (`object`, `character`, `text`, `panel`, `subject`). Provate dal vivo: il modello le accetta tutte (il compilatore ufficiale del repo rifiuta `panel` e `subject`, il modello no).
- **Database completo come I4** per la descrizione; le voci di medium e genere vanno in `meta`, le altre nella `caption`.
- **Colori**: al massimo 5 nel Summary e 5 per elemento, facoltativi.
- **Rapporto delle dimensioni**: se cambia (non solo la scala) i box restano nelle stesse frazioni della tela e un avviso lo dice.
- **Negativo**: sezione propria con i termini del database più testo libero (§9).
- Famiglia: Base e SFT hanno lo stesso id; il plug-in elenca `moss_image` e `mossImage`.

## 2. Il formato che MOSS legge (fatti verificati)

Fonti: `USERGUIDE.md`, `skills/moss-image-prompt-enhancer/references/layout.md` e `scripts/compile_prompt.py` del repo OpenMOSS, i 20 `parameters.json` ufficiali, e le prove dell'utente (A e B del 23 ottobre).

```json
{"summary":{"meta":["photograph"],"canvas":"single","palette":["#B22222"],"caption":"…"},
 "items":[{"label":"object","caption":"…","bbox":[-290,-362,10,288],"tags":["umbrella"],"palette":["#F5F5DC"]},
          {"label":"text","caption":"…","text":"Kyoto\nArashiyama","bbox":[220,-472,290,-212]}],
 "bbox_coord_space":"abs_centralized","bbox_format":"yxyx"}
```

- **`summary`**: `caption` (testo d'insieme, obbligatorio nel compilatore); `meta` (lista di tag di medium/genere, liberi); `canvas` (`single`, `multi_panel`, `collage`, di default `single`); `palette` (lista di `#RRGGBB`). Il compilatore copia `summary` invariato nel JSON finale.
- **`items[]`**: `label`, `caption`, `bbox`, e facoltativi `text` (obbligatorio per `text`, testo esatto con `\n`), `tags`, `palette`. Negli esempi ufficiali: `object` 30, `text` 21, `panel` 7 (copre quasi tutta la tela), `subject` 1 (senza `caption`), `character` 0.
- **Coordinate**: `bbox` = `[y_min, x_min, y_max, x_max]` in **pixel reali** con **origine al centro** (x a destra, y in basso). Le coordinate **non sono relative**: con un canvas più grande del previsto il modello disegna l'immagine nelle dimensioni su cui sono calcolati i box e riempie di bianco il resto; con uno più piccolo taglia l'eccesso (prova del 23 ottobre; nessun errore in nessuno dei due casi). Il compilatore converte da `[x0, y0, x1, y1]` dall'angolo: sinistra/alto per difetto, destra/basso per eccesso, poi toglie metà larghezza e metà altezza.
- **Uscita compilata**: una sola riga, `ensure_ascii=False`, separatori `,` e `:` senza spazi, `\n` escapato.
- **Impostazioni consigliate dal modello** (nota di Draw Things e guida): 50 passi, guidance 3, shift 5, sampler Euler; l'encoder legge 4096 token. Non sono compito del plug-in.
- **Il negativo** è testo libero. Gli esempi ufficiali usano `worst quality, bad anatomy` (5 volte), `worst quality, low quality, blurry, jpeg artifacts` e altre combinazioni; 7 esempi su 20 non ne hanno.

## 3. Famiglia e manifest

`id` `com.exiztenz.dthub.promptmastermoss`, nome «Prompt Master MOSS», versione 1.0, simbolo `wand.and.stars` (come gli altri Prompt Master), `families: ["moss_image", "mossImage"]` (due ortografie dello stesso id: `models-list` ufficiale scrive `mossImage`, le configurazioni `moss_image`; l'app non normalizza). Fuori dalla famiglia il plug-in si spegne. Solo generazione da testo.

## 4. Dati

| File | Dove | Note |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (lo stesso di Prompt Master) | **tutti i gruppi**: in più di F3 ci sono `render_quality` (i tag «best quality, highres» che MOSS legge), `typography_text` (le voci di lettering vanno nella `caption` come le altre: non creano elementi Testo) e `negative_terms` (alimenta §9) |
| `moss.json` | `…/Data/prompt-master/` | per ogni categoria la destinazione (`meta` o `caption`), Foto/Arte, i termini aggiuntivi del negativo (`worst quality`, `low quality`: il database condiviso non si modifica), opzioni dell'LLM, versione |
| `master-prompt.md` | `…/Data/prompt-master-moss/` | il master prompt (§8); `custom/master-prompt.md` per i ritocchi; si installa all'avvio (`DTHubPromptFolder`) |

**Destinazione `meta`**: medium (`medium_*`, `film_stock_process`), genere fotografico, movimenti e stili d'arte (tag brevi, in inglese, una voce per categoria). Tutto il resto (luce, mood, atmosfera, colore, inquadratura, artisti, qualità) va nella `caption`. L'elenco esatto si fissa al piano guardando `ideogram4.json`.

## 5. Il testo inviato (`MossComposer`) e le coordinate

Funzione pura da documento e dimensione a stringa; «Invia» la scrive nel Prompt.

- Chiavi nell'ordine: `summary` (`meta`, `canvas`, `palette`, `caption`), `items`, `bbox_coord_space` (`abs_centralized`), `bbox_format` (`yxyx`). Un item: `label`, `caption`, `text` (solo per `text`), `bbox`, `tags`, `palette`; i facoltativi vuoti si omettono.
- **Caption del Summary** senza LLM: il testo libero, poi le voci della `caption` come frase di termini inglesi; dopo una scrittura le voci sono già dentro al testo (§7). **`meta`**: le voci `meta` del database (`en`) e i tag liberi.
- **Coordinate**: ogni box è salvato in **frazioni della tela** `[x0, y0, x1, y1]` in 0–1 (origine in alto a sinistra) e convertito **solo a «Invia»** con la **larghezza e l'altezza attuali della Generazione**: `l = floor(x0·W)`, `t = floor(y0·H)`, `r = ceil(x1·W)`, `b = ceil(y1·H)`, bbox = `[t − H/2, l − W/2, b − H/2, r − W/2]`. Il box deve stare dentro la tela (si limita a 0–1); lato minimo il 2 % del lato corto.
- **Se la dimensione cambia** dopo aver disegnato: stesso rapporto → le coordinate si ricalcolano in silenzio; rapporto diverso → i box restano nelle stesse frazioni (si deformano) e sopra il canvas compare un avviso. Larghezza e altezza devono essere multipli di 16 (lo sono i multipli di 64 di Draw Things).
- **«Invia» è disattivato** (con la ragione nella riga di stato) se: la caption del Summary è vuota; non c'è nessun elemento; un elemento ha la `caption` vuota; un elemento `text` ha il testo vuoto.
- **Negativo**: «Invia» scrive nel campo negativo i termini scelti (§9) uniti da `, ` e poi il testo libero.

## 6. Interfaccia (il mockup approvato)

**Sinistra, «Summary»**: descrizione generale (diventa la `caption`); Foto / Arte e Shuffle (come I4, al massimo 3 voci per sezione); i gruppi del database con contatori; **Meta** (chip delle voci `meta` e campo per tag liberi); **Canvas** `single | multi_panel | collage`; **Palette** (fino a 5); **Negativo** (§9).

**Destra**: **Canvas** (menu della dimensione solo nel mockup: nel plug-in la dimensione è quella della Generazione; punto di origine al centro; si crea un box trascinando sul vuoto, si sposta, si ridimensiona dall'angolo; il colore dipende dal tipo; **clic sull'etichetta → menu dei cinque tipi**) ed **Elementi** (una scheda per box: selettore del tipo, `caption`, `text` solo per il tipo Testo, tags, posizione `[y0, x0, y1, x1]` dal centro, colori fino a 5; su/giù/elimina). In fondo: **Annulla**, **Scrivi con LLM**, **Invia**, riga di stato. (Il 23 ottobre l'utente ha tolto «Rivedi JSON» dopo la prova: niente finestra con il JSON né testo modificato a mano.)

## 7. Scrivi con LLM

Una sola richiesta `llm`, senza `model`, con `system` = il master prompt (§8), `options` da `moss.json` (`thinking` spento, temperatura 0,6, `maxTokens` 4096), attesa fino a 600 s, nessuna immagine. Come F3, in Markdown, con titoli:

```
## summary
due amici in una foresta di bambù (testo dell'utente)
Light Source: Dappled sunlight
## element 1 (panel)
sfondo di bambù
## element 2 (text)
scritta in basso a sinistra, bianca
```

- Parti: `summary` (descrizione + voci `Categoria: voce` destinate alla caption), una per elemento (con il tipo tra parentesi), e i tag liberi (`meta` e degli elementi) da tradurre in inglese come liste brevi.
- **Non passano mai dall'LLM**: il `text` degli elementi Testo, le parole tra virgolette, le posizioni, i colori. Le voci `meta` del database sono già in inglese.
- La risposta ha **gli stessi titoli nello stesso ordine**; il parser (`MossAnswerParser`) toglie `<think>` e recinzioni. Ripiego come I4: una chiamata per ogni parte mancante, poi la parte resta com'era e lo stato lo dice.
- **Controllo nel codice**: stesso numero e ordine di titoli; le parole tra virgolette di una `caption` restano identiche; nessun testo ancora in italiano (`F3Language.looksItalian` riusabile, una nuova richiesta con promemoria, poi resta l'originale).
- **Dopo la scrittura** i testi sostituiscono quelli dei campi e le voci del database usate si deselezionano; **Annulla** rimette la fotografia dei campi (solo l'ultima). Posizioni, tipi e colori non si toccano.

## 8. Il master prompt (bozza, da provare con l'LLM vero)

```
You prepare the text of a structured image prompt for the image model MOSS Image. The request has blocks under titles: "summary" (the whole picture) and one "element N (type)" block per element, where type is object, character, text, panel or subject; a "text" element is lettering printed in the picture; a "panel" is a backdrop or frame covering a large area; a "subject" is the main subject.

Answer with the SAME titles in the SAME order, each followed by its rewritten text. Nothing else: no JSON, no notes.

Rules:
1. Write in English, whatever the input language. Plain descriptive prose, no commands, no keyword lists.
2. Words between quotation marks are printed in the picture: copy them exactly, never translate.
3. "summary": two or three sentences about the whole scene, style, light and mood. Work the lines shaped "Category: term" into the sentences. Do not describe the individual elements.
4. "element N": only what appears inside that region: appearance, material, colour, pose. For a "text" element describe the typography and the surface it is on, never the words themselves. No positions, no coordinates, no mention of other elements.
5. Do not invent new elements.
```

## 9. Il negativo

Sezione «Negativo» nella card Summary: i **25 termini del gruppo «Negative Prompt Terms»** del database (blurry, lowres, jpeg artifacts, watermark, bad anatomy, deformed…) più **`worst quality` e `low quality`** (aggiunti da `moss.json`), come voci scelte; e un **campo di testo libero**. **Parte precompilato con `worst quality, bad anatomy`** (le voci più usate negli esempi ufficiali). «Invia» scrive nel campo negativo `voci scelte, testo libero`. Il negativo non passa dall'LLM (parole inglesi fisse).

## 10. Stato e persistenza

`state.json` per progetto (messaggio `project`, `schema` 1): descrizione, voci scelte, Foto/Arte, tag `meta` liberi, `canvas`, palette, negativo (voci e testo), elementi (tipo, `caption`, `text`, tags, colori, box in frazioni, aperto/chiuso), categorie aperte, fotografia di Annulla. **Non** si salva la dimensione. Cartella `llm/` (`request.md`, `answer.md`, `before.md`) come F3.

## 11. Codice, test e verifiche

Pacchetto `Plugins/PromptMasterMOSS/` (modello: I4; `Scripts/build.sh`, dati in stringhe Swift da `Scripts/make-*.py`). Da I4 si copiano e adattano `DataSource`, `I4Store`, `I4Sender`, lo Shuffler, la card del canvas e le schede (il selettore diventa a cinque tipi); da F3 `F3Snapshot`/Annulla e il controllo della lingua. **Nuovi**: `MossDocument`, `MossGeometry` (frazioni ↔ pixel dal centro), `MossComposer`, `MossBrief`, `MossAnswerParser`, `MossWriter`, `MossNegative`, le card.

Test (RED poi GREEN): **golden contro il compilatore ufficiale** (`compile_prompt.py`, byte per byte, per le tre etichette valide, con i casi: più tag, `\n` nel testo, non ASCII, palette, box ai bordi e frazionari); conversione frazioni → centro (cambio di scala, cambio di rapporto, dimensioni diverse, arrotondamenti); le cinque etichette; `Invia` disattivato nei quattro casi; messaggio MD e parser (titoli, ripiego, `<think>`); controllo delle virgolette e della lingua; Annulla; negativo (voci + testo libero, precompilato); stato su file; manifest e localizzazione. Verifica dal vivo (dietro variabile d'ambiente): il master prompt con l'LLM vero su tre scene e **MOSS in Draw Things** (`moss_image_base`, 50 passi, guidance 3, shift 5) con A e B del 23 ottobre come campioni.

## 12. Decisioni prese da me (da correggere se non vanno)

- **Caption obbligatoria per ogni elemento** (come il compilatore ufficiale, anche se un esempio ufficiale ha un `subject` senza `caption`).
- **JSON compilato in una riga** (uscita del compilatore) e con le chiavi nell'ordine del §5.
- **Box minimo il 2 % del lato corto** e limitati alla tela (il compilatore rifiuta quelli fuori).
- **Tag liberi tradotti dall'LLM** insieme al resto.
- **Una famiglia, due ortografie** dell'id.
- **Niente «Rivedi JSON»** (tolto dall'utente dopo la prova del 23 ottobre).

## 13. Rischi aperti

- **`panel` e `subject`**: accettati dal modello nelle prove, ma l'effetto è provato solo da una coppia di immagini (gru sul kimono comparse con la `caption` del `subject`).
- **Disallineamento silenzioso**: il modello non dà mai errore se le coordinate non corrispondono alla tela; l'unica difesa è ricalcolare dalla dimensione attuale. HiRes fix e Tiled Upscale cambiano la risoluzione effettiva: da provare cosa succede ai box.
- **Lunghezza**: l'encoder legge 4096 token; il JSON con molti elementi può avvicinarsi al limite (cinque elementi sono circa 1200 caratteri).
- **LLM piccolo**: può tradurre le virgolette o cambiare i titoli; il controllo del §7 costa un nuovo tentativo.
- **Id della famiglia**: se Draw Things usasse una terza ortografia, basta aggiungerla a `families`.
- **Voci del database**: la ripartizione `meta`/`caption` e le categorie di Foto/Arte vanno riviste guardando `ideogram4.json`.

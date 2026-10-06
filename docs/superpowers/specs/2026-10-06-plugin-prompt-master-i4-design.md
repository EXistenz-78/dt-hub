# DT Hub — Plug-in Prompt Master I4 (Ideogram 4)

Data: 6 ottobre 2026 · Stato: approvata; tappa 1 (il JSON) realizzata il 6 ottobre, tappe 2 (canvas) e 3 (LLM) da fare · Estende `2026-10-05-plugin-prompt-master-design.md` (stessi dati, stesso contratto 1, stesso modo di costruire un plug-in) e `2026-10-05-plugin-design-system-design.md` (l'aspetto) · Mockup interattivo di riferimento: `docs/superpowers/mockups/2026-10-06-prompt-master-i4.html` (la stessa pagina, con dati veri e invii simulati).

## 1. Scopo

Ideogram 4 è addestrato su didascalie JSON con uno schema fisso. Il vecchio Prompt Master 2.0 le costruiva a mano, con una pagina HTML e la traduzione DeepL (`Prompt generator/Prompt Master 2.0/docs/Prompt-Master-2.0-Ideogram4-Spec.md`, d'ora in poi «la spec vecchia»). **Prompt Master I4** la rifà dentro DT Hub come plug-in a parte per la famiglia `ideogram_4`: l'utente sceglie voci dal database, scrive testi, disegna i riquadri degli elementi sul canvas; il JSON si compone da solo e va nel campo Prompt della Generazione. L'LLM locale dell'app, facoltativo, riscrive i testi in frasi inglesi pulite, un campo alla volta dentro una sola risposta.

Decisioni dell'utente (6 ottobre 2026):
- **Plug-in separato** da Prompt Master, nome **Prompt Master I4**. Condivide il database dei termini, non il codice.
- **Una voce per categoria** (un solo Mood, una sola armonia cromatica…). Il Medium è una sola voce in tutto il campo. Nessun `en_prose` nel database: la prosa la scrive l'LLM.
- **Foto / Arte** decide quali categorie compaiono in elenco; cambiando, le scelte che spariscono si cancellano.
- **Shuffle**: al massimo 3 voci per campo, da 3 categorie a caso, una per categoria (troppe informazioni peggiorano il prompt).
- **Le voci finiscono nel JSON così come sono** finché non si usa l'LLM.
- **L'LLM**: una sola chiamata, selettiva sui campi che ne hanno bisogno; solo se non funziona si ripiega su chiamate separate. Il master prompt (§8) è la parte che più conta.
- **Background**: testo libero più le 12 voci di «Fondale e sfondo».
- **Rivedi JSON**: una finestra con il testo copiabile e modificabile a mano; è l'unica finestra sul lavoro dell'LLM.
- **Invia**: il JSON va nel campo Prompt; nessun negative prompt, si manda vuoto per cancellare i residui.
- **Canvas** come nel vecchio PM, con le proporzioni della Generazione.
- **Niente DeepL, niente importazione** del JSON nei campi: il testo modificato a mano è semplicemente ciò che parte con «Invia».

Fuori: tradurre con altro che non sia l'LLM; reimportare un JSON nei campi; termini personali (per ora); `aspect_ratio` nel JSON (non c'è); l'invio via HTTP della spec vecchia §17 (si usa il contratto dei plug-in); l'immagine di partenza e il Moodboard; il PE di Qwen.

## 2. Tre tappe

| Tappa | Cosa | Perché in quest'ordine |
|---|---|---|
| **1 — Il JSON** | Pacchetto, dati, card sinistra (descrizione, Foto/Arte, Shuffle, quattro sezioni, palette, background), card degli elementi (senza canvas: tipo, testi, palette; la posizione si scrive come numeri `[y0, x0, y1, x1]`), «Rivedi JSON», «Invia». | Il valore sta nel writer ordinato del JSON e nelle liste. Già utilizzabile da solo, senza LLM. |
| **2 — Il canvas** | Disegno, spostamento, ridimensionamento dei riquadri con le proporzioni della Generazione; «Disegna» per un elemento già creato. | È l'unica parte con gesti e geometria: si prova da sola. |
| **3 — L'LLM** | «Scrivi con LLM»: richiesta a tag, stati dei campi, parser, ripiego, master prompt, prova dal vivo. | Dipende dai campi della tappa 1 e dagli elementi della 2. |

Ogni tappa ha il suo piano e il suo merge; questa spec le copre tutte.

## 3. Dati

Il database è lo **stesso file** di Prompt Master: `~/Library/Application Support/DT Hub/Data/prompt-database.json` (id, `it`, `en`, gruppi con `restricted`, categorie con `en` e `descIt`), con la sua copia incorporata. Valgono le stesse regole di scelta (file della cartella, altrimenti incorporata; schema sconosciuto, id ripetuti o file illeggibile → incorporata e un avviso; versione più vecchia → incorporata, senza avviso; il plug-in non lo scrive mai). Un secondo file è solo di I4:

| File | Contenuto |
|---|---|
| `prompt-master/ideogram4.json` | `schema` (1), `version`, `system` (il master prompt, §8), `fields` (quali categorie alimentano ogni campo, sotto), `options` dell'LLM (§7). Sostituibile senza ricompilare, come `master-prompts.json`. |

```json
{ "schema": 1, "version": "1.0.0",
  "fields": {
    "aesthetics": { "common": ["ij_mood_merged","mood_aesthetic_register","atmosphere","color_harmony","genre_aesthetic","atmospheric_fx"], "photoOnly": ["optical_fx"] },
    "lighting":   { "common": ["light_source","light_quality","light_scheme"] },
    "style":      { "photo": ["framing","camera_angle","composition","lens_focus","photo_genre"],
                    "art":   ["art_movement","design_movement","anime_cartoon_style","cultural_tradition","artist_classical","artist_modern","artist_illustration"] },
    "medium":     { "photo": ["medium_digital_3d","film_stock_process"], "art": ["medium_digital_3d","medium_paint_draw","medium_print_craft"] },
    "background": { "common": ["background_setup"] },
    "lettering":  { "common": ["typography_text"] } },
  "mergedMood": { "id": "ij_mood_merged", "en": "Mood", "it": "Mood", "from": ["mood_emotional_tone","mood"] },
  "system": "…" }
```

**Il Mood fuso.** All'avvio `mood_emotional_tone` e `mood` si fondono in una categoria virtuale `ij_mood_merged` ("Mood"): prima le voci di `mood_emotional_tone`, poi quelle di `mood`, togliendo le doppie per `en` (minuscolo, senza spazi ai lati; vince la prima): 31 voci. Gli id dei termini restano quelli del database.

**Come si carica `ideogram4.json`.** Come gli altri: file della cartella oppure copia incorporata, stesse regole. Una categoria nominata in `fields` ma assente dal database si ignora con un avviso. Uno script `Scripts/make-i4-data.py` genera il file Swift con le copie incorporate (come `make-prompt-data.py`); non modifica nulla del database originale.

**Il codice si copia, non si condivide.** Dei file di Prompt Master servono, copiati nel nuovo pacchetto: `Models.swift`, `DataSource.swift` (con il percorso della cartella dati), la pulizia di `<think>` e recinzioni di `AnswerParser`, la struttura di `Strings.swift`. Un pacchetto condiviso tra plug-in aggiunge un modulo da tenere allineato per due soli utenti; si estrae se un terzo plug-in lo chiede (backlog).

## 4. Il JSON

Tre chiavi in quest'ordine fisso, come nella spec vecchia §4 (l'ordine incide sulla qualità; `JSONEncoder` non lo garantisce, serve un writer proprio):

```
high_level_description
style_description:   aesthetics, lighting, photo (solo in Foto, PRIMA di medium), medium, art_style (solo in Arte, DOPO medium), color_palette
compositional_deconstruction: background, elements[ type, bbox?, text? (solo type=text), desc, color_palette? (solo se non vuota) ]
```

`bbox` = `[y0, x0, y1, x1]`, quattro interi in 0…1000 con y per primo; lato minimo 20; omesso per gli elementi «senza posizione». `color_palette`: `#RRGGBB` maiuscolo, al massimo 16 nello stile e 5 per elemento. Nessun `aspect_ratio`: le proporzioni sono solo la forma del canvas. L'ordine dell'array è l'ordine z (l'ultimo sta sopra). `text` esce verbatim, mai passato all'LLM per essere riscritto.

**Il writer** (`OrderedJSON`): albero di chiavi ordinate; rientro di 2 spazi; array e oggetti vuoti `[]` e `{}`; una voce per riga; `": "`; niente escape di `/` né dei caratteri non ASCII; escape di `" \ \n \r \t \b \f` e degli altri sotto 0x20 come `\u00XX`. Test golden contro gli esempi della spec vecchia §4.3 e §4.4 (byte per byte) e almeno otto altri casi (Foto/Arte, con e senza bbox, testo e oggetto, palette vuote e piene, non ASCII, `/` e virgolette nel testo).

**Il valore di un campo.** Ogni campo (§5) ha un testo *grezzo* e, dopo l'LLM, una frase *scritta* (§7). Nel JSON va la frase scritta **se l'ingresso da cui è nata è ancora quello attuale**, altrimenti il grezzo.
- Grezzo di un campo di voci: le `en` delle voci scelte, nell'ordine delle categorie, unite da «, ».
- Grezzo di `high_level_description`: il testo dell'utente, com'è (in qualsiasi lingua).
- Grezzo di `background`: il testo dell'utente, poi la voce scelta di «Fondale e sfondo», unite da «, ».
- Grezzo di un elemento: la sua descrizione, poi la voce Text & Lettering se c'è.

Il testo modificato a mano nella finestra **vince su tutto** (§6), finché non lo si ripristina.

## 5. Interfaccia

Due colonne, come i tab di DT Hub, con i componenti di `DTHubDesign` (`DSCollapsibleCard`, `dsPanel`, `DSPanelHeader`, `DSPillButtonStyle`, `DSCheckboxToggleStyle`); stringhe in una tabella `L` (it/en). Il mockup è la guida visiva; quando diverge da questo testo vale il testo.

**Sinistra, una card lunga.**
1. **High level description**: campo multilinea.
2. **Foto / Arte** (due pulsanti) e **Shuffle**. Cambiando Foto/Arte spariscono le categorie dell'altra modalità e **le loro scelte si cancellano** (anche le frasi scritte che ne derivavano diventano da riscrivere).
3. **Quattro sezioni comprimibili**: *Aesthetics*, *Lighting*, *Photo* o *Art style* (secondo la modalità), *Medium*. Dentro, le categorie (comprimibili), dentro le voci con una casella. **Una sola voce per categoria**: sceglierne una toglie la precedente della stessa categoria. In *Medium* la scelta è una sola in tutta la sezione. Ogni riga di categoria mostra la voce scelta. Le categorie per modalità sono quelle di `fields` (§3): *Aesthetics* 7 in Foto (6 + Optical & Visual Effects) e 6 in Arte; *Lighting* 3; *Photo* 5; *Art style* 7; *Medium* 2 in Foto e 3 in Arte.
4. **Palette colori**: fino a 16 campioni; **+** ne aggiunge uno a caso (`#RRGGBB`), il campione si cambia con il selettore di sistema, **×** lo toglie.
5. **Background**: campo di testo e, sotto, la categoria «Fondale e sfondo» (12 voci, una sola).

**Destra, in alto — Canvas** (tappa 2). Un rettangolo con **le proporzioni di larghezza × altezza della Generazione** (da `context.parameters`; se mancano, quadrato) che segue la Generazione quando l'utente le cambia. Sulla griglia 0–1000:
- trascinare sul vuoto crea un elemento `obj` con quel riquadro (se è almeno 20 × 20; altrimenti si scarta);
- trascinare un riquadro lo sposta (resta dentro il canvas); le quattro maniglie del selezionato lo ridimensionano (lato minimo 20; il lato opposto resta fermo);
- «Disegna» sulla card di un elemento senza posizione lo arma: il prossimo riquadro valido va a quell'elemento invece di crearne uno nuovo;
- bordo tratteggiato per gli oggetti, pieno per i testi; etichetta `E{n} · tipo` con `n` la posizione nell'elenco; il selezionato in primo piano.
Cambiare proporzioni non tocca i riquadri (sono frazioni).

**Destra, in basso — Elementi.** Una card per elemento, **chiusa** all'inizio: etichetta `E{n}`, estratto, ↑ ↓ (riordinano: cambiano z, etichette, ordine nel JSON), **×**. Aperta: descrizione (il tipo, *Oggetto* o *Testo*, non si cambia sulla card: si sceglie con i pulsanti per aggiungere, e con il tag sopra il riquadro nel canvas, tappa 2); per il testo il menu **Text & Lettering** (una voce, 14) e il campo «testo (reso verbatim)»; la riga `[y0, x0, y1, x1]` o «nessuna posizione» con «Disegna»; la palette (fino a 5). Cambiare tipo non cancella nulla. Sotto: **Aggiungi oggetto** e **Aggiungi testo** (creano un elemento senza posizione), **Scrivi con LLM** (§7), **Rivedi JSON**, **Invia**, la riga di stato.

**Cosa riceve l'LLM.** Una tabella (nel mockup, sotto il canvas) con i campi e il loro stato: *grezzo*, *riscritto*, *da riscrivere* (cambiato dopo l'ultima riscrittura), *vuoto*. Si apre per vedere cosa uscirà.

**Rivedi JSON.** Una finestra con il JSON attuale in un campo modificabile, **Copia**, **Ripristina dai campi**, **Chiudi**. Modificare il testo crea un *JSON modificato a mano*: da allora è quel testo che «Invia» manda, finché non si preme «Ripristina dai campi» o non si lancia «Scrivi con LLM» (che rigenera tutto e lo dice). Cambiare un campo con un testo a mano attivo **non lo tocca**; accanto a «Invia» compare «JSON modificato a mano · Ripristina». La finestra non controlla che il testo sia JSON valido: è una finestra, non un importatore. Il testo a mano si ricorda tra una sessione e l'altra.

**Invia.** `contribute {fields: {prompt: <JSON o testo a mano>, negativePrompt: ""}}`; la riga di stato dice «Inviato» o i conflitti, come Sphere Light. Il negativo vuoto serve a cancellare i residui di una generazione precedente.

**Persistenza** (UserDefaults, `com.exiztenz.dthub.promptmasteri4.state.v1`, con `schema`): descrizione, modalità, id delle voci scelte per campo, colori, testo e voce del background, elementi (con le loro voci Text & Lettering, riquadri, palette), le frasi scritte con l'ingresso che le ha generate, il testo a mano, le sezioni aperte.

## 6. Shuffle

Per ognuna delle quattro sezioni (Aesthetics, Lighting, Photo/Art style, Medium) e per il Background:
1. si cancella la scelta della sezione;
2. si prendono **al massimo 3 categorie a caso** tra quelle visibili della sezione (se ne ha meno, tutte);
3. da ognuna una voce a caso;
4. *Medium*: **una sola** voce, a caso dall'unione delle categorie visibili;
5. *Background*: una voce di «Fondale e sfondo».

Non tocca descrizione, elementi, palette, modalità Foto/Arte, il testo a mano. Il generatore casuale è passato dall'esterno (testabile con un seme).

## 7. Scrivi con LLM

**Quando si abilita.** C'è almeno un campo con contenuto grezzo il cui stato non sia *riscritto*. Con un *JSON modificato a mano* attivo il pulsante avvisa nella riga di stato che il testo a mano sarà scartato; per sicurezza non lo scarta se la richiesta fallisce.

**Cosa viene riscritto.** Ogni campo ha un **ingresso** (un testo canonico: il suo testo libero e le sue voci come righe `Categoria: voce`, §7.1). Un campo è *da riscrivere* se ha ingresso non vuoto e non ha una frase scritta, oppure l'ingresso è diverso da quello con cui la frase fu scritta. I campi già riscritti e invariati **non si rigenerano** e non vengono rimandati (se non come contesto sola lettura). Un campo che torna vuoto perde la sua frase.

**Una sola richiesta, a tag (§7.1).** Una chiamata `llm` con `system` = il master prompt (§8), senza `model` (vale il modello linguistico scelto nell'app), `options`: `thinking` spento, temperatura 0,6, `maxTokens` 4096 (come `options` in `ideogram4.json`), attesa fino a 600 s. Nessuna immagine.

**Ripiego.** Se la risposta non contiene la frase di uno o più campi richiesti (tag mancante o vuoto, risposta senza tag, errore), per **ognuno dei campi mancanti** si fa una chiamata a parte con lo stesso system prompt e una richiesta con quel solo campo; con un solo campo richiesto, se non ci sono tag, vale il testo intero della risposta (ripulito). Le chiamate sono in sequenza e la riga di stato dice «campo 3 di 5». Un campo che fallisce anche da solo resta *grezzo*, e la riga di stato lo nomina. Non c'è annullamento (il contratto non lo prevede).

**Mentre lavora** il pulsante dice «Sto scrivendo…» ed è disattivato; i campi restano modificabili, ma una frase arrivata per un ingresso nel frattempo cambiato si salva con *l'ingresso con cui è partita*, quindi risulta subito *da riscrivere*.

### 7.1 Il messaggio

```
<high_level_description>
due amici in una tavola calda al neon, di notte
</high_level_description>
<aesthetics>
Mood: melancholic
Color Harmony: Split-complementary scheme
</aesthetics>
<lighting>
Light Source: Neon lighting
</lighting>
<photo>
Framing: Medium shot
Lens, Focal Length & Focus: Wide aperture f/1.4
</photo>
<medium>
Film Stock & Process: Expired film
</medium>
<background>
la strada bagnata dalla finestra
Background Setup: blurred background
</background>
<element_1 kind="object">
un cliente solo al bancone con una tazza
</element_1>
<element_2 kind="text">
Lettering style notes: insegna sopra la finestra
Text & Lettering: lettering formed from glowing neon tube
Printed text (never repeat it): OPEN ALL NIGHT
</element_2>
<already_written>
lighting: lit by the cold glow of neon signs
</already_written>
```

- Nomi dei tag: `high_level_description`, `aesthetics`, `lighting`, `photo` o `art_style`, `medium`, `background`, `element_1` … `element_N`. Il numero è la posizione nell'elenco (1-based). L'attributo `kind` è `object` o `text`.
- Le righe di voci sono `Categoria: voce` con **la categoria in inglese e la voce in `en`** (il motivo è quello di Prompt Master: «butterfly lighting» senza la categoria diventa farfalle). Più voci della stessa categoria non ci sono (una per categoria).
- Il testo libero resta nella lingua dell'utente. Il testo verbatim di un elemento `text` si manda **solo come contesto** («Printed text (never repeat it)»); una descrizione vuota e nessuna voce non fanno richiedere l'elemento.
- Posizioni e dimensioni dei riquadri e i colori delle palette **non** si mandano.
- `<already_written>` elenca, in sola lettura, le frasi già buone dei campi non richiesti (nome del campo e testo), perché le nuove restino coerenti con esse. Manca se non ce ne sono.

### 7.2 Il parser (`I4AnswerParser`)

Toglie i blocchi `<think>…</think>` e le recinzioni ```; poi cerca i tag **richiesti**, senza distinguere maiuscole, accettando `-` e spazio al posto di `_` (`<High level description>` vale `<high_level_description>`), con il contenuto fino al tag di chiusura; il contenuto si ripulisce da spazi, da virgolette che avvolgono tutto e da a capo interni (diventano spazi). Tag non richiesti e testo fuori dai tag si ignorano. Un tag richiesto presente due volte: vale l'ultimo non vuoto. L'esito è `[campo: testo]` più l'elenco dei campi mancanti.

## 8. Il master prompt

È il file `system` di `ideogram4.json` (sostituibile). Prima versione, da rivedere alla prova:

```
You write short pieces of English text for the fields of a structured image caption. The caption is read by Ideogram 4, an image model trained on captions with a fixed layout. You never write the caption itself: the app puts each piece of text where it belongs, so every piece must make sense on its own.

WHAT YOU RECEIVE
The request holds one block for each field to write. The block is wrapped in a tag named after the field: <high_level_description>, <aesthetics>, <lighting>, <photo> or <art_style>, <medium>, <background>, and <element_1> up to <element_N>. A block contains the user's own words, in any language, and/or lines shaped like "Category: term". Those lines are terms the user picked from a vocabulary; the category tells you what kind of thing the term is. For example "Lighting Scheme: butterfly lighting" is a way to light a face, not butterflies, and "Art Movement: Pop Art" is a style, not a picture of a pop singer.
An <already_written> block may follow. It lists fields that are final. Read it so your new text agrees with it. Never rewrite it and never answer for it.
An element block has a kind. kind="object" is something that appears in the picture. kind="text" is lettering that appears in the picture; its block may carry a line "Printed text (never repeat it)": that is what the lettering says, given to you only so you know what you are describing.

WHAT YOU WRITE
Reply with one tag for each block in the request, with the same names, in the same order. Inside each tag, one piece of English text. Nothing else: no JSON, no markdown, no notes, no extra tags, no tag inside another tag.

RULES FOR EVERY PIECE
1. English only, whatever language the input is in.
2. One complete sentence that stands alone (high_level_description may use two). Write it as a plain description of the picture, not as a command and not as a list of keywords.
3. Be faithful. Every term in the block must show up in the sentence with the meaning its category gives it. The user's own words say what they want; the terms refine it. Never drop a term, soften it, or say the opposite of it.
4. Stay short. Add at most a few words of connecting detail so the sentence reads naturally. Do not invent new objects, people, places, colors or events. Too much information makes the picture worse.
5. Stay in your field. Each piece covers only the topic of its own tag (see below). Do not mention anything that belongs to another field, do not repeat what <already_written> says, and never write hex codes, pixel sizes, coordinates, or position words such as "top left" or "in the corner": position is handled elsewhere.
6. No labels, no quotation marks around the whole piece, no opening such as "This image shows".
7. The high_level_description is the overview of the picture. The background and the elements are parts of that same picture, seen in detail. Let them add detail inside the overview: never contradict it, never repeat its sentences, and never pull into one element something that belongs to another. If the user's own words disagree with each other, keep each as written and do not settle the matter.

WHAT EACH FIELD COVERS
- high_level_description (up to 60 words): the whole picture in plain words: who or what is there, what they do, where. No style, no light, no camera.
- aesthetics (up to 35 words): the overall feeling of the picture: mood, atmosphere, color harmony, genre, visual effects.
- lighting (up to 35 words): where the light comes from, how it looks, its direction and the shadows it casts.
- photo (up to 35 words): how the picture was photographed: framing, camera angle, lens, depth of field, composition, photographic genre.
- art_style (up to 35 words): the art style: movement, tradition, designers or artists the look recalls ("in the style of …"), how it looks.
- medium (up to 25 words): what the picture is made of or with: the material, technique or process.
- background (up to 40 words): what lies behind everything else: the setting or backdrop and its depth. No foreground subject.
- element, kind="object" (up to 50 words): that one thing alone: what it is, what it looks like, materials, pose, its own colors. Nothing about the rest of the scene, nothing about where it sits.
- element, kind="text" (up to 40 words): the lettering itself: letterforms, material, color, finish, and how it sits with what is around it. Never write, quote or translate the printed words; the app adds them on its own.

If a block holds only a few words, still write a full sentence from them, without adding anything the user did not hint at.

EXAMPLE
Request:
<aesthetics>
Mood: melancholic
Color Harmony: Split-complementary scheme
</aesthetics>
<element_1 kind="text">
Lettering style notes: sopra la porta
Text & Lettering: hand-painted vintage signage
Printed text (never repeat it): BAR
</element_1>
Reply:
<aesthetics>
A melancholic mood, with colors set against each other in a split-complementary scheme.
</aesthetics>
<element_1>
Hand-painted vintage signage with slightly worn letterforms, set above the door.
</element_1>
```

Il master prompt dichiara l'inglese come unica lingua d'uscita; i limiti di parole sono provvisori e si regolano alla prova. Le fonti sul formato di Ideogram 4 sono la spec vecchia e le didascalie d'esempio; una ricerca online sulle didascalie ben riuscite è un lavoro a parte, come per i master prompt di Prompt Master (§9 di quella spec).

## 9. Codice

Un pacchetto in `Plugins/PromptMasterI4/` con la struttura di Prompt Master: libreria dinamica `PromptMasterI4`; kit e design system con `moduleAliases` `PromptMasterI4Kit` e `PromptMasterI4Design`; `Scripts/build.sh` e `Scripts/make-i4-data.py`; identificatore `com.exiztenz.dthub.promptmasteri4`; nome «Prompt Master I4»; versione 1.0; `families: ["ideogram_4"]` (sulle altre il tab è grigio, e Prompt Master è grigio su `ideogram_4`: a ogni famiglia il suo plug-in).

Tipi puri e testabili, senza SwiftUI:
- `I4Database` (carica il database condiviso e `ideogram4.json`, fonde il Mood, risolve le categorie di ogni campo per modalità), `DataSource` (file o incorporato, avvisi);
- `I4Document` (descrizione, modalità, scelte per campo, colori, background, elementi) e `I4Element`; `BBox` e `CanvasGeometry` (frazioni ↔ punti, clamp, lato minimo 20, normalizzazione min/max, spostamento, ridimensionamento dai quattro angoli);
- `OrderedJSON` e `I4Payload` (il JSON, con il valore di ogni campo secondo §4);
- `I4Shuffler` (§6);
- `I4Fields` (i campi come ingresso/grezzo/frase/stato; l'ingresso canonico del §7.1);
- `I4Brief` (il messaggio del §7.1), `I4AnswerParser` (§7.2), `I4Writer` (la chiamata, il ripiego, l'esito);
- `I4State` (UserDefaults, scelte, stati, testo a mano).
Le viste: `I4View` (due colonne), `TermSectionsView`, `CanvasView`, `ElementCardView`, `PaletteRow`, `JSONSheet`.

## 10. Test e verifiche

**Tappa 1** (pacchetto): `OrderedJSON` (escape, vuoti, rientro) e `I4Payload` (golden: spec vecchia §4.3/§4.4 e otto casi; photo prima di medium, art_style dopo; `text` solo per i testi; `bbox` solo con posizione; palette vuota dell'elemento omessa, quella dello stile sempre presente); `I4Database` (Mood fuso a 31 voci; categorie per modalità con i conteggi del §5; categoria ignota → avviso; database in cartella con schema sconosciuto → incorporato); `I4Document` (una voce per categoria; Medium una sola; Foto→Arte cancella le scelte nascoste e lascia quelle comuni); `I4Shuffler` (al massimo 3 voci per sezione da categorie diverse, Medium sempre 1, Background 1, sezioni con meno di 3 categorie, deterministico con il seme, non tocca descrizione/elementi/palette); `I4State` (ricarica; stato di una versione sconosciuta → default); `Strings` (it/en stesse chiavi). Dal vivo con l'istanza isolata: il tab, scelte, Shuffle, un elemento a mano, «Rivedi JSON» con una modifica e «Invia» che mette il JSON nel Prompt e svuota il negativo; il tab grigio su altre famiglie.

**Tappa 2**: `CanvasGeometry` (clamp, lato minimo 20 in disegno e ridimensionamento, normalizzazione, spostamento che resta nel canvas, armamento assegna al selezionato senza crearne un altro, proporzioni della Generazione da `context.parameters` e quadrato senza). Dal vivo: disegnare, spostare, ridimensionare, cambiare la dimensione nella Generazione e vedere il canvas seguirla.

**Tappa 3**: `I4Fields` (stati *grezzo / riscritto / da riscrivere / vuoto*; una frase resta valida se l'ingresso è uguale e diventa da riscrivere se cambia; vuoto perde la frase; Foto→Arte); `I4Brief` (tag giusti e nell'ordine, categoria in inglese, una voce per riga, `kind`, testo verbatim solo come contesto, `<already_written>` solo se c'è, posizioni e colori assenti, elemento senza contenuto escluso); `I4AnswerParser` (tag corretti, maiuscole e trattini, `<think>`, recinzioni, tag mancante, tag non richiesto, tag doppio, risposta senza tag con un solo campo, virgolette attorno); `I4Writer` con un LLM finto (risposta completa → una chiamata sola; tag mancante → una chiamata per quel campo e non per gli altri; risposta senza tag → una per campo; un campo che fallisce da solo resta grezzo; frase arrivata dopo una modifica dell'ingresso → da riscrivere; testo a mano scartato solo a successo). Dal vivo con il modello vero (l'8B dell'utente): prova a gruppi, una riscrittura selettiva (cambiare un campo e rilanciare riscrive solo quello), la finestra «Rivedi JSON» sul risultato, un messaggio fuori formato che fa scattare il ripiego; **prova A/B della regola 7** (coerenza tra descrizione generale, background ed elementi): la stessa scena con e senza la regola, per vedere se il background e gli elementi ripetono la descrizione o prendono dettagli l'uno dall'altro; se la regola fa più danni che bene si toglie dal file (`ideogram4.json`), senza toccare il codice.

## 11. Decisioni prese da me (da correggere se non vanno)

- Il tipo dell'elemento non si cambia sulla card (decisione dell'utente, 6 ottobre, per risparmiare spazio): oggi si sceglie solo aggiungendo; col canvas lo cambierà il tag sopra il riquadro.
- Il codice di Prompt Master si copia, non si condivide.
- I campi e le categorie per modalità stanno in `ideogram4.json`, non nel codice.
- Il Mood fuso si calcola all'avvio dal database (nessuna categoria nuova nel file condiviso).
- Foto → Arte conserva le scelte delle categorie comuni (per esempio un Medium digitale) e cancella le altre.
- Nessun termine personale in questa versione.
- Il testo a mano resta anche cambiando i campi; lo scartano solo «Ripristina» e una «Scrivi con LLM» riuscita (che lo dice).
- Il testo verbatim degli elementi di testo va all'LLM come contesto, mai da riscrivere; esce nel JSON com'è.
- Il ripiego è una chiamata per campo mancante, in sequenza, anche quando la risposta non ha alcun tag.
- L'LLM non riceve posizioni né colori.
- Il thinking è spento e la temperatura è 0,6.
- Il negativo vuoto si manda sempre con «Invia».
- Un elemento aggiunto con il pulsante si apre da solo (c'è da scrivere); gli altri partono chiusi.
- Un testo a mano svuotato non si manda («Invia» si disattiva); si torna ai campi con «Ripristina dai campi».
- La finestra «Rivedi JSON» usa un campo di testo di AppKit senza sostituzioni (virgolette dritte, niente trattini lunghi): quello di SwiftUI le trasformerebbe e il JSON non sarebbe più valido.
- Nella tappa 1 il plug-in non legge il `context` (il tab è grigio sulle altre famiglie dal manifesto); la dimensione della Generazione arriva con il canvas.

## 12. Rischi aperti

- **L'LLM generico decide la qualità delle frasi.** Un modello piccolo può non rispettare i tag; per questo il ripiego e il master prompt con un esempio. Si prova con l'8B dell'utente.
- **I limiti di parole sono ipotesi.** Ideogram 4 non ha un tetto dichiarato nelle fonti a disposizione; si regolano alla prova.
- **Il canvas segue la dimensione della Generazione solo quando l'app rimanda `context`.** Valgono le regole di Prompt Master (`PluginContextKey`): da verificare dal vivo cambiando larghezza e altezza a mano.
- **Il JSON è più lungo di un prompt comune.** Draw Things lo accetta com'è (spec vecchia §17.1); la verifica con un'immagine vera è un passo della prova della tappa 1.
- **Il negativo vuoto** dipende da come l'app applica `negativePrompt: ""` per la famiglia `ideogram_4` (il compositore lo scarta se la famiglia non usa il negativo): da controllare nella tappa 1 e, se serve, il negativo vuoto si toglie dall'invio.
- **I master prompt delle altre famiglie** restano un lavoro a parte; questo master prompt si rivede con la stessa ricerca.
- Il plug-in non è firmato né notarizzato: la distribuzione ad altri è un lavoro a parte.

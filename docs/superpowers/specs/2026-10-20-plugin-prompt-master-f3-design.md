# DT Hub — Plug-in Prompt Master F3 (FLUX.3 Klein)

Data: 20 ottobre 2026 · Stato: **bozza da approvare; non implementabile finché FLUX.3 Klein non è in Draw Things** (l'id della famiglia e il formato delle coordinate nel prompt non sono noti, §3 e §13) · Fa da modello a `2026-10-06-plugin-prompt-master-i4-design.md` (stesso contratto 1, stessi dati, stesso modo di costruire un plug-in) · Mockup di riferimento: `docs/superpowers/mockups/2026-10-20-prompt-master-f3.html`.

## 1. Scopo

FLUX.3 legge prompt **strutturati con riquadri**: una descrizione in prosa che cita gli elementi con dei segnaposto `<id>`, e subito dopo un array JSON che dice, per ogni id, dove sta (`bbox`) e che cosa è (`desc`). **Prompt Master F3** è il plug-in che lo costruisce: l'utente descrive la scena, scrive la composizione con gli `<id>`, posiziona i riquadri sul canvas e descrive ogni elemento; il testo finale va nel campo Prompt della Generazione. L'LLM locale dell'app, facoltativo, traduce in inglese e arricchisce i testi, **senza mai toccare gli `<id>`**.

Decisioni dell'utente (19–20 ottobre 2026):
- **Plug-in separato** da Prompt Master I4, che non si tocca. Dal codice di I4 si copia solo ciò che serve (BBox, canvas, schede degli elementi). I plug-in sono pacchetti indipendenti.
- **Il prompt si scompone in tre parti**: descrizione generale, composizione, BBOX. **Quattro card:** Descrizione generale, Composizione, Canvas, Elementi.
- **Descrizione generale** = un Prompt Master ridotto in una card: database dei termini senza il gruppo H «Technical», Foto/Arte/Shuffle, un campo di testo.
- **Composizione** = una casella di testo libera, compatta. Scrivere `<xxx>` crea un elemento: un box sul canvas e una scheda con l'id già inserito.
- **Non esistono elementi senza BBOX.** Gli id sono liberi; se ne compare uno ripetuto c'è un avviso che consiglia di numerarli (`_1`, `_2`…).
- **Un solo pulsante «Scrivi con LLM»**, in fondo. Il risultato **sostituisce i testi nell'interfaccia** (si vede già il prompt finale). **«Annulla»** rimette i testi di prima, **solo l'ultima scrittura**.
- Le parti da elaborare vanno all'LLM **in Markdown**, salvate in una cartella temporanea per il ripristino e, forse, per ricordare lo stato tra una sessione e l'altra.
- L'LLM riceve **l'ordine tassativo** di non modificare i testi tra `<>`: solo tradurre in inglese e arricchire il testo attorno.
- Un **master prompt specifico** per F3 istruisce l'LLM sulle tre parti.

Fuori da questa spec: l'**editing** con immagini di riferimento (`from`, `src_bbox`, `tgt_bbox`) è del plug-in «Flux3 Inpainting» (spec a parte). Krea 3 non ha una sintassi BBOX.

## 2. Il formato che FLUX.3 legge

Griglia **0–1000**, origine in alto a sinistra, ordine **`[top, left, bottom, right]` = `[y0, x0, y1, x1]`** (lo stesso di I4), `top < bottom`, `left < right`. Gli id vanno **anche nella prosa**; le box possono sovrapporsi. Schema del testo inviato:

```
<descrizione generale>

<composizione, con gli <id>>

[
  {
    "id": "woman_1",
    "bbox": [250, 350, 850, 650],
    "desc": "A young woman in a black trench coat…"
  }
]
```

Fonti: documentazione BFL (`docs.bfl.ai/flux_3/flux3_image_bounding_boxes`), il repo `black-forest-labs/flux-3-image-klein`, le note raccolte il 20 ottobre (verificate dall'utente). **Rischio noto:** il repo di Klein mostra in `boxes.json` coordinate **0–1**; si controlla in Draw Things quale formato legge il modello nel campo Prompt (§13). Nel codice c'è **un solo punto** che decide la scala (`BBoxScale.grid`: 1000 o 1) e come si scrive nel JSON.

## 3. Famiglia e manifest

`id` `com.exiztenz.dthub.promptmasterf3`, nome «Prompt Master F3», versione 1.0, simbolo `curlybraces.square`, `families: [<id della famiglia>]`. **L'id della famiglia è sconosciuto finché Draw Things non la espone** (ipotesi `flux_3_klein`, non usarla): sta in una costante sola (`F3Plugin.family`). Fuori dalla famiglia il plug-in si spegne e il tab sparisce (regola del contratto 1); Prompt Master generico e I4 restano com'erano. Solo generazione da testo: se nel Moodboard ci sono immagini il prompt è lo stesso (le regioni di un edit sono di Flux3 Inpainting).

## 4. Dati

| File | Dove | Note |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (lo stesso di Prompt Master) | tutti i gruppi **tranne H «Technical»** (`render_quality`, `negative_terms`, `typography_text`) |
| `flux3.json` | `…/Data/prompt-master/` | quali categorie compaiono con Foto e quali con Arte; i gruppi esclusi (`excludedGroups: ["H"]`); le opzioni dell'LLM (§9); versione |
| `master-prompt.md` | `…/Data/prompt-master-f3/` | il master prompt (§10); `custom/master-prompt.md` per i ritocchi dell'utente; si installa all'avvio come in I4 (`DTHubPromptFolder`) |

Le categorie per Foto/Arte partono dall'elenco di I4 con i gruppi A–G; il dettaglio (quali Foto, quali Arte) si decide al piano guardando `ideogram4.json`. Nel testo le voci vanno in inglese (`en`), una per categoria, come in I4.

## 5. Il testo inviato (`F3Composer`)

Funzione pura da documento a stringa; **«Invia» manda questo testo** nel Prompt, con il negativo svuotato (come I4; FLUX non lo usa):

1. **Descrizione:** il testo libero, poi le voci scelte nel database come frase (`Neon light, rim light, medium shot.`) **senza LLM**; dopo una scrittura con l'LLM le voci sono già dentro al testo (§9).
2. **Riga vuota,** poi la **composizione** così com'è.
3. **Riga vuota,** poi l'**array JSON**, un oggetto per elemento nell'ordine delle schede: `id`, `bbox` `[y0, x0, y1, x1]`, `desc`. Si scrive con `JSONEncoder` (virgolette e a capo della `desc` escapati), indentato di due spazi come negli esempi ufficiali.

«Invia» è disattivato (e la riga di stato dice perché) se: non c'è nessun elemento; un elemento ha la `desc` vuota; un id è ripetuto. Mai un id nella composizione senza la sua scheda, né una scheda senza id nel testo (nascono dal testo, §7).

## 6. Interfaccia (le quattro card)

Colonna sinistra: **1 · Descrizione generale** (alta, la lista dei termini scorre dentro la card), **2 · Composizione** (compatta). Colonna destra: **3 · Canvas**, **4 · Elementi**. Aspetto e componenti dal kit (`DTHubPluginKit`/`DSCard`…), come I4.

1. **Descrizione generale:** campo di testo; **Foto / Arte** (cambiando, le voci delle categorie che spariscono si cancellano); **Shuffle** (al massimo 3 categorie, una voce ciascuna, come in I4); i **gruppi** del database con le loro categorie, una voce per categoria, contatore per gruppo.
2. **Composizione:** **solo** la casella di testo (altezza minima ~2 righe, cresce), la didascalia «Aggiungi un `<ID>` nel testo per creare un Elemento.» e, solo quando serve, l'avviso dell'id ripetuto. I `<id>` sono evidenziati con il colore dell'elemento.
3. **Canvas:** vedi §8.
4. **Elementi:** una scheda per id (chiusa, la nuova si apre da sola): chip dell'id nel suo colore, descrizione (testo libero), posizione `[y0, x0, y1, x1]` (campo modificabile come in I4), su/giù, rimuovi. In fondo: **Annulla** (attivo solo dopo una scrittura), **Scrivi con LLM**, **Invia**, riga di stato. Niente «Rivedi JSON» né «Prompt finale»: il testo che parte è quello che si vede nei campi, e dopo «Invia» sta nel Prompt.

Ogni id ha un **colore** (otto in rotazione, assegnato alla nascita e mai cambiato), lo stesso nel testo, sul canvas e nella scheda.

## 7. La composizione e gli id

**Riconoscimento.** Un id è il contenuto di un `<…>` senza `<`, `>` né a capo, tolti gli spazi ai bordi, lungo 1–40 caratteri. Gli id sono liberi (nessun formato imposto).

**Sincronizzazione.** Il testo è l'unica fonte degli id. Si sincronizza quando si smette di scrivere (~0,8 s) o il campo perde il fuoco, **mai a ogni tasto** (mentre si scrive `<woman_1` non nascono elementi a pezzi):
- id nuovo → scheda in fondo all'elenco e box sul canvas (§8);
- id sparito → la scheda e il box vengono tolti, **ma si ricordano per tutta la sessione**: se lo stesso id ricompare tornano con descrizione e posizione (così un taglia/incolla o un refuso non fa perdere il lavoro);
- **rinomina:** se in una modifica un id sparisce e uno nuovo appare nello stesso punto del testo, è una rinomina: la scheda e il box restano.
- id ripetuto: una sola scheda; appare l'avviso «`<lamp_1>` compare due volte: numera gli id (`lamp_1`, `lamp_2`…)» e «Invia» resta disattivato finché non si risolve.

## 8. Il canvas

Copia di I4 (`BBox`, `CanvasGeometry`, la card): rettangolo con le proporzioni della Generazione, griglia 0–1000, lato minimo 20, si sposta un box trascinandolo e si ridimensiona dagli angoli, il clic sull'etichetta lo seleziona (e seleziona la scheda). **Cambia:**
- **Non si creano box trascinando sul vuoto** (gli elementi nascono dal testo); il trascinamento sul vuoto non fa nulla.
- **Il box di un id nuovo** nasce **in fila a partire da in alto a sinistra, senza sovrapporsi** (l'utente di solito scrive prima tutti gli id e poi li posiziona): lato 180 su 1000 (quadrato in pixel), passo 200, a capo a destra; se la griglia è piena, sfalsato.
- L'etichetta del box è l'id, nel suo colore; il box selezionato è bianco con la maniglia.

## 9. Scrivi con LLM

**Quando.** C'è almeno un testo (descrizione, composizione, `desc` di un elemento) o una voce del database. Una sola richiesta `llm` senza `model` (vale il modello dell'app), con `system` = il master prompt (§10), `options` da `flux3.json` (come I4: `thinking` spento, temperatura 0,6, `maxTokens` 4096), attesa fino a 600 s, nessuna immagine.

**Le parti, in Markdown.** Ogni parte è un blocco con un titolo; il plug-in compone il messaggio e lo salva come file (`request.md`) nella cartella di lavoro (§11):

```
## description
due amici in una tavola calda al neon, di notte
Light Source: Neon lighting
Framing: Medium shot

## composition
Nella scena ci sono una donna <woman_1> e un ombrello rosso <umbrella_1>.

## element: woman_1
una giovane donna con un trench nero

## element: umbrella_1
ombrello rosso trasparente
```

- Le righe `Categoria: voce` sono le voci scelte, categoria in inglese e voce in `en` (stessa ragione di I4: «butterfly lighting» senza categoria diventa farfalle).
- Gli id dei titoli `## element: <id>` sono quelli delle schede; posizioni e colori **non** si mandano. Le parole tra virgolette di una `desc` (scritte, lettering) **non si traducono né si cambiano**.
- La **risposta** ha la stessa forma, **gli stessi titoli nello stesso ordine**, e il messaggio finisce con quella forma da riempire (lezione di I4: un modello piccolo risponde meglio se vede la forma). Il parser (`F3AnswerParser`) toglie `<think>` e recinzioni, cerca i titoli richiesti, ripulisce spazi e virgolette che avvolgono tutto.
- **Ripiego** come in I4: per ogni parte mancante una chiamata a parte con la sola parte; se manca ancora, quella parte resta com'era e la riga di stato lo dice.

**Il controllo degli id (nel codice, non solo nel prompt).** La composizione riscritta **deve contenere gli stessi `<id>`, gli stessi, lo stesso numero di volte**. Se non è così la parte è scartata, si riprova una volta da sola con l'ordine ripetuto, poi resta l'originale con la segnalazione «l'LLM ha cambiato gli id». Lo stesso vale per le parole tra virgolette delle `desc`.

**Dopo la scrittura.** I testi della risposta **sostituiscono** quelli dei campi, e le voci del database scelte, ormai nel testo, **si deselezionano**. La riga di stato dice cosa è cambiato.

**Annulla.** Prima di sostituire si salva una **fotografia** dei campi: testo della descrizione, voci scelte, composizione, `desc` degli elementi. «Annulla» la rimette e si spegne; la fotografia è solo l'ultima (una scrittura nuova la sostituisce). Posizioni, ordine e colori non fanno parte della fotografia (la scrittura non li tocca). Se nel frattempo si sono cambiati gli id nel testo, Annulla rimette comunque i testi e poi si risincronizza come al §7.

## 10. Il master prompt

File `master-prompt.md` (incorporato in `EmbeddedData`, generato da `Scripts/make-embedded-prompts.py` come gli altri). Bozza, da provare dal vivo con l'LLM dell'utente e accorciare (la lezione di I4: più corto = tag sbagliati di meno):

```
You prepare the text of a structured image prompt for the image model FLUX.3. The request has blocks, each under a title: "description" (the whole picture), "composition" (a sentence that names the elements of the picture with placeholders such as <woman_1>) and one "element: <id>" block for each element (what must appear inside that element's region).

Answer with the SAME titles, in the SAME order, each followed by its rewritten text. Write nothing else: no JSON, no notes, no markdown other than the titles.

Rules:
1. Write in English, whatever language the input is in. Plain descriptive prose, no commands, no keyword lists, no labels.
2. NEVER change, translate, remove, add, move to another place or rename anything between < and >. Each placeholder stays exactly as written, the same number of times. Only translate and enrich the words around them.
3. Words between quotation marks are text to be printed in the picture: copy them exactly.
4. "description": one or two sentences about the scene as a whole. Lines shaped like "Category: term" are terms picked from a vocabulary; work them into the sentence naturally. Do not describe the individual elements here.
5. "composition": keep it a short sentence that places the elements in the scene; do not describe them in detail.
6. "element: <id>": describe only what appears inside that region: appearance, material, colour, pose, in a few concrete sentences. No positions, no coordinates, no mention of other elements.
7. Do not invent new elements, and do not add placeholders.
```

## 11. Stato, cartella di lavoro e persistenza

- **Stato del tab per progetto**, come I4: `state.json` nella cartella che l'app dà al plug-in per il progetto aperto (messaggio `project`; `FileStorage`/`F3Store`, `schema` 1): descrizione, voci scelte, Foto/Arte, composizione, elementi (`id`, `desc`, box, colore, aperto/chiuso), categorie aperte, e la **fotografia di Annulla**.
- **Cartella di lavoro** `llm/` accanto a `state.json`: `request.md` (cosa è stato mandato), `answer.md` (la risposta grezza), `before.md` (i testi prima della sostituzione, in Markdown, leggibili a mano). Servono al ripristino e a capire cosa ha fatto il modello; **sono sostituiti a ogni scrittura**. Lo stato tra una sessione e l'altra resta in `state.json` (la fotografia di Annulla si legge da lì, non da `before.md`): `before.md` è una copia di cortesia, non una fonte.
- Gli id ricordati dopo una rimozione (§7) **non** si salvano: valgono per la sessione.

## 12. Codice, test e verifiche

Pacchetto `Plugins/PromptMasterF3/` (modello: I4; `Scripts/build.sh`, `Package.swift` con gli alias `…Kit`/`…Design`, dati in stringhe Swift da `Scripts/make-*.py`). Da I4 si **copiano e adattano** `BBox`, `CanvasGeometry`, la card del canvas, il campo posizione, le schede (senza colori della palette né testo/lettering), `DataSource`, `I4Prompts`, `I4Store`, `I4Sender`, lo Shuffler. **Nuovi:** `F3Document`, `F3Composer` (§5), `F3IDParser` e `F3Sync` (§7), `F3DefaultBox` (§8), `F3Brief`, `F3AnswerParser`, `F3Writer` (§9, con il controllo degli id), `F3Snapshot` (Annulla), `F3View` e le card.

Test, prima di tutto con RED poi GREEN: composizione del testo (virgolette e a capo nel JSON, ordine, scala della griglia); riconoscimento degli id (spazi, vuoti, `<>` annidati, ripetuti); sincronizzazione (nuovo, tolto, **rinomina**, ritorno di un id tolto, nessun elemento a pezzi mentre si scrive); box di default (fila, a capo, griglia piena, proporzioni); messaggio MD e parser (titoli, ripiego, `<think>`); **controllo degli id** (id cambiato, mancante, in più, parole tra virgolette); Annulla (fotografia, una sola, dopo cambio di id); stato su file e `schema`; `Invia` disattivato nei tre casi; manifest e localizzazione (`L`, test di catalogo it/en). Verifiche dal vivo (dietro variabile d'ambiente, come I4): il master prompt con l'LLM vero (Qwen3-VL 8B) su tre scene, e **FLUX.3 Klein in Draw Things** con un prompt ottenuto (formato delle coordinate, resa delle box).

## 13. Decisioni prese da me (da correggere se non vanno)

- **Invia disattivato** con descrizione di un elemento vuota o id ripetuto (la tua regola «niente elementi senza BBOX» vale per la posizione; per la `desc` ho scelto di non mandare un oggetto vuoto).
- **Voci del database senza LLM:** finiscono in coda alla descrizione come frase di termini inglesi.
- **Elementi ricordati** per la sessione dopo che l'id sparisce dal testo, e **rinomina riconosciuta** dalla posizione nel testo (alternativa: nessuna conferma, nessun recupero).
- **Sincronizzazione ritardata** (0,8 s o perdita del fuoco) per non generare elementi a ogni tasto.
- **Box di default:** lato 180/1000, passo 200, a fila da in alto a sinistra.
- **Controllo degli id nel codice** oltre al master prompt: l'ordine «non toccare i `<>`» è tassativo e un modello piccolo lo viola.
- **Niente «Rivedi JSON»** (il testo non si edita a mano come in I4): se serve dopo, si aggiunge.
- **Un colore per id** (otto in rotazione).

## 14. Rischi aperti

- **Id e scala delle coordinate** (§2, §3): finché Draw Things non ha il modello non si prova. Si scrive il codice con la costante e il punto unico, e il primo giorno si prova a mano.
- **Il formato nel campo Prompt:** un prompt con un array JSON in coda è insolito per Draw Things; se la sua tokenizzazione o il limite di lunghezza lo tagliano, la `desc` lunghe vanno accorciate (il master prompt dice «poche frasi»).
- **LLM piccolo:** può cambiare gli id o tradurre le virgolette: il controllo del §9 è lì per questo, ma costa un nuovo tentativo; se capita spesso si accorcia ancora il prompt o si passa a una chiamata per parte.
- **Modello «Klein» e prompt strutturato:** non sappiamo se la variante Klein regge bene gli stessi prompt del FLUX.3 completo; la documentazione ufficiale parla di FLUX.3 in generale.
- **Lista dei termini del database:** Foto/Arte per i gruppi A–G va riguardata (alcune categorie, come gli artisti, forse non servono a una scena con riquadri).

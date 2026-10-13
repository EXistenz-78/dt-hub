# Plug-in LoRA Advisor — Design

Data: 13 ottobre 2026. Stato: disegno approvato in chat dall'utente, sezione per sezione (ricerca per nome e «Riassumi tutti» aggiunti il 13 ottobre); da rivedere per iscritto prima del piano.
Base: `main` **0.2.1** (`9326053`). Mockup: `docs/superpowers/mockups/2026-10-13-lora-advisor.html`.

## 1. Obiettivo

Un plug-in con due funzioni:

1. **«I tuoi LoRA»**: un elenco visuale dei LoRA del server, ognuno con un'anteprima e un campo **Note**. Note e anteprima si compilano dalla pagina del LoRA: il plug-in la cerca su Civitai dal nome, oppure l'utente ne incolla il link (Civitai o Hugging Face). Da ogni riga il LoRA si aggiunge a Generazione.
2. **«Consiglia»**: l'LLM locale sceglie dall'elenco i LoRA adatti a una richiesta (di partenza, il prompt attuale) e li propone con peso e motivazione.

L'elenco conta più del consiglio: funziona anche senza LLM.

## 2. Decisioni (dell'utente, 12–13 ottobre)

- **Il gestore dei LoRA dell'app non cambia** (compatto e pratico). Anteprima e note vivono solo nel plug-in.
- **Il plug-in riceve dall'app solo l'elenco dei LoRA** con trigger, peso e famiglia.
- **Un solo campo «Note»** per LoRA: vi finisce il testo della pagina, poi il riassunto; l'utente lo modifica o aggiunge i suoi appunti nello stesso campo. Nessun campo «descrizione» a parte.
- **Tre passi, ognuno con il suo tasto, mai da soli:**
  1. **«Cerca le pagine»** cerca su Civitai e su Hugging Face, dal nome (anche senza la sigla iniziale dell'utente), la pagina dei LoRA che non ne hanno una; se non c'è un nome uguale propone dei candidati da scegliere;
  2. l'**importazione** scarica testo e anteprima della pagina (parte da sola dopo una ricerca riuscita, o da «Importa dalla pagina» con un link incollato);
  3. **«Riassumi tutti»** fa riassumere all'LLM le Note ancora grezze.
- **Ogni passo lavora solo su ciò che manca:** la prima volta a tappeto; dopo, solo sui LoRA nuovi e su quelli a cui l'utente ha dato o cambiato il link. Mai di nuovo su tutto.
- **L'utente corregge solo dove serve:** incolla il link giusto, o scrive a mano, per i LoRA non trovati o trovati male.
- **Anteprima:** la **prima immagine della galleria** della pagina. Nessuna scelta tra più immagini, nessun filtro sulle immagini per adulti. Sostituibile a mano con un file o con l'immagine di partenza di Control.
- **Rete:** il plug-in fa richieste di rete, solo al clic e con i limiti del §6. Va detto nel README.
- **`civitai.red`** è un sito secondario di Civitai (confermato dall'utente): i suoi link valgono come quelli di `civitai.com`.
- **Consiglio:** un solo campo di testo, precompilato con il prompt attuale, che si può riscrivere per cercare un'esigenza.
- **I LoRA di famiglie diverse non si mescolano:** il consiglio riguarda solo i LoRA della famiglia del modello attuale; nessun interruttore «Tutte le famiglie».
- **Layout:** due card affiancate come in Batch plus. A **sinistra, larga**, «I tuoi LoRA»; a **destra, stretta**, «Consiglia».
- **Aggiunta manuale:** ogni riga dell'elenco ha «Aggiungi», non solo i consigliati.

## 3. Il plug-in

- Nome «LoRA Advisor», cartella `Plugins/LoRAAdvisor/`, id `com.exiztenz.dthub.loraadvisor`, versione 1.0, zip `LoRAAdvisor.dthubplugin.zip`.
- Famiglie: tutte (come Batch plus e AI Assistant).
- Modello di riferimento per struttura, build e test: `Plugins/BatchPlus/`.
- Testi in italiano e inglese (tabella `L` del plug-in).
- Richiede DT Hub ≥ 0.2.2 per `loraCatalog` (§4). Con un'app più vecchia il tab mostra una riga: «Serve DT Hub 0.2.2 o successivo per l'elenco dei LoRA.» Finché il plug-in non è acceso per il lavoro non riceve il contesto, e il tab dice: «Accendi LoRA Advisor per il lavoro (menu dell'header) per vedere i tuoi LoRA.»

## 4. Aggiunta al contratto 1 (app 0.2.2)

Il messaggio `context` guadagna un campo facoltativo:

```json
"loraCatalog": [
  {"file": "analog_film_35_lora_f16.ckpt", "name": "Analog Film 35", "family": "flux2_9b", "trigger": "analogfilm35", "weight": 0.8}
]
```

- È l'elenco **unito** del gestore (`ConnectionMonitor.catalog`): trigger e peso sono quelli che l'utente ha impostato in «Gestisci LoRA…», altrimenti quelli del server e il peso 1.
- `family` manca quando il server non la dice; `trigger` vuoto = nessuna.
- Un'app ≥ 0.2.2 manda sempre il campo, anche vuoto (nessun LoRA, server non collegato): se manca, l'app è più vecchia.
- Come ogni contesto, arriva solo ai plug-in accesi per il lavoro (menu dell'header) e di nuovo quando il loro tab viene mostrato.
- Kit: `DTHubContext.loraCatalog` (`[DTHubCatalogLoRA]`), lettura tollerante: una voce illeggibile si salta e non costa il resto del contesto.
- `PluginKit/README.md` documenta il campo.

Nient'altro cambia nel contratto: per aggiungere un LoRA il plug-in usa `contribute.loras`, che esiste.

## 5. Dati

Globali, non per progetto: note e anteprime riguardano il LoRA, non un lavoro.

- Cartella `~/Library/Application Support/DT Hub/Data/LoRAAdvisor/`.
- `loras.json`:

```json
{"schema": 1, "loras": {
  "analog_film_35_lora_f16.ckpt": {
    "link": "https://civitai.com/models/123456", "notes": "…", "thumbnail": "3F2A….jpg",
    "searched": true, "foundBySearch": true, "rawNotes": true
  }
}}
```

- **Campi** (tutti facoltativi):
  - `link`: la pagina del LoRA;
  - `notes`: il campo Note;
  - `thumbnail`: il nome del file in `thumbs/`;
  - `manualThumbnail`: l'anteprima l'ha scelta l'utente (file o Control): l'importazione non la sostituisce;
  - `searched`: «Cerca le pagine» è già passato su questo LoRA (trovato o no): non lo ricerca più;
  - `foundBySearch`: il link viene dalla ricerca, non dall'utente (etichetta «trovato automaticamente»);
  - `rawNotes`: le Note sono ancora il testo grezzo della pagina, in attesa del riassunto;
  - `candidates`: le pagine trovate senza un nome uguale, tra cui l'utente sceglie: `[{"title", "link", "info", "downloads"}]`.
- `thumbs/<nome>.jpg`: JPEG, lato lungo 256 px. Il nome è generato; il file vecchio si cancella quando l'anteprima cambia o si rimuove.
- `pages/<nome>.txt`: il testo ripulito della pagina, tenuto finché le Note sono grezze, così «Riassumi» non riscarica nulla. Si cancella dopo il riassunto o quando l'utente modifica le Note.
- Chiave: il nome del file del LoRA, come in `loras.json` dell'app.
- **Modificare le Note a mano** toglie `rawNotes`: sono dell'utente, e nessun passo automatico le tocca più.
- **Cambiare il link a mano** toglie `foundBySearch`.
- Una voce senza alcun campo non si scrive.
- Le voci dei LoRA che il server non ha più restano nel file; tornano se il LoRA ricompare.
- Scrittura a ogni modifica (con mezzo secondo di attesa mentre si scrive nelle Note). File mancante o illeggibile = elenco vuoto; un file illeggibile non si sovrascrive finché l'utente non modifica qualcosa.
- Il plug-in risponde «ok» al messaggio `project` e lo ignora: il suo stato è globale per scelta.

## 6. Pagine: cercare, importare, riassumere

### 6.1 «Cerca le pagine» (Civitai e Hugging Face)

Rivista il 13 ottobre dopo la prima prova dell'utente: su 141 LoRA il solo confronto «nome uguale» su Civitai ne aveva trovati 11. I nomi dell'utente cominciano con una sua sigla di famiglia (`k2`, `q21`, `zit`…), i titoli su Civitai sono lunghi e decorati, e molti LoRA stanno su Hugging Face.

- Lavora sui LoRA di `loraCatalog` **senza link e con `searched` non vero**. Il tasto mostra quanti sono («Cerca le pagine · 12») ed è spento a zero.
- **Due nomi per LoRA:** il nome intero e il nome **senza la prima parola** (la sigla). Il nome intero è quello del catalogo; se è vuoto, il nome del file senza estensione, senza i suffissi di Draw Things (`_lora`, `_f16`, `_q8p`…) e con `_` e `-` come spazi.
- **Fino a tre richieste per LoRA**, una alla volta:
  1. Civitai con il nome senza la prima parola (se il nome ha più parole);
  2. Civitai con il nome intero: `https://civitai.com/api/v1/models?query=<nome>&types=LORA&limit=10&nsfw=true` (`nsfw=true` serve: senza, i LoRA per adulti non compaiono);
  3. Hugging Face con il nome senza la prima parola: `https://huggingface.co/api/models?search=<nome>&sort=downloads&direction=-1&limit=5` (i più scaricati per primi: un LoRA ha spesso molte copie, l'originale è quello più preso).
- **Filtro per modello** (chiesto dall'utente dopo la seconda prova): un risultato di Civitai si scarta quando il suo modello di base è di una famiglia diversa da quella del LoRA (`LAFamily`: `krea_2` ↔ «Krea 2»; `z_image` ↔ «ZImageTurbo/Base»; `flux2_9b` ↔ «Flux.2 Klein 9B», distinto da Klein 4B e da «Flux.2 D»; `qwen…` ↔ «Qwen», «Qwen 2.1»; SDXL ↔ «SDXL», «Pony», «Illustrious», «NoobAI»; `v1` ↔ «SD 1.x»; `v2`, `sd3…`, `flux1`, video…). Vale prima del confronto dei nomi e prima di scegliere i candidati. Nel dubbio si tiene: famiglia del LoRA sconosciuta, o modello di base fuori tabella («Other», «Chroma»…). Hugging Face non si filtra: la sua ricerca non dice il modello di base.
- **Esito:**
  - **un risultato con il nome uguale** a uno dei due nomi (senza maiuscole, accenti, spazi, punteggiatura e un'eventuale versione in coda; per Hugging Face conta il nome del repository senza l'autore): `link`, `foundBySearch` e `searched` veri, e parte l'importazione (§6.3). Le richieste successive non si fanno;
  - **altrimenti, se ci sono risultati:** `searched` vero e in `candidates` i primi tre di Civitai (prima quelli del nome senza sigla) e i primi due di Hugging Face. La riga mostra «scegli la pagina»;
  - **nessun risultato:** solo `searched` vero; la riga mostra «pagina non trovata».
- **Scegliere:** nella riga aperta ogni candidato ha il nome, «Civitai · <modello di base>» oppure «Hugging Face · <n> download», un tasto che apre la pagina nel browser e **«Usa questa»**, che la collega come un link dato dall'utente (niente «trovato automaticamente») e la importa. Dei candidati non si scaricano anteprime: sarebbero centinaia di immagini, e caricarle all'apertura della riga violerebbe «rete solo al clic».
- Avanzamento visibile («7 di 12»), mezzo secondo tra un LoRA e l'altro, tasto «Ferma». Fermato o chiuso il tab, i LoRA non ancora cercati restano da cercare.
- Risposta 429 da uno dei due siti: la ricerca si ferma con «Civitai chiede di rallentare: riprova più tardi.»; il LoRA in corso e i successivi restano da cercare. Un sito che non risponde: quel LoRA resta da cercare e si passa al successivo.
- **Sulla riga:** «Non è questo» (solo con `foundBySearch`) toglie link, anteprima e Note grezze della pagina, e lascia `searched` vero; «Cerca di nuovo» su una riga «pagina non trovata» o «scegli la pagina» ripete la ricerca per quel LoRA.
- I bundle (più LoRA come versioni di una sola pagina) non si trovano dal nome: per quelli serve il link con `?modelVersionId=`.

### 6.2 Link riconosciuti

- `https://civitai.com/models/<id>` e `https://civitai.red/models/<id>`, con o senza `/<slug>` e `?modelVersionId=<v>`.
- `https://huggingface.co/<autore>/<repo>` (anche con `/tree/…` o `/blob/…` in coda, ignorati).
- Qualunque altro indirizzo: «Link non riconosciuto: servono una pagina di Civitai o di Hugging Face.» Nessuna richiesta parte.
- Il link incollato si salva appena è valido, anche se l'importazione fallisce.

### 6.3 Importazione

Parte dopo una ricerca riuscita, o dal tasto «Importa dalla pagina» della riga.

**Civitai.** Una richiesta a `https://civitai.com/api/v1/models/<id>` (API pubblica, senza chiave; anche per i link di `civitai.red`, che dà gli stessi dati).

- Versione: quella di `modelVersionId` se c'è nel link, altrimenti la prima.
- Se la versione non è `availability: "Public"`, o la risposta è 401/403: «Questa pagina richiede l'accesso. Scegli tu un'immagine e scrivi le note.»
- Testo: `description` del modello ripulita dall'HTML + `baseModel` + `trainedWords` della versione.
- Anteprima: la prima voce di `images` con `type` diverso da `video`.

**Hugging Face.**

- `https://huggingface.co/api/models/<autore>/<repo>` per l'elenco dei file, e `https://huggingface.co/<autore>/<repo>/raw/main/README.md` per la scheda.
- Testo: il README senza l'intestazione YAML.
- Anteprima, in ordine: la prima immagine d'esempio della scheda (`cardData.widget[].output.url`); poi la prima immagine citata nel README (`![…](…)` o `<img src>`), se punta a un file del repository o a un indirizzo ammesso; altrimenti il primo file immagine dell'elenco (`.png`, `.jpg`, `.jpeg`, `.webp`), da `…/resolve/main/<file>`.
- Molti repository non hanno immagini: allora l'anteprima resta com'era e il plug-in lo dice («Nessuna immagine nella pagina.»); il testo si importa lo stesso.

**Cosa scrive.**

- Ripulitura del testo: tag HTML tolti, entità decodificate, spazi compattati, al massimo 6000 caratteri; salvato in `pages/`.
- **Note vuote o grezze:** vi vanno i primi 400 caratteri del testo ripulito, con `rawNotes` vero.
- **Note scritte dall'utente:** con «Importa dalla pagina» il plug-in chiede conferma («Sostituire le note con il testo della pagina?» — Sostituisci / Tieni le mie); con «Tieni le mie» importa solo l'anteprima. Dopo una ricerca non chiede e tiene le Note dell'utente.
- **Anteprima scelta a mano dall'utente:** l'importazione non la sostituisce.

### 6.4 «Riassumi tutti» e «Riassumi»

- Lavora sulle voci con `rawNotes` vero. Il tasto mostra quante sono («Riassumi tutti · 12») ed è spento a zero o senza un LLM per i plug-in («Serve un LLM assegnato ai plug-in (Preferenze › LLM).»). «Riassumi» sulla riga fa lo stesso per una voce.
- Per ognuna, una alla volta: l'LLM riceve il testo di `pages/` e scrive un riassunto di al massimo 60 parole circa, nella lingua dell'interfaccia, che dice a cosa serve il LoRA e cita le parole di attivazione e i pesi consigliati se la pagina li dà. `thinking: false`.
- Il testo della pagina va nel prompt dentro un blocco delimitato, con l'istruzione di trattarlo come materiale da riassumere e di ignorare ogni ordine che contiene.
- Riuscito: le Note diventano il riassunto, `rawNotes` si toglie, il file in `pages/` si cancella. Fallito (errore dell'LLM o risposta vuota): la voce resta grezza e la riga lo dice.
- Avanzamento visibile e tasto «Ferma»; le voci non ancora riassunte restano grezze.
- Usa l'LLM: come per ogni richiesta all'LLM, l'app può dover liberare la memoria del server delle immagini.

### 6.5 Limiti di rete

- Solo al clic su «Cerca le pagine», «Cerca di nuovo» o «Importa dalla pagina»; mai in automatico (nemmeno all'apertura del tab o all'arrivo di LoRA nuovi).
- Solo `GET`, sessione senza cookie né credenziali, senza cache, timeout 20 s.
- Indirizzi contattati, scritti nel codice: `civitai.com` e i suoi sottodomini (le immagini passano da `image.civitai.com` a `blobs-b2.civitai.com`); `huggingface.co` e `hf.co` con i loro sottodomini (le immagini arrivano da `us.aws.cdn.hf.co` e simili). Un reindirizzamento fuori da questi si rifiuta. Solo `https`. `civitai.red` si accetta nei link ma non si contatta.
- Dimensioni: risposta JSON o README al massimo 5 MB, immagine al massimo 10 MB; oltre, errore.
- L'immagine si decodifica con ImageIO (primo fotogramma se animata) e si ricodifica in JPEG da 256 px: sul disco non resta mai il file scaricato.
- Dal Mac escono: con «Cerca le pagine», **i nomi dei LoRA** come testo di ricerca, a Civitai e a Hugging Face; con l'importazione, la richiesta della pagina e dell'immagine. Nessun prompt, nessun altro dato.

### 6.6 Errori

Una riga sotto il link, in `DS.remove`, e la voce resta com'era: «Pagina non trovata.» (404), «La pagina non risponde.» (timeout o rete), «Risposta non leggibile.», «Immagine troppo grande.», più i messaggi sopra. Durante un'importazione dalla riga il tasto diventa «Annulla».

## 7. «I tuoi LoRA» (card di sinistra, larga)

- In alto il titolo, i tasti **«Cerca le pagine · n»** e **«Riassumi tutti · n»** (§6.1, §6.4; durante il lavoro uno solo dei due è attivo, con l'avanzamento e «Ferma») e un campo di ricerca nell'elenco (nome, trigger, note; senza distinguere maiuscole e accenti).
- I LoRA di `loraCatalog` raggruppati per famiglia: prima quella del modello attuale (con «· modello attuale»), poi le altre in ordine di nome, in fondo «Famiglia sconosciuta». L'intestazione è la chiave della famiglia, come nel gestore dell'app (i nomi leggibili sono un rinvio già nel backlog).
- **Riga chiusa:** anteprima 64 pt (riquadro tratteggiato se manca), nome, «trigger: … · peso …» (o «nessun trigger»), la prima riga delle Note (o «Nessuna nota.»), lo stato della pagina quando c'è («trovato automaticamente», «pagina non trovata», «da riassumere»), e a destra **«Aggiungi»**.
- **Riga aperta** (clic sulla riga; una sola aperta alla volta): anteprima 112 pt con il menu «Anteprima» (Scegli file…, Usa l'immagine di Control, Rimuovi); Note su più righe; campo del link e «Importa dalla pagina»; secondo lo stato, «Riassumi», «Non è questo» o «Cerca di nuovo».
- **«Aggiungi»** manda a Generazione `{file, weight, trigger}` con i valori del catalogo:
  - spento per un LoRA di una famiglia diversa da quella del modello attuale (aiuto: «È di un'altra famiglia di modelli.»);
  - acceso per un LoRA di famiglia sconosciuta;
  - per un LoRA già nella lista di Generazione, al posto del tasto c'è «già nella lista».
- Trigger e peso si leggono soltanto: si cambiano nel gestore dell'app.
- **Trascinamento:** un'immagine trascinata su una riga (chiusa o aperta) diventa la sua anteprima, scelta dall'utente: un file dal Finder, o i dati dell'immagine quando il browser li passa. Se arriva solo un indirizzo il plug-in non lo segue («Il browser ha passato solo l'indirizzo: salva l'immagine e trascina il file.»): la rete resta solo per le pagine.
- «Usa l'immagine di Control» è spenta senza un'immagine di partenza. «Scegli file…» accetta PNG, JPEG, WebP, HEIC; un file che non si decodifica dà «Immagine non leggibile.».
- Come per ogni plug-in, «Aggiungi» funziona solo se il plug-in è acceso per il lavoro; altrimenti l'app risponde con l'errore di sempre, mostrato nella riga di stato del tab.

## 8. «Consiglia» (card di destra, 320 pt)

- Campo di testo precompilato con il prompt attuale ogni volta che arriva un contesto, **finché l'utente non lo modifica**; un tasto ↺ lo riporta al prompt attuale.
- Sotto: «Solo i LoRA di <famiglia>» e il tasto **«Consiglia»**.
- **Candidati:** i LoRA di `loraCatalog` con la famiglia del modello attuale. Quelli di famiglia sconosciuta o diversa mai.
- **Prefiltro:** oltre 40 candidati restano i 40 con più parole in comune tra la richiesta e nome + trigger + note (a parità, prima chi ha delle note).
- **Prompt per l'LLM:** la richiesta, la guida della famiglia in una riga, e una riga numerata per candidato: `n. nome | trigger | note` (note tagliate a 300 caratteri, a capo tolti). `thinking: false`.
- **Risposta attesa:** una lista JSON di al massimo cinque voci, `[{"n": 3, "weight": 0.8, "why": "…"}]`; `why` in una frase, nella lingua dell'interfaccia. Lettura tollerante: testo attorno alla lista ignorato; `n` fuori elenco o ripetuto scartato; `weight` mancante o non numerico = quello del catalogo, altrimenti riportato in −1,5…2,5; oltre cinque voci, le prime cinque.
- **Schede dei consigli:** anteprima 44 pt, nome, motivazione, peso modificabile, **«Aggiungi»**; per un LoRA già nella lista, l'etichetta «già nella lista» e il tasto **«Aggiorna il peso»**. In fondo **«Aggiungi tutti»**.
- **Stati:** «Nessun LoRA adatto.» (lista vuota); «Non ho capito la risposta dell'LLM.» (nessuna lista leggibile); «Nessun LoRA per questa famiglia.» (zero candidati, tasto spento); senza un LLM per i plug-in il tasto è spento con «Serve un LLM assegnato ai plug-in (Preferenze › LLM).»; durante la richiesta il tasto diventa «Annulla».
- I consigli non si salvano: spariscono quando cambia il modello o si chiude l'app.

## 9. Sicurezza e privacy

- Il testo scaricato è un dato non fidato: entra solo nel prompt del riassunto (blocco delimitato) e nelle Note come testo semplice; non viene mai interpretato come comando né come markup.
- Le Note entrano nel prompt del consiglio: un LoRA con note «malevole» può al più farsi consigliare. L'utente vede sempre nome e motivazione prima di aggiungere.
- Nessuna chiave API, nessun account, nessun download dei file dei modelli.
- Un abbinamento per nome può essere sbagliato: per questo le righe trovate dalla ricerca sono etichettate e hanno «Non è questo».
- README del plug-in e README principale: LoRA Advisor contatta Civitai e Hugging Face solo quando si preme «Cerca le pagine» o «Importa dalla pagina»; con la ricerca manda a Civitai i nomi dei LoRA; nient'altro lascia il Mac.

## 10. Test

- **Kit:** `loraCatalog` letto; voce illeggibile saltata; campo assente = nil.
- **App (HubCore):** il contesto porta `loraCatalog` con trigger e peso del gestore; assente con catalogo vuoto.
- **Plug-in** (logica pura, rete e LLM dietro protocolli con finti):
  - archivio: salva e rilegge; voce vuota non scritta; LoRA sparito conservato; file illeggibile non sovrascritto prima di una modifica; anteprima vecchia cancellata;
  - link: i formati del §6.2 riconosciuti (anche `civitai.red`); altri siti, `http`, indirizzi con credenziali rifiutati;
  - ricerca: quali LoRA cerca (senza link e mai cercati); nome dal catalogo o dal file ripulito; accetta solo il nome uguale (maiuscole, punteggiatura, versione in coda); non trovato → `searched`; 429 ferma tutto; «Ferma» lascia gli altri da cercare; «Non è questo» e «Cerca di nuovo»;
  - importazione: Note vuote o grezze sostituite, Note dell'utente tenute (dopo una ricerca) o chieste (dal tasto); anteprima scelta a mano non sostituita; testo in `pages/`;
  - riassunto: solo le voci grezze; riuscito toglie `rawNotes` e il file in `pages/`; fallito lascia la voce grezza; Note modificate a mano escono dal giro;
  - Civitai: versione dal link o la prima; non pubblica e 401/403 → messaggio; prima immagine non-video; `trainedWords` nel testo;
  - Hugging Face: immagine dal README, poi dall'elenco dei file; nessuna immagine; YAML tolto;
  - ripulitura dell'HTML e taglio a 6000; estratto di 400 caratteri nelle Note;
  - rete: reindirizzamento fuori dagli indirizzi ammessi rifiutato; limiti di 5 e 10 MB; timeout;
  - anteprima: ricodificata a 256 px; dato che non è un'immagine → errore;
  - consiglio: solo la famiglia attuale; prefiltro a 40; righe dei candidati; lettura della risposta (testo attorno, `n` sbagliati, pesi fuori limite, più di cinque);
  - contributo: `{file, weight, trigger}` dal catalogo; «già nella lista».
  - PNG del tab (`RenderTests`), come negli altri plug-in.
- **A mano:** «Cerca le pagine» su tutti i LoRA veri, poi di nuovo (non ricerca nulla); un LoRA aggiunto dopo (cerca solo quello); «Riassumi tutti», poi di nuovo (nulla da fare); un bundle con `?modelVersionId=`; un link di `civitai.red`; importazione da una pagina Hugging Face vera; LoRA per adulti; pagina senza immagini; Note già scritte (conferma); anteprima da file e da Control; Aggiungi dalla riga e dal consiglio; LoRA di un'altra famiglia spento; consiglio con Qwen3-VL 8B; senza LLM.

## 11. Versioni e rilascio

- App **0.2.2** (aggiunta `loraCatalog`), plug-in **LoRA Advisor 1.0**; gli altri plug-in invariati.
- La release avrà **otto** plug-in: aggiornare la tabella «Download», il README (sezione Plug-ins) e `Plugins/README.md`.

## 12. Fuori ambito (rinviati)

- Ricerca automatica senza tasto (all'apertura o all'arrivo di LoRA nuovi).
- Ricerca dentro le versioni di un bundle; anteprime dei candidati; note ricavate dai prompt d'esempio delle immagini o dall'immagine stessa con un LLM con visione (proposte il 13 ottobre, non scelte).
- Riconoscere il LoRA dall'hash del file (Draw Things converte i LoRA: l'hash non coincide con l'originale).
- Scegliere un'altra immagine della galleria della pagina.
- Note e anteprime anche per i modelli, non solo per i LoRA.
- Modificare trigger e peso dal plug-in.
- Nomi leggibili delle famiglie.
- Pagine che richiedono l'accesso (account o chiave API).
- Altri siti oltre a Civitai e Hugging Face.

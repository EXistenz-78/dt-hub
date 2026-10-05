# DT Hub — Plug-in Prompt Master (PM)

Data: 5 ottobre 2026 · Stato: approvata il 5 ottobre 2026; tappa 1 (il contratto) realizzata, tappe 2 e 3 da fare · Estende `2026-10-03-plugin-design.md` (contratto 1), `2026-10-04-plugin-sphere-light-design.md` (come si costruisce un plug-in) e `2026-10-05-plugin-design-system-design.md` (l'aspetto dell'app)

## 1. Scopo

Prompt Master 2.0 è oggi una pagina HTML (`Prompt generator/Prompt Master 2.0`): un database di 875 termini in 40 categorie e 8 gruppi, un compositore che li ordina secondo il «dialetto» del modello, un briefing da incollare a mano in una chat, la traduzione con DeepL. Va rifatto, non portato: dentro DT Hub il plug-in conosce già il modello scelto e può usare l'LLM locale dell'app e mandare il risultato alla Generazione.

Decisioni dell'utente (5 ottobre 2026):
- **Ideogram 4 resta fuori**: sarà un plug-in a parte, che può condividere il database.
- **Il database si condivide e si aggiorna a parte**: un file JSON in una cartella comune, sostituibile senza ricompilare.
- **L'LLM fa il lavoro di composizione**: il plug-in non ordina più i termini secondo un dialetto; manda all'LLM il master prompt della famiglia, il testo dell'utente e l'elenco dei termini, e l'LLM scrive il prompt, **sempre e solo in inglese**.
- **Interfaccia**: a sinistra una card con i termini (gruppi → categorie → termini con casella); a destra due card (testo libero; termini scelti + «Scrivi prompt»). La colonna centrale del vecchio PM sparisce.
- **Famiglie**: solo quelle di `~/Library/Containers/com.liuliu.draw-things/Data/Library/Caches/net/configs.json`; per ognuna un master prompt. I master prompt vanno rivisti con una ricerca online (lavoro a parte, §9).
- **Qwen Image 2.1**: i due modelli linguistici ufficiali di prompt enhancing, `qwen3.5_9b_qwen_image_2.1_pe_t2i` e `…_pe_i2i`, sostituiscono l'LLM generico per quella famiglia. I2I si sceglie **da solo**: solo se c'è un'immagine di partenza; il Moodboard **non decide** tra T2I e I2I, ma con l'I2I si manda al modello insieme all'immagine di partenza (§7).

Fuori: Ideogram 4 e il suo compositore JSON; Midjourney e le altre famiglie non in `configs.json`; la traduzione con DeepL (la fa l'LLM); importare o esportare termini nel formato del vecchio PM; applicare da solo il formato che il PE suggerisce; la distribuzione.

## 2. Tre tappe e un lavoro a parte

| Tappa | Cosa | Perché in quest'ordine |
|---|---|---|
| **1 — DT Hub** | Il messaggio `llm` impara `system`, `model` e `options`; `context` impara l'immagine di partenza, il Moodboard e l'elenco dei modelli linguistici (§6). | Il plug-in ne ha bisogno già per il master prompt come system prompt. Serve anche ai plug-in futuri. È piccola e si prova da sola. |
| **2 — Plug-in** | Il tab di PM per le 13 famiglie con l'LLM generico, `qwen_image_2.1` compresa; la scelta del PE di Qwen quando i modelli ci sono (§7). | Utilizzabile da subito, anche senza i PE. |
| **3 — PE di Qwen** | Procurarsi i due PE in MLX e provarli dal vivo. | Esistono già conversioni MLX della comunità (§12): un download da ~5,6 GB (4 bit, scelto dall'utente il 5 ottobre) o ~9,7 GB (8 bit) per modello, fatto dall'utente o con il suo permesso. |
| **Lavoro a parte** | Revisione dei master prompt con la ricerca online e il notebook (§9). | Si consegna come file; non blocca il codice. |

Ogni tappa ha il suo piano e il suo merge. Questa spec le copre tutte.

## 3. Dati

Tre file JSON in `~/Library/Application Support/DT Hub/Data/`, ognuno con una **copia incorporata** nel plug-in (il bundle contiene solo la libreria, niente risorse: uno script genera un file Swift con il JSON in una stringa grezza, come `make-recommended-settings.py` per l'app).

| File | Contenuto | Chi lo scrive |
|---|---|---|
| `prompt-database.json` | Gruppi, categorie, termini. Condiviso con altri plug-in. | l'utente lo sostituisce per aggiornarlo |
| `prompt-master/master-prompts.json` | Per famiglia: nome, master prompt (inglese), `negative` (sì/no), `hiddenCategories`, lunghezza obiettivo. | l'utente lo sostituisce (la revisione del §9 arriva così) |
| `prompt-master/custom-terms.json` | Termini aggiunti dall'utente. | il plug-in |

**Quale versione vale.** Ogni file ha `schema` e `version`. All'avvio il plug-in legge il file della cartella; se manca, è illeggibile, ha uno `schema` che il plug-in non conosce o una `version` più vecchia di quella incorporata, vale la copia incorporata (il file illeggibile o con schema sconosciuto genera un avviso nella riga di stato, e non viene toccato). Il plug-in non scrive mai su `prompt-database.json` e su `master-prompts.json`; scrive solo i termini personali.

**Il database snellito.** Si genera da quello di PM 2.0 con `Scripts/make-prompt-data.py`, che **non modifica** l'originale (serve ancora al vecchio PM e al nodo ComfyUI). Si tengono `id` (identici), `it` ed `en` per termine; per categoria `id`, gruppo, `it`, `en` e la descrizione. Si perdono `en_tag` (diverso da `en` in 81 voci su 875) ed `en_prose` (c'è in 811 voci, pesa il doppio di `en`), `slot`, `lang_expansion`: la prosa e i tag li scrive l'LLM. Lo stesso script semina `hiddenCategories` di ogni famiglia dalle regole del vecchio database (`only_for`, `blocked_for`, `blocked_categories`).

**Le famiglie** (la chiave è la `version` di Draw Things, come `FamilyTraits`): `flux1`, `flux2`, `flux2_9b`, `flux2_4b`, `krea_2`, `qwen_image`, `qwen_image_2.1`, `z_image`, `sdxl_base_v0.9`, `v1`, `ernie_image`, `hidream_i1`, `cosmos2.5_2b` (Anima). Le varianti senza `version` (Edit, Lightning, Base, KV) arrivano con la `version` della base. Il manifesto dichiara queste 13 in `families`: sulle altre (Ideogram 4, video) il tab è grigio. Per le famiglie già descritte nel vecchio PM il primo master prompt parte dalle sue note; per `qwen_image_2.1`, `flux2`, `hidream_i1` e `cosmos2.5_2b` serve la ricerca del §9: finché non c'è, vale un master prompt generico per prosa, marcato nel file come provvisorio.

## 4. Interfaccia

Due colonne, con i componenti di `DTHubDesign` (due prodotti con alias, come Sphere Light); le stringhe in una tabella `L` (it/en).

**Sinistra — una card lunga**, a tre livelli: i **gruppi** (A–H), sotto le **categorie**, sotto i **termini** con checkbox. Gruppi e categorie si comprimono (`DSCollapsibleCard` annidate o righe equivalenti; sono chiusi all'inizio, lo stato aperto/chiuso si ricorda). Ogni riga di gruppo e di categoria mostra il numero di termini scelti. Nell'header:
- **Foto / Arte**: due pulsanti. Cambiano solo ciò che pesca lo Shuffle (come nel vecchio PM): in «Foto» le categorie fotografiche (inquadratura, angolo, composizione, ottica, genere fotografico, effetti ottici), in «Arte» quelle artistiche (movimenti, stili, artisti, supporti). Non nascondono nulla nell'elenco.
- **Shuffle**: sostituisce la selezione con un termine a caso per categoria tra quelle che la famiglia non nasconde; le categorie di supporto condividono un solo pescaggio; il gruppo H (qualità, negativo, testo) resta fuori. Lo shuffle è deterministico con un generatore passato (testabile).
- **Cerca**: filtra per `it` ed `en` senza distinguere maiuscole e accenti; gruppi e categorie con risultati si aprono da soli, il resto sparisce.
- Le categorie in `hiddenCategories` della famiglia attiva non compaiono.
- In fondo a ogni categoria: «+ Aggiungi un termine» (un campo di testo, una stringa nella lingua che vuole; vedi sotto). I termini personali hanno un segno distintivo e un cestino al passaggio del mouse.

**Destra, in alto — «Descrizione»**: un campo di testo multilinea per soggetto, scena e azione, in qualsiasi lingua. Accanto un pulsante **Shuffle scena**: chiede all'LLM un soggetto e un'ambientazione (un breve messaggio fisso, nella lingua dell'interfaccia) e li scrive nel campo; non tocca la selezione.

**Destra, in basso — «Termini scelti»**: l'elenco dei termini scelti (nome nella lingua dell'interfaccia, categoria in piccolo), ognuno con una X per toglierlo; nell'angolo in alto a destra la **X arancione** (`DS.remove`, come nel tab Control) che svuota tutto l'elenco. Sotto il pulsante **«Scrivi prompt»**, attivo se c'è del testo o almeno un termine. Mentre l'LLM lavora il pulsante dice «Sto scrivendo…» e resta disattivato (il contratto non ha l'annullamento). Una riga di stato sotto ({risultato, errori}).

**Termini personali.** Un termine personale è una stringa e una categoria; l'LLM la traduce, quindi non servono due lingue. Sta in `custom-terms.json`, separato dal database, così sostituire il database non li cancella. Non c'è importa/esporta.

**Persistenza** (UserDefaults, chiave `com.exiztenz.dthub.promptmaster.state.v1`): testo, id dei termini scelti, Foto/Arte, gruppi e categorie aperti, interruttore booru (§5).

## 5. Scrivere il prompt

«Scrivi prompt» manda un messaggio `llm` (§6) con:
- `system`: il master prompt della famiglia. Tutti chiedono **esplicitamente solo inglese**, un solo prompt, nessun commento.
- `prompt`: la richiesta, in un formato fisso: la descrizione dell'utente (nella sua lingua) e l'elenco dei termini in inglese (`en`; i personali come scritti).
- Se la famiglia usa il negativo (`negative: true`), il master prompt chiede un JSON `{"prompt": …, "negative": …}`; altrimenti basta il testo.

La risposta si ripulisce: via i blocchi `<think>…</think>` e le recinzioni ```; se è JSON si prende `prompt` (e `negative`); se non lo è vale il testo intero. Il risultato va alla Generazione con `contribute {fields: {prompt, negativePrompt?}}`; il negativo si scrive solo per le famiglie che lo usano. La riga di stato dice «Inviato» (o i conflitti, come Sphere Light).

Per `v1` e `sdxl_base_v0.9` c'è un interruttore **«Tag booru»** nel tab (Pony e Illustrious hanno la stessa famiglia di SDXL e Draw Things non li distingue): acceso, il master prompt aggiunge la regola dei tag.

## 6. Tappa 1 — Il contratto (additivo, il numero resta 1)

**Plug-in → app, `llm`.** Oggi `{prompt, images}`. Chiavi nuove, tutte facoltative:
- `system`: il system prompt della sessione;
- `model`: il nome di un modello nella cartella dell'LLM (come lo mostra `availableModels()`); l'app lo carica al posto di quello scelto nelle impostazioni, che resta com'è, e libera la memoria con la regola di inattività esistente. Se non c'è, risposta `error` («modello non trovato»): il plug-in ripiega sul generico;
- `options`: `temperature` (0–2), `topP` (0–1), `topK` (0–200), `presencePenalty` (−2–2), `maxTokens` (1–32768) e `thinking` (booleano; arriva al modello come `enable_thinking` del template di chat); i numeri fuori limite si riportano nei limiti. Senza `options` valgono i valori attuali (temperatura 0,6, 1024 token). L'attesa del plug-in (`timeout`, 300 secondi se non detto, al massimo 1800) è un parametro della libreria dei plug-in e **non viaggia** nel messaggio: l'app non ha un tempo massimo.

Il servizio MLX (`MLXLanguageModelService`) passa `system` come `instructions` della sessione e le opzioni a `GenerateParameters`/`additionalContext`. `LanguageModelManager.respond` accetta il modello da usare e lo carica con lo stesso controllo della memoria. Il kit dei plug-in (`DTHubHost.askLanguageModel` e `askLanguageModelAnswer`, che dà anche il motivo dell'errore) prende gli stessi parametri e il timeout. `context` viene rimandato anche quando l'utente torna sul tab di un plug-in, così un modello aggiunto nel frattempo compare.

**App → plug-in, `context`.** Tre chiavi nuove, facoltative: `startImage` (il percorso del file dell'immagine di partenza del tab Control, se c'è), `moodboard` (i percorsi delle immagini del Moodboard accese, nell'ordine delle miniature) e `languageModels` (nome, percorso e `supportsImages` dei modelli linguistici della cartella). Il plug-in può così cercare il PE per nome e leggerne il system prompt dalla cartella (§7). Chi non le conosce le ignora: i plug-in esistenti non cambiano.

## 7. Qwen Image 2.1 e i modelli PE

I due modelli ufficiali sono Qwen3.5-VL 9B affinati per riscrivere un prompt breve in uno dettagliato; rispondono con un JSON (`rewritten_prompt` o `positive_prompt`, e `wh_ratio`, come «3:2») dopo un blocco `<think>`. Impostazioni consigliate da Qwen: temperatura 1,0, top-p 0,95, top-k 20, presence penalty 1,5 per T2I e 0 per l'editing, fino a 16.256 token (24.000 per l'editing), thinking acceso.

**Quando si usano.** Famiglia `qwen_image_2.1` e il modello PE giusto presente nell'elenco `languageModels` (una cartella il cui nome, in minuscolo e con `-` e `.` sostituiti da `_`, contiene `qwen_image_2_1_pe_t2i` o `qwen_image_2_1_pe_i2i`: riconosce sia `qwen3.5_9b_qwen_image_2.1_pe_t2i…` sia `Qwen-Image-2.1-PE-T2I-MLX-4bit`; il resto del nome è libero e non c'è nessun percorso scritto nel codice. Se più cartelle corrispondono, per esempio 4 bit e 8 bit insieme, vale la più grande, cioè la più precisa) e, accanto, il suo `system_prompt.txt` (o `system_prompt_t2i.txt`/`system_prompt_edit.txt`; si copia dal repository Hugging Face: il testo non si incorpora, per la licenza Qwen Research). Se manca una delle due cose, vale l'LLM generico con il master prompt del file, e la riga di stato lo dice.

**T2I o I2I.** I2I se `context.startImage` c'è; altrimenti T2I. **Il Moodboard non decide**, per scelta dell'utente: con il solo Moodboard è T2I e le sue immagini non si mandano. La regola è una funzione pura (`PEPlanner`) con il suo test: cambiarla è una riga.

**Cosa si manda.** `model` = il PE scelto; `system` = il suo file; `prompt` = descrizione e termini, come al §5 senza il master prompt nostro; per I2I `images` = l'immagine di partenza e poi le immagini del Moodboard accese, nell'ordine delle miniature, al massimo 10 in tutto (il PE le legge come `<image1>`, `<image2>`…; che Draw Things dia lo stesso ordine al modello di immagine è da verificare dal vivo); `options` = le impostazioni di Qwen. Dalla risposta si prende il prompt; `wh_ratio` compare come riga «Formato consigliato: 3:2» sotto il prompt, senza cambiare la dimensione.

## 8. Codice

Un pacchetto in `Plugins/PromptMaster/` con la struttura di Sphere Light (libreria dinamica; kit e design system con `moduleAliases` `PromptMasterKit`, `PromptMasterDesign`; `Scripts/build.sh`; identificatore `com.exiztenz.dthub.promptmaster`; classe `PromptMasterEntry`; versione 1.0). Tipi puri e testabili, senza SwiftUI: `PromptDatabase` (caricamento, validazione, scelta della versione), `DataLocator` (cartella dati), `TermTree` (gruppi, categorie, ricerca, conteggi), `Shuffler`, `BriefBuilder` (messaggio per l'LLM), `AnswerParser`, `PEPlanner`, `CustomTermsStore`, `PMState`. Le viste usano `DSCollapsibleCard`, `dsPanel`, `DSPanelHeader`, `DSPillButtonStyle`, `DSCheckboxToggleStyle`.

## 9. Lavoro a parte: i master prompt

Per ognuna delle 13 famiglie si rivede il master prompt contro le fonti online (schede dei modelli, guide ufficiali, documentazione) con l'aiuto del notebook: la **struttura** consigliata (per alcuni modelli soggetto→ambiente→stile, per altri un ordine diverso), la lunghezza, cosa evitare, il negativo, il testo in immagine. Ogni master prompt dichiara l'inglese come unica lingua d'uscita. Il risultato è `master-prompts.json` con la sua `version`, sostituibile senza toccare il plug-in. Si fa dopo la tappa 2 o in parallelo; le fonti consultate si annotano nel file.

## 10. Test e verifiche

**Tappa 1** (HubCore/HubKit, PluginKit): il messaggio `llm` con le chiavi nuove si legge e, senza, vale il vecchio; `respond` con un modello da nome carica quello (servizio finto), con un nome sconosciuto dà errore, e non cambia `settings.selectedModel`; le opzioni arrivano al servizio; `context` si codifica con e senza le chiavi nuove e un plug-in vecchio lo decodifica; test dell'`options.timeout` (tetto 1800). Dal vivo: il plug-in di prova (Sample) manda un `llm` con `system` e `options` e riceve la risposta del modello locale.

**Tappa 2** (pacchetto del plug-in): `PromptDatabase` (valido; schema sconosciuto → incorporato; versione più vecchia → incorporato; file mancante); `TermTree` (ricerca senza maiuscole e accenti, conteggi, categorie nascoste); `Shuffler` (un termine per categoria, medium in un solo pescaggio, gruppo H escluso, Foto/Arte, deterministico); `BriefBuilder` (testo in lingua qualsiasi, termini in `en`, termini personali); `AnswerParser` (con `<think>`, con recinzioni, JSON con e senza `negative`, testo semplice, JSON malformato → testo intero); `PEPlanner` (nomi delle cartelle con trattini, punti e underscore; due cartelle che corrispondono, vince la più grande; T2I senza immagine, I2I con immagine di partenza, **T2I con solo Moodboard (e nessuna immagine mandata)**, I2I con immagine di partenza e Moodboard (l'immagine di partenza per prima, al massimo 10), PE mancante, system prompt mancante); `CustomTermsStore` (aggiunta, cancellazione, sopravvive alla sostituzione del database); `Strings` (it/en stesse chiavi). Dal vivo con l'istanza isolata: il tab, una selezione e «Scrivi prompt» con il modello locale (Qwen3-VL-2B) che mette il prompt in Generazione; una famiglia che usa il negativo e una no; il tab grigio su `ideogram_4`; lo stesso database sostituito a mano e riletto; riavvio con lo stato ricordato.

**Tappa 3**: i due PE convertiti compaiono in `languageModels`, T2I senza e I2I con immagine di partenza producono un prompt e un `wh_ratio` leggibili.

## 11. Decisioni prese da me (da correggere se non vanno)

- Il database snellito tiene `id`, `it`, `en`; i termini personali sono una stringa sola; sono in un file separato.
- Foto/Arte guida solo lo Shuffle, non l'elenco.
- Le categorie che una famiglia non usa sono nascoste, non grigie.
- Lo «Shuffle scena» scrive nella lingua dell'interfaccia.
- Il negativo si chiede all'LLM solo per le famiglie che lo usano, e solo per quelle si scrive nel campo.
- Il `system_prompt.txt` del PE non si incorpora: lo copia l'utente nella cartella del modello.
- Il formato suggerito dal PE si mostra, non si applica.
- Nessun pulsante di annullamento durante la scrittura (il contratto non lo prevede).

## 12. Rischi aperti

- **I PE vanno procurati in MLX.** I file in `Downloads` sono nel formato di Draw Things (`int8_convrot`, un solo `.safetensors`, senza `config.json`); lo scanner dell'LLM non li vede. Esistono conversioni della comunità, non ufficiali: `prithivMLmods/Qwen-Image-2.1-PE-T2I-MLX` e `…-PE-I2I-MLX` (fatte con `mlx-vlm`, torre visiva intatta; BF16 ~17,5 GB nella radice, `8bit/` ~9,7 GB e `4bit/` ~5,6 GB in sottocartelle). Da verificare dopo il download: che ogni variante abbia `config.json`, tokenizer e template di chat, e che `mlx-swift-lm` la carichi. Lo scanner cerca `config.json` al massimo due livelli sotto la cartella dei modelli: una sottocartella `8bit/` dentro `publisher/modello/` sarebbe troppo profonda, quindi la variante scelta va scaricata in una cartella propria (per esempio `prithivMLmods/Qwen-Image-2.1-PE-T2I-MLX-8bit`). Il `system_prompt` va comunque copiato dal repository ufficiale. Le versioni «Heretic»/«Abliterated» sono modifiche non volute e non si usano. Finché non ci sono, `qwen_image_2.1` usa il generico.
- **La qualità dell'LLM generico decide la qualità degli altri 12 master prompt.** Oggi nella cartella MLX c'è solo Qwen3-VL-2B 4 bit: per un prompt buono ne serve uno più grande. È una scelta dell'utente, non del plug-in.
- **Moodboard e I2I.** La nota di Draw Things dice che Qwen Image 2.1 legge le immagini di riferimento dal canvas **e** dal Moodboard. Con il solo Moodboard il PE T2I scrive un prompt che non sa nulla di quelle immagini: per scelta dell'utente quel caso resta T2I e le immagini non si mandano; da riprovare dopo la prova dal vivo (backlog: «Famiglie che leggono il Moodboard»). Con l'immagine di partenza e il Moodboard insieme, il PE I2I li riceve tutti; l'ordine in cui Draw Things li dà al modello di immagine (immagine di partenza per prima?) è da verificare.
- **Thinking lungo.** Un PE da 9 B con thinking acceso può metterci minuti; per questo `timeout` entra nel contratto e il pulsante resta occupato con un testo chiaro.
- **Memoria.** Caricare un PE da 9 B mentre il modello di immagine è in memoria: vale la regola esistente (libera il server se le impostazioni lo dicono); altrimenti l'app dice che la memoria non basta.
- **Master prompt provvisori** per `qwen_image_2.1`, `flux2`, `hidream_i1` e `cosmos2.5_2b` fino alla ricerca del §9.
- Il plug-in non è firmato né notarizzato: la distribuzione ad altri è un lavoro a parte.

# DT Hub — Design dei plug-in scaricabili (M8)

Data: 3 ottobre 2026 · Stato: M8a e M8b realizzate · **Sostituisce** nella spec principale (`2026-09-29-dt-hub-core-design.md`) la parte di §4 "Plugins/… un pacchetto per plug-in" e il *modo di consegna* del contratto di §8 (che resta valido per il contenuto: contributi, conflitti, pipeline).

## 1. Scopo

I plug-in sono **pacchetti che si scaricano a parte** e si aggiungono a DT Hub solo se servono, senza ricompilare l'app. Le funzioni specializzate (Prompt Master, Sphere Light, Qwen Image 2.1) arrivano così.

Decisioni dell'utente (3 ottobre 2026):
- un plug-in è un **bundle caricato dentro l'app** (non un programma separato, non un insieme di soli dati);
- **si installa scaricando il file a mano** e aggiungendolo dalle Preferenze (o trascinandolo): niente catalogo nell'app, niente installazione da indirizzo web;
- le Preferenze avranno, quando esisterà, **un link alla pagina GitHub** da cui scaricare i plug-in; finché la pagina non c'è, il link non compare;
- spec principale §8 invariata nel contenuto: i contributi sono sempre visibili prima del Run (ora **evidenziati in teal nei campi, senza una card a parte**), un plug-in non cambia mai il modello e non lancia generazioni da solo.

## 2. Il pacchetto: `.dthubplugin`

Un bundle macOS (cartella) con:
- `Contents/Info.plist`: `CFBundleIdentifier` (l'identificatore del plug-in, unico), `CFBundleName`, `CFBundleShortVersionString`, `CFBundleExecutable`, `NSPrincipalClass`, `DTHubContract` (intero: la versione del contratto per cui è fatto);
- `Contents/MacOS/<eseguibile>` (codice compilato per arm64, firmato almeno ad hoc: i binari arm64 senza firma non partono; il linker firma ad hoc da sé);
- `Contents/Resources/…` (risorse proprie).

Il **manifesto** vero e proprio lo restituisce il codice (`dthubManifest`, JSON): `id` (= `CFBundleIdentifier`), `name`, `version`, `contract`, `symbol` (nome di un SF Symbol per l'icona), `families` (elenco di famiglie di modello; assente = tutte).

## 3. Il confine tra app e plug-in (contratto versione 1)

Verificato con un prototipo (3 ottobre 2026): **nessun codice Swift è condiviso** tra app e plug-in, quindi il plug-in non dipende dalla versione del compilatore né dalla build di HubKit. Si parlano con selettori Objective-C e messaggi JSON.

La classe principale (`NSPrincipalClass`, sottoclasse di `NSObject`) risponde a:
- `dthubManifest() -> Data`: il manifesto (JSON);
- `dthubMakeViewController() -> NSViewController`: la vista del tab del plug-in (di solito `NSHostingController` con una vista SwiftUI);
- `dthubStart(_ host: NSObject)`: l'app consegna l'oggetto **host**, che risponde a `dthubSend(_ message: Data, reply: @escaping (Data) -> Void)` (il plug-in parla all'app);
- `dthubHandle(_ message: Data, reply: @escaping (Data) -> Void)`: l'app parla al plug-in.

**Messaggi:** JSON `{"type": "...", …}`, con una risposta JSON. Un messaggio sconosciuto riceve `{"type":"unsupported"}` e non è un errore.
- *App → plug-in*: `context` (parametri correnti in sola lettura, modello e famiglia scelti, catalogo di modelli e LoRA, cartella temporanea per le immagini), `activate`, `deactivate`;
- *plug-in → app*: `notice` (un avviso da mostrare), e in M8b `contribute` (parametri, prompt, negativo, immagine di partenza, moodboard, maschera, pipeline) e `llm` (una richiesta al servizio di linguaggio, spec principale §9).
- Le **immagini** non viaggiano nei messaggi: si scambiano come file PNG nella cartella temporanea del contesto.

**Versione del contratto.** L'app dichiara l'insieme delle versioni che capisce (all'inizio solo la 1). Un plug-in con una versione che non c'è si rifiuta con un messaggio ("serve DT Hub più recente" / "plug-in per un contratto non più supportato"). I messaggi nuovi si aggiungono senza cambiare versione; si cambia versione solo se cambia il significato di quelli esistenti.

**`DTHubPluginKit`.** Un pacchetto Swift nel repository, che gli autori usano al posto di HubKit: tipi `Codable` del contratto (manifesto, messaggi, contributi), un protocollo `DTHubPlugin` (identificatore, nome, vista, gestione dei messaggi) e una classe base `DTHubPluginEntry` che implementa i selettori sopra e instrada verso il protocollo. Non dipende da HubKit né dal resto dell'app. Un plug-in di esempio (il bundle di prova) vive nel repository ed è anche il modello da copiare.

## 4. Installazione e gestione (Preferenze → Plug-in)

- Un elenco dei plug-in installati: nome, versione, stato (**spento**, **acceso**, **non caricabile** con il motivo) e, per ognuno, l'interruttore e "Rimuovi".
- **Aggiungi…** (scelta del file) o **trascinamento** del `.dthubplugin` sul pannello. DT Hub legge il manifesto, mostra nome, versione e l'avviso "**Questo plug-in esegue codice sul tuo Mac con gli stessi permessi di DT Hub**", e solo dopo la conferma lo copia in `~/Library/Application Support/DT Hub/Plug-ins/<identificatore>.dthubplugin`.
- Un plug-in appena installato è **acceso dall'installazione** (l'utente ha appena confermato: cambiato il 3 ottobre 2026; un aggiornamento lascia l'interruttore com'era). Acceso, si carica **all'avvio successivo** (il codice caricato non si scarica: lo stato mostra "si carica al prossimo avvio"). Spegnerlo o rimuoverlo ha effetto allo stesso modo al prossimo avvio.
- Se si aggiunge un plug-in con lo stesso identificatore: la versione più alta sostituisce quella installata (dopo conferma), efficace al prossimo avvio; la stessa versione o una più bassa si rifiuta con un messaggio.
- Dopo la conferma si toglie dalla copia l'attributo di quarantena (`com.apple.quarantine`) lasciato dal download. **Da verificare dal vivo** con un file scaricato davvero (il prototipo non l'ha provato).
- **Due interruttori, due scopi** (confermato dall'utente): quello delle Preferenze decide se il codice si **carica all'avvio** (spento, il codice non gira mai: serve soprattutto a fermare un plug-in che dà problemi senza cancellarlo); quello del menu dell'header decide se un plug-in già caricato **conta per il lavoro in corso**.
- **Riavvia DT Hub:** quando una modifica aspetta il riavvio (un plug-in acceso o spento, aggiornato, installato o rimosso mentre era caricato), le Preferenze mostrano il pulsante "Riavvia DT Hub".
- **Versione:** la riga mostra la versione installata; se quella in uso è più vecchia lo dice ("è in uso la versione X; la Y dal prossimo avvio").
- **Avvisi dei plug-in:** il banner conta 8 secondi mentre la finestra è quella in uso; l'ultimo avviso di ogni plug-in resta sotto la sua riga nelle Preferenze.
- Il **link alla pagina GitHub** dei plug-in: un indirizzo nelle Preferenze; compare solo quando è impostato.
- **Header → menu Plug-in** (spec principale §7): elenca i plug-in **accesi** e li attiva o disattiva per il lavoro in corso (decide se il loro tab e i loro contributi contano); grigio se incompatibile con la famiglia del modello scelto.

## 5. Caricamento

All'avvio l'app scandisce la cartella dei plug-in. Per ognuno: legge `Info.plist`, controlla `DTHubContract`, l'unicità dell'identificatore e (dopo il caricamento) che il manifesto coincida. Carica (`Bundle.load()`) solo quelli **accesi**. Ogni problema (bundle illeggibile, contratto non supportato, manifesto diverso, classe principale mancante) diventa lo stato "non caricabile" con il motivo, **senza far cadere l'app**.

Il codice di un plug-in gira nel processo dell'app: **un suo crash fa cadere DT Hub**. Rischio accettato, mitigato così: l'installazione si conferma con un avviso; tenendo premuto ⌥ all'avvio non si carica nessun plug-in; le Preferenze permettono di spegnere o rimuovere.

## 6. Firma e permessi

L'app ha il *hardened runtime*; per caricare un bundle firmato da altri (o solo ad hoc) serve l'entitlement `com.apple.security.cs.disable-library-validation`, che si aggiunge al target (un file `.entitlements`). Verificato nel prototipo: con l'entitlement il bundle si carica e risponde; senza, un'app firmata con *hardened runtime* rifiuta le librerie firmate da un'altra identità. L'app non è in sandbox (`ENABLE_APP_SANDBOX = NO`, già così). Firma e notarizzazione per distribuire l'app a terzi restano fuori.

## 7. Contributi, conflitti, pipeline (M8b)

Il contenuto è quello della spec principale §8, trasportato dai messaggi `contribute` e `llm`. **Non c'è una card Contributi** né un "impostato da" (deciso dall'utente il 3 ottobre 2026): i contributi si vedono nei campi stessi. Niente blocchi e niente tasti per sbloccare: **un campo è sempre modificabile**.

**Come si comporta un campo di Generazione**
1. Un plug-in manda un valore per il campo: il campo prende un **teal al 30%** e mostra quel valore.
2. L'utente lo modifica a mano: il teal sparisce e **accanto al suo valore resta, tra parentesi, quello inviato dal plug-in** (per riferimento, per esempio `Passi 30 (24)`). **Prompt e negativo fanno eccezione: nessun valore tra parentesi**, il campo perde solo il teal.
3. Lo **stesso plug-in** manda un altro valore: si riparte dal punto 1, anche sopra le modifiche manuali.
4. **Al Run parte quello che c'è nel campo in quel momento**; il valore tra parentesi è solo un riferimento.
5. Spegnere un plug-in (dalle Preferenze o dal menu dell'header per questo lavoro) toglie il suo teal e le sue parentesi: i valori restano nei campi come valori manuali.

**Conflitto** (l'unico caso): un plug-in **diverso** manda un valore a un campo che porta ancora il valore di un altro plug-in (campo in teal o con il valore tra parentesi). Compare un **pop-up** con il nome del campo e **due pulsanti**: «<plug-in A> · <valore>» e «<plug-in B> · <valore>»; quello che si sceglie prevale e va nel campo con il teal. Se più campi sono in conflitto insieme, un solo pop-up li elenca tutti, ciascuno con i suoi due pulsanti. Chiuderlo con Esc lascia i campi come sono. Il pop-up è modale: non esiste uno stato "conflitto in sospeso" e il Run non viene mai bloccato per questo.

**Altri contributi, stessa regola**
- **Immagine di partenza e maschera:** nelle schede del tab Control, con la provenienza del plug-in (spec del tab Control §7); sono un solo valore, quindi se due plug-in ne propongono una vale lo stesso pop-up. Le immagini del **Moodboard** invece si sommano (vedi sotto).
- **Pipeline** (lista ordinata di passaggi: modifiche alla configurazione, ingressi, se l'output precedente diventa l'immagine di partenza): **sul pulsante Run**, che diventa «Run · N passaggi» in teal, con i passaggi elencati nel suggerimento. Se due plug-in ne propongono una, lo stesso pop-up fa scegliere («<plug-in> · N passaggi»). Non essendo un campo, si toglie dal menu contestuale del pulsante («Togli la pipeline»). Senza pipeline, il Run esegue un solo passaggio con la configurazione corrente.
- **LoRA e Moodboard si sommano** (sono liste): i LoRA e le immagini che arrivano da plug-in diversi si **aggiungono** alla lista, ciascuno col suo teal al 30% (e, per le immagini, la provenienza del plug-in), e non c'è mai un pop-up. Lo stesso LoRA già presente prende il peso dell'ultimo plug-in che lo manda. Spegnere il plug-in toglie il teal e lascia le voci in lista come manuali.
- Un plug-in non cambia mai il modello e non lancia generazioni da solo.
I messaggi di M8b e le scelte fatte nel prototipo sono al §11.

## 8. Test e verifiche

**Unitari (HubCore):** lettura e validazione di `Info.plist` e del manifesto (campi mancanti, contratto non supportato, identificatore diverso dal bundle); scansione della cartella (bundle validi, rotti, duplicati); installazione (copia, rifiuto di versione uguale o più bassa, sostituzione con versione più alta, rimozione); stati (spento, acceso, non caricabile con motivo); l'interruttore e la conferma; ⌥ all'avvio.
**Con un bundle vero:** il bundle di prova del repository si carica e risponde a manifesto, vista e messaggio (come nel prototipo); un bundle con contratto sbagliato è "non caricabile" senza far cadere nulla.
**Dal vivo:** installare da un file scaricato davvero (quarantena); app con l'entitlement.

## 9. Tappe

| Tappa | Contenuto | Esito |
|---|---|---|
| **M8a** | `DTHubPluginKit`, bundle di prova, entitlement, scansione e caricamento, installazione/rimozione e Preferenze → Plug-in, messaggi `context`, `activate`, `notice`, il menu Plug-in dell'header | si installa e si accende un plug-in che mostra il proprio tab |
| **M8b** | Messaggi `contribute` e `llm`, campi in teal con il valore del plug-in tra parentesi dopo una modifica manuale, pop-up di scelta nei conflitti, schede del tab Control con provenienza, pipeline sul pulsante Run | un plug-in contribuisce e il Run lo esegue |
| Poi | Prompt Master, Sphere Light, Qwen Image 2.1: ognuno a parte, come suo `.dthubplugin` | |

## 10. Fuori e rischi

**Fuori:** catalogo o negozio nell'app; installazione da indirizzo web; scaricamento a caldo del codice; plug-in in un processo separato; firma e notarizzazione per la distribuzione.
**Rischi:** il codice di un plug-in può far cadere l'app o fare qualunque cosa possa fare DT Hub (l'utente lo conferma all'installazione); la quarantena dei file scaricati non è provata; un cambio del significato dei messaggi richiede una nuova versione del contratto e un aggiornamento dei plug-in.

## 11. I messaggi di M8b (verificati in un prototipo il 4 ottobre 2026)

Il contratto resta la **versione 1**: i nuovi messaggi sono aggiunte, e un'app che non li conosce risponde `{"type":"unsupported"}`. Tutti viaggiano come JSON nello stesso canale di M8a; solo un plug-in **attivo per il lavoro** (menu dell'header) può mandarli, gli altri ricevono `{"type":"error","text":…}`.

**`contribute`** (plug-in → app). Ogni chiave è facoltativa; ciò che non si legge è lasciato fuori e non è un errore. Risposta `{"type":"ok","conflicts":n}` (più `problems` se un'immagine non si è potuta leggere); i conflitti li risolve l'utente nel pop-up, la risposta non aspetta.
- `fields`: `prompt`, `negativePrompt` (testo); `width`, `height`, `steps`, `cfgZeroInitSteps`, `seed`, `batchSize`, `batchCount` (interi); `guidanceScale`, `shift` (numeri); `cfgZeroStar`, `resolutionDependentShift`, `randomSeed` (booleani); `sampler` (numero Draw Things o nome). Sono i campi delle card Prompt, Dimensioni, Campionamento, Seed e batch. I valori si limitano come fanno le card (`clamped()`), e il segno sul campo ricorda il valore **già limitato**. Il modello, le card Avanzate e la forza non si possono contribuire (backlog).
- `loras`: `[{file, weight, mode, trigger}]`, si aggiungono; lo stesso file già presente prende peso, modo e trigger nuovi.
- `moodboard`: `[{path, name}]` (file nella cartella temporanea del plug-in), si aggiungono con provenienza «da <plug-in>»; se **lo stesso** plug-in le rimanda, sostituiscono quelle che aveva mandato (e che sono ancora lì).
- `startImage`: `{path, name}`, l'immagine di partenza del tab Control (provenienza del plug-in); la maschera non si può contribuire in M8b (backlog).
- `pipeline`: `{name, steps: [{title, fields, loras, moodboard, startImage, useOutputAsStart}]}`. Il passaggio esegue i campi del tab con le sue modifiche sopra; `loras` e `moodboard` del passaggio **sostituiscono** quelli del tab per quel passaggio (`[]` = nessuno), se assenti restano quelli del tab; `startImage` o l'output del passaggio precedente (`useOutputAsStart`) sostituiscono l'immagine di partenza (inquadrata sul canvas del passaggio, senza la maschera del tab).

**`llm`** (plug-in → app): `{prompt, images:[percorsi]}` → `{"type":"llm","text":…}` oppure `error` (nessun modello scelto, immagini non supportate…). La risposta può tardare (il modello si carica); la libreria dei plug-in aspetta fino a 300 secondi.

**Scelte del prototipo.**
- Un campo prende il teal finché **contiene** il valore del plug-in; se l'utente lo modifica compare il valore tra parentesi, e se riscrive lo stesso valore il teal torna. Prompt e negativo: teal, mai parentesi. Il segno non si salva: al riavvio i valori restano, senza teal.
- Conflitto: solo se un **altro** plug-in manda un valore **diverso** da quello che il plug-in precedente aveva mandato, anche se l'utente nel frattempo l'ha cambiato. Valori uguali: nessun pop-up, il segno passa al nuovo plug-in. Lo stesso plug-in che chiede due volte la stessa cosa sostituisce la domanda precedente. Esc lascia tutto com'è.
- La pipeline resta sul pulsante Run finché non la si toglie («Togli la pipeline», menu contestuale del pulsante) o il plug-in si spegne: non si consuma al Run. Ogni passaggio è una generazione normale e le sue immagini vanno nella striscia dei Risultati; un passaggio che fallisce o Stop fermano la pipeline; il campo Seed non si aggiorna.
- **Più plug-in nello stesso processo:** ognuno porta la propria copia di `DTHubPluginKit`; due copie con lo stesso nome di modulo definiscono due volte le stesse classi Objective-C ("Class … is implemented in both"). Ogni plug-in deve dare alla propria copia un nome di modulo suo con `moduleAliases` in `Package.swift` (il sorgente continua a fare `import DTHubPluginKit`); il plug-in di esempio lo fa e il README lo dice.
- Il plug-in di esempio 1.2 (e la sua variante B, per provare i conflitti) manda tutto questo e risponde a un messaggio `press` (come premere un pulsante), usato dai test.

> **Aggiornato il 4 ottobre 2026:** i passaggi della pipeline con `fields` e `loras` qui sopra sono sostituiti da passaggi che nominano un preset (`2026-10-04-preset-pipeline-design.md`).

# LoRA Turbo ed Edit nell'app

Data: 2026-11-17. Tocca l'app (`App/`, `Packages/Sources/HubCore`, `HubKit`, `HubMCP`). Segue `2026-11-17-lora-advisor-categorie-design.md` (LoRA Advisor 1.7, già in `main`), che registra per ogni LoRA nel `loras.json` dell'app: `category` (`character`, `style`, `slider`, `edit`, `turbo`), e per le Turbo `steps`, `guidance`, `shift`. Il catalogo dell'app (`CatalogLoRA`) li porta già; nessuno li usa ancora.

## Scopo

1. **Turbo.** Quando una LoRA Turbo viene attivata, l'app imposta da sola steps, guidance e shift che la LoRA porta con sé.
2. **Edit.** Una LoRA Edit attiva rende Edit anche il modello: tutto ciò che dipende dal fatto che il modello sia Edit (schede e controlli, forza dell'immagine di partenza, plug-in per modelli edit, piano di calcolo, agente) lo tratta come Edit. Esempio: con MOSS Image e una LoRA edit selezionata, i plug-in per i modelli edit si attivano.

## Obiettivi, non-obiettivi, anti-obiettivi

**Obiettivi:** attivare una LoRA Turbo basta per generare con i suoi parametri; togliere la LoRA riporta i valori di prima; «modello Edit» ha una sola definizione nell'app.

**Non-obiettivi:** mostrare o modificare la categoria nel gestore LoRA; usare la categoria nei consigli di Advise; modifiche al plug-in LoRA Advisor; pubblicazione (serve il via libera dell'utente ed è fuori da questo lavoro).

**Anti-obiettivi:** sovrascrivere i valori di un preset, di un progetto o di un «recall» appena caricati; perdere un valore che l'utente ha cambiato a mano dopo l'attivazione; far apparire parametri turbo su una LoRA che non è Turbo; che due punti dell'app discordino su cosa sia un modello Edit.

## Vincoli

- I valori Turbo vengono dal catalogo (`CatalogLoRA.category == "turbo"` e `steps`, `guidance`, `shift` non nulli); un campo nil non si tocca.
- Gli intervalli sono quelli dei parametri di generazione (`GenerationParameters`: steps, guidanceScale, shift); un valore fuori intervallo viene riportato dentro, mai rifiutato.
- Preset, progetti e «recall» impostano l'elenco delle LoRA in blocco: non passano dai punti di attivazione e non devono mai essere toccati.
- Tutte le aggiunte e rimozioni interattive, dell'agente (MCP `add_lora`/`remove_lora`) e dei plug-in (`contribute`) devono dare lo stesso risultato.
- Stile del progetto: Swift 6, Swift Testing, logica pura in HubCore con test, il controller resta sottile; stringhe in italiano e inglese.

## Approcci considerati

Per l'attivazione Turbo:
- **A. Ogni aggiunta e rimozione passa dal controller (scelta dell'utente).** La scheda LoRA (`LoRACard`, oggi `parameters.addLoRA` diretto), l'agente (`AppAgentHost.addLoRA`) e i plug-in (`ContributionStore`) usano lo stesso punto di ingresso (`GenerationController.addLoRA` / `removeLoRA` / sostituzione). Lì si applicano e si ripristinano i valori. Preset e progetti restano fuori per costruzione.
- **B. Osservare `parameters.loras`.** Un solo punto, ma «cambia di una sola LoRA» scambierebbe un preset con una LoRA per un'aggiunta e ne riscriverebbe gli steps. Scartato.
- **C. Applicare i valori solo al RUN senza toccare i campi.** Scartato dall'utente.

Per Edit: una definizione unica «modello edit oppure LoRA edit attiva» al posto delle letture sparse di `capabilities.isEditModel`. Iniettare il flag nelle capacità del modello, o limitarlo al controllo dei plug-in, lascerebbe la scheda Control e la forza dell'immagine incoerenti con i plug-in: scartati.

## Il design

### 1. Turbo: attivazione e ripristino (scelta B dell'utente: ripristino se non toccati)

Logica pura in HubCore, per esempio un tipo `TurboLoRAs` (nome a scelta del costruttore) che lavora su `GenerationParameters` e sul catalogo, senza dipendere dall'interfaccia.

- **Attivazione** (una LoRA si aggiunge, o sostituisce un'altra): se nel catalogo è Turbo e ha almeno un valore tra steps/guidance/shift, si salva un'istantanea `before` dei tre parametri correnti, si impostano i valori non nil (riportati negli intervalli) e si registra l'attivazione `{file, before, applied}` in una pila. I valori che l'utente ha già in `parameters` prima dell'aggiunta sono quelli salvati in `before`. Una LoRA già presente (aggiornamento del peso) non è un'attivazione.
- **Più Turbo:** vale l'ultima aggiunta; ogni attivazione salva i valori che trovava.
- **Rimozione** (o sostituzione di una LoRA con un'altra): per ogni parametro, se il valore corrente è ancora uguale a quello applicato da quell'attivazione si ripristina, altrimenti si lascia quello dell'utente. Si ripristina il `before` dell'attivazione; se sotto nella pila c'è un'altra Turbo ancora attiva, il ripristino ne riapplica i valori al posto di `before`. Togliere una Turbo che non è l'ultima (non è quella attualmente applicata) la elimina dalla pila e le attivazioni sopra ereditano il suo `before` per i parametri il cui `before` era uguale ai valori che essa aveva applicato, così togliere poi la più recente non riporta valori di una LoRA che non c'è più.
- **Azzeramento della pila:** quando l'elenco delle LoRA viene sostituito in blocco (preset, progetto, recall, reset dei valori del modello) o cambia il modello. Il valore dei parametri resta com'è.
- **Sostituzione** (`replaceLoRA`): equivale a rimozione della vecchia e attivazione della nuova, nello stesso passaggio.
- **Modifiche a mano** dopo l'attivazione non vengono mai riapplicate né contrastate.
- Il cambiamento deve essere visibile in modo minimo (scelta mia da controllare: la riga della LoRA dice che ha impostato steps/guidance/shift; il costruttore decide la forma).

I punti di ingresso da portare sul controller: `App/Generation/Cards/LoRACard.swift` (aggiunta, rimozione, sostituzione), `App/Agent/AppAgentHost.swift` (`addLoRA`, rimozione), `ContributionStore` (`contribute.loras`, già su `GenerationController.addLoRA`; da verificare anche la rimozione).

### 2. Edit: una definizione unica

Una funzione pura in HubCore, per esempio `isEditModel(model: CatalogModel?, loras: [LoRASelection], catalog: ModelCatalog) -> Bool`: vera se il modello è Edit (`capabilities.isEditModel`) oppure una LoRA selezionata è `category == "edit"` nel catalogo. Si sostituisce con essa ogni lettura di `capabilities.isEditModel` che riguarda il modello scelto:
- `GenerationController.isEditModel()` e chi lo usa (scheda Generazione `GenerationTabView`, controlli dell'immagine di partenza `StartImageControls`, forza `JobComposer.usesFullStrength`, `cuPasses`);
- il contesto dei plug-in (`MainWindowView.contextKey`, `PluginContextKey.isEditModel`: deve cambiare anche quando cambia l'elenco delle LoRA, così i plug-in per modelli edit compaiono e spariscono subito) e `plugins.startImageStrength` in `DTHubApp`;
- l'agente (`AppAgentHost`: stato e controllo di compatibilità dei plug-in).
Per i passi di una pipeline (`GenerationController` ~603, `CUPlanner` ~73) si usano le LoRA del passo, se il passo le dichiara; altrimenti solo il modello.

**Da verificare dal vivo (costruttore):** con un modello non Edit (MOSS Image) e una LoRA edit, le immagini del Moodboard vengono davvero inviate come riferimenti alla generazione; se la generazione non lo fa per i modelli non Edit, va deciso con l'utente (non qui).

### 3. Test e documenti

- Test puri in HubCore: attivazione (valori nil, fuori intervallo, LoRA non Turbo, LoRA senza valori), ripristino (invariati, cambiati a mano, parziale), più Turbo in ordine e rimozione fuori ordine, sostituzione, azzeramento (blocco, cambio modello), `isEditModel` (modello edit, LoRA edit, entrambi, nessuno, file sconosciuto al catalogo).
- Test dei punti di ingresso: la scheda LoRA, l'agente e il contributo di un plug-in producono lo stesso risultato; un preset con una LoRA Turbo non cambia i suoi steps.
- Test del contesto dei plug-in: aggiungere una LoRA edit cambia `isEditModel` e rifà il contesto.
- Documenti: README principale (funzioni e sezione degli strumenti MCP se cambia il comportamento di `add_lora`), `PluginKit/README.md` se il significato di `isEditModel` nel contesto cambia, spec del server MCP se serve. Il briefing si aggiorna alla pubblicazione, non qui.

## Decisioni mie (da controllare)

- Una sola Turbo applicata alla volta (l'ultima aggiunta); ripristino a pila con ereditarietà del `before`.
- Azzeramento della pila su sostituzione in blocco della lista e su cambio modello.
- Avviso minimo visibile che la LoRA ha impostato i parametri.
- Edit per passi di pipeline: LoRA del passo se dichiarate.
- Nessun cambiamento al gestore LoRA, ad Advise, al plug-in.

## Lasciato al costruttore

Nomi dei tipi e dei file; forma esatta dell'avviso; come ottenere le LoRA di un passo di pipeline; dove vivono esattamente le intestazioni delle schede che dipendono da «Edit»; come l'agente comunica all'utente il cambio dei parametri.

# Selettore dei modelli con DT+ — Design

Data: 16 ottobre 2026. Stato: disegno approvato in chat dall'utente, sezione per sezione; da rivedere per iscritto prima del piano.
Base: `main` **0.2.3** (`12cfd1b`), ramo `feat/model-picker` (worktree `.worktrees/model-picker`, indipendente dal ramo `feat/cu-meter`).

## 1. Obiettivo

Con DT+ acceso il menu dei modelli è lunghissimo (605 voci) e **non mostra i modelli Official** che il cloud ha. Si sostituisce, **solo con DT+ acceso**, con un pannello con **ricerca** e un albero **collassabile** a due livelli: **Official / Community / Uncurated** e, dentro, le **famiglie**.

## 2. Decisioni (dell'utente, 16 ottobre)

- **Tre liste**, come in Draw Things: **Official** (nel codice dell'app; 129 voci, 16 segnate `deprecated`), **Community** (`models.json`, 253 voci), **Uncurated** (`uncurated_models.json`, 384 voci). Le pubblica insieme `https://kcjerrell.github.io/dt-models/` (`official_models.json`, `community_models.json`, `uncurated_models.json`); su `models.drawthings.ai` ci sono solo le ultime due.
- **Con DT+ spento non cambia niente:** il menu di oggi, con i modelli installati raggruppati per famiglia, indipendentemente dalle liste.
- **Con DT+ acceso:** pannello con campo di ricerca in cima e albero a due livelli collassabili (livello 1: origine; livello 2: famiglia). **Aperto solo Official**; Community, Uncurated e tutte le famiglie chiusi.
- **Modelli locali con DT+ acceso:** se sono in una lista compaiono nella lista (li distingue solo l'assenza della nuvola); se **non** sono in nessuna lista, **sono nascosti dal pannello**; restano nel catalogo (senza origine), così se uno è il modello scelto RUN lo trova e il pulsante ne mostra il nome (revisione del 16 ott: toglierli dal catalogo bloccava RUN).
- **Due scelte dell'assistente** (approvate con la sezione): lo stato aperto/chiuso resta finché l'app è in esecuzione e riparte dallo stato iniziale a ogni avvio; all'apertura il cursore è nel campo di ricerca, Esc chiude il pannello.

## 3. Fonti

- Briefing §7 e nota Obsidian «DT Hub - Fonti esterne»; backlog «DT+: le tre liste di modelli».
- Misure del 16 ott 2026 sull'echo del cloud (1 444 file): Official 107 di 129, Community 224 di 253, Uncurated 381 di 384; nessuna sovrapposizione tra le tre liste; nessun Official è in `models.json`, in `uncurated_models.json` né nelle specifiche incluse nella libreria DrawThings-Swift 2.2.0.
- I campi dell'Official sono in camelCase (`defaultScale`, `textEncoder`, `deprecated`, `autoencoder`, `prefix`, `version`, `file`, `name`) e sono meno completi di quelli delle altre due liste (per esempio nessun `modifier`): i metadati degli Official sono ricavati da Swift (README di `kcjerrell/dt-models`).

## 4. Dati

- **`ModelSource`** in `HubKit/Catalog`: `official`, `community`, `uncurated` (con ordine fisso di visualizzazione in quest'ordine). **`CatalogModel.source: ModelSource?`** (nil fuori da DT+); `init` con default nil.
- **Terza lista:** `LiveModelList.official` (stessa `CachedDownload`, cache `…/DT Hub/official-models-list.json`, un download per avvio, nuovo tentativo dopo 10 minuti). Il suo lettore converte ogni voce nel JSON di specifica che il resto del codice già capisce (`defaultScale` → `default_scale`, `textEncoder` → `text_encoder`; `file`, `name`, `version`, `prefix`, `autoencoder` invariati) e restituisce a parte l'insieme dei file `deprecated`.
- **Nomi corretti nel codice:** oggi `LiveModelList.shared` è `models.json` (chiamata «official» nei commenti) e `LiveModelList.community` è `uncurated_models.json`. Diventano `LiveModelList.community` e `LiveModelList.uncurated`; i commenti, il briefing e la nota Obsidian si correggono. I **nomi dei file di cache restano** (`models-list.json`, `community-models-list.json`), perché non si perdano le copie già salvate.
- **Origine di un modello:** dal nome del file; se è in più liste vince Official, poi Community, poi Uncurated.
- **`CatalogBuilder.cloudCatalog`** (DT+ acceso, elenco del cloud noto): modelli = quelli **locali presenti nel cloud e in almeno una lista** (tengono la descrizione del server, ricevono l'origine) più i **remoti** (in una lista, nel cloud, non installati; segnati `isRemote`). Esclusi dal catalogo: gli Official `deprecated` non installati. I locali fuori lista restano nel catalogo con `source == nil` e `ModelCatalog.modelsBySource` non li elenca (nascosti dal pannello). Senza l'elenco del cloud (mai ottenuto) resta il ripiego di oggi (tutti i modelli delle liste), ora con l'origine.
- **Raggruppamento:** `ModelCatalog.modelsBySource` → `[ModelSourceGroup]` (origine, conteggio, `[ModelFamilyGroup]`), accanto a `modelsByFamily` che resta invariato (lo usa il menu con DT+ spento).
- **La richiesta di generazione** di un modello **non installato** registra la sua specifica dalle liste (`registerRemoteSpec` cerca in Official, Community, Uncurated); per un modello installato non si registra niente: vale la specifica del server (quella più scarna degli Official non deve sostituirla). **Da verificare nella fase 2** (prova dell'utente) che il cloud esegua un Official dal solo elenco.

## 5. Interfaccia (solo con DT+ acceso)

- Il pulsante del modello resta come oggi (nome, famiglia, freccina). Con DT+ spento apre il menu attuale; con DT+ acceso apre un **pannello** (popover) sotto di esso.
- **Pannello:** larghezza circa 340 pt, altezza massima circa 420 pt con scorrimento. In alto il campo di ricerca (cursore pronto all'apertura); sotto l'albero:
  - **Livello 1:** Official, Community, Uncurated, ciascuno con il numero di modelli in intestazione (i modelli dopo il filtro, quando c'è una ricerca).
  - **Livello 2:** le famiglie (la chiave della famiglia, come nel menu di oggi; senza famiglia in coda).
  - **Righe:** nome del modello; nuvola per i remoti; spunta sul modello scelto; clic = sceglie e chiude il pannello (`generation.chooseModel`).
- **Stato iniziale:** solo Official aperto. Le famiglie chiuse.
- **Ricerca:** nel nome, nel nome del file e nella famiglia, senza distinguere maiuscole e accenti (`localizedStandardContains`). Con testo nel campo i gruppi (di entrambi i livelli) con risultati sono aperti, gli altri nascosti; cancellando il testo si torna allo stato aperto/chiuso di prima. Nessun risultato: «Nessun modello».
- **Stati vuoti:** gli stessi messaggi del menu di oggi (non collegato, ricerca modelli spenta sul server, nessun modello).
- **Accessibilità:** etichette per VoiceOver su gruppi e righe (nome, nuvola «in cloud», scelto).
- **Struttura del codice:** la logica pura sta in `HubCore` (`ModelTree`: albero, filtro, conteggi, stato aperto/chiuso); la vista nuova in `App/MainWindow/ModelPickerView.swift`; `HeaderBar.modelMenu` sceglie fra menu attuale e pannello in base al DT+.

## 6. Errori e casi limite

- Elenco Official non scaricabile e mai salvato (per esempio il sito di dt-models non risponde): con DT+ acceso mancano nel pannello gli Official non scaricati e quelli installati, ma il catalogo si costruisce lo stesso e un modello installato scelto continua a girare.
- Il modello scelto non è nelle liste (per esempio un locale fuori lista con DT+ appena acceso): il pulsante continua a mostrarne il nome; il pannello non lo elenca.
- Famiglia sconosciuta (nil): gruppo «—» in coda, come oggi.
- Il numero di voci è alto (600+): le viste dell'albero si costruiscono pigramente (solo i gruppi aperti), e il filtro lavora su dati già in memoria.

## 7. Test (prima il test visto fallire)

1. **`ModelTree` (HubCore):** stato iniziale (solo Official aperto, famiglie chiuse), conteggi, ordine Official / Community / Uncurated e famiglie in ordine naturale, gruppo vuoto omesso; ricerca per nome, file e famiglia con accenti e maiuscole; apertura automatica dei gruppi con risultati e ritorno allo stato precedente a ricerca vuota; nessun risultato.
2. **Lettore dell'Official (DTBridge):** conversione camelCase → specifica, insieme dei `deprecated`, copia su disco con rete assente.
3. **`CatalogBuilder.cloudCatalog`:** origine assegnata con la priorità (Official > Community > Uncurated); locali fuori lista nascosti; Official deprecati nascosti se non installati e visibili se installati; con DT+ spento nessun cambio (test esistenti).
4. **Catalogo dei testi** (italiano e inglese) e `ModelCatalogTests` esistenti.
5. **Prove a mano dell'utente:** albero con DT+ acceso, ricerca, un Official non scaricato che gira.

## 8. Fasi

1. Origine, terza lista, nomi corretti, catalogo DT+ (HubKit, DTBridge) con i test: gli Official non scaricati compaiono nell'elenco di DT+ (nel menu di oggi, senza ancora l'albero).
2. **Prova dell'utente (non si può fare prima della fase 1: i modelli Official non sono ancora nell'elenco):** con DT+ acceso e una build di quel ramo, un Official non scaricato (per esempio FLUX.1 schnell) gira dal solo elenco? In Draw Things sì (è il senso di DT+); resta da vedere in DT Hub, dove la richiesta porta una specifica ridotta. Se no, si decide con l'utente come completare i dati di quel modello prima di proseguire.
3. `ModelTree` in HubCore con i test.
4. Pannello, collegamento nell'header, testi in italiano e inglese.
5. Revisione dell'intero ramo, README, prove a mano, backlog e briefing.

## 9. Rischi

- **Official non eseguibili dal solo elenco:** metadati meno completi (nessun modificatore e altro) e libreria che non li conosce. Lo chiude la prova della fase 2, subito dopo la fase 1 e prima dell'albero. In Draw Things l'uso senza scaricare è proprio il senso di DT+.
- **Conflitti con `feat/cu-meter`:** entrambi toccano `HeaderBar`, `CatalogBuilder` e `CloudCatalog`, in punti diversi; il secondo ramo a essere unito risolve i conflitti.
- **Cosa il cloud esegue davvero:** i file Uncurated ci sono (381 di 384) ma un utente di Discord ha avuto «accesso solo a modelli locali e community» con LTX; non si sa se il cloud li esegua tutti.
- **Dati di terzi:** `kcjerrell.github.io/dt-models` non è di Draw Things; se sparisce, l'Official resta quello salvato in cache.

## 10. Fuori ambito

Il menu con DT+ spento; raggruppare le quantizzazioni; ricordare lo stato aperto/chiuso tra un avvio e l'altro; preferiti e ordine personale; le liste dei LoRA; i modelli video.

## 11. Punti aperti

- Il nome dei gruppi in italiano: «Official», «Community», «Uncurated» restano in inglese (sono i nomi delle liste in Draw Things).
- Se la prova della fase 2 mostra che un Official richiede più dati, la spec va rivista per quel punto.

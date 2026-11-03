# Aggiornamento automatico di DT Hub e dei plug-in — disegno

Data: 3 novembre 2026. Stato: da approvare (spec), poi piano.

## Obiettivo

Oggi chi ha DT Hub deve accorgersi da solo che esiste una versione nuova, scaricare lo zip dell'app e quello di ogni plug-in dal release su GitHub, sostituire l'app a mano e aggiungere i plug-in uno per uno da Preferenze. L'obiettivo della 1.0.0 è che l'app **controlli da sola, all'avvio, se il repository `EXistenz-78/dt-hub` ha un release più nuovo**, lo dica con un avviso discreto e, **solo dopo la conferma dell'utente**, scarichi e installi la nuova app e **soltanto i plug-in che sono davvero più nuovi di quelli installati**.

## Cosa dice l'utente (requisiti)

1. Il controllo avviene da solo all'avvio; **scaricare e installare avviene solo dopo un dialogo** che dice cosa, da dove e quanto (come il download del modello LLM).
2. La versione di ogni plug-in pubblicata si legge da **un manifest nel release**, con versione e sha256 per plug-in.
3. L'app **si sostituisce da sola** (non solo «mostra in Finder»), senza dipendenze pesanti (niente Sparkle).
4. L'avviso è un **banner nell'app** più una scheda in **Preferenze › Aggiornamenti**.
5. Si verifica il **sha256** di ogni file prima di installarlo.
6. Offline o con un errore, l'avvio non si disturba; nessun dato di nessuno viene inviato.

Supposizione (da correggere se sbagliata): chi usa DT Hub ha lo stesso Mac per Draw Things e per l'app, e l'app sta in `/Applications` o in una cartella dell'utente; quindi lo scambio in sede è il caso normale e il ripiego «mostra in Finder» il raro.

## Fuori ambito (prima versione)

- Installare plug-in **nuovi** (non presenti sul Mac): si aggiornano solo quelli già installati.
- Scaricare il gRPCServerCLI di Draw Things: resta come oggi (`ServerVersion`, solo avviso).
- Aggiornamenti differenziali, canali beta, ritorno a una versione precedente.
- Intel o altre architetture: il manifest nomina un solo zip dell'app (`arm64`).
- Una chiave di firma propria per l'app: resta firmata ad-hoc.

## Cosa si è verificato (3 novembre 2026, sola lettura)

- `ServerVersionChecker` / `GitHubReleases.fetch()` (`HubCore/Server/ServerVersion.swift`) fanno già una richiesta a GitHub all'avvio con `URLSession`, ricordano l'ultimo esito e tacciono quando la rete manca: è il modello da imitare.
- Il release `v0.9.0` ha 16 asset: `DT-Hub-0.9.0-macOS-arm64.zip` e un `<Nome>.dthubplugin.zip` per plug-in (15). GitHub dà per ciascuno un `digest` sha256, ma la **versione** di un plug-in sta solo nel suo `Contents/Info.plist` (`CFBundleShortVersionString`), dentro lo zip.
- `PluginFolder.install(_:info:)` rifiuta già una versione non più alta e toglie `com.apple.quarantine`; `PluginRegistry.offer(for:)` e `install(_:)` sono il flusso da riusare. `PluginVersion` confronta già le versioni numero per numero.
- L'app non è in sandbox (`ENABLE_APP_SANDBOX = NO`); l'entitlement è solo `disable-library-validation`. `MARKETING_VERSION` è 0.9.0 nel progetto.
- `api.github.com` senza token concede 60 richieste all'ora per indirizzo; `github.com/<repo>/releases/latest/download/<asset>` è un reindirizzamento ai file e non conta in quel limite.

## Scelte

### 1. Il manifest `dthub-release.json`

Un asset in più di ogni release, generato dagli zip veri e caricato per ultimo:

```json
{
  "schema": 1,
  "tag": "v1.0.0",
  "app": {"version": "1.0.0", "asset": "DT-Hub-1.0.0-macOS-arm64.zip", "sha256": "…", "size": 26296563},
  "plugins": [
    {"id": "com.exiztenz.dthub.promptmasteri4", "name": "Prompt Master I4", "version": "1.2",
     "contract": 1, "asset": "PromptMasterI4.dthubplugin.zip", "sha256": "…", "size": 608492}
  ]
}
```

Il sha256 sta solo qui: il file nasce dagli zip pubblicati, quindi non c'è una seconda fonte da far concordare. `ReleaseManifest` (in `HubCore/Updates/`) lo decodifica e lo valida: `schema == 1`, `tag` non vuoto, versioni non vuote, nomi di asset senza `/` né `..`, sha256 di 64 cifre esadecimali. Un `schema` più alto, o un manifest che non passa la validazione, vale «nessuna informazione».

Lo genera un nuovo `Scripts/make_release_manifest.py <tag> <cartella-degli-zip>` (Python, come gli altri script): legge la versione e l'identificatore dall'`Info.plist` di ogni `.dthubplugin.zip` (scompattato in temp), la versione dell'app dallo zip dell'app, calcola sha256 e dimensione.

### 2. Il controllo

`UpdateChecker.check(installed:)` fa **una sola richiesta**: `GET https://github.com/EXistenz-78/dt-hub/releases/latest/download/dthub-release.json` (timeout 15 s, nessuna intestazione che non serva). `releases/latest` salta bozze e prerelease. Niente API di GitHub: il limite delle 60 richieste non entra in gioco.

`fetch` è iniettato (come `ServerVersionChecker.releases`): ritorna `Data?`; nil = rete assente, HTTP diverso da 200 o timeout.

`UpdatePlan.make(manifest:, appVersion:, plugins:, supportedContracts:)` produce l'elenco delle offerte:

- **App**: se `PluginVersion(app.version) > PluginVersion(versione in esecuzione)`.
- **Plug-in**: per ogni identificatore **già installato** (`PluginFolder.scan()`), se la versione del manifest è più alta. Un plug-in non installato non si propone. Un plug-in con `contract` non supportato dall'app in esecuzione (`PluginContract.supported`) non si propone finché l'app non è aggiornata: dopo il riavvio il controllo successivo lo prende.
- Una voce che l'utente ha già rifiutato con «Più tardi» alla **stessa versione** (o a una più alta di quella offerta) non rientra nel banner; resta visibile in Preferenze.

### 3. Quando si controlla

All'avvio, se l'interruttore «Controlla all'avvio» è acceso (acceso all'inizio) e dall'ultimo controllo sono passate **12 ore** (`UserDefaults`: `updates.lastCheck`, `updates.checkOnLaunch`). Se è spento non si fa nessuna richiesta di rete. «Controlla ora» in Preferenze forza il controllo. Il controllo parte in un `Task` dopo l'avvio e non blocca nulla.

### 4. Offline, errori, limite

- Controllo all'avvio che fallisce: **silenzio**; si riprova al lancio seguente (non si aggiorna `updates.lastCheck`).
- Controllo da «Controlla ora» che fallisce: messaggio chiaro in Preferenze («Non riesco a raggiungere GitHub»).
- Release senza manifest (come la 0.9.0): stesso trattamento, ma il messaggio dice «Questo release non ha informazioni per l'aggiornamento automatico».
- L'ultimo piano calcolato non si conserva tra gli avvii: serve solo l'ora dell'ultimo controllo riuscito e le versioni rifiutate.

### 5. Il dialogo e il download

«Dettagli…» (dal banner o da Preferenze) apre un foglio con: la versione attuale e la nuova dell'app, ogni plug-in con «1.1 → 1.2», la dimensione di ciascuno e il totale, «da github.com/EXistenz-78/dt-hub», un link alle note del release (`/releases/tag/<tag>`), una casella per voce (accese) e due pulsanti: **Scarica e installa** e **Più tardi**.

`UpdateInstaller` esegue, voce per voce:

1. scarica `https://github.com/EXistenz-78/dt-hub/releases/download/<tag>/<asset>` in una cartella temporanea nuova (`URLSession.download`, con progresso);
2. verifica il sha256 contro il manifest (a blocchi di 4 MiB, come `ServerVersionChecker.sha256`); se non coincide il file si scarta e la voce fallisce;
3. scompatta con `/usr/bin/ditto -x -k` in una cartella vuota;
4. per un plug-in: legge il bundle con `PluginBundleReader`, controlla che identificatore e versione coincidano con il manifest, poi `PluginRegistry.offer(for:)` e `install(_:)`; l'effetto vale dal riavvio, come oggi;
5. per l'app: vedi il punto 6.

Si installano prima i plug-in e poi l'app; una voce che fallisce non ferma le altre. L'esito di ogni voce (installata, fallita con il motivo) compare nel foglio e in Preferenze.

### 6. Sostituire l'app

`AppReplacer.replace(running:, with:)` lavora sul `.app` scompattato:

1. controlli: `CFBundleIdentifier` uguale a quello in esecuzione, versione più alta, `codesign --verify --deep --strict` riuscito (iniettato nei test);
2. toglie la quarantena dal bundle (`PluginFolder.removeQuarantine`, da rendere interno al modulo);
3. se la cartella che contiene l'app è scrivibile: sposta il vecchio `.app` in una cartella temporanea, muove il nuovo al suo posto e, se qualcosa va storto, rimette il vecchio; a scambio riuscito il vecchio si butta nel Cestino (`trashItem`), non si cancella;
4. se non è scrivibile (o il percorso è su un disco montato o in App Translocation): lascia il `.app` scompattato in `~/Downloads` e lo mostra in Finder; l'utente lo trascina in `/Applications`;
5. fine: con lo scambio fatto compare **Riavvia ora** (o **Più tardi**). Il riavvio lancia un `sh -c 'while kill -0 <pid>; do sleep 0.2; done; open "<percorso>"'` staccato e poi chiude l'app. Con **Più tardi** il nuovo `.app` è già al suo posto e parte al prossimo lancio.

### 7. L'interfaccia

- **Banner** sopra il contenuto di `MainWindowView`: «Disponibile DT Hub 1.0.0 e 3 plug-in» con **Dettagli…** e **Più tardi**. Compare solo quando ci sono offerte non rifiutate.
- **Preferenze › Aggiornamenti** (nuova scheda dopo «Plug-in», icona `arrow.down.circle`): versione in uso, ora dell'ultimo controllo, interruttore «Controlla all'avvio», **Controlla ora**, e lo stesso elenco di offerte con **Dettagli…**.
- **Più tardi** salva, per ogni identificatore (`app` per l'app), la versione rifiutata (`updates.dismissed`: dizionario id → versione). Una versione più alta di quella rifiutata rimette l'offerta.
- Testi in `App/Localizable.xcstrings`, inglese e italiano, chiavi `updates.*`.

## Dati e file toccati

Nuovi in `Packages/Sources/HubCore/Updates/`: `ReleaseManifest.swift`, `UpdatePlan.swift`, `UpdateChecker.swift`, `UpdateInstaller.swift`, `AppReplacer.swift`, `UpdateSettings.swift` (frequenza, interruttore, rifiuti). Test in `Packages/Tests/HubCoreTests/`.

Il controller (`UpdateController`, `@Observable`, a stati) sta in `HubCore/Updates/` per poterlo provare con i test. Nuovi nell'app: `UpdateBanner.swift`, `UpdateDetailsSheet.swift`, `UpdatesPreferencesView.swift`.

Nuovo: `Scripts/make_release_manifest.py` con il suo test.

Modificati: `App/DTHubApp.swift` (costruzione e controllo all'avvio), `App/Preferences/PreferencesView.swift` (la scheda), `App/MainWindow/MainWindowView.swift` (il banner), `PluginFolder.swift` (`removeQuarantine` visibile al modulo), `App/Localizable.xcstrings`, `README.md` e `Plugins/README.md`.

La base degli indirizzi si può cambiare con `defaults write com.exiztenz.DTHub debug.updateBaseURL <url>` (solo per la prova con un release locale, come `debug.keepGuidedSessionFiles`); senza, vale quella di GitHub.

Non toccati: `PluginRegistry`, `ServerVersion`, `PluginKit`, i plug-in.

## Errori e casi limite

- Rete assente, timeout, HTTP ≠ 200, JSON illeggibile, `schema` più alto del noto: nessun avviso all'avvio (vedi §4).
- Sha256 diverso: il file si scarta, nulla si installa, la voce risulta fallita.
- Zip con più di un bundle, o bundle con identificatore o versione diversi da quelli del manifest: fallita.
- `codesign` non riesce, bundle id diverso o versione non più alta: l'app non si sostituisce.
- Spazio disco o permessi: errore; il vecchio `.app` resta al suo posto.
- Il manifest propone una versione dell'app più bassa o uguale: nessuna offerta (mai un ritorno indietro).
- Due controlli insieme (avvio e «Controlla ora»): il secondo aspetta il primo.
- Il download è interrotto (app chiusa): la cartella temporanea resta e il sistema la pulisce; al lancio dopo si ricomincia.
- Il foglio è aperto e arriva un secondo controllo: l'elenco mostrato non cambia finché il foglio non si chiude.

## Test

- `ReleaseManifest`: un esempio valido; `schema` 2; nomi di asset con `/` o `..`; sha256 non esadecimale; campi mancanti.
- `UpdatePlan`: app più nuova / uguale / più vecchia; versioni `1.10` > `1.9`; un plug-in non installato non si propone; uno con contratto non supportato non si propone; rifiuto alla stessa versione (nascosta) e offerta di una versione più alta del rifiuto (riappare).
- `UpdateChecker`: `fetch` che dà nil, dati non validi, dati validi; la frequenza di 12 ore e l'interruttore (nessuna richiesta quando è spento, nessuna prima delle 12 ore, una dopo).
- `UpdateInstaller` con `download`, `unzip` e `sha256` iniettati e cartelle temporanee: tutto bene; sha256 diverso; bundle con id o versione sbagliati; una voce che fallisce non ferma le altre.
- `AppReplacer` con un finto `.app` in una cartella temporanea: scambio riuscito, rollback quando il passo finale fallisce, cartella non scrivibile → ripiego su Finder, `codesign` che fallisce, bundle id diverso.
- `UpdateController`: macchina a stati con tutto iniettato (rifiuto, errore, installazione).
- `make_release_manifest.py`: prova con due zip finti; il manifest prodotto passa `ReleaseManifest`.
- Prova vera, fuori dalla sandbox: una release di prova su GitHub (repo di prova o pre-release) con un'app e un plug-in più nuovi; si avvia una build 0.9.x, si vede il banner, si accetta e si controlla che l'app si riavvii nella versione nuova e il plug-in sia aggiornato. Se la release di prova non si può pubblicare, si prova con un server locale e `fetch` sostituito.

## Da decidere nel piano (non blocca la spec)

- Il nome esatto dello script di riavvio (`sh` staccato) e come provarlo senza riavviare davvero l'app.
- Se `trashItem` del vecchio `.app` funziona anche con l'app ancora in esecuzione (si prova dal vivo).
- Dove compare l'esito per ogni voce nel foglio (elenco con segni o righe di stato).
- Come generare il release di prova senza toccare il repository pubblico.

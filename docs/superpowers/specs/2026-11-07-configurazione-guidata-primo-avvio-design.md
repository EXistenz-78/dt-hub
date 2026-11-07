# Configurazione guidata al primo avvio: design

Data: 2026-11-07. Stato: bozza per revisione.

## Obiettivo

Al primo avvio di DT Hub su un Mac pulito compare uno sheet sulla finestra principale che porta l'utente, passo dopo
passo, ad avere l'app pronta a generare: un server Draw Things raggiungibile, una cartella di output, e (facoltativo)
un modello linguistico per Enhance/Generate Prompt. Chi aggiorna da una versione precedente non lo vede.

Non è un sostituto delle Preferenze (⌘,): è un percorso breve che scrive nelle stesse impostazioni, con la stessa
logica. Tutto ciò che si fa qui si può rifare nelle Preferenze.

## Decisioni già prese con l'utente

- Passi: **Server Draw Things**, **Cartella di output**, **Modello linguistico**. Aggiornamenti e privacy restano fuori.
- Presentazione: **sheet** su `MainWindowView`, con Indietro / Avanti / Salta, riapribile da **Aiuto → Configurazione
  guidata**.
- Viste dei passi: **nuove e snelle** (approccio B), che chiamano la logica già esistente. Niente incorporamento dei
  Form delle Preferenze.
- Server: l'utente può configurare **Draw Things (server già attivo), il ServerCLI, o entrambi**. Non si può andare
  avanti se **almeno uno** non è valido. Per il ServerCLI il link di download e il pulsante per scegliere il binario
  compaiono **da subito**, senza clic aggiuntivi.

## Stato "primo avvio"

- Chiave UserDefaults `onboarding.completed` (Bool). Impostata a `true` quando lo sheet si chiude in qualunque modo
  (Fine o Salta).
- `OnboardingGate.shouldShow(defaults:)`, funzione pura in HubCore, vera solo se `onboarding.completed` non è vero **e**
  non esistono già le chiavi `drawThings.connection` o `drawThings.managedServer`. Così chi ha già usato l'app non vede
  nulla dopo l'aggiornamento. Le due chiavi sono quelle di `ConnectionSettingsStore` e `ManagedServerSettingsStore`:
  la spec le legge da lì, non le duplica come stringhe.
- Riaprire da menu ignora il flag e parte dallo stato attuale delle impostazioni, precompilato.

## Architettura

- `OnboardingState` (`@Observable`, `@MainActor`, in `App/Onboarding/`): passo corrente, regole di avanzamento,
  `isPresented`. Nessuna dipendenza da SwiftUI.
- `OnboardingSheet` (SwiftUI): contenitore con titolo, indicatore dei passi, barra Indietro/Salta/Avanti; mostra la vista
  del passo corrente.
- Una vista per passo: `OnboardingWelcomeStep`, `OnboardingServerStep`, `OnboardingOutputStep`,
  `OnboardingLanguageStep`, `OnboardingDoneStep`.
- Cablaggio in `DTHubApp`: un `OnboardingState` creato in `init()`, passato a `MainWindowView` (che applica
  `.sheet(isPresented:)`) e a un `CommandGroup(.help)` per la voce di menu.
- Nessun nuovo accesso al disco o alla rete oltre a quello già fatto dai controller esistenti.

## Passo: Server

Due blocchi indipendenti, entrambi sempre visibili:

1. **Draw Things già attivo** (`ConnectionSettings`): host, porta, TLS, segreto condiviso, con validazione di
   `ConnectionSettings.validationError`. Valido = nessun errore di validazione.
2. **ServerCLI avviato da DT Hub** (`ManagedServerSettings`): campo binario con pulsante **Scegli…**, campo cartella
   modelli con **Scegli…** e **Usa quella dell'app Draw Things**, porta. Il binario è precompilato con
   `CLILocator.find()`. Se il binario manca o non è eseguibile, il **link ai download**
   (`releases` di draw-things-community) è mostrato **subito**, non dopo un errore. Valido =
   `ManagedServerSettings.validationError() == nil`.

Regole:

- **Avanti è disabilitato finché almeno un blocco è configurato.** Il ServerCLI è configurato quando è valido (il
  binario non è mai vuoto per default, quindi è una scelta deliberata). Draw Things già attivo ha un valore predefinito
  sempre valido (`localhost:7859`), quindi conta come configurato solo dopo che l'utente ha premuto **Connetti**.
- Se **solo uno** è valido, quello diventa la modalità attiva (`ManagedServerSettings.mode`).
- Se **entrambi** sono validi, compare un selettore "Quale usare ora?" con default su **Draw Things già attivo**
  (nessun processo da avviare); l'altro resta salvato e si può attivare dal pallino di stato come oggi
  (`switchServer()`).
- Il pulsante **Connetti** chiama `connection.apply(...)` e mostra lo stato in tempo reale (`connection.indicator`),
  come la scheda Draw Things delle Preferenze. Una connessione fallita **non** blocca Avanti: l'utente ha comunque
  impostato un server valido ed è libero di avviarlo dopo. L'errore resta visibile.
- Le bozze restano locali al passo fino a Connetti o Avanti, come nelle Preferenze; Avanti applica se ci sono
  modifiche non applicate.

## Passo: Cartella di output

Mostra la cartella predefinita (`controller.outputFolder`), **Scegli…** e **Mostra nel Finder**. Applica con
`controller.setOutputFolder(_:)` e `projects.refresh()`, come `OutputPreferencesView`. Avanti è sempre abilitato: la
cartella predefinita è già valida.

## Passo: Modello linguistico (facoltativo)

Due vie, come nelle Preferenze, ridotte al minimo:

- **LM Studio**: indirizzo (precompilato), **Prova**, elenco dei modelli trovati.
- **Cartella MLX**: cartella dei modelli, e **Scarica il modello consigliato** con la conferma che nomina dimensione e
  destinazione (stessa finestra di conferma delle Preferenze, nessun download senza consenso). Avanzamento e
  annullamento tramite `LanguageModelDownloadController`.

Avanti e Salta sono sempre abilitati. La scelta di famiglia/uso per ogni modello **non** è nello sheet: resta nelle
Preferenze. Un download avviato prosegue anche se lo sheet si chiude, perché appartiene all'app.

## Passo: Fine

Riepilogo di una riga per ogni passo (Server: modalità e stato; Output: cartella; Modello: scelto/saltato) e pulsante
**Inizia**, che imposta `onboarding.completed` e chiude lo sheet.

## Errori e casi limite

- Chiusura con Esc o Salta: `onboarding.completed = true`; nessuna impostazione parziale viene scartata (ciò che è
  stato applicato resta).
- Cartella modelli senza permesso macOS: stessi avvisi e `PrivacySettingsLink` delle Preferenze.
- Server managed che non parte: l'errore è quello di `ManagedServerText`, già usato altrove.
- Nessuna rete: il link di download resta visibile; nessuna chiamata di rete fatta dallo sheet oltre alla connessione
  al server e al download esplicitamente richiesto.

## Localizzazione

Tutte le stringhe in `Localizable.xcstrings`, chiavi `onboarding.*`, italiano e inglese come il resto dell'app.
Riuso delle chiavi `prefs.*` esistenti dove il testo è identico, per non duplicare.

## Test

- HubCore (unit): `OnboardingGate.shouldShow` (pulito / già completato / chiavi di connessione presenti).
- App (unit): `OnboardingState` — ordine dei passi, Avanti disabilitato senza server valido, abilitato con uno dei due,
  selettore della modalità solo con entrambi validi e default su "già attivo".
- Verifica manuale in app: `defaults delete com.exiztenz.DTHub` per simulare l'installazione pulita; poi scenari: solo
  Draw Things, solo CLI (con e senza binario), entrambi, aggiornamento da versione esistente (nessuno sheet), riapertura
  da menu.

## Fuori ambito

Aggiornamenti e privacy, scelta di famiglia/uso dei modelli linguistici, plug-in, tour dell'interfaccia.

## Decisioni confermate in revisione

1. Con entrambi i server validi il selettore parte su "Draw Things già attivo".
2. Voce di menu "Aiuto → Configurazione guidata": confermata (l'app oggi non ha un menu Aiuto personalizzato, va aggiunto).

# CU Meter — Design

Data: 15 ottobre 2026. Stato: disegno approvato in chat dall'utente, sezione per sezione; da rivedere per iscritto prima del piano.
Base: `main` **0.2.3** (`12cfd1b`).

## 1. Obiettivo

Con DT+ acceso, mostrare **prima del RUN** quanto la generazione si avvicina al limite di **Compute Units (CU) per RUN**, così l'utente sa se deve abbassare passi o risoluzione, o usare un boost.

Un abbonato a DT+ ha fino a **40 000 CU per RUN**; se un RUN ne richiede di più deve ridurre i parametri o acquistare dei **boost**, ognuno dei quali alza il limite di **20 000 CU** (più boost si possono usare su uno stesso RUN). Draw Things calcola la stima in anticipo, in locale, e la mostra in una barra nell'app; DT Hub oggi non la mostra, ed è la lacuna principale di compatibilità con DT+.

## 2. Decisioni (dell'utente, 15 ottobre)

- **Il calcolo è quello ufficiale di Draw Things**, portato in `DTBridge`: il server non restituisce la stima (la fa l'app prima di mandare il lavoro al cloud), quindi DT Hub deve calcolarla.
- **Famiglie di immagini moderne:** Z Image, Qwen Image (anche 2.1), FLUX.1, FLUX.2 (9B, 4B), Krea 2, Ideogram 4, ERNIE, SD3 (e Large), PixArt, AuraFlow, HiDream, SeedVR2. Fuori dal primo giro: video (DT Hub non genera video) e SD 1.5 / SDXL / Kandinsky / Wurstchen (UNet, i due file più grandi: la famiglia non coperta mostra «—»).
- **Visibile solo con DT+ acceso**, nell'**header, accanto all'interruttore DT+**.
- **Le soglie si leggono dal server**, non si scrivono nel codice: l'echo a `compute.drawthings.ai:443` (lo stesso che `CloudCatalog` già fa, senza account); si usa il valore `plus`.
- **Verifica:** i test ufficiali portati **più 6–8 letture reali** della barra CU nell'app Draw Things, date dall'utente.
- **Non blocca il RUN:** DT Hub avvisa, lo decide il cloud.
- **DT++ (100 000 CU) non è pubblico** (se ne parla solo come desiderio su Discord): non va previsto. Il codice non deve però dare per scontato 40 000.
- **Verificato dall'utente il 15 ottobre 2026 sull'app Draw Things:** soglia **40 000** CU e **+20 000 per boost**.

## 3. Fonti

Raccolte nel briefing (`docs/superpowers/briefing-prossima-sessione.md`, §7) e nella nota Obsidian «DT Hub - Fonti esterne». Per questo lavoro:

- `drawthingsai/draw-things-community` (GPL-3.0, come DT Hub): `Libraries/ModelZoo/Sources/ComputeUnits.swift` (formula, bias, soglie, boost), `Libraries/SwiftDiffusion/Sources/Models/InstructionCount/*.swift` (conteggio delle operazioni per architettura), `Libraries/ModelZoo/Tests/ComputeUnitsTests.swift` (coefficienti di calibrazione), `imageService.proto` (`ComputeUnitThreshold`, `EchoReply.thresholds`).
- Formula (dal sorgente letto): `CU = ⌈ (istruzioniMain × passi × max(forza, 0,05) + istruzioniFixed) × 5,14816e-12 × bias ⌉`; `bias` 1,0 per le famiglie del primo giro (2,5 per le UNet, fuori dal primo giro).
- Il sorgente dà **`perBoost = 60000`** e un limite dopo *n* boost di `max(soglia, (n−1)·60000 + max(soglia, 60000))`: **diverge dalla verifica dell'utente (+20 000 per boost).** Vale la verifica dell'utente; il sorgente può essere di una versione diversa dell'app.

## 4. Architettura

Solo `DTBridge` conosce la libreria Draw Things; il resto dell'app no (spec principale §4).

- **`HubKit` (tipi neutri):** `CUEstimate` (valore, soglia, boost necessari, stato `ok` / `vicino` / `oltre`) e un protocollo per chi stima.
- **`DTBridge/ComputeUnits/`:** il port. Un file per famiglia (stesse funzioni del codice ufficiale), un file di base con le primitive (matmul, attenzione) e la formula con i boost, e una tabella famiglia → funzione (la chiave è quella che DT Hub già usa, per esempio `flux2_9b`). Intestazione di licenza e attribuzione con i commit ufficiali da cui si porta. Famiglia non coperta → nessuna stima.
- **Ingressi:** modello e famiglia, larghezza e altezza di partenza, passi, strength, batch size, presenza dell'immagine di partenza, numero di immagini di riferimento (Moodboard e modelli «edit»), CFG attivo o no, lunghezza del testo del modello in token (dalla specifica del modello).
- **Soglie:** una lettura per avvio con cache su disco e nuovo tentativo dopo 10 minuti (come `CloudCatalog`); si usa `plus`, o `community` se manca.
- **App:** `CUMeterView` in `HeaderBar`, accanto a `dtPlusButton`; compare solo con `connection.dtPlus && connection.canUseDTPlus`.

## 5. Comportamento

- **Cosa si misura:** una richiesta, cioè un passaggio del RUN. Il **batch size** moltiplica le CU (entra nel conteggio); il **batch count** no (richieste separate, ognuna col suo limite).
- **Pipeline di preset, Batch plus, plug-in:** si mostra il **passaggio più pesante**; nel popover il passaggio e il suo valore.
- **Stati** (soglia dal server, per esempio 40 000): verde fino al 90 %; ambra («vicino») dal 90 % al 100 %; rosso («oltre») sopra il limite, con «serve 1 boost» / «servono N boost» (limite dopo *n* boost = soglia + 20 000 × *n*; boost necessari = ⌈(CU − soglia) / 20 000⌉). Il margine del 90 % copre il caso visto su Discord (39 972 sulla barra e boost chiesto lo stesso).
- **Header:** indicatore compatto, per esempio `32,4k / 40k`, con barra sottile. Il popover al clic mostra il valore esatto, le CU senza il Moodboard, il passaggio più pesante e i boost necessari.
- **Casi senza stima:** famiglia non coperta, specifica mancante o soglie non lette → «—» con una riga che spiega perché (con le soglie non lette ma la stima possibile: solo «32,4k CU», senza barra).
- **Si ricalcola** a ogni cambio di modello, dimensioni, passi, strength, batch size, immagine di partenza o Moodboard: è un calcolo locale.

## 6. Errori e casi limite

- Soglie non leggibili (offline o echo senza soglie): valore senza barra; se c'è la copia su disco, si usa finché non scade. Nessun limite scritto nel codice.
- Modello DT+ non scaricato: la famiglia viene dalla specifica registrata, quindi il calcolo funziona come per i modelli locali.
- Valori fuori misura (passi o dimensioni a zero): 0, come il codice ufficiale; il misuratore resta spento.
- Nessun dato dell'utente viene scritto e nessuna connessione nuova oltre all'echo già esistente.

## 7. Test (prima il test visto fallire, poi il codice)

1. I test di `ComputeUnitsTests.swift` portati (coefficienti per famiglia, dimensioni piccole).
2. **Riferimenti reali:** le 6–8 letture dell'utente (famiglia, dimensioni, passi, batch, strength, Moodboard sì o no).
3. Formula e boost, con casi sul limite (39 972, 40 000, 40 001, 60 000, 60 001).
4. Soglie: lettura, cache, scadenza, risposta senza `plus`.
5. Vista (verde, ambra, rosso, «—») e passaggio più pesante di una pipeline.
6. Prova a mano dell'utente: DT+ acceso, il numero in header coincide con quello dell'app Draw Things; alzando i passi cambiano i colori.

## 8. Fasi

1. **Prova di lettura delle soglie:** l'echo a `compute.drawthings.ai` restituisce `plus` senza account, e `DrawThingsClient` espone `thresholds`? Se no, si ferma e si torna al disegno.
2. Port delle primitive e del primo gruppo di famiglie, con i test ufficiali.
3. Letture dell'utente come test di riferimento.
4. Formula e boost.
5. Tipi in `HubKit`, lettura delle soglie e integrazione con parametri e pipeline.
6. Vista in header (italiano e inglese in `Localizable.xcstrings`), revisione finale, comandi per le prove a mano.

## 9. Rischi

- **Allineamento:** ogni famiglia nuova di Draw Things mostra «—» finché non si porta; il costo è basso e visibile, non un errore silenzioso. Le funzioni portate vanno riconfrontate con il sorgente ufficiale quando cambia.
- **Versione del sorgente:** il codice letto può non coincidere con l'app dell'utente; per questo i test a valori reali (fase 3).
- **Soglie via echo:** da provare nella fase 1.
- **Licenza:** il codice portato è GPL-3.0, come DT Hub; il README e le intestazioni devono dirlo.

## 10. Fuori dal primo giro

Famiglie video e UNet (SD 1.5 / SDXL / Kandinsky / Wurstchen); stima del tempo e del costo in denaro; riconoscere il livello dell'account (Plus, futuro DT++); messaggio chiaro per un rifiuto da throttling con DT+ (circa 500 richieste in 24 ore, via gRPC: oggi arriva come `internalError` generico; è un lavoro a parte, nel backlog).

## 11. Punti aperti

- **Esito della fase 1 (15 ott 2026, 11:05):** l'echo a `compute.drawthings.ai:443` senza account risponde **senza soglie** (`hasThresholds = false`, `plus = 0`, `community = 0`, `expireAt = 0`). La fonte delle soglie va riconsiderata (vedi §2, decisione sulle soglie); l'implementazione si ferma al Task 1 finché l'utente non decide.

- Il margine del 90 % per l'ambra è una stima; le letture dell'utente possono dire di cambiarlo.
- Se la lettura dell'echo non basta (fase 1), serve un altro modo di ottenere la soglia: da rivedere con l'utente.

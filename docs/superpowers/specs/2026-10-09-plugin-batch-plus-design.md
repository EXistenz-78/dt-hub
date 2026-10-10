# Plug-in «Batch plus» — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
**Prerequisito:** `2026-10-09-pipeline-passaggi-con-valori-design.md` unito in `main` (passaggi con `fields`/`loras`, `DTHubContext.parameters`, contesto aggiornato).

## 1. Obiettivo

Un plug-in che prepara una **serie di RUN consecutive** e la manda all'app come pipeline: l'utente preme RUN e ottiene un'immagine per passaggio. Due modalità che si escludono:

- **Parametri:** i parametri della scheda Generazione in sola lettura, ciascuno con un campo «incremento»; un numero di passaggi; il passaggio *k* usa valore + (k−1) × incremento. Più incrementi compilati variano **insieme**.
- **Prompt:** un elenco puntato di prompt; un passaggio per punto; parametri invariati.

Esempio: passi 10 (incremento 10) e guidance 3 (incremento 2), 3 passaggi → (10, 3), (20, 5), (30, 7).

## 2. Decisioni (dell'utente, 9 ottobre)

- Incrementi al posto di intervalli. Il passaggio 1 usa i valori attuali.
- Niente griglia (tutte le combinazioni): i valori variano solo insieme.
- Parametri con incremento: **passi, guidance, shift, CFG-Zero (passi iniziali), seed, peso di ciascun LoRA**. Gli altri (modello, dimensioni, sampler, interruttori, batch, avanzate, extra) si vedono **senza** incremento.
- **«Seed fisso»**, acceso di default: tutti i passaggi usano il seed attuale con seed casuale spento, salvo un incremento sul seed (allora seed + (k−1) × incremento, sempre non casuale).
- Valori fuori limite: li riporta nei limiti l'app; il plug-in mostra **l'anteprima** dei valori di ogni passaggio prima dell'invio.
- Modalità Prompt: il prompt negativo e i parametri restano quelli della scheda; nessuna variazione parziale del prompt (il plug-in non vede il prompt attuale).

Decisioni prese da Claude (da confermare alla revisione): «Seed fisso» vale anche in modalità Prompt (non è una variazione di parametro: rende i prompt confrontabili); con «Shift automatico secondo la risoluzione» acceso, il campo incremento dello shift è disattivato con la nota «Draw Things ignora lo shift»; massimo 50 passaggi, con avviso da 20 in su.

## 3. Identità e stato

- `id: "com.exiztenz.dthub.batchplus"`, nome `Batch plus`, versione `1.0`, simbolo `square.stack.3d.up`, **tutte le famiglie** (`families: nil`).
- Stato del pannello (modalità, incrementi per chiave, numero di passaggi, «Seed fisso», testo dei prompt) salvato **per progetto** con il messaggio `project` (come gli altri plug-in: `state.json` nella cartella che l'app indica; `UserDefaults` prima del primo `project`).
- Testi italiano/inglese (tabella `L`), design system del kit (`DTHubDesign`).

## 4. Modalità Parametri

- Righe dai `parameters` del contesto: Modello (nome dal contesto), Dimensioni, **Passi**, **Guidance**, Sampler (nome da un elenco nel plug-in, come in Sphere Light per il numero 16), **Shift** (+ «auto» se acceso), CFG-Zero* (sì/no) e **passi iniziali**, **Seed** (+ «casuale» se acceso), Batch, una riga per **LoRA** (nome file, **peso**), gruppo «Avanzate» richiudibile con chiave e valore (sola lettura).
- Campo incremento: testo breve, accetta virgola o punto, segno meno per decrementi. Vuoto o 0 = non varia. Per passi, passi iniziali e seed solo interi (decimali → bordo rosso, invio disattivato).
- Numero di passaggi: 2–50.
- Anteprima: tabella *passaggio → valori che cambiano* (solo le colonne con incremento), con i valori calcolati (non riportati nei limiti: quello lo fa l'app; una nota lo dice).
- Pulsante **«Invia la serie»**: disattivato se nessun incremento è compilato o un campo è non valido.
- Senza `parameters` nel contesto (app vecchia): messaggio «Aggiorna DT Hub per usare la modalità Parametri».

## 5. Modalità Prompt

- Un editor di testo. Ogni riga che inizia (dopo gli spazi) con `-`, `•` o `*` apre un punto; le righe successive non vuote senza segno si aggiungono al punto precedente con uno spazio; i punti vuoti sono scartati. Numero di passaggi = numero di punti (mostrato sotto l'editor).
- Anteprima: elenco numerato dei prompt (prime ~80 lettere).
- **«Invia la serie»** disattivato con meno di 2 punti.

## 6. Pipeline inviata

`host.contribute(["pipeline": ["name": <nome>, "steps": [...]]])`:

- Parametri: `name` = `"Batch plus · " + parametri che variano` (es. «Batch plus · Passi, Guidance»); passaggio *k*: `title` = valori (es. «Passi 20 · Guidance 5»), `fields` = chiavi numeriche che variano (`steps`, `guidanceScale`, `shift`, `cfgZeroInitSteps`, `seed`), più `seed` e `randomSeed: false` se «Seed fisso»; `loras` = `[{file, weight}]` per i LoRA che variano.
- Prompt: `name` = «Batch plus · Prompt»; passaggio *k*: `title` = «Prompt k», `fields` = `{prompt: <punto k>}` (+ seed fisso se acceso).
- Mai `preset`, mai dimensioni. La risposta dell'app (`ok`/`conflicts`/`error`) diventa una riga di stato sotto il pulsante.

## 7. Test (nel pacchetto del plug-in)

Calcolo dei valori (interi e decimali, decrementi, incremento vuoto/0, più incrementi insieme); lettura dell'incremento (virgola/punto, segno, interi rifiutati con decimali); parser dell'elenco (segni diversi, righe di continuazione, punti vuoti); costruzione dei passaggi (chiavi JSON esatte, seed fisso con e senza incremento sul seed, LoRA per file, nessun `preset`/`width`/`height`); stato per progetto (round trip, file assente/rotto → iniziale); decodifica del contesto con e senza `parameters`.

## 8. Da verificare a mano

- Passi 10→30 in 3 passaggi con seed fisso: 3 immagini con 10/20/30 passi (sidebar dei Risultati o EXIF), stesse avanzate della scheda.
- Peso di un LoRA 0,4→1,2 in 5 passaggi.
- Modalità Prompt con 3 punti.
- Stop a metà serie; RUN di nuovo ripete la serie; «Rimuovi pipeline» la toglie.
- Cambio di passi nella scheda, ritorno nella scheda Batch plus: valore aggiornato.

## 9. Fuori ambito

Griglia X/Y; variazione parziale del prompt (S/R); avanzate, dimensioni e forza dell'immagine variabili; salvataggio di serie con nome.

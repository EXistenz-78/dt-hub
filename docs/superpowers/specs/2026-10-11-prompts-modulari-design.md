# Prompt modulari (Rules + Family + custom) — specifica

Data: 11 ottobre 2026. Stato: da approvare. Segue la discussione del 11 ottobre sui «master prompt».

## 1. Scopo

Oggi i testi che guidano l'LLM stanno in tre posti diversi e in tre forme diverse: le note di famiglia nel codice dell'app
(`PromptGuides.swift`), i master di Prompt Master in un JSON incorporato nel plug-in, i master di Character Sheet in file `.txt`.
Le note di famiglia di DT Hub e di Prompt Master sono lo stesso testo copiato (generato da Prompt Master), quindi divergono ad
ogni ritocco, e l'utente non può leggerle né cambiarle senza ricompilare.

Si passa a un sistema **modulare, in Markdown, in cartelle accessibili**:

- sempre formato **MD**, anche in futuro;
- ogni proprietario ha la sua cartella in `~/Library/Application Support/DT Hub/Data/<proprietario>/`;
- **Rules prompt** (le regole generali del compito) e **Family prompt** (le istruzioni di una famiglia di modelli) sono file
  separati, **uniti solo al momento dell'invio** all'LLM;
- una cartella `custom/` dove l'utente mette istruzioni sue.

Il «master prompt» non ha un significato per l'LLM: è un nome nostro. L'LLM vede solo testo. Contano il ruolo del messaggio
(system) e l'ordine.

## 2. Termini

| Termine | Che cos'è | Dove sta |
|---|---|---|
| **Rules prompt** | Regole del *compito* (migliora, descrivi, fondi descrizione e termini, chat…): scrivi in inglese, niente commenti, ecc. Dipende da *chi chiede*. | Del richiedente: DT Hub, Prompt Master, AI Assistant. |
| **Family prompt** | Istruzioni di una *famiglia di modelli* (lunghezza, struttura, uso del negativo, **protocollo di risposta**). | **Solo DT Hub.** I plug-in lo ricevono nel contesto. |
| **Livello utente** | File dell'utente che si aggiunge (o sostituisce) in `custom/`. | Del richiedente. |
| **Specialista** | Prompt di un solo plug-in e di una sola famiglia (Character Sheet, Prompt Master I4): non usa Rules + Family, resta com'è e cambia solo il formato. | Del plug-in. |

Il **protocollo di risposta** (solo prosa, oppure JSON `{"prompt","negative"}`) dipende dalla famiglia e sta quindi nel
**Family prompt**. L'intestazione del file dice al codice cosa aspettarsi (`negative: true|false`); il testo dice all'LLM cosa fare.
I due devono concordare. Il README avverte che le Family rules non vanno modificate («lo sconsigliamo»; chi lo fa se ne
assume le conseguenze). **Rete di sicurezza nel codice:** se ci si aspetta JSON e la risposta è solo prosa, quella prosa è
il prompt e il negativo resta vuoto.

## 3. Cartelle e file

```
~/Library/Application Support/DT Hub/Data/
  DTHub/
    family/            flux1.md  flux2.md  flux2_9b.md  qwen_image_2.1.md  …   (una per famiglia, id di Draw Things)
    rules/             enhance.md  describe.md
    custom/            (vuota; qui l'utente aggiunge)  +  families.txt (di servizio)
  prompt-master/
    rules/             compose.md          (fonde descrizione e termini)
    custom/
    …                  (database e custom-terms.json come oggi)
  AIAssistant/
    rules/             chat.md
    custom/
  CharacterSheet/      master-prompt.md  master-prompt-expressions.md  master-prompt-poses.md
                       static-prompt*.md   (da .txt a .md, stesso contenuto)
  prompt-master-i4/    master-prompt.md    (il testo `system` che oggi sta in ideogram4.json)
                       ideogram4.json      (resta: `fields`, `options`, `mergedMood`: configurazione, non testo per l'LLM)
                       custom/
```

`families.txt` è un file di servizio **riscritto dall'app a ogni avvio**: nome e id di ogni famiglia, e se usa il negativo,
così l'utente sa come chiamare i suoi file. Esempio di riga: `Qwen Image 2.1 = qwen_image_2.1 (senza negativo)`. Sta in
`DTHub/custom/`, a portata di mano.

## 4. Formato dei file

Markdown con un'**intestazione** (blocco `---` con righe `chiave: valore`, sottoinsieme semplice di YAML, senza liste annidate)
e il **corpo**, che è il testo per l'LLM.

Family prompt:

```
---
label: Qwen Image 2.1
version: 1
negative: false
words: 300-450
maxWords: 500
---
Length: aim for {words} words. … never beyond {maxWords} words …
```

Segnaposto nel corpo, sostituiti all'invio: `{label}`, `{words}`, `{maxWords}`. Così contatori dell'interfaccia e testo per
l'LLM vengono dalla stessa fonte. Rules prompt: solo `version`.

File `custom/`: nomi uguali ai compiti, `enhance.md`, `describe.md` (DT Hub), `compose.md` (Prompt Master), `chat.md`
(AI Assistant). Più, per ritoccare **una sola famiglia**, `family-<id>.md` (DT Hub). Intestazione facoltativa:
`mode: append` (predefinito) o `mode: replace`.

## 5. Assemblaggio all'invio

System prompt, in quest'ordine:

1. **Rules** del richiedente per il compito (livello utente `replace` incluso).
2. **Family prompt** della famiglia selezionata (con segnaposto risolti), se ne esiste uno.
3. **Livello utente** (`append`): il file del compito, poi il `family-<id>.md`, ciascuno preceduto da una riga fissa del
   codice: «In caso di conflitto, le istruzioni seguenti hanno la precedenza.» Il livello utente è sempre l'ultimo (nei prompt
   l'ultima istruzione pesa di più).

`mode: replace` in un file `custom/` sostituisce il livello corrispondente (Rules per il file del compito, Family per
`family-<id>.md`). Nessuna precedenza è garantita al cento per cento con un modello piccolo; per questo c'è l'anteprima (§7).

**LLM con system prompt proprio** (i PE di Qwen): invariato, arriva il suo system prompt e il testo dell'utente così com'è.
Se esiste un file `custom/` per il compito, si accoda al suo system prompt. Senza file non cambia nulla.

I file si **rileggono a ogni richiesta** (nessuna cache): una modifica vale subito.

## 6. Come i plug-in ricevono i Family prompt

Il messaggio `context` ha già `promptGuide`. Si estende (aggiunta facoltativa al contratto 1): `familyPrompt` (corpo con i
segnaposto già risolti), `negative`, `words`, `maxWords`. Un plug-in compone: **le sue Rules + `familyPrompt` + il suo livello
utente**. I plug-in non leggono le cartelle di DT Hub.

## 7. Interfaccia

- Preferenze › LLM: pulsante **Apri cartella dei prompt** e, per ogni famiglia, l'indicatore **«Personalizzato»** quando
  c'è un `family-<id>.md`.
- **Prompt finale**: anteprima del testo assemblato per famiglia e compito (solo lettura). È lo strumento per capire cosa riceve
  l'LLM.
- File illeggibile o con intestazione errata: l'avviso nello stato e si torna al livello sotto.

## 8. File di base: creazione e aggiornamento

Le copie incorporate (nell'app e in ogni plug-in) sono i valori di partenza. Ognuno scrive i **propri** file di base nella sua
cartella: all'avvio, se un file manca o la sua `version` è **più bassa** di quella incorporata, lo (ri)scrive, e conserva il
vecchio come `<nome>.md.bak`. Se la `version` del file è uguale o più alta, non lo tocca. L'utente che modifica un file di base
e lo vuole tenere alza la `version`; per tutto il resto c'è `custom/`.

**Migrazione.** Character Sheet: i `.txt` esistenti si leggono ancora per una versione (stesso contenuto, nuova estensione
`.md` alla prima scrittura). Prompt Master: le note di famiglia di `master-prompts.json` si eliminano (passano a DT Hub); resta
nel plug-in ciò che serve solo a lui (`hiddenCategories`, vocabolari).

## 9. Fuori da questa specifica

Prompt Master I4 e Character Sheet come specialisti (§2): restano a sé, senza Rules + Family; si cambia solo il formato del
master (per I4 il testo `system` di `ideogram4.json` esce in un `.md`, nella fase 3; `fields`, `options` e `mergedMood`
restano in JSON). Valgono per loro `custom/`, l'aggiornamento per `version` con `.bak` e la lettura a ogni richiesta. Niente editor di prompt nell'app. Niente avviso «la guida di base è cambiata dalla tua copia».

## 10. Verifiche

- **Automatiche, su tutte le famiglie:** il testo assemblato per ogni famiglia e compito è uguale al system prompt di oggi
  (`PromptBrief.system`, master di Prompt Master). Le differenze si guardano una per una.
- **Con l'LLM, su poche famiglie:** **Qwen Image 2.1** (prosa, senza negativo), **FLUX.2 [klein] 9B** (prosa, senza
  negativo) e **Krea 2** (negativo e risposta JSON) per Migliora e Genera. Ideogram 4 come specialista, in fase 3: il
  prompt della caption di I4 prima e dopo la conversione.
- Fallback: intestazione mancante o rotta, JSON atteso e prosa ricevuta, `custom/` vuota, file `replace`.

## 11. Fasi

1. Lettore comune (intestazione, segnaposto, assemblaggio) nel kit dei plug-in e in HubCore; Family prompt e Rules di DT
   Hub; `custom/`; `families.txt`; anteprima; test di uguaglianza.
2. Prompt Master: usa `familyPrompt` dal contesto; le sue Rules in `compose.md`; `custom/`; scompaiono le note di famiglia
   duplicate.
3. Specialisti e AI Assistant: Character Sheet (`.txt` → `.md`), Prompt Master I4 (master in `.md`), AI Assistant
   (`rules/chat.md`, `custom/`).

Ogni fase si prova a mano e si unisce a parte.

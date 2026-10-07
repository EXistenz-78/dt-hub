# Plug-in Character Sheet — Design

Data: 7 ottobre 2026. Stato: approvato in chat dall'utente (disegno a sezioni); da implementare in una sessione locale con Xcode e Swift.

## 1. Obiettivo

Da **una sola immagine** di un personaggio, preparare in Generazione un **foglio di design** (character sheet) con Qwen Image 2.1, come fa un workflow di ComfyUI della comunità (`Character_Sheet_Production`, versione 3.0 per Qwen Image 2.1).

Come funziona quel workflow (studiato il 7 ottobre): un LLM con visione riceve l'immagine, un lungo system prompt («master prompt», circa 9.500 caratteri: audit visivo, «identity locks», mappa di 7 zone con coordinate, 10 sezioni) e la richiesta `Entity name: <nome>`; scrive il prompt del foglio; poi Qwen Image 2.1 (modo edit, stessa immagine come riferimento, canvas 3:2 a circa 3,4 MP) genera il foglio. In alternativa il workflow ha un **prompt statico** (circa 400 parole, stesso layout, nessun LLM).

Il plug-in fa la parte «preparare»: immagine nel Moodboard, canvas 3:2, prompt nel campo prompt (statico, oppure scritto da un LLM locale). Il pulsante RUN resta quello dell'app.

**Successo:** con Qwen Image 2.1 scelto, un'immagine caricata e un clic su «Prepara», la Generazione ha il Moodboard, 2304×1536 e il prompt pronti; un RUN dà il foglio. Lo scopo del primo prototipo è **confrontare** due LLM (Qwen3-VL 8B e Qwen PE I2I) e il prompt statico.

## 2. Decisioni (dell'utente, 7 ottobre)

1. Il tab ha: caricamento dell'immagine, **campo per il nome del personaggio**, **interruttore «Prompt statico»**, **menù per scegliere il modello LLM**.
2. Con l'LLM spento: l'immagine va nel Moodboard e il prompt statico in Generazione. Con l'LLM acceso: l'immagine va nel Moodboard **e** all'LLM insieme al master prompt, e la risposta va nel campo prompt.
3. Si provano **Qwen3-VL 8B** e **Qwen PE I2I** uno contro l'altro; solo se nessuno dei due convince da solo si valuta l'opzione C (due passaggi). Per ora il **master prompt è quello del workflow**, così com'è.
4. Il master prompt e il prompt statico stanno in **due file fuori dal repo**, modificabili al volo (il testo è dell'autore del workflow, senza licenza dichiarata, e il repo è pubblico).

Decisioni prese da Claude, approvate:
- il canvas **2304×1536** (3:2) viene imposto sempre, senza casella;
- nome vuoto ⇒ `CHARACTER`;
- il menù elenca solo i modelli con visione.

## 3. Architettura

Un pacchetto come Sphere Light: `Plugins/CharacterSheet/` (libreria dinamica, alias di modulo `CharacterSheetKit` / `CharacterSheetDesign`, nessuna risorsa nel bundle). Id `com.exiztenz.dthub.charactersheet`, nome «Character Sheet», `families: ["qwen_image_2.1"]` (fuori da lì il plug-in si spegne e il tab sparisce), simbolo SF `person.text.rectangle`. Nessuna modifica all'app né al contratto 1.

```
Plugins/CharacterSheet/
  Package.swift
  Scripts/build.sh                       come gli altri plug-in
  Scripts/extract-from-workflow.py       estrae i due file dal JSON di ComfyUI
  Sources/CharacterSheet/
    CharacterSheetPlugin.swift           manifest, context, activate/deactivate, collega vista e logica
    CSTemplates.swift                    cartella dei file, lettura, segnaposto {{name}}
    CSBrief.swift                        la richiesta all'LLM (due forme) e le impostazioni
    CSAnswer.swift                       legge la risposta (testo o JSON)
    CSMessages.swift                     i corpi di `contribute`
    CSRunner.swift                       «Prepara»: l'intera sequenza, con closure (testabile)
    CSState.swift                        stato osservato del tab + memoria della scelta
    CharacterSheetView.swift             il tab (SwiftUI, con DTHubDesign)
    Strings.swift                        tabella L, italiano e inglese
  Tests/CharacterSheetTests/             un file di test per CSTemplates, CSBrief, CSAnswer, CSMessages, CSRunner, CSState
  README.md                              in inglese, con la riga «Works with» e il credito al workflow
```

README della radice dei plug-in (`Plugins/README.md`): una riga nella tabella. Nel README del plug-in: «inspired by» il workflow, senza testo suo.

### 3.1 I due file: `CSTemplates`

Cartella: `~/Library/Application Support/DT Hub/Data/CharacterSheet/` (stessa radice `Data/` di Prompt Master). File: `master-prompt.txt`, `static-prompt.txt`.

```swift
enum CSTemplateFile: String { case master = "master-prompt.txt", staticPrompt = "static-prompt.txt" }
enum CSTemplateError: Error, Equatable { case missing(CSTemplateFile), empty(CSTemplateFile) }
enum CSTemplates {
  static var defaultFolder: URL
  static func load(_ file: CSTemplateFile, from folder: URL) -> Result<String, CSTemplateError>   // testo senza spazi agli estremi
  static func fill(_ text: String, name: String) -> String   // sostituisce ogni {{name}} con il nome, o con CHARACTER se vuoto o di soli spazi
}
```

`extract-from-workflow.py --source <workflow.json> --out <cartella>`: nel JSON cerca il sotto-grafo «Character Sheet Prompt Maker» e prende il testo del nodo «Prompt Template (Important)» (master) e quello dell'altro nodo di testo lungo (statico); nel statico sostituisce la frase `Extract character name (or use "CHARACTER")` con `Character name "{{name}}"`. Esce con errore se non trova i due testi. Non ha percorsi personali.

### 3.2 La richiesta: `CSBrief`

Due forme, scelte dal **nome** del modello (come Prompt Master sceglie il PE T2I): `-` e `.` letti come `_`, minuscolo; se contiene `qwen_image_2_1_pe_i2i` è il PE I2I, altrimenti è «generico».

```swift
struct CSRequest: Equatable { let model: String; let prompt: String; let images: [String]; let system: String; let options: DTHubLLMOptions }
enum CSBrief {
  static func isPEI2I(_ modelName: String) -> Bool
  static let peSystemFileNames = ["system_prompt.txt", "system_prompt_i2i.txt"]
  static func peSystem(inFolder folder: URL, read: (URL) -> String?) -> String?   // primo file non vuoto
  /// Generico: system = master, richiesta = "Entity name: <nome>".
  static func generic(model: String, image: String, name: String, master: String) -> CSRequest
  /// PE I2I: system = quello del PE; richiesta = master + "\n\nEntity name: <nome>".
  static func peI2I(model: String, image: String, name: String, master: String, peSystem: String) -> CSRequest
}
```

Opzioni:
- generico (impostazioni dell'autore del workflow): temperatura 0.9, topP 0.95, topK 20, `thinking: true`, `maxTokens: 16384` (la nota del workflow avverte di risposte vuote con valori bassi), attesa 900 s;
- PE I2I (impostazioni di Qwen): temperatura 1.0, topP 0.95, topK 20, presence penalty 0, `thinking: true`, `maxTokens: 24000`, attesa 1800 s.

Un'immagine sola: nessuna etichetta `<image1>` (il system del PE lo prevede solo da due immagini in su).

### 3.3 La risposta: `CSAnswer`

`static func parse(_ raw: String) -> String?`: stessa logica di `AnswerParser` di Prompt Master (copiata, il plug-in è un pacchetto separato), senza rapporto: toglie `<think>…</think>` (anche non chiuso ⇒ nulla), le recinzioni ```, una sola coppia di virgolette; se trova un oggetto JSON legge `rewritten_prompt` (o `prompt`, `positive_prompt`); altrimenti tutto il testo. Le righe vuote tra i paragrafi restano. `nil` se non resta nulla. `ratio_follow` e `wh_ratio` si ignorano (il foglio è sempre 3:2).

### 3.4 I messaggi: `CSMessages`

```swift
enum CSMessages {
  static let width = 2304, height = 1536
  static func moodboard(imagePath: String, name: String) -> [String: Any]   // contribute: {"moodboard": [{"path", "name"}]}
  static func size() -> [String: Any]                                       // contribute: {"fields": {"width": 2304, "height": 1536}}
  static func prompt(_ text: String) -> [String: Any]                       // contribute: {"fields": {"prompt": text}}
}
```

### 3.5 La sequenza: `CSRunner`

Come `SphereSender`: parla con l'app e col disco tramite closure, quindi si prova senza app.

```swift
@MainActor struct CSRunner {
  var contribute: @MainActor ([String: Any]) async -> [String: Any]?
  var ask: @MainActor (CSRequest) async -> DTHubLLMAnswer
  var copyImage: (String, String) throws -> String      // (origine, cartella temporanea) → percorso copiato
  var readTemplate: (CSTemplateFile) -> Result<String, CSTemplateError>
  var readPESystem: (DTHubLanguageModel) -> String?
  var now: () -> Date
  func prepare(_ job: CSJob, progress: (String) -> Void) async -> CSOutcome
}
```

`CSJob` = immagine, nome, `useStatic`, modello scelto (se non statico), `tempFolder`. `CSOutcome` = riga di stato finale (testo localizzato) più, se riuscito, parole e secondi.

Ordine in `prepare`, con una riga di avanzamento a ogni passo:
1. immagine mancante ⇒ errore, fine; `tempFolder` mancante ⇒ errore, fine;
2. carica il file di testo che serve (statico, oppure master) ⇒ errore chiaro se manca o è vuoto, **prima** di toccare l'app;
3. copia l'immagine in `tempFolder` come `com.exiztenz.dthub.charactersheet-reference.<estensione>` e la manda al **Moodboard**; manda le **dimensioni** (se un `contribute` risponde con errore, la riga lo dice e si ferma);
4. statico: scrive il prompt con `fill` e finisce. LLM: se PE I2I legge il suo `system_prompt.txt` (assente ⇒ errore con il nome del file, **nessun ripiego**), costruisce la richiesta, chiede, passa la risposta a `CSAnswer.parse` (vuota ⇒ errore «nessuna risposta utilizzabile»), scrive il prompt;
5. riga finale con parole del prompt e secondi trascorsi (per confrontare i modelli).

I campi non vengono mai toccati se un passo prima della scrittura fallisce; Moodboard e dimensioni, già inviati, restano (sono innocui e riusabili).

### 3.6 Lo stato e il tab

`CSState` (`@MainActor @Observable`): `family`, `languageModels` (dal `context`), `tempFolder`, `imagePath`, `name`, `useStatic`, `selectedModel` (nome), `busy`, `status`. `visionModels` = i `languageModels` con `supportsImages`. Memoria su disco (`settings.json` nella cartella dei file): `useStatic` e `selectedModel`; immagine e nome no. Un modello salvato che non c'è più ⇒ il primo con visione. Nessun modello con visione ⇒ il menù dice «nessun modello con visione» e «Prepara» funziona solo con lo statico.

`CharacterSheetView` (design system dell'app): miniatura con «Scegli…» e trascinamento; campo «Nome del personaggio»; interruttore «Prompt statico»; menù «Modello LLM» (disattivato con lo statico); pulsante «Prepara» (disattivato senza immagine o se `busy`); pulsante «Apri cartella» dei file di testo (`NSWorkspace`); riga di stato `.caption`, rossa se errore; spinner mentre `busy`. Testi in italiano e inglese (tabella `L`).

## 4. Errori

Tutti diventano la riga di stato, mai una finestra: immagine mancante; cartella temporanea assente (`context` non ancora arrivato); file di testo mancante o vuoto (dice quale e in che cartella); `system_prompt.txt` del PE mancante; app che non risponde (`askLanguageModelAnswer` dà il motivo); risposta vuota o con `<think>` non chiuso; `contribute` con errore. L'LLM non è annullabile (come nell'app): «Prepara» resta disattivato mentre lavora.

## 5. Test

Swift Testing, `swift test` nel pacchetto del plug-in; test `@MainActor` dove serve; niente `UserDefaults`.
- `CSTemplates`: `load` (file presente, assente, vuoto, spazi agli estremi); `fill` (segnaposto ripetuto, nome vuoto e di soli spazi ⇒ `CHARACTER`, testo senza segnaposto invariato).
- `CSBrief`: `isPEI2I` (varianti di nome, T2I escluso); testo e opzioni esatti delle due forme; `peSystem` (primo file non vuoto, nessuno ⇒ nil).
- `CSAnswer`: prosa, virgolette, ```json, `rewritten_prompt`, `<think>` chiuso e non chiuso, JSON malformato ⇒ tutto il testo, vuoto ⇒ nil.
- `CSMessages`: forma dei tre corpi.
- `CSRunner` (closure finte): statico senza chiamare l'LLM; generico (system, richiesta, immagine, opzioni); PE I2I; PE senza system ⇒ errore e nessuna chiamata; file mancante ⇒ nessun `contribute`; risposta vuota ⇒ campi intatti; ordine delle chiamate (Moodboard, dimensioni, poi prompt); riga finale con parole e secondi.
- `CSState`: modelli con visione, selezione di ripiego, memoria dell'interruttore e del modello.
- Script: provato a mano sul JSON dell'utente (due file non vuoti, segnaposto presente).

## 6. Fuori ambito (YAGNI)

Opzione C (due passaggi); modo A (una frase breve al PE); preset; più personaggi o più immagini; altre famiglie; `VAEDeGrid` e il sampler del workflow; annullare l'LLM; salvare i fogli; modificare i testi dentro il tab; casella per non imporre il canvas.

## 7. Da verificare a mano (dopo il prototipo)

- Con Qwen Image 2.1 in DT e l'immagine nel Moodboard, il prompt statico produce un foglio con l'identità giusta? È la domanda che decide se il plug-in vale.
- Qwen3-VL 8B 4bit segue il master prompt o lo ripete (come l'autore dice di Qwen3-VL)?
- Qwen PE I2I con il master prompt come richiesta: lo applica, lo riassume o lo riscrive?
- Tempi e memoria con thinking acceso (PE I2I fino a 24.000 token).
- Artefatti a griglia a 2304×1536 (il workflow li toglie con `VAEDeGrid`, che in DT non c'è).

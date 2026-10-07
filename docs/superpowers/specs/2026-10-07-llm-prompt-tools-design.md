# Funzioni LLM nell'app: «Migliora Prompt» e «Genera Prompt» — Design

Data: 7 ottobre 2026. Stato: approvato in chat dall'utente (decisioni 1–4 sotto); da implementare in una sessione locale con Xcode e Swift.

## 1. Obiettivo

Finora il servizio LLM (MLX, `LanguageModelManager`) lo usano solo i plug-in. Questo lavoro aggiunge due funzioni dell'app, indipendenti dai plug-in:

- **Migliora Prompt / Enhance Prompt** — nella card Prompt del tab Generazione: manda all'LLM il prompt attuale con le regole del modello selezionato e scrive la risposta nel campo prompt (e nel prompt negativo dove la famiglia lo usa).
- **Genera Prompt / Generate Prompt** — nella card Immagine del tab Control (Canvas): manda l'immagine di partenza con la richiesta «descrivila come prompt per il modello selezionato» e scrive la risposta nello stesso modo.

Successo: con un modello LLM scelto nelle impostazioni (visione per Genera Prompt), un clic produce un prompt in inglese, adatto alla famiglia del modello, nel campo prompt; un secondo clic su «Annulla» lo riporta com'era.

## 2. Decisioni (dell'utente, 7 ottobre)

- **Master prompt semplificati, dentro l'app, indipendenti dal plug-in Prompt Master.** Si usano solo i blocchi «Model notes» di ogni famiglia più la regola generica: scrivere solo in inglese, rispondere solo con il prompt, nessun commento o altro testo fuori dal prompt.
- **Il risultato di entrambi i tasti va nel campo prompt (e nel negativo, se applicabile).**

Decisioni prese da Claude, approvate:
1. Prima di sovrascrivere si ricorda il prompt precedente: link «Annulla» (costo se sbagliata: una riga di stato in più).
2. «Genera Prompt» sovrascrive anche un prompt non vuoto, senza finestra di conferma; stesso «Annulla».
3. Famiglie senza guida (per esempio Ideogram 4, che ha il suo plug-in): il tasto resta attivo con la sola regola generica, in prosa.
4. Nessun tasto Stop: `LanguageModelManager.respond` non è annullabile (voce di backlog). Il tasto resta disabilitato mentre l'LLM risponde.

## 3. Architettura

Tutta la logica sta in **HubCore** (testabile con `swift test`, senza UI). La UI e il collegamento sono nell'app.

```
HubCore/PromptAssist/
  PromptGuides.swift     dati: famiglia → PromptGuide (label, usesNegative, notes)   [generato una volta, poi a mano]
  PromptBrief.swift      funzioni pure: system, richiesta di enhance, richiesta di describe, parser della risposta
  PromptAssistant.swift  @MainActor @Observable: stato (working, failure, annulla) e le due operazioni
App/Generation/Cards/PromptCard.swift       tasto «Migliora Prompt» + riga di stato
App/Control/ImageCard.swift                 tasto «Genera Prompt» + riga di stato
App/Generation/GenerationController.swift   possiede l'assistente, due metodi sottili, family(in:)
App/DTHubApp.swift                          (nessuna modifica attesa: il controller ha già `languageModel`)
App/Localizable.xcstrings                   testi IT/EN
Scripts/make-prompt-guides.py               estrae le «Model notes» da Plugins/PromptMaster/Data/master-prompts.json
```

Non si tocca il PluginKit né il contratto 1: i plug-in già distribuiti restano compatibili.

### 3.1 Dati: `PromptGuide`

```swift
public struct PromptGuide: Equatable, Sendable {
  public let label: String       // "FLUX.2 [klein] 9B"
  public let usesNegative: Bool  // la famiglia legge un prompt negativo ⇒ si chiede anche quello
  public let notes: String       // il blocco «Model notes:» (righe "- …"), in inglese, senza l'intestazione
}
public enum PromptGuides {
  public static let all: [String: PromptGuide]            // chiave = `version` di Draw Things (CatalogModel.family)
  public static func guide(for family: String?) -> PromptGuide?
}
```

Le 13 famiglie di partenza (stesse chiavi di `master-prompts.json`): `flux1, flux2, flux2_9b, flux2_4b, krea_2, qwen_image, qwen_image_2.1, z_image, sdxl_base_v0.9, v1, ernie_image, hidream_i1, cosmos2.5_2b`. `usesNegative` è il campo `negative` del JSON (vero per `krea_2, qwen_image, ernie_image, cosmos2.5_2b, sdxl_base_v0.9, v1`).

Lo script copia solo il testo dopo `Model notes:` di `system` e scarta: la prima riga «You write prompts for…», il paragrafo del brief (descrizione + termini, che qui non esiste), la regola di lingua/formato (sostituita da quella generica), `booruSystem` e la nota «Provisional…». Poi il file generato si può ritoccare a mano: **nessuna sincronizzazione continua col plug-in** (le due copie possono divergere, è voluto).

### 3.2 Messaggi: `PromptBrief` (funzioni pure)

```swift
public struct PromptPair: Equatable, Sendable { public var prompt: String; public var negative: String }
public struct PromptRequest: Equatable, Sendable {
  public let prompt: String; public let images: [URL]; public let options: LanguageModelOptions
}
public enum PromptBrief {
  public static func system(family: String?) -> String
  public static func enhance(_ current: PromptPair, family: String?) -> PromptRequest
  public static func describe(imageAt url: URL, family: String?) -> PromptRequest
  public static func parse(_ raw: String) -> PromptPair?   // nil se non resta nulla; non sa la famiglia: la sceglie PromptAssistant
}
```

**System** (inglese), in quest'ordine:
1. `You write prompts for the image model "<label>".` — senza guida: `You write prompts for an image-generation model.`
2. Regola generica, famiglia senza negativo (o senza guida):
   `The final prompt must be written exclusively in English, whatever the language of the input. Reply with the prompt only: no title, no quotation marks around it, no explanation, no comments, no markdown, no alternatives.`
3. Regola generica, famiglia con negativo:
   `The final prompt must be written exclusively in English, whatever the language of the input. Reply with a JSON object and nothing else, in this shape: {"prompt": "...", "negative": "..."}. "prompt" is the final prompt; "negative" lists only what to avoid, short and targeted. Both values are in English. No explanation, no comments, no markdown.`
4. Se c'è la guida: riga vuota, `Model notes:`, poi `notes`.

**Opzioni:** `LanguageModelOptions(system: <sopra>, maxTokens: 2048, thinking: false)` (come il plug-in Prompt Master: un modello che ragiona di default consumerebbe i token nel ragionamento).

**Richiesta enhance** (`images: []`):
```
Improve the prompt below for this model. Keep every element it describes and never contradict it; add concrete visual detail as the model notes ask. The prompt may be in any language.

Prompt:
<prompt>
```
e, solo se la famiglia usa il negativo **e** il negativo attuale non è vuoto, in coda: `\n\nNegative prompt:\n<negative>`.

**Richiesta describe** (`images: [url]`):
```
Describe this image as a prompt for this model, following the model notes. Describe only what is visible; do not invent a story.
```

**Parser** (`parse`): stessa logica di `Plugins/PromptMaster/Sources/PromptMaster/AnswerParser.swift`, senza il rapporto: toglie `<think>…</think>` (anche non chiuso), le recinzioni ``` e una sola coppia di virgolette; se trova un oggetto JSON legge `prompt` (anche `rewritten_prompt`, `positive_prompt`) e `negative` (anche `negative_prompt`); altrimenti tutto il testo è il prompt. Il `negative` del risultato è `""` se la risposta non lo contiene. (La logica è duplicata di proposito: il plug-in è un pacchetto separato e non può dipendere da HubCore.)

### 3.3 Operazioni: `PromptAssistant`

```swift
@MainActor @Observable public final class PromptAssistant {
  public enum Kind: Equatable, Sendable { case enhance, describe }
  public enum Failure: Equatable, Sendable { case emptyPrompt, noImage, emptyAnswer, model(LanguageModelError) }

  public typealias Respond = @MainActor (String, [URL], LanguageModelOptions) async throws(LanguageModelError) -> String
  public init(respond: @escaping Respond)

  public private(set) var working: Kind?        // nil = libero; i tasti sono disabilitati se non nil
  public private(set) var failure: Failure?     // dell'ultima operazione; azzerato da ogni nuova operazione
  public func enhance(_ current: PromptPair, family: String?) async -> PromptPair?
  public func describe(imageAt url: URL?, current: PromptPair, family: String?) async -> PromptPair?
  /// Il prompt di prima, solo finché i campi sono ancora quelli scritti dall'ultima operazione.
  public func undoOffer(current: PromptPair) -> PromptPair?
  public func clearUndo()
}
```

Regole:
- `enhance` con prompt vuoto (solo spazi) → `failure = .emptyPrompt`, nessuna chiamata all'LLM, ritorna nil.
- `describe` con `url == nil` → `failure = .noImage`, nessuna chiamata.
- Se `working != nil` la chiamata ritorna nil subito (una alla volta).
- Risposta senza testo utile (`parse` nil) → `.emptyAnswer`, ritorna nil. Errore del servizio → `.model(error)`.
- Successo: ritorna `PromptPair(prompt: parsed.prompt, negative: <parsed.negative se la famiglia ha guida con usesNegative e la risposta lo contiene, altrimenti current.negative>)`. Ricorda `current` come «prima» e il risultato come «scritto» per `undoOffer`.
- `undoOffer(current:)` ritorna il «prima» solo se `current == scritto`; chi modifica a mano un campo fa sparire il link.
- Il risultato **viene applicato dal chiamante** (il controller), non dall'assistente: l'assistente non conosce i campi.

### 3.4 App

`GenerationController` (App/Generation/GenerationController.swift):
- `let assistant: PromptAssistant`, creato in `init` con `{ p, i, o in try await languageModel.respond(to: p, images: i, options: o) }`.
- `func enhancePrompt(in connection: DrawThingsConnection) async` — chiama `assistant.enhance(PromptPair(prompt: prompt, negative: negativePrompt), family: family(in: connection))`; se ritorna un valore, assegna `prompt` e `negativePrompt`.
- `func promptFromImage(in connection: DrawThingsConnection) async` — URL da `control.inputs.image.flatMap(control.copyURL(of:))`; stesso schema con `assistant.describe`.
- Nessuna logica propria: tutto il comportamento sta in HubCore, dove è testato.

`PromptCard`: sotto i campi, riga con il tasto «Migliora Prompt» (`DSPillButtonStyle`, icona `wand.and.stars`), spinner mentre `working == .enhance`, e a destra il link «Annulla» quando `undoOffer` non è nil. Il tasto è disabilitato se `working != nil`. Un errore sta in una riga `.caption` rossa sotto il tasto.

`ImageCard`: nella riga dei pulsanti (accanto a Sostituisci/Adatta) il tasto «Genera Prompt» con lo stesso trattamento (spinner, «Annulla», errore). Visibile solo con un'immagine caricata.

Errori: `LanguageModelErrorText.message(_:)` (App/Preferences/LanguagePreferencesView.swift) per `.model`; tre testi nuovi per `emptyPrompt`, `noImage`, `emptyAnswer`. Il caso «modello senza visione» è già `imagesNotSupported` → `llm.error.noImages`.

Testi nuovi in `Localizable.xcstrings` (it/en, `extractionState: manual`): `prompt.enhance`, `prompt.enhance.help`, `prompt.undo`, `prompt.assist.error.empty`, `prompt.assist.error.noImage`, `prompt.assist.error.noAnswer`, `control.image.describe`, `control.image.describe.help`.

## 4. Flusso dei dati

Enhance: campo prompt (+ negativo) → `PromptBrief.enhance` → `LanguageModelManager.respond` (carica il modello se serve, dopo il controllo memoria; libera il server delle immagini se le impostazioni lo chiedono) → `PromptBrief.parse` → `controller.prompt` / `negativePrompt`.
Describe: immagine di partenza (copia in `ControlStore`) → `PromptBrief.describe` → stesso percorso.

## 5. Gestione degli errori

Tutti gli errori del servizio passano da `LanguageModelError` e dai testi già esistenti. Un errore non tocca i campi. Nessun ritentativo automatico.

## 6. Test

HubCoreTests (`swift test` da `Packages/`), con il servizio LLM finto (come `FakeLanguageModelService` in `LanguageModelTests.swift`, ma qui basta una closure `Respond`):
- `PromptGuides`: le 13 chiavi esistono; `usesNegative` giusto per ognuna; nessuna `notes` vuota, e nessuna contiene «Model notes:», «Provisional master prompt» o «Tag mode is ON» (booru e nota provvisoria restano fuori); `guide(for: nil)` e famiglia ignota → nil.
- `PromptBrief.system`: famiglia con/senza negativo, senza guida; contiene le note; contiene la regola «exclusively in English».
- `PromptBrief.enhance` / `describe`: testo esatto, `images`, `options` (`maxTokens 2048`, `thinking false`, `system` valorizzato); il negativo entra solo se la famiglia lo usa e non è vuoto.
- `PromptBrief.parse`: prosa; virgolette; recinzione ```json; `<think>` chiuso e non chiuso; JSON con `prompt`+`negative`; JSON malformato → tutto il testo; vuoto → nil.
- `PromptAssistant`: i casi di §3.3 (prompt vuoto, nessuna immagine, una alla volta, risposta vuota, errore del servizio, successo con e senza negativo, annulla offerto e poi tolto dopo una modifica manuale).

L'app non ha test di UI: verifica a mano (§8).

## 7. Fuori ambito (YAGNI)

Stop/annulla della richiesta; migliorare il solo negativo; interruttore «booru» per SD; scelta di un modello LLM diverso da quello delle impostazioni; più varianti per richiesta; adattare il formato (rapporto) come fa Prompt Master; sincronizzazione dei dati col plug-in; ritocchi del tab del plug-in.

## 8. Da verificare a mano (non fattibile senza Mac + modello)

- Con Qwen3-VL 8B 4bit: Migliora Prompt su una famiglia FLUX.2 (prosa) e su SD 1.5 (JSON con negativo); Genera Prompt su una foto.
- Immagini grandi: `MLXLanguageModelService` passa l'URL del file a mlx-vlm (`UserInput.Image.url`) senza ridimensionare: controllare tempo e memoria con un PNG da 2048 px o più; se pesa, ridimensionare in `ControlStore` prima di passarla (da decidere allora).
- Modello LLM senza visione: Genera Prompt mostra «il modello non legge immagini».
- RUN subito dopo un'operazione: il modello viene liberato (`prepareForRun`) senza blocchi.
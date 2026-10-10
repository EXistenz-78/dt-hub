# Migliora Prompt con immagine di partenza e Moodboard — Design

Data: 9 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` a `053d65c` (release 0.1.4).

## 1. Obiettivo

Oggi «Migliora Prompt» manda all'LLM solo il testo. Nei lavori image-to-image il prompt parla di «image 1», «image 2»… (immagine di partenza e Moodboard) che l'LLM non vede: migliora senza sapere di cosa si parla, e rischia di togliere i riferimenti che servono al modello generativo.

Si mandano anche l'immagine di partenza e le immagini accese della Moodboard, numerate come le numera Draw Things, con la richiesta di **conservare i riferimenti** «image N».

«Genera Prompt» non cambia.

## 2. Decisioni (dell'utente e approvate in chat, 9 ottobre)

- Immagini: l'immagine di partenza (card Immagine) se c'è, poi le Moodboard **accese** nell'ordine delle miniature.
- **Numerazione** (verificata dall'utente in Draw Things, 9 ottobre): con immagine di partenza → partenza = 1, Moodboard = 2, 3…; senza → la prima Moodboard = 1. Tutto in **una sola funzione** testata.
- La Moodboard si manda solo per le famiglie che la leggono (`FamilyTraits.usesMoodboard`); l'immagine di partenza sempre, se c'è.
- Servono LLM che leggono immagini: il router salta quelli senza visione (prima l'LLM della famiglia per Migliora, poi «Tutti gli altri»).
- Se nessun LLM per Migliora legge immagini: si manda **solo il testo** come oggi e sotto il pulsante compare una nota «Immagini non inviate: nessun LLM per Migliora legge immagini».
- System prompt proprio dell'LLM: con immagini si preferisce `system_prompt_i2i.txt`, poi `system_prompt.txt` (non il t2i).
- Immagine di partenza intera (la copia in Control), non ritagliata come il canvas. Nessun limite al numero di Moodboard.

## 3. Testo delle immagini (inglese)

`PromptBrief.imageLabels(hasStart: Bool, references: Int) -> [String]` restituisce una riga per immagine, nell'ordine d'invio:

- con partenza: `Image 1: the start image (the picture being edited).`, poi `Image 2: reference image 1.`, `Image 3: reference image 2.`…
- senza partenza: `Image 1: reference image 1.`, `Image 2: reference image 2.`…

Il blocco che precede il prompt nella richiesta:

```
Attached images:
- <riga 1>
- <riga 2>

The prompt refers to these images. Look at them to make the description concrete and accurate, and keep every reference to an image (image 1, image 2…) exactly as written.
```

- **Senza system prompt proprio:** blocco, riga vuota, poi la richiesta di oggi (`Improve the prompt below…`, `Prompt:`, negativo se la famiglia lo usa). System e opzioni come oggi.
- **Con system prompt proprio:** blocco, riga vuota, poi il testo dell'utente; opzioni come oggi per l'LLM con system prompt proprio (`maxTokens 16384`, `thinking true`, valori di `generation_config.json`).
- Nessuna immagine: richiesta identica a oggi.

## 4. Scelta dell'LLM

- `LanguageModelRouter.model(for:family:models:assignments:needsImages:)` — nuovo parametro `needsImages: Bool = false`: con `true` un LLM senza visione è scartato anche per `.enhance` (oggi solo per `.describe`); l'esito «scartati solo per le immagini» resta `.imagesNotSupported`.
- `LanguageModelManager.model(for:family:needsImages:)` lo passa avanti.
- `PromptAssistant.Resolve` diventa `@MainActor (LanguageModelTask, String?, Bool) -> Result<Choice, LanguageModelError>` (il `Bool` è `needsImages`).
- In `enhance` con immagini: `resolve(.enhance, family, true)`; se dà `.imagesNotSupported`, `resolve(.enhance, family, false)` e richiesta **senza** immagini, con `note = .imagesNotSent`. Ogni altro errore resta un `failure`.

## 5. System prompt con immagini

`LanguageModelProfile.systemPrompt(for: .enhance, withImages: Bool)`: con `withImages` il primo non vuoto tra `system_prompt_i2i.txt` e `system_prompt.txt`; senza, come oggi (`system_prompt_t2i.txt`, poi `system_prompt.txt`). `systemPrompt(for:)` resta e vale `withImages: false`.

## 6. App

- `PromptAssistant.enhance(_:family:images:)` con `public struct EnhanceImages: Equatable, Sendable { public var start: URL?; public var references: [URL] }` (vuoto = come oggi). Nuova proprietà osservabile `note: Note?` (`enum Note { case imagesNotSent }`), azzerata a ogni operazione.
- `GenerationController.enhancePrompt(in:)`: `start = control.startImageURL`; `references = traits(in: connection).usesMoodboard ? control.moodboardURLs : []`.
- `PromptCard`: sotto il pulsante, se `assistant.note == .imagesNotSent`, la riga `prompt.assist.note.imagesNotSent` in `.caption`, `.secondary` (non rossa: il miglioramento è avvenuto).
- Testi: `prompt.assist.note.imagesNotSent` «Immagini non inviate: nessun LLM per Migliora legge immagini.» / «Images not sent: no LLM for Enhance reads images.»; `prompt.enhance.help` aggiornato: «… usa anche l'immagine di partenza e la Moodboard, se ci sono» / «… also uses the start image and the Moodboard, when present».

## 7. Test

HubCoreTests: `imageLabels` (con/senza partenza, 0–3 riferimenti); `PromptBrief.enhance` con immagini (blocco + richiesta di oggi, `images` nell'ordine, senza immagini identico a oggi; versione con system prompt proprio); `LanguageModelRouter` con `needsImages` (salta il testo-solo per `.enhance`, `.imagesNotSupported` se solo testo-solo); `LanguageModelProfile.systemPrompt(for: .enhance, withImages:)`; `PromptAssistant.enhance` con immagini (resolve con `true`; ripiego su `false` con `note == .imagesNotSent` e richiesta senza immagini; `note` azzerata dall'operazione successiva; `.noModelSelected` resta `failure`).

## 8. Da verificare a mano

- Con Qwen3-VL su «Tutti gli altri · Entrambi»: un prompt che cita image 2 viene arricchito con dettagli veri della Moodboard e conserva «image 2».
- Con un solo LLM senza visione: nota «Immagini non inviate», prompt migliorato come oggi.
- Famiglia che non legge la Moodboard (SDXL): va solo l'immagine di partenza.

## 9. Fuori ambito

Ritaglio dell'immagine secondo l'inquadratura del canvas; limite al numero di immagini; maschera e disegno; Genera Prompt.

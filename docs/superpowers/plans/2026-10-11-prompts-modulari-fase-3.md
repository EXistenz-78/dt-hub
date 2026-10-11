# Prompt modulari — fase 3 (specialisti e AI Assistant) — piano di implementazione

> Eseguito inline (nativo) subito dopo la fase 2, sullo stesso ramo `prompts-fase2` (commit separati). Spec: `docs/superpowers/specs/2026-10-11-prompts-modulari-design.md` (§2, §3, §9, fase 3 di §11). Vale quanto detto nel piano della fase 2 per `DTHubPromptFolder`, i file di base, `custom/`, la riga di precedenza e `.bak`.

**Goal:** i prompt degli specialisti (Character Sheet, Prompt Master I4) e quelli di AI Assistant diventano file Markdown nelle loro cartelle `Data/<proprietario>/`; Character Sheet e I4 restano a sé (niente Rules + Family).

## Task 1: Character Sheet — `.txt` → `.md` (1.2)
- `CSTemplateFile` ha raw value `.md` e `legacyName` (`.txt`); `CSTemplates.load` legge `.md`, altrimenti il `.txt` d'un tempo, e toglie un'eventuale intestazione; `migrateLegacy(in:)` rinomina i `.txt` (stesso contenuto) senza sovrascrivere un `.md` esistente; `seedMissing` non scrive un `.md` accanto a un `.txt` rimasto; il plug-in migra all'avvio.
- Test (`CSTemplatesTests`): `.txt` ancora letto, `.md` vince, intestazione non fa parte del testo, migrazione, nessuna sovrascrittura, seed.
- Script (`make-builtin-texts.py`, `extract-from-workflow.py`) e README coi nomi `.md`.

## Task 2: Prompt Master I4 — master prompt in `.md` (1.2)
- `Data/prompt-master-i4/master-prompt.md` (`version: 1`) + `custom/master-prompt.md`; `I4Prompts` (`install`, `system(in:)`, `problems(in:)`); `IdeogramConfig` perde `system` (`ideogram4.json` 1.2.0, resta in `Data/prompt-master/`); `I4State.writeSystem` legge il file a ogni scrittura; avvisi nello stato; `DTHubPromptFolder.assemble` salta una Family vuota.
- Ruling: `ideogram4.json` non si sposta (config, non testo per l'LLM; Prompt Master ha già una `custom/` nella sua cartella: il master di I4 ha la sua).
- Test (`DataTests`): file scritto all'avvio, `system` uguale all'incorporato, custom `append`/`replace`/vuoto, file rotto o più vecchio con avviso, file proprio non riscritto.

## Task 3: AI Assistant — `rules/chat.md` + `custom/chat.md` (1.1)
- `ChatRules.builtIn` (MD con `{tab}`, `{guide}`, `{samplers}`); `SystemPrompt.make(context:samplerNames:folder:)` assembla regole + custom e poi riempie i segnaposto (lo stato della scheda per ultimo, così un `{guide}` scritto nel prompt dell'utente non viene letto come segnaposto).
- Test (`HistoryAndPromptTests`): il testo è **identico** a quello di prima (fotografia `LegacyChatPrompts` per un contesto completo e uno vuoto), dopo `install` uguale, `custom` accodato dopo la riga di precedenza, `replace` con segnaposto, file rotto o vecchio → incorporato, segnaposto nel prompt lasciato com'è.

## Review Focus (esercitati dai test sopra)
Intestazione rotta o `version` più vecchia → copia incorporata con avviso; file `custom` vuoto → ignorato; `.txt` e `.md` insieme → nessuna sovrascrittura; cartella di sola lettura → nessun errore (`DTHubPromptFolder.install`, già coperto in kit).

# Prompt Master

Un plug-in di DT Hub: un elenco di termini (8 gruppi → 40 categorie → 875 termini di fotografia, luce, colore, stile e
materia) che si scelgono con una casella, più una descrizione libera in qualsiasi lingua. «Scrivi prompt» manda tutto
all'LLM locale dell'app, con il master prompt della famiglia del modello scelto, e il prompt inglese che ne esce finisce
nel campo Prompt della Generazione (e nel negativo, per le famiglie che lo leggono).

- **Foto / Arte** guidano solo lo Shuffle (quali categorie pesca); **Shuffle** sostituisce la selezione con un termine a caso
  per categoria; **Shuffle scena** chiede all'LLM un soggetto e un'ambientazione e li scrive nella descrizione.
- **Termini personali:** «Aggiungi un termine» in fondo a ogni categoria (una stringa, in qualsiasi lingua).
- **Cosa riceve l'LLM:** la descrizione, poi i termini in inglese **con la loro categoria**, una riga per categoria
  (`Light Source: Starlight`, `Color Palette: Jewel tones`): la categoria dice come usare il termine (una luce, una palette,
  un genere) e evita che «butterfly lighting» diventi farfalle.
- **Qwen Image 2.1:** se nella cartella dei modelli c'è il prompt enhancer T2I ufficiale (`…PE-T2I…`, con il suo
  `system_prompt.txt` accanto ai pesi) il plug-in usa quello al posto dell'LLM generico, con una richiesta in prosa
  (la descrizione e una riga `Look: …`). Sotto il prompt compare il formato che suggerisce, con un pulsante **Applica** che
  porta larghezza e altezza della Generazione a quel rapporto, con la stessa area in pixel. Se il PE non c'è, vale il
  modello scelto con il master prompt di ripiego (che ha la stessa struttura, massimo 500 parole). Il PE I2I non c'è: è per un
  plug-in dedicato a Qwen Image 2.1.
- Funziona con 13 famiglie (`PMFamilies.all`); sulle altre il tab è grigio.

## I dati

Tre file JSON, ognuno con una copia incorporata nel plug-in (un bundle contiene solo la libreria):

| File | Dove | Chi lo scrive |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (condiviso con altri plug-in) | tu, per aggiornarlo |
| `master-prompts.json` | `…/Data/prompt-master/` | tu (la revisione dei master prompt arriva così) |
| `custom-terms.json` | `…/Data/prompt-master/` | il plug-in |

Vale il file se esiste, si legge, ha `schema` 1 e una `version` non più vecchia di quella incorporata; altrimenti vale la
copia incorporata (e se il file non si legge o ha un layout sconosciuto la riga di stato lo dice). Il plug-in non scrive mai i
primi due. Le copie incorporate e i file di `Data/` si rigenerano con `Scripts/make-prompt-data.py` da Prompt Master 2.0
(che non viene modificato).

## Costruirlo

    Plugins/PromptMaster/Scripts/build.sh OUT_FOLDER     # fa OUT_FOLDER/PromptMaster.dthubplugin
    cd Plugins/PromptMaster && swift test                # 112 test

Poi si aggiunge in DT Hub › Preferenze › Plug-in e si accende dal menu Plug-in dell'header. Richiede il contratto `llm`
con `system`, `model` e `options` e il `context` con `languageModels` e `parameters` (tappa 1).

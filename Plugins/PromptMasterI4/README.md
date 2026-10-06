# Prompt Master I4

Un plug-in di DT Hub per **Ideogram 4** (`ideogram_4`): compone la didascalia JSON a ordine fisso che il modello ha visto in
addestramento e la manda nel campo Prompt della Generazione. Si scelgono voci dal database dei termini (una per categoria),
si scrivono i testi, si definiscono gli elementi (oggetti e scritte, con il loro riquadro e i loro colori).

- **Card sinistra:** la descrizione generale (`high_level_description`); **Foto / Arte** (cambiando, le voci delle categorie
  che spariscono si cancellano); **Shuffle** (al massimo 3 categorie per sezione, una voce ciascuna; Medium e Background una
  sola); le sezioni **Aesthetics**, **Lighting**, **Photo** o **Art style**, **Medium** (categorie e voci, una voce per
  categoria, un solo Medium); la palette (fino a 16 colori); il background (testo e una voce di «Fondale e sfondo»).
- **Card destra:** gli elementi, una card ciascuno, chiusa all'inizio (un elemento nuovo si apre da solo): oggetto o testo,
  descrizione, menu **Text & Lettering** e testo verbatim (per le scritte), posizione `y0, x0, y1, x1` su 0–1000 (lati di
  almeno 20), palette fino a 5 colori, su/giù (l'ordine è l'ordine z), togli. In fondo **Aggiungi elemento senza posizione**,
  **Rivedi JSON** e **Invia**.
- **Rivedi JSON:** il testo del JSON, copiabile e modificabile a mano; è quello che «Invia» manda finché non si preme
  «Ripristina dai campi». **Invia** mette il JSON nel Prompt e svuota il negativo.
- Il JSON ha le chiavi nell'ordine dello schema: `photo` PRIMA di `medium`, `art_style` DOPO; senza `aspect_ratio`. Finché non
  c'è l'LLM (tappa 3) le voci entrano con il loro nome inglese (`en`) e i testi come sono stati scritti.

## I dati

| File | Dove | Chi lo scrive |
|---|---|---|
| `prompt-database.json` | `~/Library/Application Support/DT Hub/Data/` (lo stesso di Prompt Master) | tu, per aggiornarlo |
| `ideogram4.json` | `…/Data/prompt-master/` | tu: quali categorie alimentano ogni campo, le impostazioni dell'LLM, il master prompt |

Vale il file se esiste, si legge, ha `schema` 1, nessun id ripetuto e una `version` non più vecchia di quella incorporata;
altrimenti vale la copia incorporata (e se il file non si legge o ha un layout sconosciuto la riga di stato lo dice). Il
plug-in non scrive mai nessuno dei due. Le copie incorporate e i file di `Data/` si rigenerano con `Scripts/make-i4-data.py`
(il database si copia da `Plugins/PromptMaster/Data/`, che non viene modificato; un test controlla che siano uguali).

## Costruirlo

    Plugins/PromptMasterI4/Scripts/build.sh OUT_FOLDER   # fa OUT_FOLDER/PromptMasterI4.dthubplugin
    cd Plugins/PromptMasterI4 && swift test              # 58 test (I4_RENDER_DIR=cartella salva i PNG del tab)

Poi si aggiunge in DT Hub › Preferenze › Plug-in e si accende dal menu Plug-in dell'header. Il tab è grigio sulle famiglie
diverse da `ideogram_4` (e Prompt Master è grigio su `ideogram_4`).

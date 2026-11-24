# Plug-in Prompt Master Ming — design (24 novembre 2026)

Ramo `prompt-master-ming`. Plug-in per **Ming-Image 0.1 Design** (`ming_image`), nato dalla copia di Prompt Master MOSS e
adattato. Compatibile MCP dalla prima versione (spec MCP §22).

## Fonti

- **Sintassi e struttura del JSON:** il nodo ComfyUI di NidAll, [comfyui-ming-image-prompt-builder](https://github.com/NidAll/comfyui-ming-image-prompt-builder)
  (GPL-3.0, `nodes.py`): due chiavi, `canvas_settings` (`aspect_ratio`, `ambient_lighting`, `image_style`) e `layers` dallo sfondo al
  primo piano, quattro chiavi per livello (`description`, `coordinates`, `hierarchy_and_relation`, `color_specs`); coordinate
  `cx, cy, w, h` a tre decimali; rapporto ridotto con il MCD; testo canonico `A text element reading exactly "…" in …`; uscita
  `json.dumps(indent=2, ensure_ascii=False)`. Implementazione indipendente in Swift; il test `theExportIsByteForByteTheNodesPrettyJSON`
  confronta l'uscita con quella di Python.
- **Regole di composizione:** il Family prompt Ming v3 dell'app (`EmbeddedPrompts.swift`), che il plug-in riceve con il contesto
  (`promptGuide.familyPrompt`) e usa per «Componi con LLM»; `compose-prompt.md` ne è la copia di riserva (solo il caso JSON).
- **Funzionamento e codice:** Prompt Master MOSS (canvas, schede, catalogo, scrittura con LLM, sessione per progetto, strumenti MCP),
  con I4 e F3 come riferimento.

## Scelte

- **Elenco = ordine di Ming**: L1 è lo sfondo, l'ultimo livello sta davanti (il nodo tiene l'elenco al contrario e inverte
  all'export; qui non serve).
- **Tipi**: Oggetto e Testo. Il Testo ha le parole esatte a parte (mai mandate all'LLM) e l'aspetto delle lettere.
- **Termini del database**: le categorie della luce vanno in `ambient_lighting`, le altre in `image_style`; nascosti il negativo
  (Ming non lo legge), pose ed espressioni.
- **Import** (pulsante, barra sopra il canvas, strumento `import_json`): dal campo Prompt della Generazione, che arriva con il
  `context`. Valido solo se tutto il documento lo è; tollera recinzioni Markdown, `<think>`, colori non validi (scartati),
  chiavi in più. `aspect_ratio` letto in tutte le forme (`2:3`, `portrait, 832 x 1248 px`, `1024×1024`, parole); se la forma
  cambia, la dimensione della Generazione si imposta con `contribute.fields` (lato lungo invariato, multipli di 32).
- **Testi importati**: forma canonica (regola `_detect_text` del nodo) oppure una sola frase tra virgolette in una descrizione che
  parla di lettere (la forma del Family prompt). La descrizione originale si riscrive identica finché l'aspetto non cambia;
  cambiando solo le parole si sostituiscono al loro posto.
- **Annulla** copre scrittura, composizione, import e «Svuota» (un'istantanea dell'intero lavoro).

## Fatto dopo la prima prova

- Import tollerante: virgolette tipografiche, virgola mancante o in più si riparano (con un avviso); altrimenti l'errore dice riga e colonna.
- Interfaccia: simbolo `wand.and.stars` come gli altri Prompt Master; Importa, Annulla, Svuota solo icona; card di sinistra nell'ordine
  Foto/Arte e Shuffle, Image Style, gruppo Luce, Ambient Lighting, altri gruppi.
- Prompt Master 1.8 esclude `ming_image` (`PMFamilies.withDedicatedPlugin`).

## Da fare

- Prova reale in DT Hub con un LLM locale (Componi, Scrivi) e una generazione Ming dal JSON del plug-in.
- Screenshot `docs/images/prompt-master-ming.png` per il README.

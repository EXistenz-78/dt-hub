# Lista LoRA della tab Generazione: sezioni per categoria e ricerca

Data: 2026-11-18. Tocca `App/Generation/Cards/LoRACard.swift` e HubCore. Usa la categoria che LoRA Advisor 1.7 scrive nel `loras.json` dell'app (`CatalogLoRA.category`).

## Scopo
Il menu «Aggiungi LoRA» (e il menu sul nome di ogni LoRA scelta, che sostituisce) mostra oggi due sezioni: LoRA della famiglia del modello, poi di famiglia ignota. Con centinaia di LoRA è lungo da scorrere. Si vuole: la lista divisa per tipo (categoria) e un campo di ricerca.

## Design (approvato dall'utente in conversazione)
- Un `Menu` di sistema non può contenere un campo di testo: i due menu diventano **un popover** aperto dagli stessi pulsanti («Aggiungi LoRA» e il nome della LoRA, che sostituisce). In alto il campo di ricerca con il focus già dentro.
- **Sezioni per categoria**, nell'ordine Personaggio · Stile · Slider · Edit · Turbo · Senza categoria; dentro ogni sezione le LoRA per nome (stesso ordinamento di oggi, `localizedStandardCompare`). Le sezioni vuote non si mostrano.
- **Quali LoRA:** le stesse di oggi (`catalog.loras(for: family)`: quelle della famiglia del modello e quelle di famiglia ignota; con famiglia ignota tutte). Quelle di famiglia ignota portano una piccola etichetta («famiglia ignota»). La divisione per famiglia sparisce.
- **Ricerca:** per nome e trigger, senza maiuscole né accenti (`folding`), con una sottostringa; filtra tutte le sezioni. Con la ricerca vuota si vede tutto.
- **Comportamento:** un clic su una LoRA la aggiunge o la sostituisce (`controller.addLoRA` / `replaceLoRA`, come oggi) e chiude il popover; le LoRA già scelte sono disattivate; quella che si sta sostituendo ha il segno di spunta; la ricerca si azzera a ogni apertura; nessun risultato → testo «Nessuna LoRA trovata». Invio sceglie il primo risultato (scelta mia).
- **Logica pura in HubCore** con test: `LoRAPickerSections.make(loras: [CatalogLoRA], query: String) -> [Section]` (`Section { category: LoRACategoryKey?; loras: [CatalogLoRA] }`, categoria `nil` = senza categoria). La vista resta sottile.

## Non-obiettivi
Gestore LoRA (finestra), LoRA Advisor, ordinamento diverso, anteprime nel popover. Nessuna modifica ai dati.

## Decisioni mie
Invio sceglie il primo risultato; etichetta «famiglia ignota»; testi IT/EN nel catalogo delle stringhe dell'app; l'ordine fisso delle categorie; categoria sconosciuta = «Senza categoria».

# Default personalizzati per modello (design)

## Obiettivo
L'utente può salvare le impostazioni attuali di un modello (steps, guidance, sampler, shift, switch dello shift e LoRA con peso, modalità e trigger) come default di quel modello, e tornare ai default originali.

## Decisioni
- `App/Resources/RecommendedSettings.json` resta immutato e non viene copiato.
- Un file di soli override, `~/Library/Application Support/DT Hub/recommended-overrides.json`, ha lo stesso schema (`{"models": {…}}`) e contiene solo i modelli personalizzati.
- Strati, dal più debole al più forte: JSON dell'app, lista online di Draw Things (`merging`), override dell'utente. Gli override vincono sempre, anche sulla lista online.
- Chiave = nome del file senza quantizzazione (come oggi): il default vale per tutte le quantizzazioni del modello.
- Schede e pulsanti nella scheda Sampling: «Salva come default» e «Ripristina default». Disattivati senza modello scelto e per i modelli video (`VideoDefaults` resta separato e ha la precedenza).
- Salva: scrive o sostituisce la voce del modello selezionato. Ripristina: cancella la voce del modello e applica alla scheda i valori che restano (JSON/lista online/famiglia), se ce ne sono.
- Non si salvano dimensioni, seed, batch, schede Advanced.

## LoRA
- `RecommendedValues.loras: [LoRASelection]?`: `nil` = i LoRA della scheda non cambiano (come oggi); un elenco, anche vuoto, **sostituisce** i LoRA della scheda quando si sceglie il modello. Solo una voce salvata dall'utente ha `loras`.
- Un LoRA non installato sul server viene lasciato fuori; gli altri parametri si applicano comunque e sotto la scheda Sampling compare l'avviso «LoRA xxx mancante». Con catalogo vuoto (server non raggiungibile) non si filtra.

## Robustezza
- File mancante o rotto: nessun override. Scrittura atomica; una scrittura fallita perde la modifica al prossimo avvio.
- Voci rotte nel file sono ignorate, il resto resta.

## Test
`RecommendedSettingsTests`: lettura/scrittura di `loras`, strati (override > lista online > JSON), applicazione con LoRA mancanti, round-trip dello store.

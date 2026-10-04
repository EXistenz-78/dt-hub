# DT Hub — Plug-in Sphere Light Reference (SLR)

Data: 4 ottobre 2026 · Stato: realizzata · Primo plug-in vero; usa il contratto 1 così com'è (`2026-10-03-plugin-design.md`, `2026-10-04-preset-pipeline-design.md`)

## 1. Scopo

Portare dentro DT Hub l'app standalone **Sphere Light Reference** (`Draw Things/LightDirectionApp`, 1300 righe di Swift), che oggi funziona così: si dispongono fino a tre luci su una sfera, si preme Genera, la sfera 1024 px viene copiata negli appunti come `data:image/png;base64`, e uno script di Draw Things (`Light-Direction-Companion.js`) la incolla nel Moodboard e lancia una o due generazioni. Con il plug-in il giro negli appunti sparisce: la sfera arriva al Moodboard di DT Hub e la sequenza è una **pipeline di preset**.

Decisioni dell'utente (4 ottobre 2026):
- si parte da SLR, non da Prompt Master (che va rifatto quasi da zero);
- **l'app standalone resta com'è** e non si sviluppa più: il plug-in prende una **copia** del codice, senza pacchetto condiviso.

Fuori: Prompt Master e Qwen Image 2.1; modificare l'app standalone; uno slider del peso del LoRA nel plug-in (sta nel preset, deciso il 4 ottobre); il pulsante «Script» e il campo degli appunti dell'app standalone; la distribuzione (firma, notarizzazione, pagina di download).

## 2. Cosa fa il plug-in

Un tab «Sphere Light» con le stesse due colonne dell'app standalone:
- **Luci** (sinistra): da 1 a 3 blocchi comprimibili; per ognuno rotazione −180…180°, elevazione −90…90°, intensità 0,2…3, durezza dell'ombra 0…1, colore. Le luci predefinite, l'aggiunta (fino a 3) e la rimozione (non sotto 1) sono quelle dell'app.
- **Anteprima** (destra): la sfera 220 px, ricalcolata dopo 60 ms dall'ultimo movimento, con il rendering dell'app (`SphereRenderer`, 10 campioni d'ombra).
- **Invio**: due caselle e due pulsanti. Le caselle (checkbox, ricordate tra un avvio e l'altro): **«Overcast (ombre da nuvoloso)»**, che attiva o disattiva il primo passaggio della pipeline, e **«Salva anche sulla Scrivania»**, spenta all'inizio. I pulsanti:
  - **«Invia a Generazione»**: renderizza la sfera a 1024 px (16 campioni), la scrive nella cartella lasciata dall'app e manda la **pipeline** del §3;
  - **«Solo la sfera nel Moodboard»**: manda solo l'immagine (`moodboard`), per chi vuole usare prompt e parametri suoi.
  Con «Salva anche sulla Scrivania» accesa, i due pulsanti salvano anche una copia come `Sphere Light NNN.png` nella Scrivania, col primo numero libero (`001`, `002`…): un file esistente non si sovrascrive mai. Se il salvataggio fallisce lo dice nella riga di stato e l'invio al Moodboard va avanti.
- Una riga di stato sotto i pulsanti («Inviato», «Inviato. N conflitti nell'app», errori).

La sfera non parte mai da sola: né al muoversi di uno slider né all'attivazione. Così il plug-in non sovrascrive il lavoro dell'utente.

## 3. Preset e pipeline

Il plug-in registra all'**attivazione** (`activate`) due preset con acronimo **SLR** (risposta `existing` se ci sono già, mai sovrascritti):

| Preset | Prompt | Parametri | LoRA |
|---|---|---|---|
| `SLR · Overcast` | «make it an overcast day, remove the shadows» | passi 4, guidance 1, sampler 16 (DDIM Trailing), shift 3 con l'interruttore «Shift in base alla risoluzione» spento (acceso, Draw Things ignora lo shift), batch 1, CFG-Zero* spento | nessuno |
| `SLR · Match the sun` | «match light direction, colors and intensity from the reference image 2» | gli stessi | `flux_2_sun_direction_lora_v1_lora_f16.ckpt`, peso 0,6 |

I valori sono quelli dello script (`buildMatchSunConfig`, `FLATTEN_SHADOWS_CONFIG`). Il modello non è nei preset: lo sceglie l'utente (Flux 2 Klein 9B), il manifesto dichiara `families: ["flux2_9b"]` e il menu dei plug-in lo mostra grigio sulle altre famiglie.

«Invia a Generazione» manda `pipeline {name: "Sphere Light", steps}`:
1. con la casella Overcast **accesa**: `{title: "Overcast", preset: "SLR · Overcast"}` (parte dal canvas dell'utente), poi `{title: "Match the sun", preset: "SLR · Match the sun", moodboard: [sfera], useOutputAsStart: true}`;
2. con la casella Overcast **spenta**: il solo secondo passaggio, senza `useOutputAsStart`.

Il preset è sempre quello che l'utente vede nel menu: se cambia il peso del LoRA e lo salva con lo stesso nome, vale quello. Se lo cancella, il plug-in lo ricrea alla prossima attivazione. Se manca al Run, l'app dice «Preset non trovato».

## 4. Codice

Un pacchetto Swift **in questo repository**, `Plugins/SphereLight/`, con la struttura di `PluginKit/Examples/Sample` (libreria dinamica, kit con `moduleAliases` `SphereLightKit`, bundle con `make-bundle.sh`). Identificatore `com.exiztenz.dthub.spherelight`, classe principale `SphereLightEntry`, versione 1.0, simbolo `lightbulb.max`.

Si copiano dall'app standalone, senza cambiare la logica: `Vec3`, `LightParams` (`Models.swift`), `SphereRenderer`, `LightControlView`, la persistenza dello stato (`PersistedLight`/`PersistedState`, con le due caselle) e il salvataggio sulla Scrivania (`saveToDesktop`, che prende la cartella come parametro) con la chiave `com.exiztenz.dthub.spherelight.state.v1`. Cambiano:
- **Niente `DesignSystem.swift`**: i controlli sono quelli standard di SwiftUI (slider, `ColorPicker`, `Toggle`, pulsanti), come il resto del tab del Sample. Via `DSBackground`, `DSWindowConfigurator`, i pulsanti «vetro».
- **Niente `Bundle.module` né file `.strings`**: il bundle di un plug-in contiene solo la libreria. Le stringhe (italiano e inglese, scelte con la lingua preferita del sistema) stanno in una piccola tabella nel codice (`Strings.swift`).
- Il rendering in primo piano passa a `Task.detached` come nell'app.
- `SphereRenderer.pngData` scrive nella `tempFolder` del messaggio `context` un file `com.exiztenz.dthub.spherelight-sphere.png`; rinviare lo sostituisce nel Moodboard (il contratto sostituisce le immagini che lo stesso plug-in aveva mandato).
- Un piccolo tipo puro, `SLRMessages`, costruisce i JSON (preset, pipeline con e senza Overcast, solo Moodboard): è la parte testabile.

## 5. Test e verifiche

**Unitari** (target di test del pacchetto): `SLRMessages` (nomi dei preset con «SLR · », valori dei due preset, passaggi con e senza Overcast, `useOutputAsStart` solo con Overcast, il percorso della sfera nel Moodboard del secondo passaggio); `SphereRenderer` (dimensioni, PNG che si decodifica, il lato illuminato più chiaro del lato opposto per una luce a destra, due luci diverse danno immagini diverse); salvataggio sulla Scrivania (in una cartella di prova, mai la vera Scrivania: primo numero libero, `Sphere Light 001.png`; con `001` e `003` presenti scrive `004`; non sovrascrive; cartella inesistente = errore); persistenza (andata e ritorno di tre luci con colore e delle due caselle, un salvataggio senza luci vale come assente, al massimo tre luci); `Strings` (italiano e inglese hanno le stesse chiavi).
**Dal vivo** (istanza isolata di DT Hub): installare il bundle, accenderlo, vedere i due preset nel menu Preset; «Invia a Generazione» con la casella Overcast spenta e accesa mostra «Run · 1 passaggio»/«Run · 2 passaggi»; il Run con Klein e il LoRA reale; modificare il peso del LoRA nel preset e vedere che vale; sull'altra famiglia il plug-in è grigio; riaprendo l'app le luci tornano.

## 6. Rischi aperti

- Il LoRA `flux_2_sun_direction_lora_v1` e Klein 9B devono essere installati: il plug-in non li scarica e non controlla che ci siano (se manca, lo dice Draw Things).
- Il rendering a 1024 px con 16 campioni d'ombra è pesante: come nell'app standalone gira fuori dal thread principale, e il pulsante resta disattivato finché non finisce.
- La persistenza usa `UserDefaults` dell'app che ospita il plug-in, con una chiave sua: un'app e un plug-in non si pestano i piedi, ma la chiave è condivisa con i test.
- Il plug-in non è firmato né notarizzato: la distribuzione ad altri è un lavoro a parte.

## 7. Tappe

Una tappa sola: branch dedicato, spec → piano → prova su un `main` pulito → revisione → prova dell'utente → merge (come le altre).

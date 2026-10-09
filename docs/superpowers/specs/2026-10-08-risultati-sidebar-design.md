# Sidebar delle informazioni nella finestra Risultati — Design

Data: 8 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode e Swift.
Base: `origin/main` a `50e8a0e` (release 0.1.3).

## 1. Obiettivo

La finestra Risultati mostra l'immagine scelta, la striscia e pochi dati (seed). Si aggiunge una **sidebar richiudibile** a destra che mostra i dati dell'immagine selezionata: prompt, parametri e altri dati salvati nel suo EXIF.

Successo: scelta un'immagine (di questa sessione o ripristinata all'avvio), la sidebar mostra prompt, negativo, modello, parametri, LoRA, input, tempo e file; il testo si seleziona e si copia con il mouse; il tasto della finestra la apre e la chiude e la scelta è ricordata.

## 2. Decisioni (dell'utente, 8 ottobre)

- Contenuto: prompt, parametri e «eventuali altri dati».
- **Niente pulsante «Copia»:** il testo è selezionabile (`textSelection`) e basta.
- Approvato in chat: sidebar aperta al primo avvio e poi ricordata; mostra i dati dell'immagine primaria della selezione; sola lettura; la larghezza minima della finestra cresce con la sidebar aperta.

Decisioni prese da Claude (da confermare alla revisione):
1. **Sezione «Avanzate»** con i soli valori diversi dal default di `AdvancedParameters` (refiner, hires fix, clip skip…), nominati con la chiave del JSON. Costo se sbagliata: una sezione in più, che compare solo se serve.
2. **Il toggle è un pulsante** nella finestra (sopra l'area dell'immagine), senza voce di menu né scorciatoia.

## 3. Dati

Ogni `GeneratedImage` ha già `job: GenerationJob` (prompt, negativo, modello, `parameters`, `imageStrength`, `moodboardCount`, `maskSettings`), `elapsed`, `date`, `fileURL`, `saveError`. Per le immagini ripristinate all'avvio il `job` è letto dall'EXIF (`PNGImageStore.job(in:)`), quindi **la sidebar non legge l'EXIF per conto suo**.

## 4. Architettura

```
HubCore/Output/ResultInfo.swift         dalla GeneratedImage alle sezioni da mostrare (logica pura, testata)
App/Results/ResultInfoSidebar.swift     la vista della sidebar (testi localizzati, testo selezionabile)
App/Results/ResultsView.swift           il pannello a destra e il pulsante; preferenza ricordata
App/Localizable.xcstrings               testi it/en
```

### 4.1 `ResultInfo` (HubCore)

```swift
public struct ResultInfo: Equatable, Sendable {
  public enum Field: Equatable, Sendable {
    case prompt, sentPrompt, negativePrompt
    case model, size, seed, steps, guidance, sampler, shift, cfgZero
    case lora            // una riga per LoRA
    case imageStrength, moodboard, mask
    case advanced(key: String), extra(key: String)
    case time, date, fileName, folder, notSaved
  }
  public enum Kind: Equatable, Sendable { case prompt, model, loras, input, advanced, extra, file }
  public struct Row: Equatable, Sendable { public let field: Field; public let value: String }
  public struct Section: Equatable, Sendable { public let kind: Kind; public let rows: [Row] }
  public let sections: [Section]       // solo quelle con almeno una riga, in quest'ordine
  public init(_ image: GeneratedImage, locale: Locale = .current, timeZone: TimeZone = .current)
}
```

Regole delle righe (`value` già formattato, in lingua neutra salvo numeri e data, che seguono `locale`):

| Sezione | Riga | Quando | Valore |
|---|---|---|---|
| prompt | `prompt` | sempre (anche vuoto → riga assente se il testo è vuoto) | `job.prompt` |
| prompt | `negativePrompt` | non vuoto | `job.negativePrompt` |
| prompt | `sentPrompt` | `job.promptWithTriggers` ≠ `job.prompt` (con spazi ai bordi tolti) | `job.promptWithTriggers` |
| model | `model` | non vuoto | `job.model` |
| model | `size` | sempre | `"1024 × 1024"` |
| model | `seed` | sempre | `String(seed)` (nessun separatore delle migliaia) |
| model | `steps`, `guidance`, `sampler` | sempre | intero, numero, `sampler.displayName` |
| model | `shift` | sempre | `"auto"` se `resolutionDependentShift`, altrimenti il numero |
| model | `cfgZero` | `cfgZeroStar` acceso | `"<cfgZeroInitSteps>"` (passi iniziali) |
| loras | `lora` | una per LoRA | `"<file> · <peso> · <mode>"`, più `" · <trigger>"` se c'è |
| input | `imageStrength` | non nil | numero, 2 decimali al massimo |
| input | `moodboard` | `moodboardCount > 0` | il numero |
| input | `mask` | `maskSettings` non nil | `"blur 1.5 · outset 0 · preserve"` (`preserve` solo se `preserveOriginal`) |
| advanced | `advanced(key:)` | chiave di `AdvancedParameters` diversa dal default | il valore |
| extra | `extra(key:)` | una per voce di `parameters.extra` | valore JSON compatto |
| file | `time` | `elapsed` non nil | `ElapsedText.label` («42sec») |
| file | `date` | sempre | data e ora abbreviate secondo `locale`/`timeZone` |
| file | `fileName`, `folder` | `fileURL` non nil | nome file; percorso della cartella |
| file | `notSaved` | `saveError` non nil | il testo dell'errore |

«Avanzate»: si codificano `parameters.advanced` e `AdvancedParameters.default` in JSON e si elencano, in ordine alfabetico di chiave, quelle con valore diverso. Nessun elenco scritto a mano: un campo nuovo di `AdvancedParameters` compare da solo.

### 4.2 La vista

- Larghezza fissa 300 pt a destra dell'area attuale, separata da un `Divider`; sfondo e intestazioni di sezione con i componenti del design system già usati dalla finestra (`DSGroupHeader`).
- Ogni riga: etichetta piccola e secondaria sopra, valore sotto. `prompt`, `negativePrompt` e `sentPrompt` a tutta larghezza, con font del corpo e `textSelection(.enabled)`; le altre righe con carattere monospazio per seed e numeri. Tutto il testo è selezionabile.
- Scorre in verticale (`ScrollView`) se non entra.
- Nessuna immagine scelta (striscia vuota): messaggio «Nessuna immagine selezionata».
- Con più immagini selezionate: in cima una riga secondaria «N immagini selezionate: dati della principale».
- Durante un RUN con anteprima la sidebar continua a mostrare l'immagine scelta nella striscia, non l'anteprima (che non ha ancora un job salvato).

### 4.3 Apertura e chiusura

- `@AppStorage("results.sidebar.open")`, default `true`.
- Un pulsante `sidebar.trailing` (`DSGlassCircleButtonStyle`) in alto a destra dell'area dell'immagine, con `help` «Mostra/Nascondi le informazioni».
- Con la sidebar aperta la larghezza minima della finestra passa da 520 a 820 pt (`minWidth` condizionale); se la finestra è più stretta, AppKit la allarga. Da provare a mano.

## 5. Errori e casi limite

- Job senza campi opzionali: le sezioni vuote non compaiono.
- `Locale` e fuso orario passano da `ResultInfo.init` per poter testare date e numeri.
- Valori molto lunghi (prompt da 500 parole): scorrimento della sidebar, nessun troncamento.
- Immagine non salvata (`fileURL == nil`): riga `notSaved` con l'errore; niente `fileName`/`folder`.

## 6. Test

HubCoreTests: `ResultInfoTests` con la `GeneratedImage` costruita a mano (`testImage()` di `FakeBackend.swift`, job di prova): job minimo; job completo (tutte le righe nell'ordine delle sezioni); negativo vuoto → nessuna riga; trigger → `sentPrompt`; nessun trigger → nessuna `sentPrompt`; shift `auto`; CFG-Zero; LoRA con e senza trigger; mask; avanzate (solo diverse dal default, ordine alfabetico, nulla se uguali); extra; tempo assente; `fileURL` nil con `saveError`; locale italiano vs inglese per i decimali. L'app non ha test di UI: verifica a mano (§8).

## 7. Fuori ambito (YAGNI)

PNG esterni trascinati nell'app (EXIF non di DT Hub); modifica dei valori dalla sidebar; «applica solo questo campo»; confronto tra due immagini; menu o scorciatoia da tastiera; mostrare la Description PNG separata (è `sentPrompt`).

## 8. Da verificare a mano

- Immagine di questa sessione e immagine ripristinata all'avvio: stessi dati.
- Aprire e chiudere: la finestra si allarga/stringe, la scelta resta al riavvio.
- Selezionare e copiare un prompt con il mouse; scorrimento con prompt lungo.
- Più immagini selezionate: nota e dati della principale.
- Italiano e inglese; modalità chiara e scura.

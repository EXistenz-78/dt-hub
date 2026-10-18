# Percorsi predefiniti puliti e permessi — Design

Data: 18 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode.
Base: `origin/main` **0.3.0** (`e5e1875`).

## 1. Problema

Segnalazione su Reddit: lo scaricamento del modello LLM consigliato fallisce con un errore di permesso su `/Volumes/LLM-VLM/MLX`.

- **Causa principale:** `LanguageModelSettings.defaultFolder = "/Volumes/LLM-VLM/MLX"`, il disco dello sviluppatore.
  - Su un altro Mac il disco non c'è.
  - Il downloader crea `…/MLX/mlx-community/.dthub-download-<UUID>` con le cartelle intermedie, quindi prova a creare `/Volumes/LLM-VLM`.
  - `/Volumes` è di root: errore «You don't have permission».
- **Cause secondarie:**
  - in `Config/Info.plist` non c'è nessuna descrizione d'uso per i dischi esterni, i dischi di rete e le cartelle protette (Documenti, Scrivania, Download);
  - lo scanner degli LLM (`LanguageModelScanner`) e il controllo dei `.ckpt` (`FileSystemProbe.live.hasModelFiles`) usano `try?`, così una cartella **senza permesso** sembra **vuota**.

## 2. Cosa dice il codice degli altri percorsi (verificato il 18 ottobre)

- **Modelli di Draw Things (modalità «managed»):**
  - `modelsFolder` è vuoto di default; nessun percorso dello sviluppatore;
  - il pulsante «Usa la cartella dei modelli predefinita dell'app Draw Things» propone `~/Library/Containers/com.liuliu.draw-things/Data/Documents/Models`, solo se l'utente lo preme.
  - **Ha però lo stesso difetto secondario:** con una cartella senza permesso, `hasModelFiles` dà falso e l'avviso dice «Questa cartella non contiene modelli… scegli quella cartella», che è sbagliato.
  - Il server avviato da DT Hub legge i modelli con i permessi di DT Hub: anche lui ha bisogno delle descrizioni d'uso.
- **Programma `gRPCServerCLI`:** vuoto di default; `CLILocator` cerca solo in `~/Applications`, `/opt/homebrew/bin`, `/usr/local/bin`. Nessun problema.
- **Cartella di uscita:** `~/Pictures/DT Hub`, cartella standard non protetta. Nessun problema.
- **Altri dati** (preset, pipeline, sessione, server): `~/Library/Application Support/DT Hub/…`. Nessun problema.
- Una ricerca di `/Volumes`, `LLM-VLM` e `/Users/` nei sorgenti (app, pacchetti, kit, plug-in) trova solo `LanguageModelSettings`.

## 3. Decisioni (dell'utente, 18 ottobre)

- **Nuovo default LLM:** `~/Library/Application Support/DT Hub/LLM`.
  - Si crea alla prima apertura del Finder o al primo scaricamento, non all'avvio.
  - Resta modificabile come oggi (campo + «Scegli…»).
  - Nuovo pulsante **«Mostra nel Finder»** accanto a «Scegli…»: crea la cartella se manca e la apre.
- **Nessuna migrazione:** chi ha già salvato una cartella la tiene. Chi ha salvato il vecchio default lo tiene, e lo può cambiare.
- **Descrizioni d'uso** in `Config/Info.plist`, tradotte in `App/InfoPlist.xcstrings` (it/en), per:
  - `NSRemovableVolumesUsageDescription`;
  - `NSNetworkVolumesUsageDescription`;
  - `NSDocumentsFolderUsageDescription`;
  - `NSDesktopFolderUsageDescription`;
  - `NSDownloadsFolderUsageDescription`.
- **«Vuota» e «senza permesso» sono distinte**, sia per gli LLM sia per i modelli di Draw Things:
  - messaggio «DT Hub non ha il permesso di leggere questa cartella.»;
  - pulsante **«Apri Privacy e sicurezza»**, che apre il pannello File e cartelle.
- **Errore di scaricamento chiaro:** quando la cartella non si può creare o scrivere, si dice quale cartella e perché, invece del testo grezzo di sistema.

## 4. Dettagli

### 4.1 Cartella LLM

- `LanguageModelSettings.defaultFolder` diventa una proprietà calcolata: `applicationSupportDirectory` + `DT Hub/LLM`, come `UserPipelineStore.defaultFolder`.
- Il commento della proprietà `folder` non cita più `/Volumes/LLM-VLM/MLX`.
- **Il downloader non cambia** nel comportamento: crea la cartella con le intermedie. Con il default nuovo la crea dentro la Libreria dell'utente, dove può.

### 4.2 Stato di lettura di una cartella

Un tipo nuovo in HubCore, condiviso dai due casi:

```swift
public enum FolderAccess: Equatable, Sendable {
  case readable
  case missing   // non esiste (es. disco non collegato)
  case denied    // esiste, ma macOS non la fa leggere
}
public static func access(of path: String, fileManager: FileManager = .default) -> FolderAccess
```

- `missing`: `fileExists` falso.
- `denied`: `contentsOfDirectory` lancia un errore Cocoa `NSFileReadNoPermissionError` (257), oppure POSIX `EACCES`/`EPERM` nell'errore sottostante.
- Ogni altro errore conta come `readable`, come oggi.

### 4.3 Preferenze › LLM

- Sotto il campo, al posto di «Nessun modello trovato in %@»:
  - `missing`: «La cartella non esiste: verrà creata al primo scaricamento.» (testo grigio);
  - `denied`: «DT Hub non ha il permesso di leggere questa cartella.» (rosso) + pulsante «Apri Privacy e sicurezza»;
  - `readable` senza modelli: il testo di oggi.

### 4.4 Preferenze › Draw Things (managed)

- `FileSystemProbe` guadagna `folderAccess: (String) -> FolderAccess`.
- `ManagedServerSettings.Warning` guadagna `.modelsFolderDenied`, che ha la precedenza su `.noModelFiles`.
- Nel piè di pagina: il messaggio «senza permesso» (rosso) + «Apri Privacy e sicurezza».
- `validationError` non cambia: una cartella senza permesso non blocca l'avvio, perché macOS può chiedere il permesso al server.

### 4.5 Pulsante «Apri Privacy e sicurezza»

- Apre `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`.
- Se non si apre (macOS cambia gli indirizzi), apre `x-apple.systempreferences:com.apple.preference.security`.
- Un solo componente nell'app (`PrivacySettingsLink`), usato nelle due schede.

### 4.6 Errore di scaricamento

- In `HubLanguageModelDownloader`, un errore di `createDirectory` o `moveItem` con permesso negato diventa un caso nuovo, `LanguageModelError.folderNotWritable(String)`. L'app lo mostra col testo:
  - en: «DT Hub cannot write to %@. Choose another models folder, or allow access in Privacy & Security.»;
  - it (nell'app): «DT Hub non può scrivere in %@. Scegli un'altra cartella dei modelli, oppure consenti l'accesso in Privacy e sicurezza.»
- Il `%@` è la cartella dei modelli scelta in Preferenze, non la cartella temporanea.
- Sotto il testo, il pulsante «Apri Privacy e sicurezza».

### 4.7 Testi delle descrizioni d'uso

| Chiave | en | it |
| --- | --- | --- |
| Removable | DT Hub reads and saves models and images on the external disks you choose. | DT Hub legge e salva modelli e immagini sui dischi esterni che scegli. |
| Network | DT Hub reads and saves models and images on the network disks you choose. | DT Hub legge e salva modelli e immagini sui dischi di rete che scegli. |
| Documents | DT Hub reads and saves models and images in the folders you choose in Documents. | DT Hub legge e salva modelli e immagini nelle cartelle di Documenti che scegli. |
| Desktop | DT Hub reads and saves models and images in the folders you choose on the Desktop. | DT Hub legge e salva modelli e immagini nelle cartelle della Scrivania che scegli. |
| Downloads | DT Hub reads and saves models and images in the folders you choose in Downloads. | DT Hub legge e salva modelli e immagini nelle cartelle di Download che scegli. |

## 5. Verifica

- **Test automatici (HubCore, LLMBridge):**
  - `defaultFolder` finisce con `Application Support/DT Hub/LLM` e non contiene `/Volumes`;
  - `FolderAccess`: cartella esistente → `readable`; percorso inesistente → `missing`; cartella con `chmod 000` → `denied` (il test ripristina i permessi alla fine);
  - `warning()` dà `.modelsFolderDenied` con una sonda che risponde `denied`, anche se `hasModelFiles` è falso;
  - downloader: cartella dei modelli dentro una cartella `chmod 555` → errore con il testo nuovo e il percorso della cartella dei modelli.
- **Prove a mano** (su un utente macOS nuovo, o dopo `tccutil reset All com.exiztenz.dthub`):
  1. primo avvio: Preferenze › LLM mostra `~/Library/Application Support/DT Hub/LLM` e «La cartella non esiste…»;
  2. «Mostra nel Finder» crea e apre la cartella;
  3. scaricamento del modello consigliato riuscito;
  4. cartella su un disco esterno: macOS chiede il permesso col testo nuovo; con «Non consentire» compare il messaggio rosso e il pulsante apre File e cartelle;
  5. la stessa prova con la cartella dei modelli di Draw Things in modalità «managed»;
  6. un'installazione con il vecchio default salvato lo mantiene (nessuna migrazione).

## 6. Fuori ambito

- Migrare le impostazioni salvate.
- Segnalibri di sicurezza (`bookmarkData`): DT Hub non è in sandbox.
- Chiedere il permesso all'avvio.
- Spostare i modelli già scaricati.

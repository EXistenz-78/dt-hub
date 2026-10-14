# DT Hub su macOS 15 — Design

Data: 13 ottobre 2026. Stato: approvato in chat dall'utente; da implementare in una sessione locale con Xcode.
Base: `origin/main` **0.2.2** (`7f14521`). Aggiornata il 13 ottobre dopo la 0.2.2: otto plug-in (c'è LoRA Advisor) e pubblicazione come versione alternativa (§5).

## 1. Obiettivo

DT Hub e i plug-in funzionano su **macOS 15 Sequoia**, oltre che su macOS 26. Le funzioni restano tutte. Su macOS 15 manca solo il vetro Liquid Glass, sostituito da un materiale.

## 2. Cosa dice il codice (verificato il 13 ottobre)

- **L'unica API solo macOS 26 è `glassEffect`/`Glass`**, in `PluginKit/Sources/DTHubDesign/DSGlass.swift`. La usano 4 componenti di `DSButtons.swift`, e tramite loro la usano l'app e i plug-in.
- **Nessun `#available`/`@available`** e nessuna altra API recente (Span, InlineArray, Observations, NSGlassEffectView, TextSelection…).
- **API già disponibili su macOS 15:** `Tab` (macOS 15), `@Observable` e `onKeyPress` (macOS 14).
- **Dipendenze:** DrawThings-Swift dichiara macOS 15; mlx-swift e mlx-swift-lm macOS 14.
- **Ricontrollato sulla 0.2.2** (ricerca nel testo, il compilatore lo confermerà): il plug-in LoRA Advisor e i file nuovi dell'app (`CachedDownload`, `LiveModelList`) non usano API solo macOS 26.
- **Target oggi a 26:**
  - `DTHub.xcodeproj`: `MACOSX_DEPLOYMENT_TARGET = 26.0`, due configurazioni;
  - `Packages/Package.swift`;
  - `PluginKit/Package.swift`;
  - `PluginKit/Examples/Sample/Package.swift`;
  - 8 plug-in: SphereLight, QwenInpainting, PromptMaster, PromptMasterI4, AIAssistant, CharacterSheet, BatchPlus, LoRAAdvisor.

## 3. Decisioni

- **Target minimo `.macOS(.v15)` / `15.0` ovunque.** Un plug-in compilato per 15 funziona anche su 26; uno compilato per 26 non si carica su 15.
- **Ripiego del vetro**, in `DSGlass`:
  - `if #available(macOS 26, *)`: il codice di oggi;
  - altrimenti: `.background(.ultraThinMaterial, in: shape)`. Con una tinta, sotto il materiale c'è `shape.fill(tint)`, così il pulsante principale resta colorato. Sopra, un filo `shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)`. `interactive` non ha effetto su macOS 15.
- **Nessun altro cambiamento d'aspetto voluto:** su macOS 15 i controlli di sistema hanno lo stile di macOS 15.
- **API più nuove trovate dal compilatore:** ogni errore «only available in macOS 26» si chiude con `#available` e un ripiego equivalente. Ognuno va elencato nel messaggio finale.
- **Testi:**
  - `README.md`, Requirements: «macOS 15 Sequoia or later and an Apple Silicon Mac (Liquid Glass on macOS 26).»;
  - `PluginKit/README.md`, sezione «Writing a plug-in»: «Build with `platforms: [.macOS(.v15)]`: a plug-in built for a newer macOS does not load on macOS 15.»;
  - il commento di `DSGlass` («DT Hub requires macOS 26, so there is no material fallback») va riscritto.

## 4. Verifica

- **Compilazione e test:**
  - `xcodebuild … build` dell'app;
  - `swift test` in `Packages` e in `PluginKit`;
  - `swift build` e `swift test` in ognuno degli 8 plug-in;
  - `Scripts/build.sh` di ogni plug-in.
- **Controllo dei binari:** `vtool -show-build` (oppure `otool -l | grep -A3 LC_BUILD_VERSION`) sull'eseguibile dell'app e su ogni `.dylib` dei plug-in deve dare `minos 15.0`.
- **Prova a mano su macOS 15**, su un Mac o una macchina virtuale (UTM / Virtualization su Apple Silicon):
  1. avvio, Preferenze (4 schede), connessione al server in modalità «attach» e «managed»;
  2. RUN text-to-image; con immagine di partenza, maschera e pennello; Moodboard;
  3. Migliora/Genera Prompt con un LLM MLX (testo e visione);
  4. preset, pipeline dei plug-in e dell'utente;
  5. finestre Risultati, LoRA, Canvas;
  6. gli 8 plug-in caricati e usati una volta ciascuno (per LoRA Advisor: l'elenco, «Cerca le pagine» su un LoRA, un'anteprima trascinata);
  7. aspetto: pulsanti «pill», cerchi e pulsante principale leggibili, senza riquadri vuoti dove c'era il vetro.
- **Su macOS 26:** stessa prova veloce (1, 2, 7): nulla deve cambiare.

## 5. Pubblicazione: una versione alternativa, non unita

Deciso dall'utente il 13 ottobre: la versione per macOS 15 va provata da un utente che l'ha chiesta, **senza unirla in `main`** finché non è certo che non rompa nulla.

- **Ramo** `macos-15`, pubblicato su GitHub come ramo a sé; `main` resta la 0.2.2.
- **Pre-release** su GitHub con un tag suo, `v0.2.2-macos15` (`gh release create … --prerelease --target macos-15`). GitHub non conta le pre-release come «ultima versione»: i link del README (`releases/latest/download/…`) restano sulla 0.2.2.
- **File con nomi diversi dalla release normale:** `DT-Hub-0.2.2-macOS15-arm64.zip` e gli otto plug-in ricompilati dal ramo, `<Nome>-macOS15.dthubplugin.zip`. Quelli della 0.2.2 sono compilati per macOS 26 e non si caricano su macOS 15; quelli del ramo funzionano su entrambi.
- **Note della pre-release** (in inglese): è una versione di prova per macOS 15; servono i suoi plug-in; su macOS 15 non c'è il vetro; come segnalare i problemi (Issue).
- **Stessi dati della versione normale:** l'identificativo dell'app non cambia, quindi sullo stesso Mac le due versioni condividono cartella e preferenze. Per l'utente che prova, su un Mac con macOS 15, non è un problema.
- **Niente copia in `/Applications`** e nessun cambio al numero di versione dell'app: resta 0.2.2.
- **Dopo le prove:** se va bene, l'unione in `main` e la pubblicazione normale sono un passo a parte, con un altro via libera; la pre-release si può allora cancellare.

## 6. Fuori ambito

- macOS 14 o precedenti.
- Mac Intel.
- Un aspetto «Liquid Glass simulato» su macOS 15.
- Controllare la versione di macOS dei plug-in di terzi prima di caricarli (oggi il caricamento fallisce con l'errore di sistema).

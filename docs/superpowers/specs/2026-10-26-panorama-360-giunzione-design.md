# Panorama 360 — correzione della giunzione — spec

Data: 26 ottobre 2026. Stato: **approvata dall'utente a voce (26 ott)**; esecuzione nativa. Percorso: architetturale (una pipeline guidata dal plug-in), **nessuna aggiunta al contratto**.
Estende `2026-10-25-plugin-panorama-360-design.md` §9 e `2026-10-25-panorama-360-sfera-cutout-design.md`; è l'ultima funzione prevista.

## 1. Scopo
Il panorama generato ha una linea visibile dove si ricongiungono il bordo sinistro e quello destro. Un solo pulsante, **«Correggi giunzione»**, la elimina: rigenera la zona attorno alla giunzione con un preset a scelta dell'utente e rimette il risultato nel panorama, che va ai **Risultati**.

## 2. Scelte dell'utente
- Metodo (suo): ruotare il risultato di mezza larghezza (la giunzione al centro), **ritagliare il quadrato centrale**, **mascherare la parte centrale del quadrato (50% del lato)**, rigenerare con un **preset diverso da quello del LoRA 360** (niente LoRA 360, niente modello base: molto più veloce), rimettere la fascia nel panorama.
- **Niente verde** (serve solo al LoRA 360, che qui non si usa).
- **Interfaccia: un solo pulsante.** Nessun menu dei preset, nessuna larghezza regolabile, nessuna istruzione extra: il preset si chiama per nome (per ora **`PANO Test`**, segnaposto: Flux klein 9B KV, 4 passi, guidance 1, 1024×1024, prompt «Ricostruisci l'immagine in modo da eliminare la linea di congiunzione al centro»); l'utente cambierà nome e preset quando avrà trovato quello che funziona.
- Tutto si calcola sulle **dimensioni reali** del panorama: quadrato = altezza (2048×1024 → 1024×1024; 1024×512 → 512×512).
- La rimessa nel panorama è **automatica** a fine RUN (`session.end`); il ritaglio generato non va ai Risultati.
- Metodo di fusione preso da Tiled Upscale (dissolvenza `TUFade`, correzione di luminosità `TUTone`, copiati: i plug-in sono pacchetti indipendenti).

## 3. Il flusso
1. **Pulsante «Correggi giunzione»** nella barra della card Tela, in vista **Sfera** con sorgente **Risultato**. Attivo solo se l'ultimo risultato è leggibile, **2:1 (±4%)**, con **altezza multipla di 64** e **lato del quadrato ≤ 2048**; altrimenti spento con il motivo nel tooltip.
2. Premuto, il plug-in carica il risultato, lo ruota, prepara il passo e dichiara a DT Hub una **pipeline guidata a un passo** (`contribute.pipeline {"name","guided":true,"passes":1,"estimate":{preset,size}}`). L'utente vede «Run · 1 passo» e preme RUN.
3. `session.next` (indice 1): il plug-in risponde con **un passo autonomo**: `startImage` = il quadrato (PNG `s × s`), `mask` = grigio `s × s`, 255 sulla fascia centrale (`s/2` di larghezza, da `s/4` a `3s/4`), `maskSettings {blur, outset, preserveOriginal:true}`, `size {s,s}`, `preset "PANO Test"`, `strength 1`, nessun `fields` (prompt e parametri sono del preset). Un `session.next` successivo risponde `{"done":true}`.
4. `session.end` con `reason: finished` e `previous` (il quadrato generato): il plug-in prende la **fascia centrale** generata, la **corregge di luminosità** verso l'originale e la **fonde** nel panorama ruotato con dissolvenza sui bordi della fascia, **ruota di nuovo** di mezza larghezza e manda il PNG con `contribute.result` (descrizione «Giunzione corretta · fascia N px»; il risultato è accettato durante `session.end`). Con `stopped`, `failed` o `closed`, o senza `previous`, non manda nulla e lo dice nel riquadro.
5. Il panorama corretto diventa l'ultimo risultato: la sorgente Risultato lo mostra da sola.

## 4. Geometria (sul panorama `W × H`)
- `s = H` (lato del quadrato). Il quadrato del panorama ruotato va da `x = W/2 − s/2` a `W/2 + s/2` (la giunzione a `W/2`).
- Fascia (maschera) = `s/2` al centro: da `W/2 − s/4` a `W/2 + s/4`; contesto `s/4` per lato.
- Rotazione: le colonne si spostano di `W/2` (se `W` è dispari, di `W/2` arrotondato per difetto: nessun ricampionamento); ruotare due volte dà l'identità.
- Dissolvenza ai bordi della fascia: `fade = s/16` (64 px con `s = 1024`), rampa `smoothstep` dentro la fascia: peso 0 sul bordo, 1 a `fade` pixel.
- Correzione di luminosità sulla fascia generata: `gain = blur(luminanza originale) / blur(luminanza generata)`, limitato a 0,2…5, raggio del blur `s/32`, forza 100%, applicata ai colori della fascia.
- Costanti in un solo punto (`PSSeam`): `presetName`, `strength`, `maskBlur`, `maskOutset`, `bandFraction`, `fadeDivisor`, `toneRadiusDivisor`, `maxSquare` (2048). Valori di partenza: `maskBlur 24`, `maskOutset 0`.

## 5. Errori e casi limite
- Nessun risultato / illeggibile / non 2:1 / altezza non multipla di 64 / `s > 2048`: pulsante spento, motivo in tooltip e nel riquadro.
- Preset `PANO Test` mancante nel menu dei preset: l'app lo segnala come fa per ogni pipeline («preset non trovato»); il plug-in non lo crea (è dell'utente).
- Il risultato cambia tra «Correggi» e RUN (altro RUN, altro progetto): la sessione usa il panorama caricato al pulsante; se il plug-in è stato scaricato o la sessione non c'è, `session.next` risponde `{"done":true}`.
- Cambio di progetto durante la sessione: il risultato si manda lo stesso (lo archivia l'app sotto il progetto aperto); nessuna modifica allo stato del plug-in.
- Stop o errore del passo: nessun risultato, avviso nel riquadro.

## 6. Test
Geometria per i tre casi di dimensione e per i motivi di rifiuto; rotazione esatta (e doppia = identità); ritaglio e maschera nelle posizioni giuste; fusione (colore generato al centro, originale fuori, dissolvenza monotona, luminosità riportata verso l'originale, dimensione invariata); sessione (`next` con i file, `size`, preset, strength, maskSettings; secondo `next` = done; `end` finished/stopped/failed); giunzione davvero chiusa nel test end-to-end (colonne `0` e `W−1` prendono il colore generato); stato (pulsante e motivi, dichiarazione della pipeline); messaggi `session.*` instradati dal plug-in; PNG della card.

## 7. Fasi (4 task)
1. Geometria, rotazione, ritaglio, maschera e fusione (`PSSeam`, `PSSeamImages`), copie di `TUFade`/`TUTone`.
2. Sessione guidata (`next`/`end`) e risultato.
3. Stato, plug-in, pulsante, testi.
4. README, nota Obsidian e briefing, bundle e installazione, prove a mano.
Esecuzione nativa, una revisione finale con revisore indipendente.

## 8. Fuori
Menu dei preset, verde (LoRA 360), larghezza regolabile, istruzioni extra, «vai alla giunzione», ingrandimento del ritaglio a 1024 per i panorami piccoli (da aggiungere solo se i test mostrano la qualità scarsa a 512×512).

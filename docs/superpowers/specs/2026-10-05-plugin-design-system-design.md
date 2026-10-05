# DT Hub — Il design system nel kit dei plug-in

Data: 5 ottobre 2026 · Stato: realizzata · Estende `2026-10-03-plugin-design.md` (§3 confine app/plug-in, §7 tab) e `2026-10-04-plugin-sphere-light-design.md`

## 1. Scopo

I tab dei plug-in oggi non hanno l'aspetto dell'app (card di vetro, intestazioni, pulsanti a pillola, checkbox teal), perché il design system sta in `HubKit` e un plug-in non lo vede. Lo spostiamo in un modulo che il kit dei plug-in porta con sé, così i plug-in (Sphere Light adesso, Prompt Master e Qwen Image 2.1 dopo) hanno gli stessi componenti dell'app **senza copiarli**.

Decisione dell'utente (5 ottobre 2026): strada «A» — i componenti passano nel kit dei plug-in e `HubKit` li usa da lì. Il confine app/plug-in non cambia: sempre selettori e messaggi JSON; il design system è solo SwiftUI, nessuna classe Objective-C del kit.

Fuori: cambiare l'aspetto dei componenti; nuovi componenti oltre a quello del §3; ridisegnare altri tab; la distribuzione.

## 2. Struttura

Il pacchetto `PluginKit/` ottiene un secondo modulo e un secondo prodotto:

| Modulo | Contenuto | Chi lo usa |
|---|---|---|
| **`DTHubDesign`** (nuovo, prodotto `DTHubDesign`) | `DS` (colori, raggi, spaziature), `dsPanel`, `DSPanelHeader`, `DSGroupHeader`, `DSCollapsibleCard`, `DSCardRow`, `DSTabFrame`, `DSBackground`/`DSWindowConfigurator`, `dsGlass`, pulsanti e stili (`DSPillButtonStyle`, `DSGlassCircleButtonStyle`, `DSTabButtonStyle`, `DSCheckboxToggleStyle`, `DSMenuLabel`, `dsMenuPill`) — i file di `Packages/Sources/HubKit/DesignSystem/`, tranne `DSStatusDot` | `HubKit`; i plug-in |
| `DTHubPluginKit` (esistente) | contratto del plug-in, invariato; **non** riesporta il design system (vedi sotto) | i plug-in |
| `HubKit` | tiene `DSStatusDot` (dipende da `ConnectionStatus`, un tipo dell'app) e **riesporta** `DTHubDesign`: per l'app e per i suoi moduli niente cambia (`import HubKit` basta ancora) | l'app |

Dipendenze: `Packages/Package.swift` dipende da `../PluginKit` (solo il prodotto `DTHubDesign`); `DTHubPluginKit` non dipende da `DTHubDesign`: un plug-in prende i due prodotti, ognuno con il suo alias. L'app non collega `DTHubPluginKit`, quindi non ha le sue classi Objective-C (nessun duplicato con quelle dei plug-in).

**Un plug-in ha la sua copia**, rinominata: come già per il kit, `moduleAliases` dà nomi propri ai due moduli (`SphereLightKit`, `SphereLightDesign`). I tipi del design system sono tutti SwiftUI (struct, stili); l'unica sottoclasse di `NSView` (`DSWindowConfigurator`) prende il nome del modulo rinominato, quindi due plug-in e l'app non si urtano.

## 3. Un solo ritocco ai componenti

`DSCollapsibleCard` ottiene un accessorio opzionale a destra dell'intestazione (`trailing`), per il pulsante «togli» di una luce. Gli usi esistenti non cambiano (valore predefinito: nessun accessorio).

## 4. Sphere Light con l'aspetto dell'app

Il tab usa i componenti, senza cambiare la logica:
- **Luci** (sinistra): ogni luce è una `DSCollapsibleCard` («Luce N», icona `lightbulb`, accessorio «togli» in `DS.remove`) con gli slider (traccia teal) e il colore; «Aggiungi una luce» è un `DSGlassCircleButtonStyle` o una pillola; le carte stanno in una colonna con scorrimento.
- **Anteprima** (destra): un pannello `dsPanel` con la sfera, le due caselle (`DSCheckboxToggleStyle`) e i due pulsanti (`DSPillButtonStyle`, «Invia a Generazione» in evidenza), la riga di stato sotto.
- Titoli di sezione con `DSPanelHeader`/`DSGroupHeader`.
Le stringhe restano nella tabella `L` (niente `Bundle.module`).

## 5. Test e verifiche

**Unitari:** `HubKit` continua a esporre `DS` (un test in `HubKitTests` usa `DS.accent` e `DSPillButtonStyle` con il solo `import HubKit`); tutti i test esistenti (649 + 5 Python + 30 del plug-in) restano verdi senza cambiare un file di `App/` (a parte quelli che servono davvero).
**Compilazione:** l'app si costruisce con Xcode; il plug-in si costruisce con `build.sh`.
**Bundle:** nel bundle di Sphere Light non c'è nessun simbolo del modulo `DTHubDesign` senza alias (`nm` mostra solo `SphereLightDesign`); l'app con due plug-in caricati (Sample e Sphere Light) parte senza avvisi di classi duplicate nel log.
**Dal vivo:** il tab di Sphere Light ha card, pulsanti e checkbox come l'app, in chiaro e in scuro; luci, anteprima, Invia e salvataggio funzionano come prima.

## 6. Rischi aperti

- **Provato e non regge:** `@_exported import DTHubDesign` dentro il kit con `moduleAliases` dà «unable to resolve module dependency: 'DTHubDesign'». Un plug-in importa quindi i due prodotti con i loro alias (il README del kit lo dice).
- Xcode deve risolvere `PluginKit` come pacchetto locale tramite `Packages`: da provare con una build vera.
- Chi ha già un plug-in costruito con il kit vecchio non è toccato (il contratto non cambia); per usare il design system deve ricostruirlo.

## 7. Tappa

Una tappa sola: spec → piano da un prototipo verificato → Native → revisione indipendente → prova dell'utente → merge.

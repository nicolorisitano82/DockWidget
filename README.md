# Dock Widgets

Widget dentro il Dock di macOS, senza sostituirlo: due app che si mettono nel Dock
e disegnano la propria tile tramite `NSDockTilePlugIn` — API pubblica, nessuna
SPI privata per il funzionamento di base, nessun permesso TCC.

- **Orologio** (`DockClock.app`) — quadrante analogico o digitale, secondi, data, colore.
- **In riproduzione** (`DockNowPlaying.app`) — copertina, stato play/pausa, barra di avanzamento.

## Come funziona

Il Dock carica i bundle `.docktileplugin` di terze parti dentro
`com.apple.dock.external.extra.<arch>.xpc`, un servizio XPC che ha
`com.apple.security.cs.disable-library-validation` — per questo accetta codice
firmato da team diversi da Apple.

```
DockClock.app/
├── Contents/Info.plist              → NSDockTilePlugIn = "ClockWidget.docktileplugin"
├── Contents/MacOS/DockClock         → app host: finestra impostazioni + anteprima
└── Contents/PlugIns/ClockWidget.docktileplugin/
    ├── Contents/Info.plist          → NSPrincipalClass = "ClockDockTilePlugin"
    └── Contents/MacOS/ClockWidget   → Mach-O bundle
```

Il plug-in resta caricato finché l'app è nel Dock, **anche ad app chiusa**: il
Dock gli passa un `NSDockTile`, noi ci mettiamo dentro una `NSView` e chiamiamo
`display()` quando serve. Layout, magnification, auto-hide e multi-monitor li
gestisce il Dock.

Le impostazioni viaggiano nel dominio condiviso `dev.nicolo.dockwidgets`; l'app
host scrive e manda una notifica distribuita, il plug-in rilegge e ridisegna.

## Build

Serve solo `swiftc` dei Command Line Tools — niente Xcode.

```bash
./build.sh                          # arco nativo, firma ad-hoc
ARCHS="arm64 x86_64" ./build.sh     # universal
SIGN_IDENTITY="Developer ID Application: …" ./build.sh
```

Risultato in `build/`.

## Installazione

```bash
cp -R build/DockClock.app build/DockNowPlaying.app /Applications/
open /Applications/DockClock.app
```

Nella finestra: **Aggiungi al Dock** (aggiunge la tile e riavvia il Dock).
Alla prima comparsa macOS registra il plug-in come elemento in background:
se la tile resta l'icona dell'app, abilitalo in *Impostazioni di Sistema →
Generali → Elementi login ed estensioni*.

## In riproduzione: da dove arrivano i dati

Due canali, in ordine di preferenza:

1. **MediaRemote** (framework privato). Da macOS 15.4 risponde solo a processi di
   cui il sistema si fida: un'app normale riceve un dizionario vuoto. Il processo
   che carica il plug-in è firmato Apple, quindi vale la pena provare — il codice
   lo *sonda*, non lo dà per scontato. Se risponde: ogni player, copertina,
   posizione e controlli di riproduzione.
2. **Annunci di Music e Spotify** (`DistributedNotificationCenter`). Nessun
   permesso, nessuna API privata, ma solo quei due player, niente copertina
   (si usa l'icona del player) e niente controlli.

La finestra dell'app host mostra quale canale ha risposto.

## Limiti (della strada scelta, non dell'implementazione)

- La tile è quadrata e piccola: niente testo lungo. Titolo e artista stanno nel
  menu contestuale della tile.
- Click sulla tile = lancia/attiva l'app host. Dentro la tile non c'è interazione:
  il menu contestuale è l'unico punto di contatto.
- Un widget per app: due widget = due bundle nel Dock.
- L'utente può disattivare il plug-in dagli elementi in background.

Per widget larghi o cliccabili servirebbe un'altra strada (tile `spacer-tile` nel
Dock + finestra overlay allineata via Accessibility), molto più fragile.

## Struttura

```
Sources/Shared/       SystemAppearance, palette, store impostazioni, TileView, TilePlugin
Sources/Clock/        impostazioni, disegno del quadrante, classe principale del plug-in
Sources/NowPlaying/   stato, bridge MediaRemote, sorgente, disegno, classe principale
Sources/Host/         finestra AppKit: anteprima live, controlli, installazione nel Dock
Tools/MakeIcons/      genera le .icns disegnando la tile stessa
```

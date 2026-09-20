# Dock Widgets

Widget dentro il Dock di macOS, senza sostituirlo. Il Dock resta quello di sistema
e continua a fare il layout, l'ingrandimento e la scomparsa automatica: noi ci
mettiamo il contenuto.

**[Scarica la 1.0](https://github.com/nicolorisitano82/DockWidget/releases/latest/download/DockWidgets.dmg)** ·
[sito del progetto](https://nicolorisitano82.github.io/DockWidget/) · macOS 14+ · licenza MIT

Interfaccia in italiano e inglese, secondo la lingua del Mac.

## I widget

| Widget | Forma | Cosa fa |
|---|---|---|
| **Orologio** | tile | Sei quadranti: analogico, digitale, flip, anelli, minimale, a parole. Secondi, data, fuso orario |
| **In riproduzione** | tile o barra | Copertina vera, avanzamento cliccabile per saltare nel brano, comandi |
| **Appunto** | barra | Due righe sempre in vista, un click apre il pannello per scriverle |
| **Cartella** | tile | Contenuto, conteggio, ultimi arrivi. Il click apre, il drop ci sposta i file dentro. Icona colorabile come nel Finder |
| **Dischi** | tile o barra | Spazio per volume, unità esterne appena collegate, espulsione dal tasto destro |
| **Sensori** | tile o barra | CPU, memoria, disco, rete, batteria, watt assorbiti, stato termico |
| **Azioni** | barra | Quattro celle: icona, colori, e un'azione ciascuna |

Quasi tutti si possono moltiplicare con **+** e **−**: due orologi su fusi diversi,
due cartelle su posti diversi. *In riproduzione* no, e la ragione è funzionale
invece che tecnica — una copia ha senso solo se ha un soggetto proprio, e la
riproduzione in corso è una sola.

## Come funziona

Il Dock è un processo di sistema protetto: non ci si inietta codice. Ma ha due
porte aperte, ed entrambe sono API pubbliche.

```
DockWidgets.app
├── Contents/MacOS/DockWidgets              manager, vive nella barra dei menu
├── Contents/Library/Widgets/*.app          un'app per widget, ognuna con
│   └── Contents/PlugIns/*.docktileplugin   il plug-in che disegna la tile
└── Contents/Library/LoginItems/            l'agent che disegna le barre
```

**La tile** la disegna un `NSDockTilePlugIn`, che il Dock carica in un servizio XPC
riservato alle estensioni di terze parti e tiene vivo *anche ad app chiusa*.
Nessun permesso.

**La barra** ha bisogno di spazio: lo chiediamo al Dock inserendo delle
`spacer-tile`, leggiamo via Accessibility dove le ha messe e ci appoggiamo sopra
un pannello non attivante. Il layout resta suo, l'ingrandimento anche.

**Le copie** oltre la prima vengono create al momento in
`~/Library/Application Support/DockWidgets/Widgets`, firmate sul posto, e
riallineate al modello quando l'app viene aggiornata.

## Compilare

Serve solo `swiftc` dei Command Line Tools. Niente Xcode, niente dipendenze.

```bash
./Tools/make-signing-cert.sh   # una volta sola
./build.sh && ./install.sh
```

Il certificato self-signed non è un vezzo: macOS lega i permessi alla firma del
binario, e con una firma ad-hoc ogni ricompilazione ti farebbe riconcedere
l'Accessibilità da capo.

Altri comandi: `./Tools/make-dmg.sh` per l'immagine disco,
`ARCHS="arm64 x86_64" ./build.sh` per un binario universal.

## Struttura

```
Sources/Shared/      appearance, palette, impostazioni, basi delle viste, accesso AX al Dock
Sources/Clock/       quadranti e plug-in dell'orologio
Sources/NowPlaying/  stato, ponte MediaRemote, sorgente, viste
Sources/Note/        appunto
Sources/Folder/      monitor, icona colorabile, tile
Sources/Disks/       volumi montati, tile e barra
Sources/Sensors/     letture di sistema, campionatore, tile e barra
Sources/Actions/     celle, azioni, esecutore
Sources/Overlay/     l'agent e i controller delle barre
Sources/Manager/     finestra, catalogo, installazione nel Dock, copie
Tools/               icone, screenshot del sito, certificato, immagine disco
docs/                il sito, servito da GitHub Pages
```

## Aggiungere un widget

1. **Disegnalo.** Una `TileView` per la forma quadrata, una `BarContentView` per
   quella larga. Ogni misura è una frazione della tile, perché la dimensione la
   decide il Dock e cambia di continuo.
2. **Dichiaralo.** Una voce in `WidgetCatalog`: nome, simbolo, se è replicabile e,
   se è una barra, la sua larghezza minima.
3. **Configuralo.** Un `PaneViewController` per il pannello delle impostazioni.
4. **Compila.** `build.sh` assembla bundle, plug-in, icone e firma da solo.

## Cose imparate per strada

- Da macOS 15.4 **MediaRemote risponde solo ai processi di cui il sistema si fida**:
  stesso codice e stesso istante, 32 chiavi dentro il processo del Dock e zero
  dentro il nostro. Il plug-in è diventato il lettore privilegiato che passa i
  dati agli altri.
- Il Dock **conserva le chiavi che non conosce** dentro le sue voci: i nostri
  spazi portano una firma e si ritrovano ovunque vengano trascinati.
- Scrivere le preferenze e poi mandare `killall Dock` è una corsa che si perde:
  morendo, il Dock salva la copia che ha in memoria. La sequenza giusta è
  **sospendi, scrivi, uccidi da sospeso**.
- L'arte di un'icona macOS occupa **824 punti su 1024**; il resto è il margine
  dell'ombra.
- `powermetrics` vuole root. `IOReport` no, ma su 11.414 canali di questa macchina
  l'unico contatore di energia che si muove è quello della GPU: ogni dominio
  viene sondato, e quello che tace non compare nei menu.

## Licenza

MIT. Vedi [LICENSE](LICENSE).

# Underdock

Widget dentro il Dock di macOS, senza sostituirlo. Il Dock resta quello di sistema
e continua a fare il layout, l'ingrandimento e la scomparsa automatica: noi ci
mettiamo il contenuto.

**[Scarica la 1.3](https://github.com/nicolorisitano82/Underdock/releases/latest/download/Underdock.dmg)** ·
[sito del progetto](https://nicolorisitano82.github.io/Underdock/) · macOS 14+ · licenza MIT

Interfaccia in italiano e inglese, secondo la lingua del Mac.

## I widget

| Widget | Forma | Cosa fa |
|---|---|---|
| **Orologio** | tile | Nove quadranti: analogico, digitale, flip, anelli, minimale, a parole, binario, giornata, tabellone. Secondi, data, fuso orario |
| **In riproduzione** | tile o barra | Copertina vera, avanzamento cliccabile per saltare nel brano, comandi, testi sincronizzati |
| **Appunto** | barra | Due righe sempre in vista, un click apre il pannello per scriverle |
| **Cartella** | tile | Contenuto, conteggio, ultimi arrivi. Il click apre l'anteprima, il drop ci copia dentro — anche in una sottocartella. Icona colorabile come nel Finder |
| **Dischi** | tile o barra | Spazio per volume, unità esterne appena collegate, espulsione dal tasto destro |
| **Sensori** | tile o barra | CPU, memoria, disco, rete, batteria, watt assorbiti, stato termico |
| **Note** | tile o barra | Le note di Apple: l'ultima modificata, il conteggio, e il click apre quella nota |
| **Azioni** | barra | Quattro celle: icona, colori, e un'azione ciascuna |
| **Appuntamenti** | barra | Quello che c'è adesso e quello che viene dopo, dal calendario di Apple o da un indirizzo iCal segreto di Google |
| **Meteo** | barra | Tempo, temperatura, minima e massima del posto che scegli. Previsioni di Open-Meteo, senza chiave né account |
| **Mensola** | barra | Dove posare un file per un minuto: ci si trascina sopra, ci si trascina via. Niente viene spostato né copiato |

Quasi tutti si possono moltiplicare con **+** e **−**: due orologi su fusi diversi,
due cartelle su posti diversi. *In riproduzione* no, e la ragione è funzionale
invece che tecnica — una copia ha senso solo se ha un soggetto proprio, e la
riproduzione in corso è una sola.

## La barra del notch

Oltre al Dock c'è un secondo posto: il notch. Ci passi sopra il puntatore e
scende un pannello nero largo 400 punti — gli stessi widget, ma in una copia che
ha le sue impostazioni, indipendenti da quella nel Dock. Nel notch stanno
**solo** nella forma a barra.

Il pannello ha **quattro caselle**, e ogni widget dichiara quante ne prende: una,
oppure due dove la seconda ha qualcosa da dire. *In riproduzione* a due caselle
mette una copertina grande, i comandi e i testi; *Meteo* apre le ore che
vengono; *Appuntamenti* passa dal prossimo impegno alla giornata intera;
*Sensori* mette i valori in fila invece di alternarli; *Mensola* mostra quello
che ha dentro anziché contarlo. Chi non ha niente da metterci la seconda casella
non la offre nemmeno, e un widget cresciuto a due spinge fuori l'ultimo della
fila invece di sbordare.

In alto il pannello si apre verso l'esterno, come il notch vero dove incontra la
barra dei menu.

Il ritardo di apertura e quello di chiusura si regolano: il primo evita che il
pannello scenda mentre stai solo attraversando il bordo per arrivare alla barra
dei menu, il secondo ti lascia il tempo di rientrare se esci per sbaglio. Il
pannello non si riapre finché il puntatore non se ne è andato davvero, così un
puntatore parcheggiato lassù non lo fa lampeggiare.

### La striscia di azioni

Sotto l'ultimo widget può correre una striscia di **fino a dieci icone**,
bianche su nero, piccole, centrate: le stesse azioni del widget Azioni — aprire
un'app, un indirizzo, un comando rapido, un'azione di sistema — più lo specchio.

**Lo specchio** apre una finestra senza bordi con quello che vede la fotocamera,
centrata sullo schermo e rovesciata, come si aspetta chi ci si guarda. Si chiude
con la X in alto a sinistra, dove macOS tiene la chiusura da sempre. Pizzicando
si zooma verso il puntatore, la rotella sposta l'inquadratura, il doppio clic
rimette tutto a posto.

L'icona della fotocamera **scatta**: la foto finisce sulla Scrivania col nome
dell'istante in cui è stata presa, rovesciata come quella che vedevi. Il flash è
lo schermo — bianco su tutto il monitor e luminosità al massimo per il tempo
dello scatto, poi tutto com'era.

Accanto ci sono i
comandi della **luce ad anello** di macOS: accesa o spenta, cinque colori
dall'ambra all'azzurro, e quanta luce fare. I comandi stanno a riposo quasi
invisibili e si accendono sotto il puntatore, perché la cosa da guardare è
l'immagine.

Dentro il pannello, nel nero ai lati del notch, possono starci **luminosità** e
**volume**. Fanno parte del pannello: ci sono solo mentre è aperto e se ne
vanno con lui, così la barra dei menu resta la barra dei menu. Di norma mostrano
l'intensità; un clic ingrossa la barretta per trascinarla, la rotella la muove
di un passo — quanto grande lo decidi tu. La luminosità compare solo dove il Mac
la lascia leggere.

## Aggiornamenti

Underdock chiede a GitHub se c'è una versione nuova — una volta al giorno in
silenzio, o quando glielo chiedi dal menu — e mostra le note di rilascio prima
di scaricare niente. L'immagine disco scende nei Download come qualsiasi altro
file, e da lì puoi trascinarla a mano come sempre oppure farla mettere a posto
dall'app: monta l'immagine, controlla che dentro ci sia la stessa applicazione
firmata dalla stessa mano, si scambia col bundle in esecuzione e riparte. Un
aggiornamento firmato da qualcun altro viene rifiutato anche se l'indirizzo è
quello giusto.

## Come funziona

Il Dock è un processo di sistema protetto: non ci si inietta codice. Ma ha due
porte aperte, ed entrambe sono API pubbliche.

```
Underdock.app
├── Contents/MacOS/Underdock              manager, vive nella barra dei menu
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
`~/Library/Application Support/Underdock/Widgets`, firmate sul posto, e
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
- Il Dock conserva le chiavi che non conosce dentro le sue voci **finché non
  riscrive lui quella voce**, cosa che fa ogni volta che salva il proprio stato.
  Una prima misura diceva il contrario, ma aveva osservato un solo riavvio. Così
  uno spazio è nostro per *posizione* — sta subito dopo la tile del widget — e il
  marchio è soltanto un indizio.
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

# ATM10 ComputerCraft Monitor

Sistema di monitoraggio per server Minecraft ATM10 (All The Mods 10) basato su CC: Tweaked.

## Cosa fa

Dashboard interattiva su 5 monitor Advanced che mostra:
- **Energia** del Vibrant Capacitor Bank (Ender IO) con flusso I/O calcolato
- **Storage** del sistema Refined Storage (% spazio, count item, energia)
- **Produzione api** (Productive Bees) con tracking rate/h, EMA, proiezioni
- **Controllo mob farm remote** via 2 Redstone Relay su computer satellite
- **Health monitoring** dei sotto-sistemi con alert visivi

## Hardware necessario

### Computer centrale
- 1× Advanced Computer
- 5× Advanced Monitor (varie misure: 7×5 + 1×5 + 1×5 + 8×5 + 8×5)
- 1× Wired Modem (sul computer)
- 1× Ender Modem (sul computer, per parlare col satellite)
- 5× Wired Modem (uno per monitor)
- 1× RS Bridge (Advanced Peripherals) collegato al network RS
- 1× Wired Modem sul RS Bridge
- 1× Wired Modem sul Vibrant Capacitor Bank
- Networking Cable a sufficienza

### Computer satellite (vicino alle mob farm)
- 1× Computer (basta non-Advanced)
- 1× Ender Modem
- 1× Wired Modem
- 2× Redstone Relay (CC: Tweaked) — uno per mob farm
- 2× Wired Modem (uno per relay)
- Networking Cable

## Mod richieste

- CC: Tweaked
- Advanced Peripherals (RS Bridge)
- Refined Storage 2.x
- Ender IO (Vibrant Capacitor Bank)
- Productive Bees (qualsiasi versione, tracciamo i prodotti via RS)

## Deploy iniziale (PRIMA INSTALLAZIONE)

### Sul computer CENTRALE

```
label set Centrale
mkdir cfg
mkdir programs
mkdir lib
mkdir data
mkdir log
```

Crea manualmente il file `cfg/updates.lua` (è la scintilla che fa partire tutto).
Apri l'editor e incolla solo questo:

```
edit cfg/updates.lua
```

Contenuto:
```lua
return {
    repo_base = "https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor",
    branch    = "main",
    files     = { "cfg/updates.lua" }
}
```

Salva con Ctrl + Save + Exit. Poi scarica `update.lua`:

```
wget https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor/main/programs/update.lua programs/update.lua
programs/update
reboot
```

Da qui in poi `update` scarica tutto e `reboot` riavvia con `startup.lua`.

### Sul computer SATELLITE

```
label set Satellite
wget https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor/main/satellite/farm_server.lua farm_server.lua
wget https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor/main/satellite/startup.lua startup.lua
reboot
```

Il server parte automaticamente all'avvio.

## Aggiornamenti successivi

### Sul centrale
```
update
reboot
```

### Sul satellite
```
delete farm_server.lua
delete startup.lua
wget https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor/main/satellite/farm_server.lua farm_server.lua
wget https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor/main/satellite/startup.lua startup.lua
reboot
```

## Struttura del progetto

```
atm10-cc-monitor/
├── lib/                        # Librerie riutilizzabili
│   ├── gui.lua                 # Primitive grafiche con double buffering
│   ├── rs.lua                  # Wrapper RS Bridge
│   ├── energy.lua              # Wrapper Capacitor Bank con tracking flusso
│   ├── bees.lua                # Tracker prodotti api
│   ├── farm.lua                # Client rednet per il satellite
│   ├── logger.lua              # Logger con rotazione
│   └── health.lua              # Health tracking sotto-sistemi
├── cfg/                        # Configurazioni
│   ├── bees.lua                # Lista prodotti api da monitorare
│   ├── alerts.lua              # Soglie warning/critical
│   └── updates.lua             # Lista file per self-update
├── programs/                   # Eseguibili
│   ├── central.lua             # Dashboard principale
│   ├── runner.lua              # Watchdog con auto-restart
│   └── update.lua              # Self-update da GitHub
├── satellite/                  # File per il computer satellite
│   ├── farm_server.lua
│   └── startup.lua
├── startup.lua                 # Avvio automatico del centrale
└── README.md
```

## Configurazione

### Aggiungere/rimuovere prodotti api da monitorare

Edita `cfg/bees.lua` e aggiungi/rimuovi righe nella sezione `products`. Poi:
```
update
reboot
```

### Cambiare soglie di alert

Edita `cfg/alerts.lua`, modifica le soglie, commit & push, poi `update` + `reboot`.

## Log

Gli errori e gli eventi sono in `/log/central.log`. Visualizza con `edit /log/central.log`.

## Troubleshooting

**Il programma crasha continuamente:** controlla `/log/central.log` per vedere l'errore. Se il watchdog si arrende dopo 5 retry, lancia manualmente `programs/runner` per riprovare.

**Satellite OFFLINE persistente:** verifica che il computer satellite sia acceso e con il chunk caricato. Sul satellite digita `peripherals` per verificare che veda i 2 redstone_relay.

**Capacitor o RS "non disponibile":** un peripheral si è disconnesso. Il sistema riprova automaticamente ogni 5 secondi. Verifica spie dei Wired Modem e cavi.

## Sviluppato in collaborazione con Claude

Vedi conversazione di sviluppo per dettagli architetturali.

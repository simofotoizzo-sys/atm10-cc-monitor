-- /cfg/alerts.lua
-- Configurazione soglie per gli alert visivi.

return {
    energy = {
        warn_pct = 0.30,    -- < 30% giallo
        crit_pct = 0.15,    -- < 15% rosso lampeggiante
    },
    storage = {
        warn_pct = 0.80,    -- > 80% giallo
        crit_pct = 0.95,    -- > 95% rosso lampeggiante
    },
    -- timeout in secondi per considerare un sistema offline
    timeouts = {
        satellite_warn  = 30,
        satellite_crit  = 120,
        rs_warn         = 30,
        rs_crit         = 120,
        energy_warn     = 30,
        energy_crit     = 120,
    },
    -- frequenza lampeggio degli stati critici (secondi)
    blink_period = 1,
}
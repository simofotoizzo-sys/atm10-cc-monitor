-- /cfg/updates.lua
-- Configurazione del self-update via GitHub.
-- Quando aggiungi un nuovo file al repo, aggiungilo anche qui per scaricarlo
-- automaticamente via 'update' sul computer.

return {
    -- URL base raw del repo (senza branch finale)
    repo_base = "https://raw.githubusercontent.com/simofotoizzo-sys/atm10-cc-monitor",
    branch    = "main",

    -- Lista file da scaricare (path relativo al repo = path sul computer)
    files = {
        -- Librerie
        "lib/gui.lua",
        "lib/rs.lua",
        "lib/energy.lua",
        "lib/bees.lua",
        "lib/farm.lua",
        "lib/logger.lua",
        "lib/health.lua",

        -- Configurazioni
        "cfg/bees.lua",
        "cfg/alerts.lua",
        "cfg/updates.lua",   -- si auto-aggiorna

        -- Programmi
        "programs/central.lua",
        "programs/runner.lua",
        "programs/update.lua",

        -- Startup centrale
        "startup.lua",
    },
}

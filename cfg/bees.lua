-- /cfg/bees.lua
-- Configurazione prodotti monitorati per il dashboard api.
-- Per aggiungere un prodotto: aggiungi una riga { id = "...", label = "..." }.
-- L'ID deve corrispondere ESATTAMENTE all'ID interno Minecraft (vedi F3+H).

return {
    -- Intervallo di campionamento in secondi
    sample_interval = 30,

    -- Quanti campioni tenere in RAM (massimo storico)
    -- 2880 campioni × 30s = 24 ore
    history_max = 2880,

    -- File di persistenza dello storico
    history_file = "/data/bees_history.json",

    -- Ogni quanti sample salvare su file (60s = ogni 2 sample)
    save_every_n_samples = 2,

    -- Lista prodotti monitorati
    products = {
        { id = "minecraft:emerald",                  label = "Smeraldi" },
        { id = "minecraft:diamond",                  label = "Diamanti" },
        { id = "minecraft:iron_ingot",               label = "Iron Ingot" },
        { id = "allthemodium:allthemodium_nugget",   label = "ATM Nugget" },
        { id = "minecraft:coal",                     label = "Coal" },
        { id = "minecraft:copper_ingot",             label = "Copper" },
        { id = "minecraft:netherite_scrap",          label = "Netherite Scrap" },
        { id = "minecraft:gold_ingot",               label = "Gold" },
        { id = "minecraft:quartz",                   label = "Nether Quartz" },
        { id = "minecraft:lapis_lazuli",             label = "Lapis" },
    },
}
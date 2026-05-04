-- /programs/runner.lua
-- Watchdog: lancia central.lua e lo riavvia in caso di crash.

package.path = package.path .. ";/?.lua;/?/init.lua"
local logger = require("lib.logger")

local TARGET = "/programs/central.lua"
local MAX_RESTARTS_PER_MIN = 5
local RESTART_DELAY = 5

local restarts = {}

local function pruneOldRestarts()
    local cutoff = os.epoch("utc") - 60 * 1000
    while restarts[1] and restarts[1] < cutoff do
        table.remove(restarts, 1)
    end
end

print("=== RUNNER ===")
print("Target: " .. TARGET)
logger.info("Runner avviato")

while true do
    pruneOldRestarts()
    if #restarts >= MAX_RESTARTS_PER_MIN then
        local msg = "Troppi crash (" .. #restarts .. " in 60s). Mi fermo."
        print(msg)
        logger.error(msg)
        print("Per riprovare: lancia di nuovo /programs/runner.lua")
        return
    end

    print("")
    print("Avvio target...")
    logger.info("Avvio " .. TARGET)
    local ok, err = pcall(function() shell.run(TARGET) end)

    if ok then
        print("Target terminato normalmente.")
        logger.info("Target terminato normalmente")
        return
    else
        local msg = "CRASH: " .. tostring(err)
        print(msg)
        logger.error(msg)
        table.insert(restarts, os.epoch("utc"))
        print(("Riavvio fra %d secondi (crash %d/%d)"):format(
            RESTART_DELAY, #restarts, MAX_RESTARTS_PER_MIN))
        sleep(RESTART_DELAY)
    end
end

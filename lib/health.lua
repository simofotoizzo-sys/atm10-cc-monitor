-- /lib/health.lua
-- Tracking stato di salute dei sotto-sistemi.

local health = {}

local systems = {
    rs        = { ok = false, last_update = 0, label = "RS Bridge" },
    energy    = { ok = false, last_update = 0, label = "Capacitor" },
    satellite = { ok = false, last_update = 0, label = "Satellite" },
    bees      = { ok = true,  last_update = os.epoch("utc"), label = "Api Tracker" },
}

function health.set(systemId, ok)
    local s = systems[systemId]
    if not s then return end
    s.ok = ok == true
    if ok then s.last_update = os.epoch("utc") end
end

function health.get(systemId)
    return systems[systemId]
end

function health.getAll()
    return systems
end

-- Ritorna "ok", "warn", o "crit" basato sui timeouts in alerts.lua
function health.getStatus(systemId, timeouts)
    local s = systems[systemId]
    if not s then return "ok" end
    if s.ok then return "ok" end
    -- e' offline: quanto tempo e' passato dall'ultimo update?
    local elapsed = (os.epoch("utc") - s.last_update) / 1000
    local warnT = timeouts[systemId .. "_warn"] or 30
    local critT = timeouts[systemId .. "_crit"] or 120
    if elapsed >= critT then return "crit" end
    if elapsed >= warnT then return "warn" end
    return "warn"  -- appena offline, comincia gia' come warn
end

-- Aggregato: ritorna "ok", "degraded", "critical"
function health.overall(timeouts)
    local critCount, warnCount = 0, 0
    for id, _ in pairs(systems) do
        local st = health.getStatus(id, timeouts)
        if     st == "crit" then critCount = critCount + 1
        elseif st == "warn" then warnCount = warnCount + 1 end
    end
    if critCount > 0 then return "critical", critCount, warnCount end
    if warnCount > 0 then return "degraded", critCount, warnCount end
    return "ok", 0, 0
end

return health
-- /lib/energy.lua
-- Wrapper sopra un peripheral 'energy_storage' con tracking flusso I/O.
-- Specifico per Vibrant Capacitor Bank di Ender IO ma funziona con
-- qualsiasi peripheral che esponga getEnergy() e getEnergyCapacity().

local energy = {}

local cap = nil
local capName = nil

-- Storico circolare di campioni { time = os.epoch("utc"), e = energia }
local history = {}
local HIST_MAX = 120  -- circa 4 minuti se sample ogni 2s

-- ============================================================
-- Init
-- ============================================================
function energy.init(name)
    if name then
        cap = peripheral.wrap(name)
        capName = name
    else
        -- cerca per tipo specifico Ender IO, poi fallback su energy_storage generico
        local candidates = {}
        for _, n in ipairs(peripheral.getNames()) do
            local types = { peripheral.getType(n) }
            for _, t in ipairs(types) do
                if t == "enderio:vibrant_capacitor_bank"
                   or t == "enderio:capacitor_bank"
                   or t:find("capacitor") then
                    table.insert(candidates, 1, n) -- priorita' alta
                    break
                elseif t == "energy_storage" then
                    table.insert(candidates, n)    -- priorita' bassa
                    break
                end
            end
        end
        if #candidates > 0 then
            capName = candidates[1]
            cap = peripheral.wrap(capName)
        end
    end
    if not cap then return false, "Capacitor Bank non trovato" end
    return true
end

function energy.isReady()    return cap ~= nil end
function energy.getName()    return capName end

-- ============================================================
-- Letture base
-- ============================================================
function energy.getStored()
    if not cap then return 0 end
    local ok, v = pcall(cap.getEnergy)
    return (ok and v) or 0
end

function energy.getCapacity()
    if not cap then return 0 end
    local ok, v = pcall(cap.getEnergyCapacity)
    return (ok and v) or 0
end

function energy.getPct()
    local cap_ = energy.getCapacity()
    if cap_ <= 0 then return 0 end
    return energy.getStored() / cap_
end

-- ============================================================
-- Sampling: chiamare periodicamente (es. ogni 2s) per popolare lo storico
-- Ritorna lo snapshot corrente
-- ============================================================
function energy.sample()
    local now = os.epoch("utc")  -- ms
    local e = energy.getStored()
    table.insert(history, { t = now, e = e })
    if #history > HIST_MAX then
        table.remove(history, 1)
    end
    return now, e
end

-- ============================================================
-- Flusso istantaneo (tra penultimo e ultimo campione)
-- Ritorna FE/t (positivo = input, negativo = output)
-- ============================================================
function energy.getFlow()
    if #history < 2 then return 0 end
    local a = history[#history - 1]
    local b = history[#history]
    local dt_ms = b.t - a.t
    if dt_ms <= 0 then return 0 end
    -- FE/t: tick = 50ms in Minecraft
    local fe_per_tick = (b.e - a.e) / (dt_ms / 50)
    return fe_per_tick
end

-- ============================================================
-- Flusso medio su una finestra (default ultimi 10s)
-- ============================================================
function energy.getAvgFlow(seconds)
    seconds = seconds or 10
    if #history < 2 then return 0 end
    local cutoff = os.epoch("utc") - seconds * 1000
    -- trova il primo campione >= cutoff
    local first
    for i = 1, #history do
        if history[i].t >= cutoff then
            first = history[i]
            break
        end
    end
    if not first then first = history[1] end
    local last = history[#history]
    local dt_ms = last.t - first.t
    if dt_ms <= 0 then return 0 end
    return (last.e - first.e) / (dt_ms / 50)
end

-- ============================================================
-- Storico per grafico
-- Ritorna una copia dell'array { {t, e}, ... }
-- ============================================================
function energy.getHistory()
    local copy = {}
    for i, s in ipairs(history) do copy[i] = s end
    return copy
end

function energy.clearHistory()
    history = {}
end

-- ============================================================
-- Snapshot completo per la GUI
-- ============================================================
function energy.snapshot()
    if not cap then return { ok = false, err = "non inizializzato" } end
    local stored = energy.getStored()
    local capa   = energy.getCapacity()
    return {
        ok       = true,
        stored   = stored,
        capacity = capa,
        pct      = (capa > 0) and (stored / capa) or 0,
        flow     = energy.getFlow(),
        avg_flow = energy.getAvgFlow(10),
        history  = history,
    }
end

return energy
-- /lib/rs.lua  v4 — Aggiunge itemBreakdown per stacked bar
-- v3 — API moderna AP 0.7.5x+ per RS 2.x in 1.21.1
-- listItems -> getItems, campo amount -> count, listFluids -> getFluids

local rs = {}

local bridge = nil
local bridgeName = nil

function rs.init(name)
    if name then
        bridge = peripheral.wrap(name); bridgeName = name
    else
        bridge = peripheral.find("rs_bridge") or peripheral.find("rsBridge")
        if bridge then bridgeName = peripheral.getName(bridge) end
    end
    if not bridge then return false, "RS Bridge non trovato" end
    return true
end

function rs.isReady()       return bridge ~= nil end
function rs.getBridgeName() return bridgeName end

function rs.isConnected()
    if not bridge then return false end
    local ok, v = pcall(bridge.isConnected)
    return ok and v == true
end

local function safeCall(fn, default)
    if not fn then return default end
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return default
end

function rs.snapshot()
    if not bridge then return { ok = false, err = "bridge non inizializzato" } end
    if not rs.isConnected() then return { ok = false, err = "bridge offline" } end

    local s = { ok = true }

    -- Energia
    s.energy_used = safeCall(bridge.getStoredEnergy, 0)
    s.energy_max  = safeCall(bridge.getEnergyCapacity, 0)
    s.energy_pct  = (s.energy_max > 0) and (s.energy_used / s.energy_max) or 0
    s.energy_usage     = safeCall(bridge.getEnergyUsage, 0)
    s.energy_avg_input = safeCall(bridge.getAverageEnergyInput, 0)

    -- Item: somma disk + external
    local diskUsed   = safeCall(bridge.getUsedItemStorage, 0)
    local diskTotal  = safeCall(bridge.getTotalItemStorage, 0)
    local extUsed    = safeCall(bridge.getUsedExternalItemStorage, 0)
    local extTotal   = safeCall(bridge.getTotalExternalItemStorage, 0)
    s.item_used = diskUsed + extUsed
    s.item_max  = diskTotal + extTotal
    s.item_pct  = (s.item_max > 0) and (s.item_used / s.item_max) or 0

    -- Fluidi
    local fdUsed  = safeCall(bridge.getUsedFluidStorage, 0)
    local fdTotal = safeCall(bridge.getTotalFluidStorage, 0)
    local feUsed  = safeCall(bridge.getUsedExternalFluidStorage, 0)
    local feTotal = safeCall(bridge.getTotalExternalFluidStorage, 0)
    s.fluid_used = fdUsed + feUsed
    s.fluid_max  = fdTotal + feTotal
    s.fluid_pct  = (s.fluid_max > 0) and (s.fluid_used / s.fluid_max) or 0

    -- Chemicals
    local cdUsed  = safeCall(bridge.getUsedChemicalStorage, 0)
    local cdTotal = safeCall(bridge.getTotalChemicalStorage, 0)
    local ceUsed  = safeCall(bridge.getUsedExternalChemicalStorage, 0)
    local ceTotal = safeCall(bridge.getTotalExternalChemicalStorage, 0)
    s.chem_used = cdUsed + ceUsed
    s.chem_max  = cdTotal + ceTotal
    s.chem_pct  = (s.chem_max > 0) and (s.chem_used / s.chem_max) or 0

    return s
end

-- ============================================================
-- Top N item per quantita' (usa getItems, campo count)
-- ============================================================
function rs.topItems(n)
    n = n or 10
    if not bridge then return {} end
    local ok, items = pcall(bridge.getItems)
    if not ok or type(items) ~= "table" then return {} end

    table.sort(items, function(a, b)
        return (a.count or 0) > (b.count or 0)
    end)

    local result = {}
    for i = 1, math.min(n, #items) do
        local it = items[i]
        table.insert(result, {
            name        = it.name or "?",
            displayName = it.displayName or it.name or "?",
            amount      = it.count or 0,    -- normalizziamo a "amount" per uso esterno
        })
    end
    return result
end

-- ============================================================
-- Lookup di un item specifico
-- ============================================================
function rs.countItem(name)
    if not bridge then return 0 end
    local ok, item = pcall(bridge.getItem, { name = name })
    if not ok or not item then return 0 end
    return item.count or 0
end

function rs.getItem(name)
    if not bridge then return nil end
    local ok, item = pcall(bridge.getItem, { name = name })
    if not ok then return nil end
    if item then
        item.amount = item.count   -- alias per compatibilita'
    end
    return item
end

function rs.listItems()
    if not bridge then return {} end
    local ok, items = pcall(bridge.getItems)
    return (ok and items) or {}
end

function rs.listFluids()
    if not bridge then return {} end
    -- proviamo prima getFluids, fallback su listFluids
    local ok, fluids = pcall(bridge.getFluids)
    if ok and fluids then return fluids end
    ok, fluids = pcall(bridge.listFluids)
    return (ok and fluids) or {}
end

function rs.craftableItems()
    if not bridge then return {} end
    local ok, items = pcall(bridge.getCraftableItems)
    return (ok and items) or {}
end

-- ============================================================
-- Item breakdown: ritorna i top N item come % del totale "item_used"
-- Utile per stacked bar di composizione storage.
-- Ritorna: { breakdown = {{name, displayName, count, pct}, ...},
--           others = N, others_pct = P, total = T }
-- ============================================================
function rs.itemBreakdown(topN)
    topN = topN or 6
    if not bridge then return nil end
    local ok, items = pcall(bridge.getItems)
    if not ok or type(items) ~= "table" then return nil end

    -- Ordina per count desc
    table.sort(items, function(a, b) return (a.count or 0) > (b.count or 0) end)

    -- Calcola totale
    local total = 0
    for _, it in ipairs(items) do total = total + (it.count or 0) end
    if total == 0 then
        return { breakdown = {}, others = 0, others_pct = 0, total = 0 }
    end

    local breakdown = {}
    local othersCount = 0
    for i, it in ipairs(items) do
        if i <= topN then
            table.insert(breakdown, {
                name        = it.name or "?",
                displayName = it.displayName or it.name or "?",
                count       = it.count or 0,
                pct         = (it.count or 0) / total,
            })
        else
            othersCount = othersCount + (it.count or 0)
        end
    end

    return {
        breakdown  = breakdown,
        others     = othersCount,
        others_pct = othersCount / total,
        total      = total,
    }
end

return rs
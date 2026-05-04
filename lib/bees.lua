-- /lib/bees.lua
-- Tracking produzione prodotti via RS Bridge:
-- - sampling periodico
-- - storico circolare in RAM
-- - rate calculation su finestra mobile
-- - EMA (exponentially moving average) per trend stabile
-- - proiezione lineare a +N ore
-- - persistenza su file JSON

local rs = require("lib.rs")

local bees = {}

local cfg = nil
local history = {}   -- history[product_id] = { {t=epoch_ms, c=count}, ... }
local sample_count = 0

-- ============================================================
-- Init
-- ============================================================
function bees.init(config)
    cfg = config
    if not cfg then error("bees.init: config mancante") end
    if not cfg.products or #cfg.products == 0 then
        error("bees.init: nessun prodotto configurato")
    end

    -- Inizializza storico vuoto per ogni prodotto
    for _, p in ipairs(cfg.products) do
        history[p.id] = history[p.id] or {}
    end

    -- Tenta caricamento da file
    bees.loadHistory()

    return true
end

-- ============================================================
-- Persistenza
-- ============================================================
function bees.saveHistory()
    if not cfg or not cfg.history_file then return end
    -- crea cartella se mancante
    local dir = cfg.history_file:match("(.+)/[^/]+$")
    if dir and not fs.exists(dir) then fs.makeDir(dir) end

    local f = fs.open(cfg.history_file, "w")
    if not f then return false end
    f.write(textutils.serialiseJSON(history))
    f.close()
    return true
end

function bees.loadHistory()
    if not cfg or not cfg.history_file then return end
    if not fs.exists(cfg.history_file) then return end
    local f = fs.open(cfg.history_file, "r")
    if not f then return end
    local content = f.readAll()
    f.close()
    local ok, data = pcall(textutils.unserialiseJSON, content)
    if ok and type(data) == "table" then
        history = data
        -- assicura una entry per ogni prodotto, anche nuovi rispetto al file
        for _, p in ipairs(cfg.products) do
            history[p.id] = history[p.id] or {}
        end
    end
end

-- ============================================================
-- Sampling
-- ============================================================
function bees.sample()
    if not cfg then return end
    local now = os.epoch("utc")

    for _, p in ipairs(cfg.products) do
        local count = rs.countItem(p.id) or 0
        local h = history[p.id]
        table.insert(h, { t = now, c = count })
        -- mantieni dimensione storico
        while #h > cfg.history_max do
            table.remove(h, 1)
        end
    end

    sample_count = sample_count + 1
    if sample_count % (cfg.save_every_n_samples or 2) == 0 then
        bees.saveHistory()
    end
end

-- ============================================================
-- Letture istantanee
-- ============================================================
function bees.getCount(productId)
    local h = history[productId]
    if not h or #h == 0 then return 0 end
    return h[#h].c
end

-- ============================================================
-- Rate calcolato su finestra mobile (FE/h equivalente: unita'/h)
-- ============================================================
-- Ritorna unita'/ora calcolato sui sample negli ultimi 'minutes' minuti
function bees.getRate(productId, minutes)
    minutes = minutes or 30
    local h = history[productId]
    if not h or #h < 2 then return 0 end

    local now = os.epoch("utc")
    local cutoff = now - minutes * 60 * 1000

    -- trova primo sample >= cutoff
    local first
    for i = 1, #h do
        if h[i].t >= cutoff then first = h[i]; break end
    end
    if not first then first = h[1] end

    local last = h[#h]
    local dt_h = (last.t - first.t) / (1000 * 3600)  -- ore
    if dt_h <= 0 then return 0 end
    return (last.c - first.c) / dt_h
end

-- ============================================================
-- EMA (exponential moving average)
-- alpha basso = piu' smoothing. tau in secondi.
-- ============================================================
function bees.getEMA(productId, tauSeconds)
    tauSeconds = tauSeconds or 1800  -- 30 min
    local h = history[productId]
    if not h or #h < 2 then return 0 end

    local ema_rate = nil
    for i = 2, #h do
        local dt_s = (h[i].t - h[i-1].t) / 1000
        if dt_s > 0 then
            local instant_rate = (h[i].c - h[i-1].c) / dt_s * 3600  -- unita'/h
            if ema_rate == nil then
                ema_rate = instant_rate
            else
                local alpha = 1 - math.exp(-dt_s / tauSeconds)
                ema_rate = ema_rate + alpha * (instant_rate - ema_rate)
            end
        end
    end
    return ema_rate or 0
end

-- ============================================================
-- Trend: 1 = salita, 0 = stabile, -1 = discesa
-- ============================================================
function bees.getTrend(productId)
    local rate = bees.getRate(productId, 30)
    if math.abs(rate) < 1 then return 0 end
    return rate > 0 and 1 or -1
end

-- ============================================================
-- Proiezione lineare: count fra hours ore (basata su rate 30m)
-- ============================================================
function bees.project(productId, hours)
    local current = bees.getCount(productId)
    local rate = bees.getRate(productId, 30)  -- unita'/h
    return current + rate * hours
end

-- ============================================================
-- Snapshot di un prodotto
-- ============================================================
function bees.snapshot(productId)
    return {
        id        = productId,
        count     = bees.getCount(productId),
        rate_30m  = bees.getRate(productId, 30),
        rate_ema  = bees.getEMA(productId, 1800),
        trend     = bees.getTrend(productId),
        n_samples = #(history[productId] or {}),
    }
end

-- ============================================================
-- Snapshot di tutti i prodotti
-- ============================================================
function bees.snapshotAll()
    if not cfg then return {} end
    local result = {}
    for _, p in ipairs(cfg.products) do
        local s = bees.snapshot(p.id)
        s.label = p.label
        table.insert(result, s)
    end
    return result
end

-- ============================================================
-- Storico raw (per grafici)
-- ============================================================
function bees.getHistory(productId, lastN)
    local h = history[productId] or {}
    if not lastN then return h end
    local result = {}
    local start = math.max(1, #h - lastN + 1)
    for i = start, #h do table.insert(result, h[i]) end
    return result
end

function bees.getProducts()
    return cfg and cfg.products or {}
end

return bees
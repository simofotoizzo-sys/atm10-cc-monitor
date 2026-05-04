-- /programs/central.lua  v4 — MGS Codec style
-- Layout completo MGS per i 5 monitor con bordi Unicode, sparkline,
-- stacked bar storage, grafici dettagliati, palette fosforo.

package.path = package.path .. ";/?.lua;/?/init.lua"

local gui    = require("lib.gui")
local rs     = require("lib.rs")
local energy = require("lib.energy")
local bees   = require("lib.bees")
local farm   = require("lib.farm")
local cfg    = require("cfg.bees")
local alerts = require("cfg.alerts")
local health = require("lib.health")
local logger = require("lib.logger")

print("=== CENTRAL DASHBOARD v4 (MGS Codec) ===")
logger.info("Central v4 (MGS Codec) avviato")

local rsOk = rs.init();   health.set("rs",     rsOk)
local enOk = energy.init();health.set("energy", enOk)
bees.init(cfg)
local fmOk = farm.init(); health.set("satellite", fmOk)

local p_top   = gui.attach("top")
local p_bar1  = gui.attach("monitor_1")  -- storage stack
local p_bar2  = gui.attach("monitor_2")  -- energy bar
local p_lat3  = gui.attach("monitor_3")  -- energy detail
local p_lat4  = gui.attach("monitor_4")  -- api dashboard

p_top:setScale(1)
p_bar1:setScale(1)
p_bar2:setScale(1)
p_lat3:setScale(0.5)
p_lat4:setScale(0.5)

local state = {
    farms          = { [1] = false, [2] = false },
    api_tab        = "lista",
    api_prod_idx   = 1,
    api_proj_hours = 6,
    blink_on       = true,
    storage_breakdown = nil,   -- cached
    last_storage_breakdown = 0,
}

-- Palette MGS Codec
local P = gui.palette
local C = gui.chars

-- ============================================================
-- Helpers formato
-- ============================================================
local function fmt(n)
    n = n or 0
    local sign = ""
    if n < 0 then sign = "-"; n = -n end
    if n >= 1e9 then return sign .. ("%.2fG"):format(n / 1e9)
    elseif n >= 1e6 then return ("%s%.2fM"):format(sign, n / 1e6)
    elseif n >= 1e3 then return ("%s%.1fk"):format(sign, n / 1e3)
    else return sign .. tostring(math.floor(n)) end
end

local function fmtRate(r)
    return ((r >= 0) and "+" or "") .. fmt(r) .. "/h"
end

local function trendArrow(t)
    if t > 0 then return "^", colors.lime
    elseif t < 0 then return "v", colors.red
    else return "-", colors.gray end
end

local function shorten(s, maxLen)
    s = tostring(s)
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 1) .. "."
end

-- Estrae nome leggibile da modid:itemid
local function shortName(s)
    s = tostring(s or "?")
    local _, _, name = s:find(":(.+)$")
    name = (name or s):gsub("_", " "):upper()
    return name
end

-- Color con alert blink
local function energyColorAlert(pct)
    if pct < alerts.energy.crit_pct then
        return state.blink_on and P.fg_crit or P.bg, "crit"
    elseif pct < alerts.energy.warn_pct then
        return P.fg_warn, "warn"
    end
    return P.fg_main, "ok"
end

local function storageColorAlert(pct)
    if pct > alerts.storage.crit_pct then
        return state.blink_on and P.fg_crit or P.bg, "crit"
    elseif pct > alerts.storage.warn_pct then
        return P.fg_warn, "warn"
    end
    return P.fg_main, "ok"
end

-- Colori per stacked bar storage (cromaticamente distinti)
local STACK_COLORS = {
    colors.lime,
    colors.yellow,
    colors.orange,
    colors.magenta,
    colors.cyan,
    colors.lightBlue,
}
local OTHERS_COLOR = colors.gray

-- ============================================================
-- Render TOP (monitor centrale 7x5, 49x25 char scale 1)
-- ============================================================
local function renderTop()
    local W, H = p_top:size()
    p_top:clear()
    p_top.buttons = {}

    -- Box esterno
    p_top:box(1, 1, W, H, P.border)

    -- ================ HEADER ================
    p_top:text(3, 1, " CODEC LINK ACTIVE ", P.accent, P.bg)
    -- health indicator a destra del titolo
    local overall = health.overall(alerts.timeouts)
    local hLabel, hCol
    if overall == "ok" then
        hLabel = "[OK]"; hCol = P.fg_main
    elseif overall == "degraded" then
        hLabel = "[DEGRADED]"; hCol = P.fg_warn
    else
        hLabel = "[CRITICAL]"
        hCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(24, 1, hLabel, hCol, P.bg)
    -- clock a destra
    local time_str = textutils.formatTime(os.time("local"), true)
    p_top:text(W - #time_str - 2, 1, time_str, P.fg_label, P.bg)

    -- ================ ENERGY ================
    local sectY = 3
    p_top:divider(1, sectY, W, P.border)
    p_top:text(3, sectY, " [ENERGY] VIBRANT CAP ", P.accent, P.bg)

    local es = energy.snapshot()
    health.set("energy", es.ok)
    if es.ok then
        local ecol = energyColorAlert(es.pct)
        -- riga numerica primaria
        p_top:text(3, sectY + 1, "STORED   :", P.fg_label, P.bg)
        p_top:text(14, sectY + 1, ("%s / %s FE"):format(fmt(es.stored), fmt(es.capacity)), P.fg_value, P.bg)
        local pctStr = ("%.1f%%"):format(es.pct * 100)
        p_top:text(W - #pctStr - 2, sectY + 1, pctStr, ecol, P.bg)

        -- riga flow
        local flow = es.flow or 0
        local fcol = (flow >= 0) and P.fg_main or P.fg_crit
        local fstr = ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t"
        p_top:text(3, sectY + 2, "FLOW     :", P.fg_label, P.bg)
        p_top:text(14, sectY + 2, fstr, fcol, P.bg)

        -- sparkline 1H (ultime 1800 sample = 1h)
        local hist = energy.getPctHistory(1800)
        p_top:text(3, sectY + 3, "1H HIST  :", P.fg_label, P.bg)
        if #hist >= 2 then
            p_top:sparkline(14, sectY + 3, W - 16, hist,
                { color = ecol, min = 0, max = 1 })
        else
            p_top:text(14, sectY + 3, "(in raccolta...)", P.fg_dim, P.bg)
        end
    else
        p_top:text(3, sectY + 1, "OFFLINE - retry auto", P.fg_crit, P.bg)
    end

    -- ================ STORAGE ================
    sectY = sectY + 5
    p_top:divider(1, sectY, W, P.border)
    p_top:text(3, sectY, " [STORAGE] REFINED ", P.accent, P.bg)

    local rss = rs.snapshot()
    health.set("rs", rss.ok)
    if rss.ok then
        p_top:text(3, sectY + 1, "ITEMS    :", P.fg_label, P.bg)
        p_top:text(14, sectY + 1, ("%s / %s"):format(fmt(rss.item_used), fmt(rss.item_max)), P.fg_value, P.bg)
        local pctStr = ("%.3f%%"):format(rss.item_pct * 100)
        p_top:text(W - #pctStr - 2, sectY + 1, pctStr, P.fg_main, P.bg)

        p_top:text(3, sectY + 2, "ENERGY   :", P.fg_label, P.bg)
        p_top:text(14, sectY + 2, fmt(rss.energy_used) .. " FE", P.fg_value, P.bg)
        local usageStr = "USAGE: " .. tostring(rss.energy_usage) .. " FE/t"
        p_top:text(W - #usageStr - 2, sectY + 2, usageStr, P.fg_dim, P.bg)

        -- TOP 3 item composizione storage (mini lista)
        if state.storage_breakdown and #state.storage_breakdown.breakdown > 0 then
            p_top:text(3, sectY + 3, "TOP COMP :", P.fg_label, P.bg)
            local x = 14
            for i = 1, math.min(3, #state.storage_breakdown.breakdown) do
                local b = state.storage_breakdown.breakdown[i]
                local nm = shorten(shortName(b.name), 7)
                local pcs = ("%.0f%%"):format(b.pct * 100)
                local seg = nm .. " " .. pcs
                local segCol = STACK_COLORS[i] or P.fg_main
                if x + #seg + 1 < W - 2 then
                    p_top:text(x, sectY + 3, seg, segCol, P.bg)
                    x = x + #seg + 2
                end
            end
        end
    else
        p_top:text(3, sectY + 1, "OFFLINE - retry auto", P.fg_crit, P.bg)
    end

    -- ================ FOOTER (Satellite + bottoni) ================
    sectY = sectY + 5
    p_top:divider(1, sectY, W, P.border)

    -- Footer decorativo a sinistra
    p_top:text(3, sectY + 1, "FREQ.140.85", P.fg_dim, P.bg)
    p_top:text(3, sectY + 2, "CH.03",       P.fg_dim, P.bg)

    -- Satellite status
    local sStatus = health.getStatus("satellite", alerts.timeouts)
    local satLabel, satCol
    if sStatus == "ok" then
        satLabel = "SAT.LINK: ONLINE";  satCol = P.fg_main
    elseif sStatus == "warn" then
        satLabel = "SAT.LINK: WARN";    satCol = P.fg_warn
    else
        satLabel = "SAT.LINK: OFFLINE"
        satCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(W - #satLabel - 2, sectY + 1, satLabel, satCol, P.bg)

    -- Bottoni farm: bordo doppio MGS
    local btnW = 16
    local btnX = W - btnW - 2

    local f1On = state.farms[1] == true
    local f1Bg = f1On and colors.green or colors.gray
    local f1Lbl = f1On and "FARM-01: ON" or "FARM-01: OFF"
    p_top:buttonBoxed("farm1", btnX, sectY + 3, btnW, 3, f1Lbl,
        f1Bg, f1On and colors.lime or P.fg_label, P.border)

    -- secondo bottone affiancato a destra del primo... ma non c'è spazio
    -- li mettiamo sovrapposti uno sopra l'altro
    local f2On = state.farms[2] == true
    local f2Bg = f2On and colors.green or colors.gray
    local f2Lbl = f2On and "FARM-02: ON" or "FARM-02: OFF"
    p_top:buttonBoxed("farm2", btnX, sectY + 6, btnW, 3, f2Lbl,
        f2Bg, f2On and colors.lime or P.fg_label, P.border)

    p_top:flush()
end

-- ============================================================
-- BAR1: stacked bar STORAGE composizione (monitor_1, 1×5, 7×25 scale 1)
-- ============================================================
local function renderBar1()
    local W, H = p_bar1:size()
    p_bar1:clear()
    p_bar1:box(1, 1, W, H, P.border)

    -- Label verticale "STORAGE"
    local label = "STORAGE"
    local lblY = 2
    for i = 1, #label do
        if lblY + i - 1 < H - 1 then
            p_bar1:text(math.floor(W / 2), lblY + i - 1, label:sub(i, i), P.accent, P.bg)
        end
    end
    -- Divider sotto label
    local barTop = lblY + #label + 1

    -- Stack bar
    local rss = rs.snapshot()
    if rss.ok and state.storage_breakdown then
        local barH = H - barTop - 2
        local barX = 2
        local barW = W - 2
        local segments = {}
        for i, b in ipairs(state.storage_breakdown.breakdown) do
            table.insert(segments, {
                pct   = b.pct,
                color = STACK_COLORS[i] or P.fg_main,
            })
        end
        if state.storage_breakdown.others_pct > 0 then
            table.insert(segments, {
                pct = state.storage_breakdown.others_pct,
                color = OTHERS_COLOR,
            })
        end
        if #segments > 0 then
            p_bar1:stackBarVertical(barX, barTop, barW - 1, barH, segments)
        end

        -- footer: count totale formattato
        local footStr = fmt(rss.item_used)
        p_bar1:textCenter(H - 1, footStr, P.fg_value, P.bg)
    else
        p_bar1:textCenter(math.floor(H / 2), "OFFLINE", P.fg_crit, P.bg)
    end

    p_bar1:flush()
end

-- ============================================================
-- BAR2: barra ENERGY (monitor_2, 1×5, 7×25 scale 1)
-- ============================================================
local function renderBar2()
    local W, H = p_bar2:size()
    p_bar2:clear()
    p_bar2:box(1, 1, W, H, P.border)

    -- Label verticale "ENERGY"
    local label = "ENERGY"
    local lblY = 2
    for i = 1, #label do
        if lblY + i - 1 < H - 1 then
            p_bar2:text(math.floor(W / 2), lblY + i - 1, label:sub(i, i), P.accent, P.bg)
        end
    end
    local barTop = lblY + #label + 1

    local es = energy.snapshot()
    if es.ok then
        local barH = H - barTop - 2
        local col = energyColorAlert(es.pct)
        -- barra fatta di 2 colonne larga (W=7, riempiamo 2..W-1)
        local barX = 2
        local barW = W - 2
        for col_x = 0, barW - 1 do
            p_bar2:vbar(barX + col_x, barTop, barH, es.pct, col, colors.gray)
        end
        -- footer: % numerica
        local pctStr = ("%.1f%%"):format(es.pct * 100)
        p_bar2:textCenter(H - 1, pctStr, P.fg_value, P.bg)
    else
        p_bar2:textCenter(math.floor(H / 2), "OFFLINE", P.fg_crit, P.bg)
    end

    p_bar2:flush()
end

-- ============================================================
-- LAT3: ENERGY DETAIL (monitor_3, 8×5, ~85×37 scale 0.5)
-- ============================================================
local function renderEnergyDetail()
    local W, H = p_lat3:size()
    p_lat3:clear()
    p_lat3:box(1, 1, W, H, P.border)

    -- Header
    p_lat3:text(3, 1, " [ENERGY DETAIL] ", P.accent, P.bg)
    p_lat3:text(W - 18, 1, " VIBRANT CAP. BANK ", P.fg_dim, P.bg)

    local s = energy.snapshot()
    if not s.ok then
        p_lat3:textCenter(math.floor(H / 2), "*** SIGNAL LOST - retry... ***", P.fg_crit, P.bg)
        p_lat3:flush()
        return
    end

    -- Sezione 1: dati istantanei (righe 3-9)
    local infoY = 3
    p_lat3:divider(1, infoY, W, P.border)
    p_lat3:text(3, infoY, " [STATUS] ", P.accent, P.bg)

    p_lat3:text(3, infoY + 1, "STORED       :", P.fg_label, P.bg)
    p_lat3:text(18, infoY + 1, ("%s FE"):format(fmt(s.stored)), P.fg_value, P.bg)

    p_lat3:text(3, infoY + 2, "CAPACITY     :", P.fg_label, P.bg)
    p_lat3:text(18, infoY + 2, ("%s FE"):format(fmt(s.capacity)), P.fg_value, P.bg)

    -- barra fine stile MGS
    local ecol = energyColorAlert(s.pct)
    local barW = W - 22
    p_lat3:hbarFine(18, infoY + 3, barW, s.pct, ecol, P.bg)
    p_lat3:text(W - 9, infoY + 3, ("%6.2f%%"):format(s.pct * 100), ecol, P.bg)
    p_lat3:text(3, infoY + 3, "LEVEL        :", P.fg_label, P.bg)

    p_lat3:text(3, infoY + 4, "FLOW NOW     :", P.fg_label, P.bg)
    local flow = s.flow or 0
    local fcol = (flow >= 0) and P.fg_main or P.fg_crit
    p_lat3:text(18, infoY + 4, ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol, P.bg)

    p_lat3:text(3, infoY + 5, "FLOW AVG 10s :", P.fg_label, P.bg)
    local avg = s.avg_flow or 0
    local acol = (avg >= 0) and P.fg_main or P.fg_crit
    p_lat3:text(18, infoY + 5, ((avg >= 0) and "+" or "") .. fmt(avg) .. " FE/t", acol, P.bg)

    p_lat3:text(3, infoY + 6, "STATUS       :", P.fg_label, P.bg)
    if math.abs(flow) < 1 then       p_lat3:text(18, infoY + 6, "STABLE",      P.fg_dim, P.bg)
    elseif flow > 0 then             p_lat3:text(18, infoY + 6, "CHARGING",    P.fg_main, P.bg)
    else                             p_lat3:text(18, infoY + 6, "DISCHARGING", P.fg_warn, P.bg) end

    -- Sezione 2: GRAFICO % ENERGIA storico (double-height)
    local g1Y = infoY + 8
    p_lat3:divider(1, g1Y, W, P.border)
    p_lat3:text(3, g1Y, " [POWER LEVEL HISTORY] last 30 min ", P.accent, P.bg)

    local hist30 = energy.getPctHistory(900)  -- 30 min @ 2s
    local chartH = 12
    local chartX = 6
    local chartW = W - 8
    if #hist30 >= 2 then
        -- Asse Y: 100% / 75% / 50% / 25% / 0%
        for i = 0, 4 do
            local label = ("%3d%%"):format(100 - i * 25)
            local row = g1Y + 2 + math.floor(i * (chartH - 1) / 4)
            p_lat3:text(2, row, label, P.fg_dim, P.bg)
        end
        -- Plot doppio half (12 righe ma per double-height usiamo 2 righe per step
        -- Sceglieremo 6 livelli verticali con sparkline standard moltiplicata
        -- piu semplice: usiamo sparkline single-height su 6 righe, una per fascia
        -- Per chiarezza usiamo 1 riga sparkline doppia + asse semplice
        p_lat3:sparklineDouble(chartX, g1Y + 5, chartW, hist30,
            { color = ecol, min = 0, max = 1 })
        -- linee zero / 50% / 100%: skip, sparklineDouble e' gia espressiva
        -- timeline X
        local tlY = g1Y + chartH
        p_lat3:text(chartX, tlY, "-30m", P.fg_dim, P.bg)
        p_lat3:text(chartX + math.floor(chartW / 2) - 2, tlY, "-15m", P.fg_dim, P.bg)
        p_lat3:text(chartX + chartW - 4, tlY, " now", P.fg_dim, P.bg)
    else
        p_lat3:textCenter(g1Y + 5, "(in raccolta dati...)", P.fg_dim, P.bg)
    end

    -- Sezione 3: GRAFICO FLOW
    local g2Y = g1Y + chartH + 1
    p_lat3:divider(1, g2Y, W, P.border)
    p_lat3:text(3, g2Y, " [I/O FLOW] last 10 min ", P.accent, P.bg)

    local flowHist = energy.getFlowHistory(300)  -- 10 min @ 2s
    if #flowHist >= 2 then
        -- min e max simmetrici intorno a 0
        local maxAbs = 1
        for _, v in ipairs(flowHist) do
            if math.abs(v) > maxAbs then maxAbs = math.abs(v) end
        end
        p_lat3:text(2, g2Y + 2,  ("+%s"):format(fmt(maxAbs)), P.fg_main, P.bg)
        p_lat3:text(2, g2Y + 4,  "    0", P.fg_dim, P.bg)
        p_lat3:text(2, g2Y + 6,  ("-%s"):format(fmt(maxAbs)), P.fg_crit, P.bg)
        p_lat3:sparklineDouble(chartX, g2Y + 3, chartW, flowHist,
            { color = P.fg_main, min = -maxAbs, max = maxAbs })
    else
        p_lat3:textCenter(g2Y + 3, "(in raccolta dati...)", P.fg_dim, P.bg)
    end

    p_lat3:flush()
end

-- ============================================================
-- LAT4: API DASHBOARD (monitor_4, 8×5, ~85×37 scale 0.5)
-- 4 tabs: DETTAGLIO, LISTA, PROIEZIONE, GRAFICI
-- ============================================================
local function renderApiHeader()
    local W = p_lat4:size()
    p_lat4:box(1, 1, W, p_lat4:size() ~= nil and select(2, p_lat4:size()) or 25, P.border)
    p_lat4:text(3, 1, " >>> APIARY MONITOR <<< ", P.accent, P.bg)
    local ts = textutils.formatTime(os.time("local"), true)
    p_lat4:text(W - #ts - 2, 1, ts, P.fg_dim, P.bg)

    -- tabs
    local tabs = {
        { id = "dettaglio",  label = "DETAIL"     },
        { id = "lista",      label = "LIST"       },
        { id = "proiezione", label = "PROJECT"    },
        { id = "grafici",    label = "CHARTS"     },
    }
    local x = 3
    for _, t in ipairs(tabs) do
        local w = #t.label + 2
        local active = (state.api_tab == t.id)
        local bg = active and colors.green or colors.gray
        local fg = active and colors.lime or P.fg_label
        p_lat4:button("apitab_" .. t.id, x, 3, w, 1, " " .. t.label, bg, fg)
        x = x + w + 1
    end
end

local function renderApiTabDettaglio()
    local W, H = p_lat4:size()
    local products = bees.getProducts()
    if #products == 0 then
        p_lat4:textCenter(math.floor(H / 2), "(nessun prodotto config.)", P.fg_dim, P.bg)
        return
    end

    if state.api_prod_idx < 1 then state.api_prod_idx = #products end
    if state.api_prod_idx > #products then state.api_prod_idx = 1 end
    local prod = products[state.api_prod_idx]
    local s = bees.snapshot(prod.id)

    p_lat4:divider(1, 5, W, P.border)
    p_lat4:text(3, 5, " [" .. shortName(prod.id) .. "] ", P.accent, P.bg)
    p_lat4:text(W - 14, 5, ("(%d / %d)"):format(state.api_prod_idx, #products), P.fg_dim, P.bg)

    p_lat4:text(3, 7,  "STORED   :", P.fg_label, P.bg)
    p_lat4:text(15, 7, fmt(s.count) .. " units", P.fg_value, P.bg)

    p_lat4:text(3, 8, "RATE 30m :", P.fg_label, P.bg)
    p_lat4:text(15, 8, fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_main or P.fg_crit, P.bg)

    p_lat4:text(3, 9, "RATE EMA :", P.fg_label, P.bg)
    p_lat4:text(15, 9, fmtRate(s.rate_ema), (s.rate_ema >= 0) and P.fg_main or P.fg_crit, P.bg)

    p_lat4:text(3, 10, "TREND    :", P.fg_label, P.bg)
    local arrow, acol = trendArrow(s.trend)
    local tlbl = (s.trend > 0 and "rising") or (s.trend < 0 and "falling") or "stable"
    p_lat4:text(15, 10, arrow .. " " .. tlbl, acol, P.bg)

    p_lat4:text(3, 11, "SAMPLES  :", P.fg_label, P.bg)
    p_lat4:text(15, 11, tostring(s.n_samples), P.fg_dim, P.bg)

    -- Grafico storico
    p_lat4:divider(1, 13, W, P.border)
    p_lat4:text(3, 13, " [HISTORY] last 30 min ", P.accent, P.bg)

    local hist = bees.getHistory(prod.id, 60)
    if #hist >= 2 then
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end
        p_lat4:sparklineDouble(4, 15, W - 7, pts, { color = P.fg_main })
        -- assi
        local minc, maxc = math.huge, -math.huge
        for _, v in ipairs(pts) do
            if v < minc then minc = v end
            if v > maxc then maxc = v end
        end
        p_lat4:text(W - 16, 15, "max: " .. fmt(maxc), P.fg_dim, P.bg)
        p_lat4:text(W - 16, 16, "min: " .. fmt(minc), P.fg_dim, P.bg)
    else
        p_lat4:textCenter(15, "(in raccolta...)", P.fg_dim, P.bg)
    end

    -- bottoni
    p_lat4:buttonBoxed("api_prev", 3,        H - 4, 14, 3, "< PREV",  colors.gray, P.fg_main, P.border)
    p_lat4:buttonBoxed("api_next", W - 16,   H - 4, 14, 3, "NEXT >",  colors.gray, P.fg_main, P.border)
end

local function renderApiTabLista()
    local W, H = p_lat4:size()
    p_lat4:divider(1, 5, W, P.border)
    p_lat4:text(3, 5, " [PRODUCTS LIST] ", P.accent, P.bg)

    p_lat4:text(3, 7,   "PRODUCT",  P.fg_label, P.bg)
    p_lat4:text(28, 7,  "STORED",   P.fg_label, P.bg)
    p_lat4:text(45, 7,  "RATE 30m", P.fg_label, P.bg)
    p_lat4:text(62, 7,  "TREND",    P.fg_label, P.bg)
    p_lat4:fill(3, 8, W - 4, 1, colors.gray)

    local all = bees.snapshotAll()
    for i, s in ipairs(all) do
        local row = 8 + i
        if row >= H - 1 then break end
        p_lat4:text(3,  row, shorten(s.label, 22), P.fg_value, P.bg)
        p_lat4:text(28, row, fmt(s.count), P.fg_main, P.bg)
        p_lat4:text(45, row, fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_main or P.fg_crit, P.bg)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(64, row, arrow, acol, P.bg)
    end
end

local function renderApiTabProiezione()
    local W, H = p_lat4:size()
    p_lat4:divider(1, 5, W, P.border)
    p_lat4:text(3, 5, " [PROJECTION] ", P.accent, P.bg)

    p_lat4:text(3, 7, "PROJECT IN:", P.fg_label, P.bg)
    p_lat4:fill(15, 7, 6, 1, colors.gray)
    p_lat4:text(17, 7, ("%4d"):format(state.api_proj_hours), P.fg_value, colors.gray)
    p_lat4:text(22, 7, "hours", P.fg_label, P.bg)
    p_lat4:buttonBoxed("api_h_minus", 30, 6, 5, 3, " - ", colors.gray, P.fg_crit, P.border)
    p_lat4:buttonBoxed("api_h_plus",  37, 6, 5, 3, " + ", colors.gray, P.fg_main, P.border)

    p_lat4:fill(3, 10, W - 4, 1, colors.gray)
    p_lat4:text(3, 10,  "PRODUCT",  P.fg_value, colors.gray)
    p_lat4:text(28, 10, "NOW",      P.fg_value, colors.gray)
    p_lat4:text(45, 10, "+" .. state.api_proj_hours .. "h", P.fg_value, colors.gray)
    p_lat4:text(62, 10, "DELTA",    P.fg_value, colors.gray)

    for i, prod in ipairs(bees.getProducts()) do
        local row = 10 + i
        if row >= H - 1 then break end
        local cur = bees.getCount(prod.id)
        local fut = bees.project(prod.id, state.api_proj_hours)
        local d = fut - cur
        local dcol = (d >= 0) and P.fg_main or P.fg_crit
        p_lat4:text(3,  row, shorten(prod.label, 22), P.fg_value, P.bg)
        p_lat4:text(28, row, fmt(cur), P.fg_main, P.bg)
        p_lat4:text(45, row, fmt(fut), P.fg_value, P.bg)
        p_lat4:text(62, row, ((d >= 0) and "+" or "") .. fmt(d), dcol, P.bg)
    end
end

local function renderApiTabGrafici()
    local W, H = p_lat4:size()
    p_lat4:divider(1, 5, W, P.border)
    p_lat4:text(3, 5, " [PRODUCTION CHARTS] last 30 min ", P.accent, P.bg)

    -- Mostra sparkline per ogni prodotto, una riga ciascuno
    local products = bees.getProducts()
    local rowY = 7
    for i, prod in ipairs(products) do
        if rowY >= H - 2 then break end
        local s = bees.snapshot(prod.id)
        local hist = bees.getHistory(prod.id, 60)
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end

        -- Label prodotto
        p_lat4:text(3, rowY, shorten(shortName(prod.id), 12), P.fg_label, P.bg)
        -- Sparkline
        if #pts >= 2 then
            p_lat4:sparkline(17, rowY, W - 38, pts, { color = P.fg_main })
        else
            p_lat4:text(17, rowY, "(no data)", P.fg_dim, P.bg)
        end
        -- Rate + trend
        local rateStr = fmtRate(s.rate_30m)
        local rcol = (s.rate_30m >= 0) and P.fg_main or P.fg_crit
        p_lat4:text(W - 18, rowY, rateStr, rcol, P.bg)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(W - 4, rowY, arrow, acol, P.bg)

        rowY = rowY + 2
    end
end

local function renderApi()
    local W, H = p_lat4:size()
    p_lat4:clear()
    p_lat4.buttons = {}
    p_lat4:box(1, 1, W, H, P.border)
    -- Header
    p_lat4:text(3, 1, " >>> APIARY MONITOR <<< ", P.accent, P.bg)
    local ts = textutils.formatTime(os.time("local"), true)
    p_lat4:text(W - #ts - 2, 1, ts, P.fg_dim, P.bg)
    -- Tabs
    local tabs = {
        { id = "dettaglio",  label = "DETAIL"  },
        { id = "lista",      label = "LIST"    },
        { id = "proiezione", label = "PROJECT" },
        { id = "grafici",    label = "CHARTS"  },
    }
    local x = 3
    for _, t in ipairs(tabs) do
        local w = #t.label + 2
        local active = (state.api_tab == t.id)
        local bg = active and colors.green or colors.gray
        local fg = active and colors.lime or P.fg_label
        p_lat4:button("apitab_" .. t.id, x, 3, w, 1, " " .. t.label, bg, fg)
        x = x + w + 1
    end

    if     state.api_tab == "dettaglio"  then renderApiTabDettaglio()
    elseif state.api_tab == "lista"      then renderApiTabLista()
    elseif state.api_tab == "proiezione" then renderApiTabProiezione()
    elseif state.api_tab == "grafici"    then renderApiTabGrafici() end

    p_lat4:flush()
end

-- ============================================================
-- Render generale
-- ============================================================
local function renderAll()
    local fns = { renderTop, renderBar1, renderBar2, renderEnergyDetail, renderApi }
    local labels = { "Top", "Bar1", "Bar2", "EnergyDet", "Api" }
    for i, fn in ipairs(fns) do
        local ok, err = pcall(fn)
        if not ok then
            print("render " .. labels[i] .. " err: " .. tostring(err))
            logger.error("render " .. labels[i] .. ": " .. tostring(err))
        end
    end
end

-- ============================================================
-- Tasks
-- ============================================================
local function safeCall(fn)
    local ok, err = pcall(fn)
    if not ok then logger.error("task: " .. tostring(err)) end
    return ok, err
end

local function taskEnergy()
    safeCall(function()
        if not energy.isReady() then
            local ok = energy.init()
            health.set("energy", ok)
        end
        energy.sample()
    end)
    while true do
        sleep(2)
        local ok = safeCall(function()
            if not energy.isReady() then
                local ok2 = energy.init()
                health.set("energy", ok2)
                if not ok2 then return end
            end
            energy.sample()
            health.set("energy", true)
        end)
        if not ok then health.set("energy", false) end
    end
end

local function taskBees()
    safeCall(bees.sample)
    while true do
        sleep(cfg.sample_interval)
        safeCall(bees.sample)
    end
end

local function taskSatSync()
    while true do
        local s, err = farm.fetchState()
        if s then
            state.farms[1] = s[1] == true
            state.farms[2] = s[2] == true
            health.set("satellite", true)
        else
            health.set("satellite", false)
            farm.findSatellite()
        end
        sleep(5)
    end
end

local function taskRsHealth()
    while true do
        sleep(5)
        local s = rs.snapshot()
        health.set("rs", s.ok == true)
    end
end

-- Task dedicato: aggiorna storage breakdown ogni 10s (è costoso, getItems pesante)
local function taskStorageBreakdown()
    while true do
        local ok, br = pcall(rs.itemBreakdown, 6)
        if ok and br then
            state.storage_breakdown = br
            state.last_storage_breakdown = os.epoch("utc")
        end
        sleep(10)
    end
end

local function taskRender()
    while true do
        renderAll()
        sleep(1)
    end
end

local function taskBlink()
    while true do
        sleep(alerts.blink_period or 1)
        state.blink_on = not state.blink_on
    end
end

local function taskClicks()
    while true do
        local _, side, x, y = os.pullEvent("monitor_touch")

        if side == "top" then
            local btn = p_top:hitTest(x, y)
            if btn == "farm1" then
                local newState = not state.farms[1]
                local ok = farm.set(1, newState)
                if ok then state.farms[1] = newState end
                renderAll()
            elseif btn == "farm2" then
                local newState = not state.farms[2]
                local ok = farm.set(2, newState)
                if ok then state.farms[2] = newState end
                renderAll()
            end

        elseif side == "monitor_4" then
            local btn = p_lat4:hitTest(x, y)
            if btn then
                if     btn == "apitab_dettaglio"  then state.api_tab = "dettaglio"
                elseif btn == "apitab_lista"      then state.api_tab = "lista"
                elseif btn == "apitab_proiezione" then state.api_tab = "proiezione"
                elseif btn == "apitab_grafici"    then state.api_tab = "grafici"
                elseif btn == "api_prev"          then state.api_prod_idx = state.api_prod_idx - 1
                elseif btn == "api_next"          then state.api_prod_idx = state.api_prod_idx + 1
                elseif btn == "api_h_minus"       then state.api_proj_hours = math.max(1,  state.api_proj_hours - 1)
                elseif btn == "api_h_plus"        then state.api_proj_hours = math.min(48, state.api_proj_hours + 1)
                end
                renderAll()
            end
        end
    end
end

print("")
print("Avvio task paralleli...")
print("Premi Ctrl+T per uscire.")
print("Log: /log/central.log")
print("")
logger.info("Task paralleli avviati (v4 MGS Codec)")

parallel.waitForAny(
    taskEnergy, taskBees, taskSatSync, taskRsHealth,
    taskStorageBreakdown, taskRender, taskBlink, taskClicks
)

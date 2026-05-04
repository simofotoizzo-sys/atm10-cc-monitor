-- /programs/central.lua  v7
-- Fix Fase 8.3:
--  - Bottoni FARM in basso al centro
--  - Tab API in basso, nav buttons sotto i tab
--  - Grafico I/O FLOW restored su monitor_3
--  - Padding ottimizzato per leggibilita'

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

print("=== CENTRAL DASHBOARD v7 ===")
logger.info("Central v7 avviato")

local rsOk = rs.init();    health.set("rs",        rsOk)
local enOk = energy.init();health.set("energy",    enOk)
bees.init(cfg)
local fmOk = farm.init();  health.set("satellite", fmOk)

local p_top   = gui.attach("top")
local p_bar1  = gui.attach("monitor_1")
local p_bar2  = gui.attach("monitor_2")
local p_lat3  = gui.attach("monitor_3")
local p_lat4  = gui.attach("monitor_4")

p_top:setScale(1)
p_bar1:setScale(1)
p_bar2:setScale(1)
p_lat3:setScale(1)
p_lat4:setScale(1)

local state = {
    farms          = { [1] = false, [2] = false },
    api_tab        = "lista",
    api_prod_idx   = 1,
    api_proj_hours = 6,
    blink_on       = true,
    storage_breakdown = nil,
}

local P = gui.palette

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
    if t > 0 then return "+", colors.lime
    elseif t < 0 then return "-", colors.red
    else return "=", colors.gray end
end

local function shorten(s, maxLen)
    s = tostring(s)
    if #s <= maxLen then return s end
    return s:sub(1, maxLen - 1) .. "."
end

local function shortName(s)
    s = tostring(s or "?")
    local _, _, name = s:find(":(.+)$")
    name = (name or s):gsub("_", " "):upper()
    return name
end

local function energyColorAlert(pct)
    if pct < alerts.energy.crit_pct then
        return state.blink_on and P.fg_crit or P.bg, "crit"
    elseif pct < alerts.energy.warn_pct then
        return P.fg_warn, "warn"
    end
    return P.fg_ok, "ok"
end

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
-- Render TOP (49x25 char a scale 1)
-- Layout righe:
-- 1:  bordo top
-- 2:  header
-- 3:  divider
-- 4-8: ENERGY (5 righe)
-- 9:  divider
-- 10-19: STORAGE (10 righe: numeri + composition con 5 item + OTHERS)
-- 20: divider
-- 21: SATELLITE
-- 22-23: bottoni farm (2 righe alti)
-- 24: spazio
-- 25: bordo bottom
-- ============================================================
local function renderTop()
    local W, H = p_top:size()
    p_top:clear()
    p_top.buttons = {}
    p_top:box(1, 1, W, H, P.border)

    -- HEADER
    p_top:text(3, 1, " CENTRALE ", P.fg_title, P.bg)
    local overall = health.overall(alerts.timeouts)
    local hLabel, hCol
    if overall == "ok" then
        hLabel = "[OK]"; hCol = P.fg_ok
    elseif overall == "degraded" then
        hLabel = "[DEGRADED]"; hCol = P.fg_warn
    else
        hLabel = "[CRITICAL]"
        hCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(15, 1, hLabel, hCol, P.bg)
    local time_str = textutils.formatTime(os.time("local"), true)
    p_top:text(W - #time_str - 2, 1, time_str, P.fg_dim, P.bg)

    -- ENERGY (3-8)
    local sectY = 3
    p_top:divider(1, sectY, W, P.border)
    p_top:text(3, sectY, " ENERGY - VIBRANT CAP ", P.fg_title, P.bg)

    local es = energy.snapshot()
    health.set("energy", es.ok)
    if es.ok then
        local ecol = energyColorAlert(es.pct)
        p_top:text(3,  sectY + 1, "STORED  :", P.fg_label, P.bg)
        p_top:text(13, sectY + 1, ("%s / %s FE"):format(fmt(es.stored), fmt(es.capacity)), P.fg_value, P.bg)
        local pctStr = ("%.1f%%"):format(es.pct * 100)
        p_top:text(W - #pctStr - 2, sectY + 1, pctStr, ecol, P.bg)

        local flow = es.flow or 0
        local fcol = (flow >= 0) and P.fg_ok or P.fg_crit
        p_top:text(3,  sectY + 2, "FLOW    :", P.fg_label, P.bg)
        p_top:text(13, sectY + 2, ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol, P.bg)

        -- sparkline 2 righe
        local hist = energy.getPctHistory(1800)
        if #hist >= 2 then
            p_top:sparklineMulti(3, sectY + 4, W - 4, 2, hist,
                { color = ecol, min = 0, max = 1 })
        else
            p_top:text(3, sectY + 4, "(in raccolta...)", P.fg_dim, P.bg)
        end
    else
        p_top:text(3, sectY + 1, "OFFLINE - retry auto", P.fg_crit, P.bg)
    end

    -- STORAGE (9-19)
    sectY = 9
    p_top:divider(1, sectY, W, P.border)
    p_top:text(3, sectY, " STORAGE - REFINED ", P.fg_title, P.bg)

    local rss = rs.snapshot()
    health.set("rs", rss.ok)
    if rss.ok then
        p_top:text(3,  sectY + 1, "ITEMS  :", P.fg_label, P.bg)
        p_top:text(12, sectY + 1, ("%s / %s"):format(fmt(rss.item_used), fmt(rss.item_max)), P.fg_value, P.bg)
        local pctStr = ("%.3f%%"):format(rss.item_pct * 100)
        p_top:text(W - #pctStr - 2, sectY + 1, pctStr, colors.cyan, P.bg)

        p_top:text(3,  sectY + 2, "USAGE  :", P.fg_label, P.bg)
        p_top:text(12, sectY + 2, fmt(rss.energy_used) .. " FE @ " .. tostring(rss.energy_usage) .. " FE/t", P.fg_value, P.bg)

        -- Composition: max 5 item + OTHERS
        p_top:text(3, sectY + 3, "COMPOSITION (matches vert. bar -->):", P.fg_dim, P.bg)
        if state.storage_breakdown and #state.storage_breakdown.breakdown > 0 then
            local maxItems = 5
            for i = 1, math.min(maxItems, #state.storage_breakdown.breakdown) do
                local b = state.storage_breakdown.breakdown[i]
                local row = sectY + 3 + i
                local segCol = STACK_COLORS[i] or colors.gray
                -- Quadratino colorato
                p_top:fill(3, row, 3, 1, segCol)
                -- Nome
                local nm = shortName(b.name)
                p_top:text(7, row, shorten(nm, 22), P.fg_value, P.bg)
                -- %
                local pcs = ("%5.1f%%"):format(b.pct * 100)
                p_top:text(W - 19, row, pcs, segCol, P.bg)
                -- Count
                p_top:text(W - 9, row, fmt(b.count), P.fg_dim, P.bg)
            end
            -- OTHERS
            if state.storage_breakdown.others_pct > 0 then
                local rowOthers = sectY + 3 + math.min(maxItems, #state.storage_breakdown.breakdown) + 1
                if rowOthers <= sectY + 9 then
                    p_top:fill(3, rowOthers, 3, 1, OTHERS_COLOR)
                    p_top:text(7, rowOthers, "OTHERS", P.fg_dim, P.bg)
                    local pcs = ("%5.1f%%"):format(state.storage_breakdown.others_pct * 100)
                    p_top:text(W - 19, rowOthers, pcs, OTHERS_COLOR, P.bg)
                    p_top:text(W - 9, rowOthers, fmt(state.storage_breakdown.others), P.fg_dim, P.bg)
                end
            end
        else
            p_top:text(3, sectY + 4, "(in raccolta...)", P.fg_dim, P.bg)
        end
    else
        p_top:text(3, sectY + 1, "OFFLINE - retry auto", P.fg_crit, P.bg)
    end

    -- FOOTER (20-24)
    local footY = 20
    p_top:divider(1, footY, W, P.border)

    -- Satellite a sinistra
    local sStatus = health.getStatus("satellite", alerts.timeouts)
    local satLabel, satCol
    if sStatus == "ok" then
        satLabel = "SATELLITE: ONLINE";  satCol = P.fg_ok
    elseif sStatus == "warn" then
        satLabel = "SATELLITE: WARN";    satCol = P.fg_warn
    else
        satLabel = "SATELLITE: OFFLINE"
        satCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(3, footY + 1, satLabel, satCol, P.bg)

    -- Bottoni farm: in basso, AFFIANCATI a destra del satellite
    local btnW = 13
    local gap = 2
    -- 2 bottoni 13x2 + gap = 28 char totali
    -- li metto a partire da W-30 (centrati a destra)
    local btn1X = W - 2 * btnW - gap - 2
    local btn2X = W - btnW - 2

    local f1On = state.farms[1] == true
    local f1Bg = f1On and colors.green or colors.red
    local f1Lbl = f1On and "FARM 1: ON " or "FARM 1: OFF"
    p_top:button("farm1", btn1X, footY + 1, btnW, 2, f1Lbl, f1Bg, colors.white)

    local f2On = state.farms[2] == true
    local f2Bg = f2On and colors.green or colors.red
    local f2Lbl = f2On and "FARM 2: ON " or "FARM 2: OFF"
    p_top:button("farm2", btn2X, footY + 1, btnW, 2, f2Lbl, f2Bg, colors.white)

    p_top:flush()
end

-- ============================================================
-- BAR1: STORAGE (composizione stack)
-- ============================================================
local function renderBar1()
    local W, H = p_bar1:size()
    p_bar1:clear()
    p_bar1:box(1, 1, W, H, P.border)

    local label = "STORAGE"
    local lblY = 2
    for i = 1, #label do
        if lblY + i - 1 < H - 1 then
            p_bar1:text(math.floor(W / 2), lblY + i - 1, label:sub(i, i), P.fg_title, P.bg)
        end
    end
    local barTop = lblY + #label + 1

    local rss = rs.snapshot()
    if rss.ok and state.storage_breakdown then
        local barH = H - barTop - 2
        local barX = 2
        local barW = W - 2
        local segments = {}
        for i, b in ipairs(state.storage_breakdown.breakdown) do
            table.insert(segments, {
                pct = b.pct, color = STACK_COLORS[i] or P.fg_main
            })
        end
        if state.storage_breakdown.others_pct > 0 then
            table.insert(segments, {
                pct = state.storage_breakdown.others_pct, color = OTHERS_COLOR
            })
        end
        if #segments > 0 then
            p_bar1:stackBarVertical(barX, barTop, barW - 1, barH, segments)
        end
        p_bar1:textCenter(H - 1, fmt(rss.item_used), P.fg_value, P.bg)
    else
        p_bar1:textCenter(math.floor(H / 2), "OFFLN", P.fg_crit, P.bg)
    end

    p_bar1:flush()
end

-- ============================================================
-- BAR2: ENERGY
-- ============================================================
local function renderBar2()
    local W, H = p_bar2:size()
    p_bar2:clear()
    p_bar2:box(1, 1, W, H, P.border)

    local label = "ENERGY"
    local lblY = 2
    for i = 1, #label do
        if lblY + i - 1 < H - 1 then
            p_bar2:text(math.floor(W / 2), lblY + i - 1, label:sub(i, i), P.fg_title, P.bg)
        end
    end
    local barTop = lblY + #label + 1

    local es = energy.snapshot()
    if es.ok then
        local barH = H - barTop - 2
        local col = energyColorAlert(es.pct)
        local barX = 2
        local barW = W - 2
        for col_x = 0, barW - 2 do
            p_bar2:vbar(barX + col_x, barTop, barH, es.pct, col, colors.gray)
        end
        local pctStr = ("%.1f%%"):format(es.pct * 100)
        p_bar2:textCenter(H - 1, pctStr, P.fg_value, P.bg)
    else
        p_bar2:textCenter(math.floor(H / 2), "OFFLN", P.fg_crit, P.bg)
    end

    p_bar2:flush()
end

-- ============================================================
-- LAT3: ENERGY DETAIL (scale 1, ~57x25 char)
-- Layout:
-- 1:  bordo top
-- 2:  header
-- 3:  divider STATUS
-- 4-9: STATUS (6 righe info)
-- 10: divider POWER LEVEL HISTORY
-- 11: titolo grafico
-- 12-19: chart power 8 righe
-- 20: asse X
-- 21: divider I/O FLOW
-- 22: titolo
-- 23-24: chart simmetrico
-- 25: bordo bottom
-- ============================================================
local function renderEnergyDetail()
    local W, H = p_lat3:size()
    p_lat3:clear()
    p_lat3:box(1, 1, W, H, P.border)

    p_lat3:text(3, 1, " ENERGY DETAIL ", P.fg_title, P.bg)

    local s = energy.snapshot()
    if not s.ok then
        p_lat3:textCenter(math.floor(H / 2), "*** SIGNAL LOST ***", P.fg_crit, P.bg)
        p_lat3:flush()
        return
    end

    -- STATUS (3-9)
    local infoY = 3
    p_lat3:divider(1, infoY, W, P.border)
    p_lat3:text(3, infoY, " STATUS ", P.fg_title, P.bg)

    p_lat3:text(3,  infoY + 1, "STORED   :", P.fg_label, P.bg)
    p_lat3:text(15, infoY + 1, fmt(s.stored) .. " FE", P.fg_value, P.bg)

    p_lat3:text(3,  infoY + 2, "CAPACITY :", P.fg_label, P.bg)
    p_lat3:text(15, infoY + 2, fmt(s.capacity) .. " FE", P.fg_value, P.bg)

    -- LEVEL bar
    p_lat3:text(3, infoY + 3, "LEVEL    :", P.fg_label, P.bg)
    local ecol = energyColorAlert(s.pct)
    local barW = W - 26
    p_lat3:hbar(15, infoY + 3, barW, s.pct, ecol, colors.gray)
    p_lat3:text(W - 9, infoY + 3, ("%6.2f%%"):format(s.pct * 100), ecol, P.bg)

    p_lat3:text(3, infoY + 4, "FLOW NOW :", P.fg_label, P.bg)
    local flow = s.flow or 0
    local fcol = (flow >= 0) and P.fg_ok or P.fg_crit
    p_lat3:text(15, infoY + 4, ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol, P.bg)

    p_lat3:text(3, infoY + 5, "AVG 10s  :", P.fg_label, P.bg)
    local avg = s.avg_flow or 0
    local acol = (avg >= 0) and P.fg_ok or P.fg_crit
    p_lat3:text(15, infoY + 5, ((avg >= 0) and "+" or "") .. fmt(avg) .. " FE/t", acol, P.bg)

    p_lat3:text(3, infoY + 6, "STATUS   :", P.fg_label, P.bg)
    if math.abs(flow) < 1 then       p_lat3:text(15, infoY + 6, "STABLE",      P.fg_dim,  P.bg)
    elseif flow > 0 then             p_lat3:text(15, infoY + 6, "CHARGING",    P.fg_ok,   P.bg)
    else                             p_lat3:text(15, infoY + 6, "DISCHARGING", P.fg_warn, P.bg) end

    -- POWER LEVEL HISTORY (10-20)
    local g1Y = 10
    p_lat3:divider(1, g1Y, W, P.border)
    p_lat3:text(3, g1Y, " POWER LEVEL HISTORY (last 30 min) ", P.fg_title, P.bg)

    local hist30 = energy.getPctHistory(900)
    local chartH = 8
    local chartX = 8
    local chartW = W - 10

    -- Asse Y
    p_lat3:text(2, g1Y + 1,                              "100%", P.fg_dim, P.bg)
    p_lat3:text(2, g1Y + 1 + math.floor(chartH * 0.5),  " 50%", P.fg_dim, P.bg)
    p_lat3:text(2, g1Y + chartH,                         "  0%", P.fg_dim, P.bg)

    if #hist30 >= 2 then
        p_lat3:sparklineMulti(chartX, g1Y + 1, chartW, chartH, hist30,
            { color = ecol, min = 0, max = 1 })
    else
        p_lat3:textCenter(g1Y + 1 + math.floor(chartH / 2), "(in raccolta...)", P.fg_dim, P.bg)
    end

    -- Asse X
    p_lat3:text(chartX, g1Y + chartH + 1, "-30m", P.fg_dim, P.bg)
    p_lat3:text(chartX + math.floor(chartW / 2) - 2, g1Y + chartH + 1, "-15m", P.fg_dim, P.bg)
    p_lat3:text(chartX + chartW - 4, g1Y + chartH + 1, " now", P.fg_dim, P.bg)

    -- I/O FLOW HISTORY (21-24)
    local g2Y = 21
    p_lat3:divider(1, g2Y - 1, W, P.border)
    p_lat3:text(3, g2Y - 1, " I/O FLOW (last 10 min) ", P.fg_title, P.bg)

    local flowHist = energy.getFlowHistory(300)
    if #flowHist >= 2 then
        local maxAbs = 1
        for _, v in ipairs(flowHist) do
            if math.abs(v) > maxAbs then maxAbs = math.abs(v) end
        end
        -- Grafico simmetrico: centro sulla riga g2Y+1, halfH=1 (totale 3 righe: pos/zero/neg)
        local centerY = g2Y + 1
        p_lat3:text(2, g2Y,     ("+%s"):format(fmt(maxAbs)), P.fg_ok,   P.bg)
        p_lat3:text(2, centerY, "  0    ",                     P.fg_dim,  P.bg)
        p_lat3:text(2, g2Y + 2, ("-%s"):format(fmt(maxAbs)), P.fg_crit, P.bg)
        p_lat3:sparklineSym(chartX, centerY, chartW, 1, flowHist,
            { posColor = P.fg_ok, negColor = P.fg_crit, maxAbs = maxAbs })
    else
        p_lat3:textCenter(g2Y + 1, "(in raccolta...)", P.fg_dim, P.bg)
    end

    p_lat3:flush()
end

-- ============================================================
-- LAT4: API DASHBOARD (scale 1, ~57x25 char)
-- Layout:
-- 1:  bordo top
-- 2:  header
-- 3:  divider
-- 4-19: tab content (16 righe)
-- 20: divider tab buttons
-- 21: tab buttons
-- 22: divider nav buttons (solo DETAIL)
-- 23-24: nav buttons (solo DETAIL: < PREV / NEXT >)
-- 25: bordo bottom
-- ============================================================

local function renderApiTabDettaglio()
    local W, H = p_lat4:size()
    local products = bees.getProducts()
    if #products == 0 then
        p_lat4:textCenter(math.floor(H / 2), "(nessun prodotto)", P.fg_dim, P.bg)
        return
    end

    if state.api_prod_idx < 1 then state.api_prod_idx = #products end
    if state.api_prod_idx > #products then state.api_prod_idx = 1 end
    local prod = products[state.api_prod_idx]
    local s = bees.snapshot(prod.id)

    p_lat4:text(3, 4, shortName(prod.id), P.fg_title, P.bg)
    p_lat4:text(W - 11, 4, ("(%d / %d)"):format(state.api_prod_idx, #products), P.fg_dim, P.bg)

    p_lat4:text(3,  6,  "STORED    :", P.fg_label, P.bg)
    p_lat4:text(15, 6,  fmt(s.count) .. " units", P.fg_value, P.bg)
    p_lat4:text(3,  7,  "RATE 30m  :", P.fg_label, P.bg)
    p_lat4:text(15, 7,  fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_ok or P.fg_crit, P.bg)
    p_lat4:text(3,  8,  "RATE EMA  :", P.fg_label, P.bg)
    p_lat4:text(15, 8,  fmtRate(s.rate_ema), (s.rate_ema >= 0) and P.fg_ok or P.fg_crit, P.bg)
    p_lat4:text(3,  9,  "TREND     :", P.fg_label, P.bg)
    local arrow, acol = trendArrow(s.trend)
    local tlbl = (s.trend > 0 and "rising") or (s.trend < 0 and "falling") or "stable"
    p_lat4:text(15, 9,  arrow .. " " .. tlbl, acol, P.bg)
    p_lat4:text(3,  10, "SAMPLES   :", P.fg_label, P.bg)
    p_lat4:text(15, 10, tostring(s.n_samples), P.fg_dim, P.bg)

    -- Grafico
    p_lat4:text(3, 12, "HISTORY (last 30 min):", P.fg_title, P.bg)
    local hist = bees.getHistory(prod.id, 60)
    if #hist >= 2 then
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end
        p_lat4:sparklineMulti(3, 13, W - 16, 6, pts, { color = colors.cyan })
        local minc, maxc = math.huge, -math.huge
        for _, v in ipairs(pts) do
            if v < minc then minc = v end
            if v > maxc then maxc = v end
        end
        p_lat4:text(W - 13, 13, "max " .. fmt(maxc), P.fg_dim, P.bg)
        p_lat4:text(W - 13, 18, "min " .. fmt(minc), P.fg_dim, P.bg)
    else
        p_lat4:textCenter(15, "(in raccolta...)", P.fg_dim, P.bg)
    end
end

local function renderApiTabLista()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, " PRODUCTS LIST ", P.fg_title, P.bg)

    p_lat4:text(3,  6, "PRODUCT",  P.fg_label, P.bg)
    p_lat4:text(22, 6, "STORED",   P.fg_label, P.bg)
    p_lat4:text(35, 6, "RATE 30m", P.fg_label, P.bg)
    p_lat4:text(50, 6, "TR",       P.fg_label, P.bg)
    p_lat4:fill(3, 7, W - 4, 1, colors.gray)

    local all = bees.snapshotAll()
    for i, s in ipairs(all) do
        local row = 7 + i
        if row >= 19 then break end
        p_lat4:text(3,  row, shorten(s.label, 17), P.fg_value, P.bg)
        p_lat4:text(22, row, fmt(s.count), colors.cyan, P.bg)
        p_lat4:text(35, row, fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_ok or P.fg_crit, P.bg)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(51, row, arrow, acol, P.bg)
    end
end

local function renderApiTabProiezione()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, " PROJECTION ", P.fg_title, P.bg)

    p_lat4:text(3, 6, "PROJECT IN:", P.fg_label, P.bg)
    p_lat4:fill(15, 6, 6, 1, colors.gray)
    p_lat4:text(17, 6, ("%4d"):format(state.api_proj_hours), P.fg_value, colors.gray)
    p_lat4:text(22, 6, "hours", P.fg_label, P.bg)
    p_lat4:button("api_h_minus", 30, 6, 5, 1, " - ", colors.red,   colors.white)
    p_lat4:button("api_h_plus",  37, 6, 5, 1, " + ", colors.green, colors.white)

    p_lat4:fill(3, 8, W - 4, 1, colors.gray)
    p_lat4:text(3,  8,  "PRODUCT",  P.fg_value, colors.gray)
    p_lat4:text(22, 8,  "NOW",      P.fg_value, colors.gray)
    p_lat4:text(35, 8,  "+" .. state.api_proj_hours .. "h", P.fg_value, colors.gray)
    p_lat4:text(50, 8,  "DELTA",    P.fg_value, colors.gray)

    for i, prod in ipairs(bees.getProducts()) do
        local row = 8 + i
        if row >= 19 then break end
        local cur = bees.getCount(prod.id)
        local fut = bees.project(prod.id, state.api_proj_hours)
        local d = fut - cur
        local dcol = (d >= 0) and P.fg_ok or P.fg_crit
        p_lat4:text(3,  row, shorten(prod.label, 18), P.fg_value, P.bg)
        p_lat4:text(22, row, fmt(cur), colors.cyan, P.bg)
        p_lat4:text(35, row, fmt(fut), P.fg_value, P.bg)
        p_lat4:text(50, row, ((d >= 0) and "+" or "") .. fmt(d), dcol, P.bg)
    end
end

local function renderApiTabGrafici()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, " PRODUCTION CHARTS (30 min) ", P.fg_title, P.bg)

    local products = bees.getProducts()
    local rowY = 6
    for _, prod in ipairs(products) do
        if rowY >= 19 then break end
        local s = bees.snapshot(prod.id)
        local hist = bees.getHistory(prod.id, 60)
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end

        p_lat4:text(3, rowY, shorten(shortName(prod.id), 11), P.fg_label, P.bg)
        if #pts >= 2 then
            p_lat4:sparklineMulti(15, rowY, W - 28, 1, pts, { color = colors.cyan })
        else
            p_lat4:text(15, rowY, "(no data)", P.fg_dim, P.bg)
        end
        local rateStr = fmtRate(s.rate_30m)
        local rcol = (s.rate_30m >= 0) and P.fg_ok or P.fg_crit
        p_lat4:text(W - 12, rowY, rateStr, rcol, P.bg)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(W - 2, rowY, arrow, acol, P.bg)

        rowY = rowY + 2
    end
end

local function renderApi()
    local W, H = p_lat4:size()
    p_lat4:clear()
    p_lat4.buttons = {}
    p_lat4:box(1, 1, W, H, P.border)

    -- HEADER
    p_lat4:text(3, 1, " APIARY MONITOR ", P.fg_title, P.bg)
    local ts = textutils.formatTime(os.time("local"), true)
    p_lat4:text(W - #ts - 2, 1, ts, P.fg_dim, P.bg)
    p_lat4:divider(1, 3, W, P.border)

    -- CONTENT (4-19)
    if     state.api_tab == "dettaglio"  then renderApiTabDettaglio()
    elseif state.api_tab == "lista"      then renderApiTabLista()
    elseif state.api_tab == "proiezione" then renderApiTabProiezione()
    elseif state.api_tab == "grafici"    then renderApiTabGrafici() end

    -- TAB BUTTONS IN BASSO (riga 20-21)
    p_lat4:divider(1, 20, W, P.border)
    local tabs = {
        { id = "dettaglio",  label = "DETAIL"   },
        { id = "lista",      label = "LIST"     },
        { id = "proiezione", label = "PROJECT"  },
        { id = "grafici",    label = "CHARTS"   },
    }
    local x = 3
    for _, t in ipairs(tabs) do
        local w = #t.label + 2
        local active = (state.api_tab == t.id)
        local bg = active and colors.green or colors.gray
        local fg = colors.white
        p_lat4:button("apitab_" .. t.id, x, 21, w, 1, " " .. t.label, bg, fg)
        x = x + w + 1
    end

    -- NAV BUTTONS (solo per DETAIL): righe 23-24
    if state.api_tab == "dettaglio" then
        p_lat4:divider(1, 22, W, P.border)
        p_lat4:button("api_prev", 3,        23, 12, 2, "< PREV", colors.blue, colors.white)
        p_lat4:button("api_next", W - 14,   23, 12, 2, "NEXT >", colors.blue, colors.white)
    end

    p_lat4:flush()
end

-- ============================================================
-- Render
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

local function taskStorageBreakdown()
    while true do
        local ok, br = pcall(rs.itemBreakdown, 5)
        if ok and br then state.storage_breakdown = br end
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
print("")
logger.info("Task paralleli avviati (v7)")

parallel.waitForAny(
    taskEnergy, taskBees, taskSatSync, taskRsHealth,
    taskStorageBreakdown, taskRender, taskBlink, taskClicks
)

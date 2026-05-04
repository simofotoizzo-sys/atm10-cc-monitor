-- /programs/central.lua  v11
-- Fix Fase 8.7:
--  - Monitor 4: tutti i 10 prodotti visibili in LIST/PROJECT/CHARTS
--  - Monitor TOP: bottoni FARM alti 2 righe in fondo
--  - Monitor 3: grafico I/O FLOW ripristinato (2 righe simmetrico)
--  - Tutti scale 1.5

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

print("=== CENTRAL DASHBOARD v11 ===")
logger.info("Central v11 avviato")

local rsOk = rs.init();    health.set("rs",        rsOk)
local enOk = energy.init();health.set("energy",    enOk)
bees.init(cfg)
local fmOk = farm.init();  health.set("satellite", fmOk)

local p_top   = gui.attach("top")
local p_bar1  = gui.attach("monitor_1")
local p_bar2  = gui.attach("monitor_2")
local p_lat3  = gui.attach("monitor_3")
local p_lat4  = gui.attach("monitor_4")

p_top:setScale(1.5)
p_bar1:setScale(1)
p_bar2:setScale(1)
p_lat3:setScale(1.5)
p_lat4:setScale(1.5)

local START_TIME = os.epoch("utc")

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
    if n >= 1e9 then return sign .. ("%.1fG"):format(n / 1e9)
    elseif n >= 1e6 then return ("%s%.1fM"):format(sign, n / 1e6)
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

local function fmtUptime()
    local sec = math.floor((os.epoch("utc") - START_TIME) / 1000)
    if sec < 60 then return tostring(sec) .. "s" end
    local m = math.floor(sec / 60)
    if m < 60 then return ("%dm"):format(m) end
    local h = math.floor(m / 60)
    return ("%dh%dm"):format(h, m % 60)
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
-- Render TOP scale 1.5 (~32x16)
-- 1: bordo, 2: header, 3: div ENERGY, 4-5: energy info
-- 6: div STORAGE, 7-10: storage info + 4 items + others
-- 11: div, 12: SAT/AVG/UP info
-- 13-14: bottoni FARM alti 2 righe (in fondo!)
-- 15: padding sottile
-- 16: bordo bottom
-- ============================================================
local function renderTop()
    local W, H = p_top:size()
    p_top:clear()
    p_top.buttons = {}
    p_top:box(1, 1, W, H, P.border)

    -- HEADER (riga 2)
    p_top:text(3, 2, "CENTRALE", P.fg_title, P.bg)
    local overall = health.overall(alerts.timeouts)
    local hLabel, hCol
    if overall == "ok" then
        hLabel = "[OK]"; hCol = P.fg_ok
    elseif overall == "degraded" then
        hLabel = "[DEGR]"; hCol = P.fg_warn
    else
        hLabel = "[CRIT]"
        hCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(13, 2, hLabel, hCol, P.bg)
    local time_str = textutils.formatTime(os.time("local"), true)
    p_top:text(W - #time_str - 2, 2, time_str, P.fg_dim, P.bg)

    -- ENERGY (3-5)
    p_top:divider(1, 3, W, P.border)
    p_top:text(3, 3, " ENERGY ", P.fg_title, P.bg)

    local es = energy.snapshot()
    health.set("energy", es.ok)
    if es.ok then
        local ecol = energyColorAlert(es.pct)
        local pctStr = ("%.1f%%"):format(es.pct * 100)
        p_top:text(W - #pctStr - 2, 3, pctStr, ecol, P.bg)
        p_top:text(3, 4, fmt(es.stored) .. " / " .. fmt(es.capacity) .. " FE", P.fg_value, P.bg)
        local flow = es.flow or 0
        local fcol = (flow >= 0) and P.fg_ok or P.fg_crit
        p_top:text(3, 5, "FLOW: " .. ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol, P.bg)
    else
        p_top:text(3, 4, "OFFLINE", P.fg_crit, P.bg)
    end

    -- STORAGE (6-10)
    p_top:divider(1, 6, W, P.border)
    p_top:text(3, 6, " STORAGE ", P.fg_title, P.bg)

    local rss = rs.snapshot()
    health.set("rs", rss.ok)
    if rss.ok then
        local pctStr = ("%.3f%%"):format(rss.item_pct * 100)
        p_top:text(W - #pctStr - 2, 6, pctStr, colors.cyan, P.bg)
        p_top:text(3, 7, fmt(rss.item_used) .. " / " .. fmt(rss.item_max) .. " items", P.fg_value, P.bg)

        if state.storage_breakdown and #state.storage_breakdown.breakdown > 0 then
            local items = state.storage_breakdown.breakdown
            -- Top 4 in 2 righe (2 per riga)
            for col = 1, 2 do
                if items[col] then
                    local b = items[col]
                    local x = 3 + (col - 1) * (math.floor(W / 2) - 1)
                    local segCol = STACK_COLORS[col] or colors.gray
                    p_top:fill(x, 8, 2, 1, segCol)
                    local nm = shorten(shortName(b.name), 6)
                    local pcs = ("%2d%%"):format(math.floor(b.pct * 100 + 0.5))
                    p_top:text(x + 3, 8, nm .. " " .. pcs, P.fg_value, P.bg)
                end
            end
            for col = 1, 2 do
                local idx = col + 2
                if items[idx] then
                    local b = items[idx]
                    local x = 3 + (col - 1) * (math.floor(W / 2) - 1)
                    local segCol = STACK_COLORS[idx] or colors.gray
                    p_top:fill(x, 9, 2, 1, segCol)
                    local nm = shorten(shortName(b.name), 6)
                    local pcs = ("%2d%%"):format(math.floor(b.pct * 100 + 0.5))
                    p_top:text(x + 3, 9, nm .. " " .. pcs, P.fg_value, P.bg)
                end
            end
            -- OTHERS riga 10
            if state.storage_breakdown.others_pct > 0 then
                p_top:fill(3, 10, 2, 1, OTHERS_COLOR)
                local pcs = ("%d%%"):format(math.floor(state.storage_breakdown.others_pct * 100 + 0.5))
                p_top:text(6, 10, "OTHERS " .. pcs, P.fg_dim, P.bg)
            end
        end
    else
        p_top:text(3, 7, "OFFLINE", P.fg_crit, P.bg)
    end

    -- SAT INFO (11-12)
    p_top:divider(1, 11, W, P.border)
    local sStatus = health.getStatus("satellite", alerts.timeouts)
    local satLabel, satCol
    if sStatus == "ok" then
        satLabel = "SAT:ON";  satCol = P.fg_ok
    elseif sStatus == "warn" then
        satLabel = "SAT:WARN";satCol = P.fg_warn
    else
        satLabel = "SAT:OFF"
        satCol = state.blink_on and P.fg_crit or P.bg
    end
    p_top:text(3, 12, satLabel, satCol, P.bg)
    if es.ok then
        local avg = es.avg_flow or 0
        local acol = (avg >= 0) and P.fg_ok or P.fg_crit
        local avgStr = "AVG:" .. ((avg >= 0) and "+" or "") .. fmt(avg)
        p_top:text(math.floor(W / 2) - math.floor(#avgStr / 2), 12, avgStr, acol, P.bg)
    end
    local upStr = "UP:" .. fmtUptime()
    p_top:text(W - #upStr - 2, 12, upStr, P.fg_dim, P.bg)

    -- BOTTONI FARM (13-14, alti 2 righe, in fondo)
    local btnW = math.floor((W - 5) / 2)
    local btn1X = 2
    local btn2X = 2 + btnW + 1

    local f1On = state.farms[1] == true
    local f1Bg = f1On and colors.green or colors.red
    local f1Lbl = f1On and "FARM 1: ON" or "FARM 1: OFF"
    p_top:button("farm1", btn1X, 13, btnW, 2, f1Lbl, f1Bg, colors.white)

    local f2On = state.farms[2] == true
    local f2Bg = f2On and colors.green or colors.red
    local f2Lbl = f2On and "FARM 2: ON" or "FARM 2: OFF"
    p_top:button("farm2", btn2X, 13, btnW, 2, f2Lbl, f2Bg, colors.white)

    p_top:flush()
end

-- ============================================================
-- BAR1: STORAGE
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
-- LAT3: ENERGY DETAIL scale 1.5 (~37x16)
-- 1: bordo, 2: header
-- 3: div STATUS
-- 4-8: status (5 righe: stored, capacity, level+bar, flow+status, avg)
-- 9: div POWER LEVEL HIST 30M
-- 10-12: chart 3 righe
-- 13: asse X
-- 14: I/O+ chart 1 riga (verde)
-- 15: I/O- chart 1 riga (rosso)
-- 16: bordo
-- ============================================================
local function renderEnergyDetail()
    local W, H = p_lat3:size()
    p_lat3:clear()
    p_lat3:box(1, 1, W, H, P.border)

    p_lat3:text(3, 2, "ENERGY DETAIL", P.fg_title, P.bg)
    p_lat3:text(W - 11, 2, "VIBRANT CB", P.fg_dim, P.bg)

    local s = energy.snapshot()
    if not s.ok then
        p_lat3:textCenter(math.floor(H / 2), "*** SIGNAL LOST ***", P.fg_crit, P.bg)
        p_lat3:flush()
        return
    end

    -- STATUS (3-8)
    p_lat3:divider(1, 3, W, P.border)
    p_lat3:text(3, 3, " STATUS ", P.fg_title, P.bg)

    p_lat3:text(3,  4, "STORED   :", P.fg_label, P.bg)
    p_lat3:text(14, 4, fmt(s.stored) .. " FE", P.fg_value, P.bg)

    p_lat3:text(3,  5, "CAPACITY :", P.fg_label, P.bg)
    p_lat3:text(14, 5, fmt(s.capacity) .. " FE", P.fg_value, P.bg)

    p_lat3:text(3, 6, "LEVEL    :", P.fg_label, P.bg)
    local ecol = energyColorAlert(s.pct)
    local barW = W - 24
    p_lat3:hbar(14, 6, barW, s.pct, ecol, colors.gray)
    p_lat3:text(W - 8, 6, ("%5.1f%%"):format(s.pct * 100), ecol, P.bg)

    p_lat3:text(3, 7, "FLOW     :", P.fg_label, P.bg)
    local flow = s.flow or 0
    local fcol = (flow >= 0) and P.fg_ok or P.fg_crit
    p_lat3:text(14, 7, ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol, P.bg)
    local statusLabel
    if math.abs(flow) < 1 then       statusLabel = "STABLE"
    elseif flow > 0 then             statusLabel = "CHARGING"
    else                             statusLabel = "DISCHARG" end
    local statCol = (flow > 0) and P.fg_ok or (flow < 0) and P.fg_warn or P.fg_dim
    p_lat3:text(W - 13, 7, "ST:" .. statusLabel, statCol, P.bg)

    p_lat3:text(3, 8, "AVG 10s  :", P.fg_label, P.bg)
    local avg = s.avg_flow or 0
    local acol = (avg >= 0) and P.fg_ok or P.fg_crit
    p_lat3:text(14, 8, ((avg >= 0) and "+" or "") .. fmt(avg) .. " FE/t", acol, P.bg)

    -- POWER LEVEL HISTORY (9-13)
    p_lat3:divider(1, 9, W, P.border)
    p_lat3:text(3, 9, " POWER LEVEL HIST 30M ", P.fg_title, P.bg)

    local hist30 = energy.getPctHistory(900)
    local chartH = 3
    local chartX = 6
    local chartW = W - 8

    p_lat3:text(2, 10, "100", P.fg_dim, P.bg)
    p_lat3:text(2, 12, "  0", P.fg_dim, P.bg)

    if #hist30 >= 2 then
        p_lat3:sparklineMulti(chartX, 10, chartW, chartH, hist30,
            { color = ecol, min = 0, max = 1 })
    else
        p_lat3:textCenter(11, "(in raccolta...)", P.fg_dim, P.bg)
    end

    p_lat3:text(chartX, 13, "-30m", P.fg_dim, P.bg)
    p_lat3:text(chartX + math.floor(chartW / 2) - 2, 13, "-15m", P.fg_dim, P.bg)
    p_lat3:text(chartX + chartW - 4, 13, " now", P.fg_dim, P.bg)

    -- I/O FLOW chart 2 righe (14-15)
    local flowHist = energy.getFlowHistory(300)
    local maxAbs = 1
    if #flowHist >= 2 then
        for _, v in ipairs(flowHist) do
            if math.abs(v) > maxAbs then maxAbs = math.abs(v) end
        end
    end
    p_lat3:text(2, 14, "I/O+", P.fg_ok, P.bg)
    p_lat3:text(2, 15, "I/O-", P.fg_crit, P.bg)
    if #flowHist >= 2 then
        p_lat3:flowMiniBar(7, 14, W - 9, flowHist, {
            posColor = P.fg_ok, negColor = P.fg_crit, maxAbs = maxAbs,
        })
        -- Label max FE/t a destra
        local mStr = "+/-" .. fmt(maxAbs)
        p_lat3:text(W - #mStr - 1, 14, mStr, P.fg_dim, P.bg)
    end

    p_lat3:flush()
end

-- ============================================================
-- LAT4: API DASHBOARD scale 1.5 (~37x16)
-- 1: bordo, 2: header
-- 3: div TAB
-- 4-13: tab content (10 righe per LIST/PROJECT/CHARTS, content for DETAIL)
-- 14: div
-- 15: tab buttons
-- 16: bordo
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

    -- Riga 4: nav buttons + nome prodotto
    p_lat4:button("api_prev", 3, 4, 4, 1, " < ", colors.blue, colors.white)
    p_lat4:text(9, 4, shortName(prod.id), P.fg_title, P.bg)
    p_lat4:text(W - 12, 4, ("(%d/%d)"):format(state.api_prod_idx, #products), P.fg_dim, P.bg)
    p_lat4:button("api_next", W - 6, 4, 4, 1, " > ", colors.blue, colors.white)

    -- Info (riga 6-9)
    p_lat4:text(3, 6,  "STORED:", P.fg_label, P.bg)
    p_lat4:text(13, 6, fmt(s.count) .. " units", P.fg_value, P.bg)
    p_lat4:text(3, 7,  "RATE  :", P.fg_label, P.bg)
    p_lat4:text(13, 7, fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_ok or P.fg_crit, P.bg)
    p_lat4:text(3, 8,  "EMA   :", P.fg_label, P.bg)
    p_lat4:text(13, 8, fmtRate(s.rate_ema), (s.rate_ema >= 0) and P.fg_ok or P.fg_crit, P.bg)
    p_lat4:text(3, 9,  "TREND :", P.fg_label, P.bg)
    local arrow, acol = trendArrow(s.trend)
    local tlbl = (s.trend > 0 and "rising") or (s.trend < 0 and "falling") or "stable"
    p_lat4:text(13, 9, arrow .. " " .. tlbl, acol, P.bg)

    -- Chart history (10-13)
    p_lat4:text(3, 10, "HISTORY 30M:", P.fg_dim, P.bg)
    local hist = bees.getHistory(prod.id, 60)
    if #hist >= 2 then
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end
        p_lat4:sparklineMulti(3, 11, W - 4, 3, pts, { color = colors.cyan })
    else
        p_lat4:text(3, 12, "(in raccolta...)", P.fg_dim, P.bg)
    end
end

local function renderApiTabLista()
    local W, H = p_lat4:size()
    -- Header colonne sopra prodotti
    p_lat4:text(3,  4, "PRODUCT",  P.fg_label, P.bg)
    p_lat4:text(18, 4, "STORED",   P.fg_label, P.bg)
    p_lat4:text(27, 4, "RATE",     P.fg_label, P.bg)
    p_lat4:text(35, 4, "TR",       P.fg_label, P.bg)

    local all = bees.snapshotAll()
    -- Mostra tutti i prodotti (max 9 dato 4-12 = 9 righe)
    for i, s in ipairs(all) do
        local row = 4 + i
        if row >= 14 then break end
        p_lat4:text(3,  row, shorten(s.label, 13), P.fg_value, P.bg)
        p_lat4:text(18, row, fmt(s.count), colors.cyan, P.bg)
        p_lat4:text(27, row, fmtRate(s.rate_30m), (s.rate_30m >= 0) and P.fg_ok or P.fg_crit, P.bg)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(36, row, arrow, acol, P.bg)
    end
end

local function renderApiTabProiezione()
    local W, H = p_lat4:size()
    -- Header con controlli
    p_lat4:text(3, 4, "PROJECT IN:", P.fg_label, P.bg)
    p_lat4:fill(15, 4, 6, 1, colors.gray)
    p_lat4:text(17, 4, ("%4d"):format(state.api_proj_hours), P.fg_value, colors.gray)
    p_lat4:text(22, 4, "h", P.fg_label, P.bg)
    p_lat4:button("api_h_minus", 25, 4, 4, 1, " - ", colors.red,   colors.white)
    p_lat4:button("api_h_plus",  31, 4, 4, 1, " + ", colors.green, colors.white)

    -- Header colonne riga 5
    p_lat4:text(3,  5, "PRODUCT",  P.fg_dim, P.bg)
    p_lat4:text(18, 5, "+" .. state.api_proj_hours .. "h", P.fg_dim, P.bg)
    p_lat4:text(27, 5, "DELTA",    P.fg_dim, P.bg)

    for i, prod in ipairs(bees.getProducts()) do
        local row = 5 + i
        if row >= 14 then break end
        local cur = bees.getCount(prod.id)
        local fut = bees.project(prod.id, state.api_proj_hours)
        local d = fut - cur
        local dcol = (d >= 0) and P.fg_ok or P.fg_crit
        p_lat4:text(3,  row, shorten(prod.label, 13), P.fg_value, P.bg)
        p_lat4:text(18, row, fmt(fut), P.fg_value, P.bg)
        p_lat4:text(27, row, ((d >= 0) and "+" or "") .. fmt(d), dcol, P.bg)
    end
end

local function renderApiTabGrafici()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, "PRODUCT      RATE     CHART", P.fg_dim, P.bg)

    local products = bees.getProducts()
    for i, prod in ipairs(products) do
        local row = 4 + i
        if row >= 14 then break end
        local s = bees.snapshot(prod.id)
        local hist = bees.getHistory(prod.id, 60)
        local pts = {}
        for _, sm in ipairs(hist) do pts[#pts + 1] = sm.c end

        p_lat4:text(3, row, shorten(shortName(prod.id), 11), P.fg_label, P.bg)
        local rateStr = fmtRate(s.rate_30m)
        local rcol = (s.rate_30m >= 0) and P.fg_ok or P.fg_crit
        p_lat4:text(15, row, rateStr, rcol, P.bg)
        if #pts >= 2 then
            p_lat4:sparklineMulti(24, row, W - 26, 1, pts, { color = colors.cyan })
        end
    end
end

local function renderApi()
    local W, H = p_lat4:size()
    p_lat4:clear()
    p_lat4.buttons = {}
    p_lat4:box(1, 1, W, H, P.border)

    -- Header (riga 2)
    p_lat4:text(3, 2, "APIARY MONITOR", P.fg_title, P.bg)
    local ts = textutils.formatTime(os.time("local"), true)
    p_lat4:text(W - #ts - 2, 2, ts, P.fg_dim, P.bg)

    -- Divider con titolo tab corrente (riga 3)
    p_lat4:divider(1, 3, W, P.border)
    local tabTitle = (state.api_tab == "dettaglio" and " DETAIL ")
                  or (state.api_tab == "lista" and " LIST ")
                  or (state.api_tab == "proiezione" and " PROJECTION ")
                  or " CHARTS "
    p_lat4:text(3, 3, tabTitle, P.fg_title, P.bg)

    if     state.api_tab == "dettaglio"  then renderApiTabDettaglio()
    elseif state.api_tab == "lista"      then renderApiTabLista()
    elseif state.api_tab == "proiezione" then renderApiTabProiezione()
    elseif state.api_tab == "grafici"    then renderApiTabGrafici() end

    -- Tab buttons in fondo (riga 14-15)
    p_lat4:divider(1, 14, W, P.border)
    local tabs = {
        { id = "dettaglio",  label = "DETAIL"  },
        { id = "lista",      label = "LIST"    },
        { id = "proiezione", label = "PROJ"    },
        { id = "grafici",    label = "CHRT"    },
    }
    -- Distribuisci tab uniformemente
    local totalTabsW = 0
    for _, t in ipairs(tabs) do totalTabsW = totalTabsW + #t.label + 2 end
    local gap = math.max(1, math.floor((W - 4 - totalTabsW) / (#tabs - 1)))
    local x = 3
    for _, t in ipairs(tabs) do
        local w = #t.label + 2
        local active = (state.api_tab == t.id)
        local bg = active and colors.green or colors.gray
        p_lat4:button("apitab_" .. t.id, x, 15, w, 1, " " .. t.label, bg, colors.white)
        x = x + w + gap
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
        local ok, br = pcall(rs.itemBreakdown, 4)
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
logger.info("Task paralleli avviati (v11)")

parallel.waitForAny(
    taskEnergy, taskBees, taskSatSync, taskRsHealth,
    taskStorageBreakdown, taskRender, taskBlink, taskClicks
)

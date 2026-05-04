-- /programs/central.lua  v3 — con health tracking + alert + recovery
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

print("=== CENTRAL DASHBOARD ===")
logger.info("Central dashboard avviato")

local rsOk, rsErr = rs.init()
health.set("rs", rsOk)
if not rsOk then logger.warn("RS init: " .. tostring(rsErr)) end

local enOk, enErr = energy.init()
health.set("energy", enOk)
if not enOk then logger.warn("Energy init: " .. tostring(enErr)) end

bees.init(cfg)
print("Bees: " .. #cfg.products .. " prodotti")

local fmOk, fmErr = farm.init()
health.set("satellite", fmOk)
if not fmOk then logger.warn("Farm init: " .. tostring(fmErr)) end

local p_top   = gui.attach("top")
local p_bar1  = gui.attach("monitor_1")
local p_bar2  = gui.attach("monitor_2")
local p_lat3  = gui.attach("monitor_3")
local p_lat4  = gui.attach("monitor_4")

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
}

-- ============================================================
-- Helpers
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

local function energyColor(pct)
    if pct < alerts.energy.crit_pct then
        return state.blink_on and colors.red or colors.black, "crit"
    elseif pct < alerts.energy.warn_pct then
        return colors.yellow, "warn"
    end
    return colors.lime, "ok"
end

local function storageColor(pct)
    if pct > alerts.storage.crit_pct then
        return state.blink_on and colors.red or colors.black, "crit"
    elseif pct > alerts.storage.warn_pct then
        return colors.yellow, "warn"
    end
    return colors.cyan, "ok"
end

-- ============================================================
-- Render TOP
-- ============================================================
local function renderTop()
    local W, H = p_top:size()
    p_top:clear()
    p_top.buttons = {}

    p_top:fill(1, 1, W, 1, colors.gray)
    p_top:text(2, 1, "CENTRALE", colors.yellow, colors.gray)

    local overall, critN, warnN = health.overall(alerts.timeouts)
    local hLabel, hCol
    if overall == "ok" then
        hLabel = "[ OK ]"; hCol = colors.lime
    elseif overall == "degraded" then
        hLabel = "[ DEGRADATO ]"; hCol = colors.yellow
    else
        hLabel = "[ CRITICO ]"
        hCol = state.blink_on and colors.red or colors.black
    end
    p_top:text(12, 1, hLabel, hCol, colors.gray)

    local time_str = textutils.formatTime(os.time("local"), true)
    p_top:text(W - #time_str - 1, 1, time_str, colors.lightGray, colors.gray)

    local es = energy.snapshot()
    health.set("energy", es.ok)
    p_top:text(2, 3, "ENERGIA - Vibrant Capacitor", colors.orange)
    if es.ok then
        local ecol, _ = energyColor(es.pct)
        p_top:hbar(2, 4, W - 4, es.pct, ecol)
        p_top:text(W - 7, 4, ("%5.1f%%"):format(es.pct * 100), ecol)
        p_top:text(2, 5, ("%s / %s FE"):format(fmt(es.stored), fmt(es.capacity)), colors.white)
        local flow = es.flow or 0
        local fcol = (flow >= 0) and colors.lime or colors.red
        local fstr = ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t"
        p_top:text(W - #fstr - 1, 5, fstr, fcol)
    else
        p_top:text(2, 4, "non disponibile", colors.red)
        p_top:text(2, 5, "(retry automatico)", colors.gray)
    end

    local rss = rs.snapshot()
    health.set("rs", rss.ok)
    p_top:text(2, 7, "STORAGE - Refined Storage", colors.orange)
    if rss.ok then
        local scol, _ = storageColor(rss.item_pct)
        p_top:hbar(2, 8, W - 4, rss.item_pct, scol)
        p_top:text(W - 8, 8, ("%6.3f%%"):format(rss.item_pct * 100), scol)
        p_top:text(2, 9, ("%s / %s items"):format(fmt(rss.item_used), fmt(rss.item_max)), colors.white)
        p_top:text(2, 10,
            ("%s FE     Uso: %d FE/t"):format(fmt(rss.energy_used), rss.energy_usage),
            colors.lightGray)
    else
        p_top:text(2, 8, "non disponibile: " .. (rss.err or ""), colors.red)
        p_top:text(2, 9, "(retry automatico)", colors.gray)
    end

    local sStatus = health.getStatus("satellite", alerts.timeouts)
    local sat_label, sat_col
    if sStatus == "ok" then
        sat_label = "Satellite: ONLINE"; sat_col = colors.lime
    elseif sStatus == "warn" then
        sat_label = "Satellite: WARN"; sat_col = colors.yellow
    else
        sat_label = "Satellite: OFFLINE"
        sat_col = state.blink_on and colors.red or colors.black
    end
    p_top:text(W - #sat_label - 1, H - 3, sat_label, sat_col)

    local btnW = 14
    local btnX = W - btnW - 1

    local f1On = state.farms[1] == true
    local f1Bg = f1On and colors.green or colors.red
    local f1Lbl = "FARM 1: " .. (f1On and "ON" or "OFF")
    p_top:button("farm1", btnX, H - 2, btnW, 1, f1Lbl, f1Bg, colors.white)

    local f2On = state.farms[2] == true
    local f2Bg = f2On and colors.green or colors.red
    local f2Lbl = "FARM 2: " .. (f2On and "ON" or "OFF")
    p_top:button("farm2", btnX, H - 1, btnW, 1, f2Lbl, f2Bg, colors.white)

    p_top:flush()
end

-- ============================================================
-- Barre verticali
-- ============================================================
local function renderBar1()
    local _, H = p_bar1:size()
    p_bar1:clear()
    local rss = rs.snapshot()
    if rss.ok then
        local col, _ = storageColor(rss.item_pct)
        p_bar1:vbar(1, 1, H, rss.item_pct, col)
    else
        p_bar1:vbar(1, 1, H, 0, colors.red)
    end
    p_bar1:flush()
end

local function renderBar2()
    local _, H = p_bar2:size()
    p_bar2:clear()
    local es = energy.snapshot()
    if es.ok then
        local col, _ = energyColor(es.pct)
        p_bar2:vbar(1, 1, H, es.pct, col)
    else
        p_bar2:vbar(1, 1, H, 0, colors.red)
    end
    p_bar2:flush()
end

-- ============================================================
-- Dettaglio energia
-- ============================================================
local function renderEnergyDetail()
    local W, H = p_lat3:size()
    p_lat3:clear()
    p_lat3:textCenter(1, "ENERGIA - Vibrant Cap Bank", colors.yellow)

    local s = energy.snapshot()
    if not s.ok then
        p_lat3:textCenter(3, "non disponibile", colors.red)
        p_lat3:textCenter(4, "(retry automatico)", colors.gray)
        p_lat3:flush()
        return
    end

    p_lat3:text(2, 3, "Stoccato:",   colors.lightGray)
    p_lat3:text(13, 3, fmt(s.stored) .. " FE", colors.white)
    p_lat3:text(2, 4, "Capacita':",  colors.lightGray)
    p_lat3:text(13, 4, fmt(s.capacity) .. " FE", colors.white)

    local barColor, _ = energyColor(s.pct)
    p_lat3:hbar(2, 6, W - 4, s.pct, barColor)
    p_lat3:text(W - 7, 6, ("%6.2f%%"):format(s.pct * 100), barColor)

    local flow = s.flow or 0
    local fcol = (flow >= 0) and colors.lime or colors.red
    p_lat3:text(2, 8,  "Flusso (now):", colors.lightGray)
    p_lat3:text(16, 8, ((flow >= 0) and "+" or "") .. fmt(flow) .. " FE/t", fcol)

    local avg = s.avg_flow or 0
    local acol = (avg >= 0) and colors.lime or colors.red
    p_lat3:text(2, 9,  "Flusso (10s):", colors.lightGray)
    p_lat3:text(16, 9, ((avg >= 0) and "+" or "") .. fmt(avg) .. " FE/t", acol)

    p_lat3:text(2, 11, "Stato:", colors.lightGray)
    if math.abs(flow) < 1 then       p_lat3:text(9, 11, "STABILE",    colors.gray)
    elseif flow > 0 then             p_lat3:text(9, 11, "IN CARICA",  colors.lime)
    else                             p_lat3:text(9, 11, "IN SCARICA", colors.orange) end

    p_lat3:flush()
end

-- ============================================================
-- API dashboard
-- ============================================================
local function renderApiHeader()
    local W = p_lat4:size()
    p_lat4:fill(1, 1, W, 1, colors.gray)
    p_lat4:text(2, 1, "API MONITOR", colors.yellow, colors.gray)
    local ts = textutils.formatTime(os.time("local"), true)
    p_lat4:text(W - #ts - 1, 1, ts, colors.lightGray, colors.gray)

    local tabs = {
        { id = "dettaglio",  label = "DETTAGLIO" },
        { id = "lista",      label = "LISTA" },
        { id = "proiezione", label = "PROIEZIONE" },
    }
    local x = 2
    for _, t in ipairs(tabs) do
        local w = #t.label + 2
        local bg = (state.api_tab == t.id) and colors.blue or colors.lightGray
        local fg = (state.api_tab == t.id) and colors.white or colors.black
        p_lat4:button("apitab_" .. t.id, x, 2, w, 1, t.label, bg, fg)
        x = x + w + 1
    end
end

local function renderApiTabDettaglio()
    local W, H = p_lat4:size()
    local products = bees.getProducts()
    if #products == 0 then return end

    if state.api_prod_idx < 1 then state.api_prod_idx = #products end
    if state.api_prod_idx > #products then state.api_prod_idx = 1 end
    local prod = products[state.api_prod_idx]
    local s = bees.snapshot(prod.id)

    p_lat4:textCenter(4, prod.label:upper(), colors.orange)
    p_lat4:textCenter(5, ("(%d / %d)"):format(state.api_prod_idx, #products), colors.gray)

    p_lat4:text(3, 7, "Stoccato:", colors.lightGray)
    p_lat4:text(20, 7, fmt(s.count) .. " unita'", colors.white)

    p_lat4:text(3, 8, "Rate 30m:", colors.lightGray)
    p_lat4:text(20, 8, fmtRate(s.rate_30m), (s.rate_30m >= 0) and colors.lime or colors.red)

    p_lat4:text(3, 9, "Rate EMA:", colors.lightGray)
    p_lat4:text(20, 9, fmtRate(s.rate_ema), (s.rate_ema >= 0) and colors.lime or colors.red)

    p_lat4:text(3, 10, "Trend:", colors.lightGray)
    local arrow, acol = trendArrow(s.trend)
    p_lat4:text(20, 10, arrow .. " " ..
        (s.trend > 0 and "in salita" or s.trend < 0 and "in discesa" or "stabile"), acol)

    p_lat4:text(3, 11, "Sample:", colors.lightGray)
    p_lat4:text(20, 11, tostring(s.n_samples), colors.gray)

    local hist = bees.getHistory(prod.id, 60)
    if #hist >= 2 then
        local gx, gy, gw, gh = 3, 14, W - 6, 6
        p_lat4:text(gx, gy - 1, "Ultimi 30 min:", colors.lightGray)
        p_lat4:fill(gx, gy, gw, gh, colors.black)
        local minc, maxc = math.huge, -math.huge
        for _, sm in ipairs(hist) do
            if sm.c < minc then minc = sm.c end
            if sm.c > maxc then maxc = sm.c end
        end
        if maxc == minc then maxc = minc + 1 end
        for i, sm in ipairs(hist) do
            local px = gx + math.floor((i - 1) / (#hist - 1) * (gw - 1))
            local py = gy + gh - 1 - math.floor((sm.c - minc) / (maxc - minc) * (gh - 1))
            p_lat4:text(px, py, "*", colors.cyan)
        end
    end

    p_lat4:button("api_prev", 3,        H - 2, 10, 2, "< PREV", colors.blue)
    p_lat4:button("api_next", W - 12,   H - 2, 10, 2, "NEXT >", colors.blue)
end

local function renderApiTabLista()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, "Prodotto",  colors.lightGray)
    p_lat4:text(25, 4, "Count",    colors.lightGray)
    p_lat4:text(40, 4, "Rate 30m", colors.lightGray)
    p_lat4:text(55, 4, "Trend",    colors.lightGray)
    p_lat4:fill(3, 5, W - 4, 1, colors.gray)

    local all = bees.snapshotAll()
    for i, s in ipairs(all) do
        local row = 5 + i
        if row >= H - 1 then break end
        p_lat4:text(3, row, shorten(s.label, 20), colors.white)
        p_lat4:text(25, row, fmt(s.count), colors.cyan)
        p_lat4:text(40, row, fmtRate(s.rate_30m), (s.rate_30m >= 0) and colors.lime or colors.red)
        local arrow, acol = trendArrow(s.trend)
        p_lat4:text(57, row, arrow, acol)
    end
end

local function renderApiTabProiezione()
    local W, H = p_lat4:size()
    p_lat4:text(3, 4, "Proiezione a:", colors.lightGray)
    p_lat4:fill(18, 4, 6, 1, colors.lightGray)
    p_lat4:text(20, 4, ("%4d"):format(state.api_proj_hours), colors.black, colors.lightGray)
    p_lat4:text(25, 4, "ore", colors.lightGray)
    p_lat4:button("api_h_minus", 30, 4, 5, 1, " - ", colors.red)
    p_lat4:button("api_h_plus",  37, 4, 5, 1, " + ", colors.green)

    p_lat4:fill(3, 6, W - 4, 1, colors.gray)
    p_lat4:text(3, 6,  "Prodotto", colors.white, colors.gray)
    p_lat4:text(25, 6, "Ora",      colors.white, colors.gray)
    p_lat4:text(40, 6, "Tra " .. state.api_proj_hours .. "h", colors.white, colors.gray)
    p_lat4:text(55, 6, "Delta",    colors.white, colors.gray)

    for i, prod in ipairs(bees.getProducts()) do
        local row = 6 + i
        if row >= H - 1 then break end
        local cur = bees.getCount(prod.id)
        local fut = bees.project(prod.id, state.api_proj_hours)
        local d = fut - cur
        local dcol = (d >= 0) and colors.lime or colors.red
        p_lat4:text(3, row, shorten(prod.label, 20), colors.white)
        p_lat4:text(25, row, fmt(cur), colors.cyan)
        p_lat4:text(40, row, fmt(fut), colors.white)
        p_lat4:text(55, row, ((d >= 0) and "+" or "") .. fmt(d), dcol)
    end
end

local function renderApi()
    p_lat4:clear()
    p_lat4.buttons = {}
    renderApiHeader()
    if     state.api_tab == "dettaglio"  then renderApiTabDettaglio()
    elseif state.api_tab == "lista"      then renderApiTabLista()
    elseif state.api_tab == "proiezione" then renderApiTabProiezione() end
    p_lat4:flush()
end

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
-- Tasks con auto-recovery
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
                if btn == "apitab_dettaglio"  then state.api_tab = "dettaglio"
                elseif btn == "apitab_lista"      then state.api_tab = "lista"
                elseif btn == "apitab_proiezione" then state.api_tab = "proiezione"
                elseif btn == "api_prev"          then state.api_prod_idx = state.api_prod_idx - 1
                elseif btn == "api_next"          then state.api_prod_idx = state.api_prod_idx + 1
                elseif btn == "api_h_minus"       then state.api_proj_hours = math.max(1, state.api_proj_hours - 1)
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
logger.info("Task paralleli avviati")

parallel.waitForAny(
    taskEnergy, taskBees, taskSatSync, taskRsHealth,
    taskRender, taskBlink, taskClicks
)

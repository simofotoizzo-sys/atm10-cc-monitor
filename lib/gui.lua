-- /lib/gui.lua  v4 — ASCII puro + sparkline multi-riga
-- Niente piu' caratteri Unicode (causano artefatti su CC: Tweaked).
-- Sparkline ridisegnate con barre verticali multi-riga per maggiore espressivita'.

local gui = {}
local Panel = {}
Panel.__index = Panel

-- ============================================================
-- Caratteri ASCII per bordi
-- ============================================================
gui.chars = {
    -- Bordi singoli ASCII
    h_s  = "-", v_s  = "|",
    tl_s = "+", tr_s = "+", bl_s = "+", br_s = "+",
    -- Bordi doppi ASCII (=)
    h_d  = "=", v_d  = "|",
    tl_d = "+", tr_d = "+", bl_d = "+", br_d = "+",
    cross = "+",
    -- Pieno (per riempimenti, in pratica useremo bg color)
    full  = "#",
}

-- ============================================================
-- Palette riequilibrata: meno verde dominante
-- Testo principale BIANCO, etichette grigio chiaro, accenti per valori.
-- ============================================================
gui.palette = {
    bg          = colors.black,
    fg_main     = colors.white,        -- testo dati primario
    fg_dim      = colors.lightGray,    -- testo secondario
    fg_label    = colors.lightGray,    -- etichette
    fg_value    = colors.white,        -- valori numerici
    fg_ok       = colors.lime,         -- valori positivi/ok (es. flow +)
    fg_warn     = colors.yellow,       -- warning
    fg_crit     = colors.red,          -- critical
    fg_title    = colors.yellow,       -- titoli sezione
    fg_accent   = colors.lime,         -- accenti minori
    border      = colors.gray,         -- bordi neutri (non lime!)
    border_hl   = colors.lime,         -- bordi enfatici (rari)
    grid        = colors.gray,
}

-- Palette codec leggera: tocca solo lime e green per renderlo piu' fosforo,
-- niente di drastico
function gui.applyCodecPalette(mon)
    pcall(mon.setPaletteColor, colors.lime,   0x44FF77)
    pcall(mon.setPaletteColor, colors.yellow, 0xFFCC00)
    -- nient'altro: lasciamo i colori standard
end

-- ============================================================
-- Costruzione Panel
-- ============================================================
function gui.attach(name)
    local mon = peripheral.wrap(name)
    if not mon then error("gui.attach: monitor '" .. tostring(name) .. "' non trovato") end
    if peripheral.getType(name) ~= "monitor" then
        error("gui.attach: '" .. name .. "' non e' un monitor")
    end
    local self = setmetatable({}, Panel)
    self.name = name
    self.mon = mon
    self.buttons = {}
    self.scale = 1
    mon.setTextScale(1)
    gui.applyCodecPalette(mon)
    local w, h = mon.getSize()
    self.buf = window.create(mon, 1, 1, w, h, true)
    self.buf.setVisible(false)
    return self
end

function Panel:setScale(s)
    self.scale = s
    self.mon.setTextScale(s)
    local w, h = self.mon.getSize()
    self.buf = window.create(self.mon, 1, 1, w, h, true)
    self.buf.setVisible(false)
end

function Panel:size() return self.buf.getSize() end

function Panel:clear(bg)
    self.buf.setBackgroundColor(bg or gui.palette.bg)
    self.buf.clear()
    self.buf.setCursorPos(1, 1)
end

function Panel:text(x, y, str, fg, bg)
    self.buf.setCursorPos(x, y)
    self.buf.setTextColor(fg or gui.palette.fg_main)
    self.buf.setBackgroundColor(bg or gui.palette.bg)
    self.buf.write(tostring(str))
end

function Panel:textCenter(y, str, fg, bg)
    local w = self.buf.getSize()
    local s = tostring(str)
    local x = math.max(1, math.floor((w - #s) / 2) + 1)
    self:text(x, y, s, fg, bg)
end

function Panel:fill(x, y, w, h, color)
    self.buf.setBackgroundColor(color)
    for dy = 0, h - 1 do
        self.buf.setCursorPos(x, y + dy)
        self.buf.write(string.rep(" ", w))
    end
end

-- ============================================================
-- Bordi ASCII
-- ============================================================
-- Bordo doppio (con =) per box principali
function Panel:box(x, y, w, h, fg)
    fg = fg or gui.palette.border
    local bg = gui.palette.bg
    -- top
    self:text(x, y, "+" .. string.rep("=", w - 2) .. "+", fg, bg)
    -- bottom
    self:text(x, y + h - 1, "+" .. string.rep("=", w - 2) .. "+", fg, bg)
    -- sides
    for dy = 1, h - 2 do
        self:text(x,         y + dy, "|", fg, bg)
        self:text(x + w - 1, y + dy, "|", fg, bg)
    end
end

-- Bordo singolo (con -) per sotto-box
function Panel:boxSingle(x, y, w, h, fg)
    fg = fg or gui.palette.fg_dim
    local bg = gui.palette.bg
    self:text(x, y,         "+" .. string.rep("-", w - 2) .. "+", fg, bg)
    self:text(x, y + h - 1, "+" .. string.rep("-", w - 2) .. "+", fg, bg)
    for dy = 1, h - 2 do
        self:text(x,         y + dy, "|", fg, bg)
        self:text(x + w - 1, y + dy, "|", fg, bg)
    end
end

-- Divisore orizzontale (+========+)
function Panel:divider(x, y, w, fg)
    fg = fg or gui.palette.border
    self:text(x, y, "+" .. string.rep("=", w - 2) .. "+", fg, gui.palette.bg)
end

-- Divisore singolo (+--------+)
function Panel:dividerThin(x, y, w, fg)
    fg = fg or gui.palette.fg_dim
    self:text(x, y, "+" .. string.rep("-", w - 2) .. "+", fg, gui.palette.bg)
end

function Panel:section(x, y, w, h, title, fg)
    self:boxSingle(x, y, w, h, fg)
    if title then
        self:text(x + 2, y, " " .. title .. " ", gui.palette.fg_title, gui.palette.bg)
    end
end

-- ============================================================
-- Barre
-- ============================================================
function Panel:hbar(x, y, w, pct, color, bg)
    pct = math.max(0, math.min(1, pct or 0))
    bg = bg or colors.gray
    self:fill(x, y, w, 1, bg)
    local filled = math.floor(w * pct + 0.5)
    if filled > 0 then self:fill(x, y, filled, 1, color) end
end

function Panel:vbar(x, y, h, pct, color, bg)
    pct = math.max(0, math.min(1, pct or 0))
    bg = bg or colors.gray
    self:fill(x, y, 1, h, bg)
    local filled = math.floor(h * pct + 0.5)
    if filled > 0 then self:fill(x, y + h - filled, 1, filled, color) end
end

-- ============================================================
-- Sparkline multi-riga (USA BARRE COLORATE)
-- Disegna sparkline alta h righe, larga w colonne usando vbar.
-- Molto piu' espressivo dei caratteri Unicode block.
-- ============================================================
function Panel:sparklineMulti(x, y, w, h, data, opts)
    opts = opts or {}
    local color = opts.color or gui.palette.fg_accent
    local bg = opts.bg or colors.black
    -- pulisci area
    self:fill(x, y, w, h, bg)
    if not data or #data == 0 then return end
    local minv, maxv = math.huge, -math.huge
    for _, v in ipairs(data) do
        if v < minv then minv = v end
        if v > maxv then maxv = v end
    end
    if opts.min then minv = opts.min end
    if opts.max then maxv = opts.max end
    if maxv <= minv then maxv = minv + 1 end

    for i = 0, w - 1 do
        local idx = (#data == 1) and 1 or (math.floor(i / (w - 1) * (#data - 1)) + 1)
        idx = math.max(1, math.min(#data, idx))
        local v = data[idx]
        local norm = math.max(0, math.min(1, (v - minv) / (maxv - minv)))
        local filled = math.floor(norm * h + 0.5)
        if filled > 0 then
            self:fill(x + i, y + h - filled, 1, filled, color)
        end
    end
end

-- Sparkline simmetrica (dati sopra/sotto zero, es. flow energia)
-- y = riga centrale (zero), h = totale (deve essere dispari)
function Panel:sparklineSym(x, y_center, w, halfH, data, opts)
    opts = opts or {}
    local pos_color = opts.posColor or gui.palette.fg_ok
    local neg_color = opts.negColor or gui.palette.fg_crit
    local bg = opts.bg or colors.black
    -- pulisci area (h totale = halfH*2 + 1)
    self:fill(x, y_center - halfH, w, halfH * 2 + 1, bg)
    if not data or #data == 0 then return end
    local maxAbs = 0
    for _, v in ipairs(data) do
        local a = math.abs(v)
        if a > maxAbs then maxAbs = a end
    end
    if opts.maxAbs then maxAbs = opts.maxAbs end
    if maxAbs <= 0 then maxAbs = 1 end

    -- riga zero
    self:fill(x, y_center, w, 1, colors.gray)

    for i = 0, w - 1 do
        local idx = (#data == 1) and 1 or (math.floor(i / (w - 1) * (#data - 1)) + 1)
        idx = math.max(1, math.min(#data, idx))
        local v = data[idx]
        local norm = math.max(-1, math.min(1, v / maxAbs))
        local filled = math.floor(math.abs(norm) * halfH + 0.5)
        if filled > 0 then
            if norm > 0 then
                self:fill(x + i, y_center - filled, 1, filled, pos_color)
            else
                self:fill(x + i, y_center + 1, 1, filled, neg_color)
            end
        end
    end
end

-- ============================================================
-- Stacked bar verticale a segmenti colorati
-- ============================================================
function Panel:stackBarVertical(x, y, w, h, segments)
    local rows = {}
    local accum = 0
    for i, seg in ipairs(segments) do
        local target = (accum + (seg.pct or 0)) * h
        rows[i] = math.max(0, math.floor(target + 0.5) - math.floor(accum * h + 0.5))
        accum = accum + (seg.pct or 0)
    end
    local cur = h - 1
    for i, seg in ipairs(segments) do
        for _ = 1, rows[i] do
            if cur < 0 then break end
            self:fill(x, y + cur, w, 1, seg.color or colors.gray)
            cur = cur - 1
        end
        if cur < 0 then break end
    end
end

-- ============================================================
-- Bottoni
-- ============================================================
function Panel:button(id, x, y, w, h, label, bg, fg)
    self.buttons[id] = {
        id = id, x = x, y = y, w = w, h = h,
        label = label, bg = bg or colors.blue, fg = fg or colors.white
    }
    self:_drawButton(self.buttons[id])
end

function Panel:_drawButton(b)
    self:fill(b.x, b.y, b.w, b.h, b.bg)
    local lx = b.x + math.max(0, math.floor((b.w - #b.label) / 2))
    local ly = b.y + math.floor((b.h - 1) / 2)
    self:text(lx, ly, b.label, b.fg, b.bg)
end

function Panel:buttonBoxed(id, x, y, w, h, label, bg, fg, borderColor)
    self.buttons[id] = {
        id = id, x = x, y = y, w = w, h = h,
        label = label, bg = bg or colors.gray, fg = fg or colors.white,
        boxed = true, border = borderColor or gui.palette.border
    }
    self:_drawButtonBoxed(self.buttons[id])
end

function Panel:_drawButtonBoxed(b)
    self:fill(b.x, b.y, b.w, b.h, b.bg)
    -- Bordo ASCII
    self:text(b.x,             b.y,            "+" .. string.rep("-", b.w - 2) .. "+", b.border, b.bg)
    self:text(b.x,             b.y + b.h - 1,  "+" .. string.rep("-", b.w - 2) .. "+", b.border, b.bg)
    for dy = 1, b.h - 2 do
        self:text(b.x,             b.y + dy, "|", b.border, b.bg)
        self:text(b.x + b.w - 1,   b.y + dy, "|", b.border, b.bg)
    end
    local lx = b.x + math.max(0, math.floor((b.w - #b.label) / 2))
    local ly = b.y + math.floor((b.h - 1) / 2)
    self:text(lx, ly, b.label, b.fg, b.bg)
end

function Panel:updateButton(id, label, bg)
    local b = self.buttons[id]
    if not b then return end
    if label then b.label = label end
    if bg then b.bg = bg end
    if b.boxed then self:_drawButtonBoxed(b)
    else self:_drawButton(b) end
end

function Panel:redrawButtons()
    for _, b in pairs(self.buttons) do
        if b.boxed then self:_drawButtonBoxed(b) else self:_drawButton(b) end
    end
end

function Panel:hitTest(x, y)
    for _, b in pairs(self.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return b.id
        end
    end
    return nil
end

function Panel:flush()
    self.buf.setVisible(true)
    self.buf.setVisible(false)
end

function gui.waitClickAny(panels, timeout)
    local timer = timeout and os.startTimer(timeout) or nil
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "monitor_touch" then
            local side, x, y = ev[2], ev[3], ev[4]
            for _, p in pairs(panels) do
                if p.name == side then
                    local id = p:hitTest(x, y)
                    if id then return p, id end
                end
            end
        elseif ev[1] == "timer" and ev[2] == timer then
            return nil
        end
    end
end

return gui

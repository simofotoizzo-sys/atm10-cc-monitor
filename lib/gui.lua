-- /lib/gui.lua  v3 — MGS Codec style
-- Aggiunge: bordi Unicode, sparkline single/double, stacked bar, palette codec.

local gui = {}
local Panel = {}
Panel.__index = Panel

-- ============================================================
-- Caratteri grafici (Unicode box drawing)
-- ============================================================
gui.chars = {
    h  = "─", v  = "│",
    tl = "┌", tr = "┐", bl = "└", br = "┘",
    H  = "═", V  = "║",
    TL = "╔", TR = "╗", BL = "╚", BR = "╝",
    LE = "╣", RE = "╠", BE = "╩", TE = "╦",
    cross_d = "╬", cross_s = "┼",
    spark = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" },
    full     = "█",
    half_top = "▀",
    half_bot = "▄",
}

-- ============================================================
-- Palette MGS Codec (verde fosforo)
-- ============================================================
gui.palette = {
    bg          = colors.black,
    fg_main     = colors.lime,
    fg_dim      = colors.green,
    fg_label    = colors.lightGray,
    fg_value    = colors.white,
    fg_warn     = colors.yellow,
    fg_crit     = colors.red,
    border      = colors.lime,
    accent      = colors.yellow,
    grid        = colors.gray,
}

function gui.applyCodecPalette(mon)
    pcall(mon.setPaletteColor, colors.lime,      0x33FF66)
    pcall(mon.setPaletteColor, colors.green,     0x008833)
    pcall(mon.setPaletteColor, colors.yellow,    0xFFCC00)
    pcall(mon.setPaletteColor, colors.red,       0xFF3333)
    pcall(mon.setPaletteColor, colors.lightGray, 0x99AA99)
    pcall(mon.setPaletteColor, colors.gray,      0x445544)
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
-- Bordi Unicode
-- ============================================================
function Panel:box(x, y, w, h, fg)
    fg = fg or gui.palette.border
    local c = gui.chars
    local bg = gui.palette.bg
    self:text(x, y, c.TL .. string.rep(c.H, w - 2) .. c.TR, fg, bg)
    self:text(x, y + h - 1, c.BL .. string.rep(c.H, w - 2) .. c.BR, fg, bg)
    for dy = 1, h - 2 do
        self:text(x,         y + dy, c.V, fg, bg)
        self:text(x + w - 1, y + dy, c.V, fg, bg)
    end
end

function Panel:divider(x, y, w, fg)
    fg = fg or gui.palette.border
    local c = gui.chars
    self:text(x, y, c.RE .. string.rep(c.H, w - 2) .. c.LE, fg, gui.palette.bg)
end

function Panel:boxSingle(x, y, w, h, fg)
    fg = fg or gui.palette.fg_dim
    local c = gui.chars
    local bg = gui.palette.bg
    self:text(x, y, c.tl .. string.rep(c.h, w - 2) .. c.tr, fg, bg)
    self:text(x, y + h - 1, c.bl .. string.rep(c.h, w - 2) .. c.br, fg, bg)
    for dy = 1, h - 2 do
        self:text(x,         y + dy, c.v, fg, bg)
        self:text(x + w - 1, y + dy, c.v, fg, bg)
    end
end

function Panel:section(x, y, w, h, title, fg)
    self:boxSingle(x, y, w, h, fg)
    if title then
        self:text(x + 2, y, " " .. title .. " ", gui.palette.accent, gui.palette.bg)
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

function Panel:hbarFine(x, y, w, pct, fg, bg)
    pct = math.max(0, math.min(1, pct or 0))
    fg = fg or gui.palette.fg_main
    bg = bg or gui.palette.bg
    local fullCols = math.floor(w * pct)
    local frac = (w * pct) - fullCols
    local fracChars = {"▏","▎","▍","▌","▋","▊","▉","█"}
    local s = string.rep("█", fullCols)
    if fullCols < w and frac > 0 then
        local idx = math.max(1, math.min(8, math.floor(frac * 8) + 1))
        s = s .. fracChars[idx]
        s = s .. string.rep(" ", w - fullCols - 1)
    else
        s = s .. string.rep(" ", w - fullCols)
    end
    self:text(x, y, s, fg, bg)
end

-- ============================================================
-- Sparkline single-height (1 riga, 8 livelli)
-- ============================================================
function Panel:sparkline(x, y, w, data, opts)
    opts = opts or {}
    local fg = opts.color or gui.palette.fg_main
    local bg = opts.bg or gui.palette.bg
    if not data or #data == 0 then
        self:text(x, y, string.rep(" ", w), fg, bg)
        return
    end
    local minv, maxv = math.huge, -math.huge
    for _, v in ipairs(data) do
        if v < minv then minv = v end
        if v > maxv then maxv = v end
    end
    if opts.min then minv = opts.min end
    if opts.max then maxv = opts.max end
    if maxv <= minv then maxv = minv + 1 end

    local sparks = gui.chars.spark
    local out = ""
    for i = 0, w - 1 do
        local idx = (#data == 1) and 1 or (math.floor(i / (w - 1) * (#data - 1)) + 1)
        idx = math.max(1, math.min(#data, idx))
        local v = data[idx]
        local norm = math.max(0, math.min(1, (v - minv) / (maxv - minv)))
        local sIdx = math.max(1, math.min(8, math.floor(norm * 7) + 1))
        out = out .. sparks[sIdx]
    end
    self:text(x, y, out, fg, bg)
end

-- ============================================================
-- Sparkline double-height (2 righe, 16 livelli)
-- ============================================================
function Panel:sparklineDouble(x, y, w, data, opts)
    opts = opts or {}
    local fg = opts.color or gui.palette.fg_main
    local bg = opts.bg or gui.palette.bg
    if not data or #data == 0 then
        self:text(x, y,     string.rep(" ", w), fg, bg)
        self:text(x, y + 1, string.rep(" ", w), fg, bg)
        return
    end
    local minv, maxv = math.huge, -math.huge
    for _, v in ipairs(data) do
        if v < minv then minv = v end
        if v > maxv then maxv = v end
    end
    if opts.min then minv = opts.min end
    if opts.max then maxv = opts.max end
    if maxv <= minv then maxv = minv + 1 end

    local sparks = gui.chars.spark
    local upperRow, lowerRow = "", ""
    for i = 0, w - 1 do
        local idx = (#data == 1) and 1 or (math.floor(i / (w - 1) * (#data - 1)) + 1)
        idx = math.max(1, math.min(#data, idx))
        local v = data[idx]
        local norm = math.max(0, math.min(1, (v - minv) / (maxv - minv)))
        local level = math.floor(norm * 16 + 0.5)
        if level <= 0 then
            upperRow = upperRow .. " "
            lowerRow = lowerRow .. " "
        elseif level <= 8 then
            upperRow = upperRow .. " "
            lowerRow = lowerRow .. sparks[level]
        elseif level < 16 then
            local upIdx = level - 8
            upperRow = upperRow .. sparks[upIdx]
            lowerRow = lowerRow .. "█"
        else
            upperRow = upperRow .. "█"
            lowerRow = lowerRow .. "█"
        end
    end
    self:text(x, y,     upperRow, fg, bg)
    self:text(x, y + 1, lowerRow, fg, bg)
end

-- ============================================================
-- Stacked bar verticale a segmenti colorati
-- segments = { { pct = 0.45, color = ..., label = ... }, ... }  (sommano a 1.0)
-- ============================================================
function Panel:stackBarVertical(x, y, w, h, segments)
    local rows = {}
    local accum = 0
    for i, seg in ipairs(segments) do
        local target = (accum + (seg.pct or 0)) * h
        rows[i] = math.max(0, math.floor(target + 0.5) - math.floor(accum * h + 0.5))
        accum = accum + (seg.pct or 0)
    end
    -- riempo dal basso
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
    local c = gui.chars
    self:text(b.x,             b.y,             c.tl .. string.rep(c.h, b.w - 2) .. c.tr, b.border, b.bg)
    self:text(b.x,             b.y + b.h - 1,   c.bl .. string.rep(c.h, b.w - 2) .. c.br, b.border, b.bg)
    for dy = 1, b.h - 2 do
        self:text(b.x,             b.y + dy, c.v, b.border, b.bg)
        self:text(b.x + b.w - 1,   b.y + dy, c.v, b.border, b.bg)
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

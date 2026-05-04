-- /lib/gui.lua  v2 — con double buffering per eliminare il flicker
local gui = {}
local Panel = {}
Panel.__index = Panel

-- ============================================================
-- Costruzione
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
    -- Crea il buffer (window) sopra il monitor
    local w, h = mon.getSize()
    self.buf = window.create(mon, 1, 1, w, h, true)
    self.buf.setVisible(false)  -- non si aggiorna automaticamente sul monitor
    return self
end

-- ============================================================
-- Util base
-- ============================================================
function Panel:setScale(s)
    self.scale = s
    self.mon.setTextScale(s)
    -- Ricrea il buffer alle nuove dimensioni
    local w, h = self.mon.getSize()
    self.buf = window.create(self.mon, 1, 1, w, h, true)
    self.buf.setVisible(false)
end

function Panel:size()
    return self.buf.getSize()
end

function Panel:clear(bg)
    self.buf.setBackgroundColor(bg or colors.black)
    self.buf.clear()
    self.buf.setCursorPos(1, 1)
end

function Panel:text(x, y, str, fg, bg)
    self.buf.setCursorPos(x, y)
    self.buf.setTextColor(fg or colors.white)
    self.buf.setBackgroundColor(bg or colors.black)
    self.buf.write(tostring(str))
end

function Panel:textCenter(y, str, fg, bg)
    local w, _ = self.buf.getSize()
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
-- Barre di progresso
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

function Panel:updateButton(id, label, bg)
    local b = self.buttons[id]
    if not b then return end
    if label then b.label = label end
    if bg then b.bg = bg end
    self:_drawButton(b)
end

function Panel:redrawButtons()
    for _, b in pairs(self.buttons) do self:_drawButton(b) end
end

function Panel:hitTest(x, y)
    for _, b in pairs(self.buttons) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            return b.id
        end
    end
    return nil
end

-- ============================================================
-- Flush: riversa il buffer sul monitor in un colpo
-- ============================================================
function Panel:flush()
    self.buf.setVisible(true)   -- forza redraw immediato sul monitor
    self.buf.setVisible(false)  -- torna invisibile per i prossimi cambi
end

-- ============================================================
-- Click handling (immutato)
-- ============================================================
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
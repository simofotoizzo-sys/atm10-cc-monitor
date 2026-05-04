-- /farm_server.lua  (SATELLITE)
-- Ascolta comandi rednet e controlla i 2 redstone_relay locali.

local PROTOCOL    = "farmctrl.v1"
local HOSTNAME    = "farm_satellite"
local OUTPUT_SIDE = "top"
local STATE_FILE  = "/farm_state"

print("=== FARM SERVER ===")
print("ID computer: " .. os.getComputerID())
print("Label: " .. (os.getComputerLabel() or "n/a"))

-- ============================================================
-- Trova i 2 redstone_relay
-- ============================================================
local relayNames = {}
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "redstone_relay" then
        table.insert(relayNames, name)
    end
end
table.sort(relayNames)

if #relayNames < 2 then
    print("ERRORE: trovati solo " .. #relayNames .. " relay (servono 2)")
    return
end

local FARM_TO_RELAY = {
    [1] = relayNames[1],   -- farm 1 = ancient knight + ghast
    [2] = relayNames[2],   -- farm 2 = mob mix
}
print("Farm 1 (Ancient/Ghast) -> " .. FARM_TO_RELAY[1])
print("Farm 2 (Mix)           -> " .. FARM_TO_RELAY[2])

-- ============================================================
-- Trova ender modem
-- ============================================================
local enderModem
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local m = peripheral.wrap(name)
        if m.isWireless() then enderModem = name; break end
    end
end
if not enderModem then
    print("ERRORE: nessun ender modem")
    return
end

rednet.open(enderModem)
rednet.host(PROTOCOL, HOSTNAME)
print("Rednet aperto su: " .. enderModem)
print("Hostname: " .. HOSTNAME)
print("Protocol: " .. PROTOCOL)

-- ============================================================
-- Stato + persistenza
-- ============================================================
local farms = { [1] = false, [2] = false }

local function saveState()
    local f = fs.open(STATE_FILE, "w")
    if f then f.write(textutils.serialise(farms)); f.close() end
end

local function loadState()
    if not fs.exists(STATE_FILE) then return end
    local f = fs.open(STATE_FILE, "r")
    if not f then return end
    local content = f.readAll(); f.close()
    local ok, data = pcall(textutils.unserialise, content)
    if ok and type(data) == "table" then
        farms[1] = data[1] == true
        farms[2] = data[2] == true
    end
end

local function applyRelay(farmId)
    local relay = peripheral.wrap(FARM_TO_RELAY[farmId])
    if relay then
        local ok, err = pcall(relay.setOutput, OUTPUT_SIDE, farms[farmId])
        if not ok then
            print("Errore relay " .. farmId .. ": " .. tostring(err))
            return false
        end
    end
    return true
end

local function applyAll()
    applyRelay(1)
    applyRelay(2)
end

loadState()
applyAll()
print("Stato iniziale: farm1=" .. tostring(farms[1]) .. " farm2=" .. tostring(farms[2]))
print("In ascolto...")
print("")

-- ============================================================
-- Loop messaggi
-- ============================================================
local function reply(senderId, payload)
    payload.ts = os.epoch("utc")
    rednet.send(senderId, payload, PROTOCOL)
end

while true do
    local senderId, msg = rednet.receive(PROTOCOL)
    if type(msg) ~= "table" or not msg.cmd then
        reply(senderId, { ok = false, err = "msg invalido" })
    elseif msg.cmd == "ping" then
        reply(senderId, { ok = true, pong = true, farms = farms })
    elseif msg.cmd == "state" then
        reply(senderId, { ok = true, farms = farms })
    elseif msg.cmd == "set" then
        local id = tonumber(msg.farm)
        if not id or not FARM_TO_RELAY[id] then
            reply(senderId, { ok = false, err = "farm id sconosciuto" })
        else
            farms[id] = (msg.on == true)
            local ok = applyRelay(id)
            saveState()
            if ok then
                print(("[%s] %s -> farm %d = %s"):format(
                    textutils.formatTime(os.time("local"), true),
                    senderId, id, tostring(farms[id])))
                reply(senderId, { ok = true, farms = farms })
            else
                reply(senderId, { ok = false, err = "errore relay" })
            end
        end
    else
        reply(senderId, { ok = false, err = "cmd sconosciuto: " .. tostring(msg.cmd) })
    end
end
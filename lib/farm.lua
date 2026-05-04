-- /lib/farm.lua  (CENTRALE)
-- Client per il farm_server sul satellite.
-- Astrae rednet e fornisce API per accendere/spegnere le 2 mob farm.

local farm = {}

local PROTOCOL = "farmctrl.v1"
local HOSTNAME = "farm_satellite"
local TIMEOUT  = 3   -- secondi di attesa risposta

local satelliteId = nil
local cachedFarms = { [1] = false, [2] = false }
local lastUpdate = 0

-- ============================================================
-- Apre il modem e cerca il satellite
-- ============================================================
function farm.init()
    -- Apri il primo modem wireless trovato
    local modemName
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            local m = peripheral.wrap(name)
            if m.isWireless() then modemName = name; break end
        end
    end
    if not modemName then
        return false, "ender modem non trovato sul centrale"
    end
    if not rednet.isOpen(modemName) then
        rednet.open(modemName)
    end

    return farm.findSatellite()
end

function farm.findSatellite()
    satelliteId = rednet.lookup(PROTOCOL, HOSTNAME)
    if not satelliteId then
        return false, "satellite non trovato (offline?)"
    end
    return true
end

function farm.getSatelliteId() return satelliteId end

-- ============================================================
-- Comunicazione (con timeout)
-- ============================================================
local function sendAndWait(msg)
    if not satelliteId then
        local ok, err = farm.findSatellite()
        if not ok then return nil, err end
    end
    rednet.send(satelliteId, msg, PROTOCOL)
    local id, reply = rednet.receive(PROTOCOL, TIMEOUT)
    if not id or id ~= satelliteId then
        return nil, "timeout o sender errato"
    end
    return reply
end

-- ============================================================
-- API pubblica
-- ============================================================
function farm.ping()
    local r, err = sendAndWait({ cmd = "ping" })
    if not r then return false, err end
    if r.ok and r.farms then
        cachedFarms[1] = r.farms[1] == true
        cachedFarms[2] = r.farms[2] == true
        lastUpdate = os.epoch("utc")
    end
    return r.ok == true
end

function farm.fetchState()
    local r, err = sendAndWait({ cmd = "state" })
    if not r then return nil, err end
    if r.ok and r.farms then
        cachedFarms[1] = r.farms[1] == true
        cachedFarms[2] = r.farms[2] == true
        lastUpdate = os.epoch("utc")
        return cachedFarms
    end
    return nil, r.err or "errore"
end

function farm.set(farmId, on)
    local r, err = sendAndWait({ cmd = "set", farm = farmId, on = on == true })
    if not r then return false, err end
    if r.ok and r.farms then
        cachedFarms[1] = r.farms[1] == true
        cachedFarms[2] = r.farms[2] == true
        lastUpdate = os.epoch("utc")
    end
    return r.ok == true, r.err
end

function farm.toggle(farmId)
    return farm.set(farmId, not cachedFarms[farmId])
end

function farm.getCachedState() return cachedFarms end
function farm.getLastUpdate()  return lastUpdate end

return farm
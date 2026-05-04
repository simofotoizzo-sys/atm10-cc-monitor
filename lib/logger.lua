-- /lib/logger.lua
-- Logger semplice con rotazione automatica.

local logger = {}

local LOG_FILE = "/log/central.log"
local MAX_SIZE = 100 * 1024  -- 100 KB

local function ensureDir()
    if not fs.exists("/log") then fs.makeDir("/log") end
end

local function rotate()
    if not fs.exists(LOG_FILE) then return end
    if fs.getSize(LOG_FILE) < MAX_SIZE then return end
    -- tronca: tieni solo la seconda meta'
    local f = fs.open(LOG_FILE, "r")
    if not f then return end
    local content = f.readAll()
    f.close()
    local half = math.floor(#content / 2)
    -- trova primo \n dopo half
    local cut = content:find("\n", half) or half
    local trimmed = content:sub(cut + 1)
    local f2 = fs.open(LOG_FILE, "w")
    if f2 then f2.write(trimmed); f2.close() end
end

function logger.log(level, msg)
    ensureDir()
    rotate()
    local f = fs.open(LOG_FILE, "a")
    if not f then return end
    local ts = os.date("%Y-%m-%d %H:%M:%S")
    f.writeLine(("[%s] [%s] %s"):format(ts, level, tostring(msg)))
    f.close()
end

function logger.info(msg)  logger.log("INFO",  msg) end
function logger.warn(msg)  logger.log("WARN",  msg) end
function logger.error(msg) logger.log("ERROR", msg) end

function logger.read(maxLines)
    if not fs.exists(LOG_FILE) then return {} end
    local f = fs.open(LOG_FILE, "r")
    if not f then return {} end
    local lines = {}
    local line = f.readLine()
    while line do table.insert(lines, line); line = f.readLine() end
    f.close()
    if maxLines and #lines > maxLines then
        local trimmed = {}
        for i = #lines - maxLines + 1, #lines do
            table.insert(trimmed, lines[i])
        end
        return trimmed
    end
    return lines
end

return logger
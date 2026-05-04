-- /programs/update.lua
-- Self-update: scarica tutti i file dal repo GitHub.
-- Legge la lista da cfg/updates.lua

package.path = package.path .. ";/?.lua;/?/init.lua"

local cfg_ok, updates = pcall(require, "cfg.updates")
if not cfg_ok then
    print("ERRORE: /cfg/updates.lua non trovato o invalido")
    print(tostring(updates))
    return
end

print("=== UPDATE ===")
print("Repo: " .. (updates.repo_base or "?"))
print("Branch: " .. (updates.branch or "main"))
print("Files: " .. #updates.files)
print("")

local base = updates.repo_base
local branch = updates.branch or "main"

if not base then
    print("ERRORE: cfg/updates.lua non ha 'repo_base'")
    return
end

local fail = 0
local ok = 0
for _, path in ipairs(updates.files) do
    local url = base .. "/" .. branch .. "/" .. path
    -- crea cartella se manca
    local dir = path:match("(.+)/[^/]+$")
    if dir and not fs.exists(dir) then fs.makeDir(dir) end
    -- delete vecchio
    if fs.exists(path) then fs.delete(path) end

    -- scarica con http.get (piu' affidabile di shell.run wget)
    write("[..] " .. path .. " ")
    local resp, httpErr = http.get(url)
    if not resp then
        print("FAIL (" .. tostring(httpErr) .. ")")
        fail = fail + 1
    else
        local content = resp.readAll()
        resp.close()
        if not content or #content == 0 then
            print("FAIL (vuoto)")
            fail = fail + 1
        else
            local f = fs.open(path, "w")
            if f then
                f.write(content)
                f.close()
                print("OK (" .. #content .. " bytes)")
                ok = ok + 1
            else
                print("FAIL (write)")
                fail = fail + 1
            end
        end
    end
end

print("")
print(("Completato: %d ok, %d fail"):format(ok, fail))
if fail == 0 then
    print("")
    print("Riavvia con: reboot")
end

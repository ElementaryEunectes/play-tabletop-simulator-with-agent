-- Read-only health read of the table's turn tracker, for the agent to run any time.
-- Prints only; changes nothing. Run through tts\tools\exec_script.ps1.
--
--   powershell -NoProfile -ExecutionPolicy Bypass -File tts\tools\exec_script.ps1 -Guid <guid> -LuaFile tts\tools\tracker_read.lua
-- The guid comes from exec_script.ps1's -Guid (it substitutes the __GUID__ placeholder); nothing
-- per-match may be baked into this tracked file.
local guid = "__GUID__"
local o = nil
pcall(function() o = getObjectFromGUID(guid) end)
if o == nil then print("tracker: NOT ON TABLE (" .. guid .. ")") return end
pcall(function() print("NAME='" .. tostring(o.getName()) .. "'") end)
pcall(function() local p = o.getPosition() print("POS z=" .. tostring(p.z) .. " x=" .. tostring(p.x)) end)
pcall(function() print("LOCKED=" .. tostring(o.getLock())) end)
pcall(function() print("SAVED_STATE='" .. tostring(o.script_state) .. "'") end)
pcall(function() print("LIVE_COLOR='" .. tostring(currentColor) .. "'") end)
pcall(function() print("LIVE_NAME='" .. tostring(self.getName()) .. "'") end)

-- dsh_panel.lua -- an in-game input panel for the DSH dialogue channel.
--
-- WHY: the TTS notebook is globally read-only in this save (every tab shows a
-- padlock, "Add New" is greyed out) and Lua has no permission API to unlock it.
-- Notes/Notebook CAN be written by script, so:
--   * the user types into THIS panel -- a script-owned XML UI, which is NOT subject
--     to the notebook permission check
--   * submitted lines are mirrored into notebook tab DSH_TAB and into the on-screen
--     Notes, where they persist and DSH can read them
--   * DSH reads the captured text back with the `panelGet` command in dsh_global.lua
--
-- API facts this relies on (verified against api.tabletopsimulator.com/ui/*):
--   * an InputField's text can ONLY be read from the value arg passed to
--     onValueChanged / onEndEdit -- UI.getAttribute(id,"text") does not return what
--     the user typed
--   * Button has no `alignment` attribute; it is `textAlignment`
--   * <Button onClick="fn(stringName)"> passes stringName as the value argument
--   * text is set as element content: <Text id="x">hello</Text>
--
-- ASCII only: this file is JSON-escaped before being sent to TTS.

DSH_LOG = DSH_LOG or {}
DSH_INPUT = DSH_INPUT or ""
DSH_TAB = DSH_TAB or 12

local TITLE = "DSH  <->  P1"
local HINT = "type below, then click SEND  (or just click outside the box)"

-- ---------------------------------------------------------------- helpers -----
local function esc(s)
    s = tostring(s or "")
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

local function history(n)
    n = n or 5
    if #DSH_LOG == 0 then return "(no messages yet)" end
    local out = {}
    local first = math.max(1, #DSH_LOG - n + 1)
    for i = first, #DSH_LOG do out[#out + 1] = esc(DSH_LOG[i]) end
    return table.concat(out, "\n")
end

local function notebookText()
    local head = "[DSH] Nomad City -- dialogue channel (notebook is read-only in-game;\n"
                .. "DSH appends here via Lua. Reply using the on-screen DSH panel.)\n"
                .. "----------------------------------------------------------\n"
    return head .. table.concat(DSH_LOG, "\n")
end

local function mirror()
    pcall(function()
        Notes.editNotebookTab({ index = DSH_TAB, body = notebookText() })
    end)
    pcall(function()
        Notes.setNotes(table.concat(DSH_LOG, "\n"))
    end)
end

-- ------------------------------------------------------------------ API ------
function DSH_buildUI()
    local xml =
        '<Panel id="dshRoot" width="400" height="300" color="#0F0F0FEE" position="0 0 -10">' ..
        '<Text id="dshTitle" color="#66CCFF" fontSize="18" alignment="MiddleCenter">' .. esc(TITLE) .. '</Text>' ..
        '<Text id="dshHint" color="#BBBBBB" fontSize="12" alignment="MiddleCenter">' .. esc(HINT) .. '</Text>' ..
        '<InputField id="dshInput" width="370" height="60" color="#FFFFFF" textColor="#101010" ' ..
        'fontSize="15" lineType="MultiLineNewLine" onValueChanged="DSH_onInput" onEndEdit="DSH_onInput" />' ..
        '<Button id="dshSend" text="SEND" width="120" height="32" colors="#2E7D32|#1B5E20|#A5D6A7|#333333" ' ..
        'textColor="#FFFFFF" fontSize="15" onClick="DSH_onClick(send)" />' ..
        '<Button id="dshSync" text="sync notebook" width="160" height="32" colors="#37474F|#263238|#90A4AE|#333333" ' ..
        'textColor="#FFFFFF" fontSize="13" onClick="DSH_onClick(sync)" />' ..
        '<Text id="dshHist" color="#EEEEEE" fontSize="12" alignment="LowerLeft">' .. history(5) .. '</Text>' ..
        '</Panel>'
    setUI(xml)
    return true
end

function DSH_push(who, text)
    text = tostring(text or "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return false end
    DSH_LOG[#DSH_LOG + 1] = "[" .. who .. "] " .. text
    mirror()
    return true
end

function DSH_onInput(player, value, id)
    DSH_INPUT = tostring(value or "")
end

function DSH_onClick(player, value, id)
    if value == "send" then
        if DSH_push("P1", DSH_INPUT) then
            DSH_INPUT = ""
            DSH_buildUI()
        else
            DSH_buildUI()
        end
    elseif value == "sync" then
        mirror()
        DSH_buildUI()
    end
end

function onLoad(player_color)
    DSH_buildUI()
end

-- read back by dsh_global.lua's panelGet command
function DSH_panelGet()
    return {
        n = #DSH_LOG,
        pending = DSH_INPUT,
        last = (DSH_LOG[#DSH_LOG] or ""),
        log = table.concat(DSH_LOG, "\n"),
        tab = DSH_TAB,
    }
end

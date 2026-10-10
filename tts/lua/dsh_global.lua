-- DSH command layer (persistent, lives in the Global script slot)
-- Receives commands via onExternalMessage (messageID 2) and replies with
-- sendExternalMessage, so we do not have to re-inject Lua every turn.
-- ASCII only: this text gets JSON-escaped and piped through PowerShell.
--
-- Verified against https://api.tabletopsimulator.com/object/ and /base/
--   Object: getGUID, getName, getGMNotes, setGMNotes, getDescription,
--           setDescription, getPosition, setPosition, getValue, setValue, getData
--   Base:   getObjects, getObjectFromGUID, getAllObjects (deprecated)
-- There is NO getNickname/setNickname on Object, and no WriteDirectory global.
--
-- Commands:
--   {cmd="ping"}
--   {cmd="selftest"}                       -- which globals/fields actually exist
--   {cmd="count"}                          -- object count + name histogram (top N)
--   {cmd="find", filter="<name substring>", limit=20}
--   {cmd="read", guid="0a7a77"}
--   {cmd="write", guid="0a7a77", value="0"}
--   {cmd="move", guid="...", x=0, y=1, z=0}
--   {cmd="setval", guid="...", value=3}
--   {cmd="getval", guid="..."}
--   {cmd="index", limit=50}                -- guid + name + position for many objects

-- Directory the optional panel override (DSH_DIR/dsh_panel.lua) can be loaded from, if
-- loadfile is available. Deliberately NOT set here: a machine-specific absolute path must not
-- be baked into the repo (this repo is meant to be clonable). Set it before this file loads
-- to use the override; without it the code below falls back to ".".
DSH_DIR = DSH_DIR or nil

-- ============================ TURN RECORD (no object involved) ============================
-- The turn count lives HERE, in the Global script, not on a piece on the table.
--
-- WHY (2026-10-10, after a long detour that this comment exists to prevent repeating):
--   * the count has to survive between commands -> a Lua global does exactly that, since every
--     message runs in the same Global environment (the F8 investigation had already proved this with
--     its __spawn_trace markers);
--   * every attempt to carry it on an OBJECT failed for a different reason: spawnObject on a custom
--     type always opened TTS's "自定义板块" dialog and blocked the thread; objects baked into the save
--     were dropped by TTS at load (four guids, all gone); clone() works but inherits the source's
--     script_state; and the piece still disappears on every reload because it is created at runtime.
--   * "record a turn" is a capability true of ANY mod, so it belongs in the generic layer - the
--     clickable token is per-session decoration and must not be load-bearing.
-- Durability: DSH_STATE is a JSON string carried in this same Global script, so it rides along with
-- whatever save the player loads. onLoad restores it. One turn recorder, one place to read it.
DSH_TURN_N = DSH_TURN_N or 0
DSH_STATE  = DSH_STATE  or ""

-- Advance (or set) the turn and re-serialise the state string. Everything that records a turn goes
-- through here so there is a single writer.
local function turnCommit(n)
    local want = tonumber(n)
    if want == nil then want = (tonumber(DSH_TURN_N) or 0) + 1 end
    DSH_TURN_N = want
    local ok, enc = pcall(function()
        return JSON.encode({ turn = want, at = os.date("%H:%M:%S"), day = os.date("%Y-%m-%d") })
    end)
    if ok and type(enc) == "string" then DSH_STATE = enc end
    if type(broadcastToAll) == "function" then
        pcall(broadcastToAll, "[DSH] turn " .. tostring(DSH_TURN_N) .. " recorded")
    end
    return DSH_TURN_N
end

function onLoad()
    -- broadcastToAll does not exist in this sandbox (see diag), so guard it instead
    -- of raising an error on every load. It is kept for builds that do have it.
    if type(broadcastToAll) == "function" then
        pcall(broadcastToAll, "[DSH] command layer loaded")
    end
    DSH_LOADS = (DSH_LOADS or 0) + 1
    -- Restore the turn count from the state string this script carries (see the block above).
    if type(DSH_STATE) == "string" and DSH_STATE ~= "" then
        local ok, t = pcall(function() return JSON.decode(DSH_STATE) end)
        if ok and type(t) == "table" and tonumber(t.turn) then DSH_TURN_N = tonumber(t.turn) end
    end
    -- The XML panel is NOT drawn on load: setUI is absent in this sandbox, and the
    -- notebook (tab 12) is the dialogue channel now.
end

local function S(v)
    -- ALWAYS a string, nil included. Returning nil here made every `"..." .. S(x)` throw on exactly
    -- the values those branches exist to report: the first live `spawn` died with "attempt to
    -- concatenate a nil value" instead of saying what went wrong, because the failure path itself
    -- concatenated S(nil). An error path that dies is worse than no error path.
    if v == nil then return "nil" end
    return tostring(v)
end

-- Readable serialisation of an arbitrary Lua value.
--
-- WHY: act() originally did `JSON.encode(res)` for tables and `tostring(res)`
-- otherwise. tostring() on a table yields "table: 0x...", and when JSON.encode
-- failed the error path also collapsed to a useless string - so getRotation
-- appeared to return something boolean-ish and getValue returned nothing at all,
-- making every successful call look broken. This walks the value instead.
local function VS(v, depth)
    depth = depth or 0
    if depth > 4 then return "..." end
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" then if v then return "true" else return "false" end end
    if t == "number" then
        if v == math.floor(v) then return string.format("%d", v) end
        return string.format("%.4f", v)
    end
    if t == "string" then return v end
    if t == "table" then
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 24 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = tostring(k) .. "=" .. VS(val, depth + 1)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return t
end

local function objs()
    local all = getObjects()
    local out = {}
    if not all then return out end
    for i = 1, #all do
        if all[i] ~= nil then out[#out + 1] = all[i] end
    end
    return out
end

local function ping()
    return { ok = true, pong = true, v = DSH_VERSION, objects = #objs(), loads = DSH_LOADS or 0, at = os.date("%H:%M:%S") }
end

local function selftest()
    local g = {}
    for _, n in ipairs({ "getObjects", "getAllObjects", "getObjectFromGUID", "getSeatedPlayers",
                         "broadcastToAll", "sendExternalMessage", "JSON", "os", "io",
                         "WriteDirectory", "writeFile", "spawnObject", "getObjectsWithTag" }) do
        g[n] = (type(_G[n]) ~= "nil")
    end
    -- probe one real object's methods
    local m = {}
    local all = getObjects()
    if all and #all > 0 then
        local o = all[1]
        for _, n in ipairs({ "getName", "getGUID", "getGMNotes", "setGMNotes", "getDescription",
                             "setDescription", "getPosition", "setPosition", "getValue", "setValue",
                             "getData", "getLock", "getQuantity", "getStateId", "getNickname" }) do
            local ok = pcall(function() return o[n] end)
            m[n] = ok
        end
    end
    return { ok = true, globals = g, objectMethods = m, objectCount = all and #all or 0 }
end

local function count(topN)
    local all = objs()
    local hist = {}
    local names = {}
    for i = 1, #all do
        local n = "?"
        local ok, v = pcall(function() return all[i].getName() end)
        if ok and v then n = v end
        if hist[n] == nil then hist[n] = 0; names[#names + 1] = n end
        hist[n] = hist[n] + 1
    end
    table.sort(names, function(a, b) return hist[a] > hist[b] end)
    topN = tonumber(topN) or 30
    local out = {}
    for i = 1, math.min(topN, #names) do
        out[#out + 1] = { name = names[i], qty = hist[names[i]] }
    end
    return { ok = true, total = #all, distinct = #names, top = out, at = os.date("%H:%M:%S") }
end

local function find(filter, limit)
    local all = objs()
    limit = tonumber(limit) or 20
    local needle = filter
    if needle == "" then needle = nil end
    local out = {}
    for i = 1, #all do
        local o = all[i]
        local nm = "?"
        local ok, v = pcall(function() return o.getName() end)
        if ok and v then nm = v end
        local hit = true
        if needle then hit = (string.find(nm, needle, 1, true) ~= nil) end
        if hit then
            local pos = { 0, 0, 0 }
            pcall(function() local p = o.getPosition(); pos = { p.x, p.y, p.z } end)
            out[#out + 1] = {
                guid = o.getGUID(), name = nm,
                x = math.floor(pos[1] * 100) / 100,
                y = math.floor(pos[2] * 100) / 100,
                z = math.floor(pos[3] * 100) / 100
            }
            if #out >= limit then break end
        end
    end
    return { ok = true, count = #out, items = out }
end

local function read(guid)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    -- Optional: act on a PLAYER instead of an object. Some verbs live on the Player instance
    -- (getHandCount / getHandTransform / getHoldingObjects / turn / blindfolded) and a seat has no
    -- guid, so `player = "Teal"` resolves the target instead of an object.
    if tostring(m.player or "") ~= "" then
        o = Player[tostring(m.player)]
        if o == nil then return { ok = false, cmd = "act", err = "no player colour " .. S(m.player) } end
    end
    local r = { ok = true, guid = guid }
    pcall(function() r.name = o.getName() end)
    pcall(function() r.gm = o.getGMNotes() end)
    pcall(function() r.desc = o.getDescription() end)
    pcall(function() r.value = o.getValue() end)
    pcall(function() local p = o.getPosition(); r.x = p.x; r.y = p.y; r.z = p.z end)
    return r
end

local function write(guid, value)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    local ok, err = pcall(function() o.setGMNotes(tostring(value)) end)
    if not ok then return { ok = false, err = "setGMNotes failed: " .. S(err) } end
    return { ok = true, guid = guid, set = tostring(value) }
end

-- Rotation / flip, deliberately written to mirror the WORKING moveTo() above.
--
-- WHY IT LOOKS LIKE THIS: the generic act() command uses
--   fn(o, { tonumber(m.x) or 0, ... })
-- and every setPosition/setRotation through it failed with
--   "cannot convert a userdata to a clr type UnityEngine.Vector3"
-- while the older moveTo() uses
--   o.setPosition({ tonumber(x), tonumber(y), tonumber(z) })
-- with plain positional arguments and succeeds. The proven shape wins: dedicated
-- commands that call the method straight off the object with a plain table.
--
-- `flip` adds 180 to the current Z angle, which is what turns a card over.
local function rotateTo(guid, x, y, z, add)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    local cur = o.getRotation()
    local nx, ny, nz = tonumber(x), tonumber(y), tonumber(z)
    if add then
        nx = cur.x + (nx or 0)
        ny = cur.y + (ny or 0)
        nz = cur.z + (nz or 0)
    end
    if nx == nil then nx = cur.x end
    if ny == nil then ny = cur.y end
    if nz == nil then nz = cur.z end
    local ok, err = pcall(function() o.setRotation({ nx, ny, nz }) end)
    if not ok then return { ok = false, err = "setRotation failed: " .. S(err) } end
    local r = o.getRotation()
    return { ok = true, guid = guid,
             x = math.floor(r.x * 100) / 100,
             y = math.floor(r.y * 100) / 100,
             z = math.floor(r.z * 100) / 100 }
end

local function moveTo(guid, x, y, z)    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    local ok, err = pcall(function() o.setPosition({ tonumber(x), tonumber(y), tonumber(z) }) end)
    if not ok then return { ok = false, err = "setPosition failed: " .. S(err) } end
    local p = o.getPosition()
    return { ok = true, guid = guid, x = p.x, y = p.y, z = p.z }
end

-- Reflection probe. This sandbox has no load()/eval() (both nil), so there is no
-- way to explore the Object API from outside. Walking the userdata metatable with
-- __index + pairs() is the remaining route: it enumerates every method name, and
-- calling the no-argument getters tells us what metadata the game exposes.
-- That matters because card NAMES are generic ("Card") - the art is the only way
-- to tell one enterprise board from another, so we need the image URL.
local function probe(guid)
    if guid == nil or guid == "" then return { ok = false, err = "no guid" } end
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end

    local r = { ok = true, guid = guid }
    local mt = getmetatable(o)
    r.metatable = type(mt)
    local idx = nil
    if type(mt) == "table" then
        for k, v in pairs(mt) do
            if k == "__index" then idx = v end
        end
    end
    r.indexType = type(idx)

    local names = {}
    local n = 0
    if type(idx) == "table" then
        for k, v in pairs(idx) do
            n = n + 1
            if n <= 400 then names[#names + 1] = tostring(k) end
        end
    end
    r.methodCount = n
    table.sort(names)
    r.methods = table.concat(names, ",")

    -- Call the metadata getters. Only these are attempted: they are read-only and
    -- are known to exist on every object. Failures are recorded, not raised.
    local getters = { "getName", "getDescription", "getGMNotes", "getGUID",
                      "getPosition", "getRotation", "getScale", "getValue",
                      "getStateId", "getStates", "getTags", "getLock",
                      "getImageURL", "getImage", "getCustomObject",
                      "getCustomMesh", "getCustomImage", "getMemo",
                      "getAltImage", "getFogColor", "getColorTint",
                      "getQuantity", "getRepositioning", "getTable" }
    r.getters = {}
    if type(idx) == "table" then
        for _, g in ipairs(getters) do
            local fn = idx[g]
            if type(fn) == "function" then
                local ok, v = pcall(function() return fn(o) end)
                if ok then
                    if type(v) == "table" then
                        local enc = JSON.encode(v)
                        r.getters[g] = enc
                    else
                        r.getters[g] = tostring(v)
                    end
                else
                    r.getters[g] = "ERR " .. S(v)
                end
            end
        end
    end
    -- A few properties are plain values, not functions.
    r.props = {}
    for _, k in ipairs({ "name", "guid", "position", "rotation", "scale",
                         "value", "description", "gm_notes", "nickname",
                         "image", "imageURL", "memo", "tags" }) do
        local ok, v = pcall(function() return o[k] end)
        if ok and v ~= nil then
            if type(v) == "table" then
                local enc = JSON.encode(v)
                r.props[k] = enc
            else
                r.props[k] = tostring(v)
            end
        end
    end
    return r
end

-- Compact batch lookup. `index` returns every object with position, which is big
-- enough that the reply can be dropped entirely (observed: "no reply from TTS").
-- This asks about specific GUIDs and returns only the fields that identify a card,
-- so it stays small enough to actually arrive.
--   {cmd="whose", guids="abc123,def456"}
local function whose(guids)
    if guids == nil or guids == "" then return { ok = false, err = "no guids" } end
    local out = {}
    local n = 0
    for g in string.gmatch(tostring(guids), "[^,%s]+") do
        n = n + 1
        if n > 60 then break end
        local o = getObjectFromGUID(g)
        local e = { guid = g }
        if not o then
            e.err = "not found"
        else
            pcall(function() e.name = o.getName() end)
            pcall(function() e.nick = o.getNickname() end)
            pcall(function() e.desc = o.getDescription() end)
            pcall(function() local p = o.getPosition(); e.x = p.x; e.y = p.y; e.z = p.z end)
            -- The whole point: the image URL is the only thing that names a card
            -- whose getName() is just "Card".
            local mt = getmetatable(o)
            local idx = nil
            if type(mt) == "table" then idx = mt.__index end
            if type(idx) == "table" then
                for _, gname in ipairs({ "getImageURL", "getImage", "getCustomObject",
                                         "getCustomImage", "getMemo", "getStates" }) do
                    local fn = idx[gname]
                    if type(fn) == "function" then
                        local ok, v = pcall(function() return fn(o) end)
                        if ok and v ~= nil then
                            if type(v) == "table" then e[gname] = JSON.encode(v)
                            else e[gname] = tostring(v) end
                        end
                    end
                end
            end
        end
        out[#out + 1] = e
    end
    return { ok = true, asked = n, items = out }
end

-- Generic object action, restricted to a whitelist.
--
-- WHY: reading was never the bottleneck - acting was. Previously the only verbs
-- were `move` (position) and `setval` (value), so flipping a card, rotating a
-- piece, locking a token or shuffling/drawing from a deck were all impossible.
-- TTS exposes those as methods on the object, and this sandbox has no load()/eval()
-- to build calls dynamically, so each verb is dispatched through an explicit table.
--
--   {cmd="act", guid="abc123", verb="flip"}
--   {cmd="act", guid="abc123", verb="setRotation", x=0, y=0, z=180}
--   {cmd="act", guid="abc123", verb="setLock", value=true}
--   {cmd="act", guid="abc123", verb="deal", value=1, player="Blue"}
--   {cmd="act", guid="abc123", verb="getRotation"}
--
-- Only methods in `verbs` may be reached, so a typo cannot call something
-- arbitrary on the object.
local function act(m)
    local guid = m.guid
    if guid == nil or guid == "" then return { ok = false, err = "no guid" } end
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end

    local verb = tostring(m.verb or "")

    -- Safety boundary: only these methods may ever be reached, so a typo or a
    -- prompt-injected instruction cannot call something arbitrary on the object.
    local verbs = {
        -- rotation / orientation: the actual "flip a card" primitive
        setRotation = true, getRotation = true,
        setPosition = true, getPosition = true,
        setScale = true,     getScale = true,
        -- board geometry: the only way to learn the map board's real world size,
        -- which is what turns a pixel on its artwork into a table coordinate.
        getBounds = true,    getBoundsNormalized = true,
        getVisualBoundsNormalized = true,
        -- artwork -> table mapping (see positionToLocal branch below)
        positionToLocal = true, positionToWorld = true,
        -- state / identity
        setLock = true,      getLock = true,
        setValue = true,     getValue = true,
        setState = true,     getStateId = true,
        setName = true,      getName = true,
        setDescription = true, getDescription = true,
        setGMNotes = true,   getGMNotes = true,
        setScriptState = true, getScriptState = true,
        setNickname = true,  getNickname = true,
        setColorTint = true, getColorTint = true,
        -- deck operations: the actual "draw / shuffle" primitives
        shuffle = true, deal = true, dealToAll = true,
        -- clone: the only way to put a copy of a resource-point indicator on a new
        -- point. The indicators live in supply stacks, so moving one takes it out of
        -- the stack; cloning leaves the supply intact.
        clone = true,        getQuantity = true, getStates = true, getTags = true,
        flip = true, setInvisibleTo = true,
        -- 2026-10-07: 骰子。装到"带骰盘的对局型模组"上必须能掷骰。
        -- roll() 无参数、无返回值，走的就是 flip 那条路径。
        roll = true,
        -- 2026-10-09 (F6): snap points, tags and the container walk. Hashes for tags, not row names:
        -- TTS matches tags by hash, so getTags returns hashes and setTags must be GIVEN hashes
        -- (read them off an object that already carries the tag, or create one in-game).
        getSnapPoints = true,   setSnapPoints = true,
        addTag = true,          removeTag = true,      setTags = true,
        hasTag = true,          hasAnyTag = true,      hasMatchingTag = true,
        -- containers and hands: the object-side way to move a card INTO a hand (the Player object
        -- has no takeObject - it only lists hands: getHandObjects/getHandTransform/getHoldingObjects)
        getObjects = true,      putObject = true,      moveToHandStash = true,
        dealToColorWithOffset = true,
        -- the Player actions TTS documents (player manager side)
        getHandCount = true,    getHandTransform = true,   getHoldingObjects = true,
        cut = true,             paste = true,          drop = true,
        -- member variables reached through the isMember branch
        use_snap_points = true, locked = true, memo = true, tooltip = true,
    }
    if not verbs[verb] then
        return { ok = false, err = "verb not allowed: " .. verb, cmd = "act" }
    end

    -- Some verbs are MEMBER VARIABLES, not methods. They must be recognised
    -- BEFORE the method lookup below, because that lookup fails on them (there is
    -- no o.getScriptState function, so fn stays nil) and the generic
    -- "object has no method" early-return then fires - which is exactly why
    -- getScriptState reported "object has no method getScriptState" even though
    -- the branch handling it exists further down. Only script_state is reachable
    -- this way; a container object has no such member and reports nil.
    local memberVerbs = { getScriptState = true, setScriptState = true }
    -- These are MEMBER VARIABLES, not methods: the method lookup below cannot find them, so they
    -- must be recognised up front (same reason script_state is listed here).
    memberVerbs.use_snap_points = true
    memberVerbs.memo = true
    memberVerbs.tooltip = true
    memberVerbs.locked = true
    local isMember = memberVerbs[verb] == true

    -- Metatable introspection does NOT work on these objects: walking mt.__index
    -- reported "no method getRotation" for a Custom_Tile, which certainly has it.
    -- TTS's object proxy resolves methods through the userdata itself, so the
    -- method is simply indexed straight off the object. Verify that, and keep the
    -- metatable path only as a fallback.
    local fn = nil
    if not isMember then
        local okIdx, direct = pcall(function() return o[verb] end)
        if okIdx and type(direct) == "function" then
            fn = direct
        else
            local mt = getmetatable(o)
            if type(mt) == "table" and type(mt.__index) == "table" then
                local cand = mt.__index[verb]
                if type(cand) == "function" then fn = cand end
            end
        end
        if type(fn) ~= "function" then
            return { ok = false, err = "object has no method " .. verb, cmd = "act" }
        end
    end

    -- Argument shapes differ per verb, so build them per family rather than
    -- guessing a single generic form.
    local call
    if verb == "setPosition" then
        call = function() return fn(o, { tonumber(m.x) or 0, tonumber(m.y) or 0, tonumber(m.z) or 0 }) end
    elseif verb == "setRotation" then
        call = function() return fn(o, { tonumber(m.x) or 0, tonumber(m.y) or 0, tonumber(m.z) or 0 }) end
    elseif verb == "setScale" then
        local sx = tonumber(m.x); if sx == nil then sx = 1 end
        local sy = tonumber(m.y); if sy == nil then sy = sx end
        local sz = tonumber(m.z); if sz == nil then sz = sx end
        call = function() return fn(o, { sx, sy, sz }) end
    elseif verb == "setLock" then
        call = function() return fn(o, m.value == true or m.value == "true") end
    elseif verb == "setState" then
        call = function() return fn(o, tonumber(m.value) or 1) end
    elseif verb == "setValue" then
        call = function() return fn(o, tonumber(m.value) or 0) end
    elseif verb == "setScriptState" then
        -- object.script_state is a MEMBER VARIABLE, not a method, so this bypasses fn().
        -- Validate the JSON first: a malformed script_state makes the object's own
        -- onLoad fail on the next load, which is how a counter silently dies.
        call = function()
            local v = tostring(m.value or "")
            if v ~= "" then
                local okj, dec = pcall(function() return JSON.decode(v) end)
                if not okj or dec == nil then
                    error("script_state is not valid JSON: " .. v)
                end
            end
            o.script_state = v
            return o.script_state
        end
    elseif verb == "getScriptState" then
        call = function() return o.script_state end
    elseif verb == "positionToLocal" then
        -- The one reliable way to learn how the board's artwork maps onto the
        -- table: feed it a world point and read back the board-local coordinate,
        -- whose range is the board's actual local size. Guessing that size from
        -- the image resolution produced a mapping that put known cities off the
        -- board, so measure it instead.
        call = function() return fn(o, { tonumber(m.x) or 0, tonumber(m.y) or 0, tonumber(m.z) or 0 }) end
    elseif verb == "positionToWorld" then
        call = function() return fn(o, { tonumber(m.x) or 0, tonumber(m.y) or 0, tonumber(m.z) or 0 }) end
    elseif verb == "setName" or verb == "setDescription" or verb == "setGMNotes" or verb == "setNickname" then
        call = function() return fn(o, tostring(m.value or "")) end
    elseif verb == "setColorTint" then
        call = function() return fn(o, { r = tonumber(m.r) or 1, g = tonumber(m.g) or 1, b = tonumber(m.b) or 1 }) end
    elseif verb == "deal" then
    elseif verb == "setTags" or verb == "addTag" or verb == "removeTag" or verb == "hasTag"
        or verb == "hasAnyTag" or verb == "hasMatchingTag" then
        -- list of strings; "a+b+c" is accepted as shorthand because the ds.ps1 command line is
        -- colon-delimited and JSON quotes/colons do not survive it
        local list = {}
        if type(m.list) == "table" then
            for _, v in ipairs(m.list) do list[#list + 1] = tostring(v) end
        else
            local raw = tostring(m.value or "")
            if raw ~= "" then for part in string.gmatch(raw, "[^+]+") do list[#list + 1] = part end end
        end
        if #list == 0 then error(verb .. " needs value=tag1+tag2 or list={...}") end
        call = function() return fn(o, list) end
    elseif verb == "setSnapPoints" then
        -- list of points; each may be {x,y,z} or a scalar y (TTS accepts both shapes)
        local pts = {}
        if type(m.list) == "table" then
            for _, v in ipairs(m.list) do
                if type(v) == "table" then pts[#pts + 1] = { tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0 }
                else pts[#pts + 1] = tonumber(v) or 0 end
            end
        else
            local raw = tostring(m.value or "")
            for part in string.gmatch(raw, "[^;]+") do
                local x, y, z = string.match(part, "^%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*,%s*(-?[%d%.]+)%s*$")
                if x then pts[#pts + 1] = { tonumber(x), tonumber(y), tonumber(z) }
                else pts[#pts + 1] = tonumber(part) or 0 end
            end
        end
        if #pts == 0 then error("setSnapPoints needs value=x,y,z;x,y,z or list={...}") end
        call = function() return fn(o, pts) end
    elseif verb == "getObjects" then
        call = function() return fn(o) end
    elseif verb == "use_snap_points" or verb == "locked" or verb == "memo" or verb == "tooltip" then
        -- MEMBER VARIABLES (o.use_snap_points = true), never methods: they are recognised in the
        -- isMember branch above, which reports the assigned value straight back.
        call = function()
            o[verb] = m.value
            return o[verb]
        end
    elseif verb == "getHandCount" or verb == "getHandTransform" or verb == "getHoldingObjects" then
        -- Player-side verbs: `o` is a Player here (see the m.player resolution in act), and these
        -- take an optional hand index. getHoldingObjects ignores it.
        call = function() return fn(o, tonumber(m.value) or 1) end
        call = function() return fn(o, tonumber(m.value) or 1, tostring(m.player or "")) end
    elseif verb == "setInvisibleTo" then
        call = function() return fn(o, tostring(m.player or "")) end
    else
        call = function() return fn(o) end
    end

    local ok, res = pcall(call)
    if not ok then return { ok = false, err = verb .. " failed: " .. S(res), cmd = "act" } end
    local out = { ok = true, guid = guid, verb = verb, cmd = "act" }
    -- Always report something, so "the call succeeded but returned nothing" is
    -- distinguishable from "the call silently failed".
    out.result = VS(res)
    return out
end

-- Full object dump: every top-level object with the fields needed to know what it
-- is (guid, type, nickname, position, rotation, lock, value, quantity, and up to
-- `states` child entries). `index` used to be enough for names but returned
-- positions only, which cannot identify a card - so this adds rotation and value,
-- i.e. exactly the state a card game is played through.
local function all(limit, wantStates)
    local objs = objs()
    limit = tonumber(limit) or 600
    local out = {}
    for i = 1, math.min(limit, #objs) do
        local o = objs[i]
        local e = {}
        -- Deliberately terse. The reply travels through the daemon's HTTP bridge,
        -- which times out at 8s, and an earlier verbose version (desc + rotation
        -- quaternion + per-state list, times 449 objects) was dropped entirely -
        -- the caller just saw "no reply from TTS". Keep every field short and
        -- bounded so the payload always arrives.
        pcall(function() e.g = o.getGUID() end)
        pcall(function() e.n = o.getName() end)
        pcall(function() e.k = o.getNickname() end)
        pcall(function()
            local p = o.getPosition()
            e.x = math.floor(p.x * 100) / 100
            e.y = math.floor(p.y * 100) / 100
            e.z = math.floor(p.z * 100) / 100
        end)
        pcall(function() local q = o.getRotation(); e.r = string.format("%.2f,%.2f,%.2f", q.x, q.y, q.z) end)
        pcall(function() local l = o.getLock(); if l then e.L = 1 end end)
        pcall(function() local v = o.getValue(); if v and v ~= 0 then e.v = v end end)
        pcall(function() local q = o.getQuantity(); if q and q ~= 1 then e.q = q end end)
        if wantStates then
            pcall(function()
                local st = o.getStates()
                local n = 0
                if type(st) == "table" then for _ in pairs(st) do n = n + 1 end end
                if n > 0 then e.s = n end
            end)
        end
        out[#out + 1] = e
    end
    return { ok = true, total = #objs, returned = #out, items = out }
end

-- Hand operations. Holding a card in a player's hand is how TTS models "in hand",
-- and it is a different mechanism from position, so it needs its own verbs.
local function hand(m)
    local player = tostring(m.player or "")
    if player == "" then return { ok = false, err = "no player colour" } end
    local pl = Player[player]
    if pl == nil then return { ok = false, err = "no player colour " .. player } end
    local action = tostring(m.action or "get")
    if action == "get" then
        local out = {}
        local ok, h = pcall(function() return pl.getHandObjects() end)
        if not ok then return { ok = false, err = "getHandObjects failed: " .. S(h) } end
        for i, o in ipairs(h or {}) do
            local e = {}
            pcall(function() e.guid = o.getGUID() end)
            pcall(function() e.name = o.getName() end)
            pcall(function() e.nick = o.getNickname() end)
            out[#out + 1] = e
        end
        return { ok = true, player = player, count = #out, items = out }
    elseif action == "take" then
        local o = getObjectFromGUID(tostring(m.guid or ""))
        if not o then return { ok = false, err = "no object" } end
        local ok = pcall(function() pl.takeObject({ guid = o.getGUID(), smooth = false }) end)
        return { ok = ok, player = player, guid = m.guid }
    elseif action == "holding" then
        -- what this player is holding RIGHT NOW (distinct from their hand zone)
        local h = {}
        local okh = pcall(function() h = pl.getHoldingObjects() or {} end)
        if not okh then return { ok = false, err = "getHoldingObjects failed" } end
        local ho = {}
        for i, o in ipairs(h) do
            local e = {}
            pcall(function() e.guid = o.getGUID() end)
            pcall(function() e.name = o.getName() end)
            ho[#ho + 1] = e
        end
        return { ok = true, player = player, count = #ho, items = ho, cmd = "hand" }
    elseif action == "give" then
        -- hand a specific object to a colour: the object-side way, because the Player object has
        -- no takeObject. smooth=false on purpose - a smooth move would need Wait before the caller
        -- could read the hand back.
        local o = getObjectFromGUID(tostring(m.guid or ""))
        if not o then return { ok = false, err = "no object with guid " .. S(m.guid) } end
        local okg, eg = pcall(function() pl.takeObject({ guid = o.getGUID(), smooth = false }) end)
        if not okg then return { ok = false, err = "hand give failed: " .. S(eg) } end
        local afterg = {}
        pcall(function() afterg = pl.getHandObjects() or {} end)
        return { ok = true, player = player, guid = m.guid, hand = #afterg, cmd = "hand" }
    elseif action == "draw" then
        -- move cards from a container INTO a hand:
        --   Deck.deal(n, colour)                            -> the normal "draw n cards"
        --   object.dealToColorWithOffset(offset, flip, colour) -> works on any single object
        local o = getObjectFromGUID(tostring(m.guid or ""))
        if not o then return { ok = false, err = "no object with guid " .. S(m.guid) } end
        local n = tonumber(m.n) or 1
        local dealt, e1 = pcall(function() return o.deal(n, player) end)
        if dealt then
            local a1 = {}
            pcall(function() a1 = pl.getHandObjects() or {} end)
            return { ok = true, player = player, guid = m.guid, n = n, hand = #a1, cmd = "hand" }
        end
        local off = m.offset
        if type(off) ~= "table" then off = { 0, 0, 0 } end
        local ok2, e2 = pcall(function() return o.dealToColorWithOffset(off, true, player) end)
        if not ok2 then
            return { ok = false, err = "deal failed: " .. S(e1) .. " ; dealToColorWithOffset failed: " .. S(e2), cmd = "hand" }
        end
        local a2 = {}
        pcall(function() a2 = pl.getHandObjects() or {} end)
        return { ok = true, player = player, guid = m.guid, n = 1, via = "dealToColorWithOffset", hand = #a2, cmd = "hand" }
    end
    return { ok = false, err = "unknown hand action: " .. action }
end

-- Metatable diagnostic. `act` kept reporting "object has no method X" for objects
-- that certainly have it (a Custom_Tile always has getRotation), which means the
-- lookup path is wrong rather than the object being unusual. Rather than guess at
-- the table shape again, report it:
--   * type() of the metatable and of every key inside it
--   * whether __index is a table or a function
--   * whether the object itself is indexable directly (o.getRotation)
--   * the first N names found on whichever table actually holds them
local function meta(guid)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    local r = { ok = true, guid = guid }
    local mt = getmetatable(o)
    r.mtType = type(mt)
    r.mtKeys = {}
    local idx = nil
    if type(mt) == "table" then
        for k, v in pairs(mt) do
            r.mtKeys[#r.mtKeys + 1] = tostring(k) .. ":" .. type(v)
            if k == "__index" then idx = v end
        end
    end
    r.indexType = type(idx)
    -- Case A: the object is indexable itself (methods hang off o directly).
    local direct = 0
    local directNames = {}
    local okA, errA = pcall(function()
        for k, v in pairs(o) do
            direct = direct + 1
            if direct <= 60 then directNames[#directNames + 1] = tostring(k) end
        end
    end)
    r.directOk = okA
    r.directErr = S(errA)
    r.directCount = direct
    -- keep the name lists short: a long reply is dropped by the HTTP bridge
    r.directNames = table.concat(directNames, ",", 1, math.min(#directNames, 25))
    -- Case B: __index is a table of methods.
    local idxCount = 0
    local idxNames = {}
    if type(idx) == "table" then
        for k, v in pairs(idx) do
            idxCount = idxCount + 1
            if idxCount <= 25 then idxNames[#idxNames + 1] = tostring(k) end
        end
    end
    r.idxCount = idxCount
    r.idxNames = table.concat(idxNames, ",")
    -- Case C: __index is a function -> the real table may be upvalue-hidden, but
    -- try indexing the object directly for a specific method name.
    local probes = {}
    for _, name in ipairs({ "getRotation", "getPosition", "getValue", "getName", "flip", "setRotation" }) do
        local ok, v = pcall(function() return o[name] end)
        probes[#probes + 1] = name .. "=" .. type(v) .. (ok and "" or "(err)")
    end
    r.methodProbe = table.concat(probes, " ")
    return r
end

-- Environment probe: list the GLOBAL functions and tables visible to this script.
--
-- WHY: the run/eval escape hatch does not exist in this sandbox (eval is nil), so
-- there is no way to introspect the environment from outside. But the mod's turn
-- system must be a Lua global (there is no other way for a mod to add a button),
-- so enumerating _G answers the important question directly: can "end turn" be
-- triggered from Lua instead of by clicking a UI button?
local function env(filter, limit)
    if type(_G) ~= "table" then return { ok = false, err = "_G is " .. type(_G) } end
    limit = tonumber(limit) or 400
    filter = filter and tostring(filter) or ""
    local out = {}
    local n = 0
    for k, v in pairs(_G) do
        n = n + 1
        if n > limit then break end
        local name = tostring(k)
        if filter == "" or string.find(name, filter, 1, true) then
            out[#out + 1] = name .. ":" .. type(v)
        end
    end
    table.sort(out)
    return { ok = true, total = n, returned = #out, names = table.concat(out, ",") }
end

local function setval(guid, value)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    local ok, err = pcall(function() o.setValue(tonumber(value) or 0) end)
    if not ok then return { ok = false, err = "setValue failed: " .. S(err) } end
    return { ok = true, guid = guid, value = o.getValue() }
end

local function getval(guid)
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object with guid " .. S(guid) } end
    return { ok = true, guid = guid, value = o.getValue() }
end

local function index(limit)
    local all = objs()
    limit = tonumber(limit) or 50
    local out = {}
    for i = 1, math.min(limit, #all) do
        local o = all[i]
        local nm, pos = "?", { 0, 0, 0 }
        pcall(function() nm = o.getName() end)
        pcall(function() local p = o.getPosition(); pos = { p.x, p.y, p.z } end)
        out[#out + 1] = {
            guid = o.getGUID(), name = nm,
            x = math.floor(pos[1] * 100) / 100,
            y = math.floor(pos[2] * 100) / 100,
            z = math.floor(pos[3] * 100) / 100
        }
    end
    return { ok = true, total = #all, returned = #out, items = out }
end

-- Escape hatch. This TTS Lua sandbox has NO load/loadstring (both nil), so code
-- cannot be compiled at runtime with the standard functions. TTS ships its own
-- eval() for exactly this purpose; whether it exists, and whether it can see
-- locally scoped parameters, is verified by the `diag` command rather than assumed.
--
-- Usage: {cmd="run", code="return 41+1"}
local function run(m, code)
    if code == nil then return { ok = false, err = "no code" } end
    if type(eval) ~= "function" then
        return { ok = false, err = "no eval() in this sandbox; use the static commands instead" }
    end
    local ok, res = pcall(function()
        return eval(code)
    end)
    if not ok then return { ok = false, err = "runtime: " .. S(res) } end
    if type(res) == "table" then
        local enc, eerr = pcall(function() return JSON.encode(res) end)
        if enc then return { ok = true, result = enc } end
        return { ok = true, result = "table (encode failed: " .. S(eerr) .. ")" }
    end
    return { ok = true, result = S(res) }
end

-- Environment inspection. Needs no loader, so it always works.
local function diag()
    local function t(n) return type(_G[n]) end
    return {
        ok = true,
        load = t("load"),
        loadstring = t("loadstring"),
        eval = t("eval"),
        setUI = t("setUI"),
        UI = t("UI"),
        Notes = t("Notes"),
        Player = t("Player"),
        JSON = t("JSON"),
        os = t("os"),
        io = t("io"),
        loadfile = t("loadfile"),
        DSH_buildUI = t("DSH_buildUI"),
        DSH_log_n = #(DSH_LOG or {}),
        loads = DSH_LOADS or -1,
        objects = #objs(),
        at = os.date("%H:%M:%S"),
        -- set by the spawn handler on its way to the reply; see the marker in DSH_spawn
        spawn_trace = tostring(__spawn_trace),
        -- guid of the last asynchronous spawn, filled in by spawnObject's callback_function
        spawn_last = tostring(__spawn_last),
    }
end

-- ------------------------------------------------------------------ panel -----
-- The in-game dialogue panel. These functions MUST live at file scope: the Global
-- script runs onLoad right after this file is evaluated, and onLoad calls
-- DSH_buildUI. When they were nested inside panelEnsure() the global never existed
-- at that moment, so the panel was never drawn (and the stale XmlUI in the save was
-- all the player saw).
--
-- A panel file at DSH_DIR/dsh_panel.lua may override these; it is optional.

DSH_LOG = DSH_LOG or {}
if DSH_INPUT == nil then DSH_INPUT = "" end

function DSH_panelGet()
    return {
        n = #DSH_LOG,
        pending = DSH_INPUT,
        last = (DSH_LOG[#DSH_LOG] or ""),
        log = table.concat(DSH_LOG, "\n"),
    }
end

function DSH_buildUI()
    local h = "(no messages yet)"
    if #DSH_LOG > 0 then
        local first = math.max(1, #DSH_LOG - 5)
        local out = {}
        for i = first, #DSH_LOG do out[#out + 1] = tostring(DSH_LOG[i]) end
        h = table.concat(out, "\n")
    end
    local shown = DSH_INPUT
    if shown == nil or shown == "" then shown = "[empty]" end
    if #shown > 30 then shown = string.sub(shown, 1, 30) .. "..." end
    local xml =
        '<Panel id="dshRoot" width="420" height="320" color="#0F0F0FEE" position="0 0 -10">' ..
        '<Text id="dshTitle" color="#66CCFF" fontSize="18" alignment="MiddleCenter">DSH  TO  P1</Text>' ..
        '<InputField id="dshInput" width="390" height="60" color="#FFFFFF" textColor="#101010" fontSize="15" ' ..
        'lineType="MultiLineNewLine" onValueChanged="DSH_onInput" onEndEdit="DSH_onInput" />' ..
        '<Button id="dshSend" text="SEND" width="130" height="32" colors="#2E7D32|#1B5E20|#A5D6A7|#333333" ' ..
        'textColor="#FFFFFF" fontSize="15" textAlignment="MiddleCenter" onClick="DSH_onClick(send)" />' ..
        '<Button id="dshClear" text="CLEAR" width="120" height="32" colors="#455A64|#263238|#90A4AE|#333333" ' ..
        'textColor="#FFFFFF" fontSize="14" textAlignment="MiddleCenter" onClick="DSH_onClick(clear)" />' ..
        '<Button id="dshHide" text="HIDE" width="100" height="32" colors="#5D4037|#3E2723|#BCAAA4|#333333" ' ..
        'textColor="#FFFFFF" fontSize="14" textAlignment="MiddleCenter" onClick="DSH_onClick(hide)" />' ..
        '<Text id="dshStatus" color="#FFD54F" fontSize="13" alignment="MiddleCenter">' ..
        'panel ready  log:' .. #DSH_LOG .. '  typed:' .. tostring(shown) .. '</Text>' ..
        '<Text id="dshHist" color="#EEEEEE" fontSize="12" alignment="LowerLeft">' .. h .. '</Text>' ..
        '</Panel>'
    local ok, err = pcall(setUI, xml)
    if not ok then
        -- last-ditch visible failure: put the reason in chat
        pcall(broadcastToAll, "[DSH] panel setUI failed: " .. tostring(err))
        return false
    end
    return true
end

local function panelEnsure()
    if type(DSH_buildUI) == "function" then return true end
    local d = DSH_DIR or "."
    local f = loadfile(d .. "/dsh_panel.lua")
    if f then pcall(f) end
    return (type(DSH_buildUI) == "function")
end

-- Input handlers. TTS invokes these as f(player_color, value, id); some UI paths
-- pass only the value. Scan every argument so the action is found either way.
function DSH_onInput(player, value, id)
    local v = nil
    for _, a in ipairs({ value, id, player }) do
        if type(a) == "string" then v = a break end
    end
    if v ~= nil then DSH_INPUT = v end
end

-- Single place that writes the status line, so every path through the panel gives
-- the user visible feedback and proves which handler actually fired.
function DSH_status(msg)
    local n = 0
    if DSH_LOG then n = #DSH_LOG end
    local s = "[nil]"
    if DSH_INPUT ~= nil and DSH_INPUT ~= "" then s = DSH_INPUT end
    pcall(function()
        UI.setAttribute("dshStatus", "text", tostring(msg) .. "  in:" .. tostring(s) .. "  log:" .. n)
    end)
end

local function DSH_looksLikeAction(s)
    if type(s) ~= "string" then return nil end
    if s == "send" or s == "sync" or s == "clear" or s == "hide" then return s end
    return nil
end

function DSH_onClick(player, value, id)
    local act = DSH_looksLikeAction(value) or DSH_looksLikeAction(id) or DSH_looksLikeAction(player)
    if act == nil then
        for _, a in ipairs({ value, id, player }) do
            if type(a) == "string" and #a <= 12 and a:match("^[%a]+$") then act = a break end
        end
    end
    local msg = "click:" .. tostring(act)
    if act == "send" then
        local v = tostring(DSH_INPUT or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if v ~= "" then
            DSH_LOG = DSH_LOG or {}
            DSH_LOG[#DSH_LOG + 1] = "[P1] " .. v
            DSH_INPUT = ""
            msg = "SENT"
        else
            msg = "empty input"
        end
    elseif act == "clear" then
        DSH_INPUT = ""
        msg = "cleared"
    elseif act == "hide" then
        pcall(setUI, '<Panel id="dshHidden" width="1" height="1" color="#00000000" position="0 0 -10" />')
        pcall(broadcastToAll, "[DSH] panel hidden - use panelShow to bring it back")
        return
    end
    if type(DSH_buildUI) == "function" then pcall(DSH_buildUI) end
    DSH_status(msg)
end

local function panelGet()
    local have = panelEnsure()
    if type(DSH_panelGet) ~= "function" then
        return { ok = false, err = "panel not loaded", panelLoaded = have }
    end
    local r = DSH_panelGet()
    r.ok = true
    return r
end

local function panelPush(text)
    panelEnsure()
    if type(DSH_push) ~= "function" then
        -- fallback append
        DSH_LOG = DSH_LOG or {}
        DSH_LOG[#DSH_LOG + 1] = "[DSH] " .. S(text)
        if type(DSH_buildUI) == "function" then pcall(DSH_buildUI) end
        return { ok = true, pushed = true, fallback = true, text = S(text) }
    end
    local done = DSH_push("DSH", text)
    if type(DSH_buildUI) == "function" then pcall(DSH_buildUI) end
    return { ok = true, pushed = done, text = S(text) }
end

local function panelShow()
    panelEnsure()
    if type(DSH_buildUI) == "function" then pcall(DSH_buildUI) end
    return { ok = true, shown = (type(DSH_buildUI) == "function") }
end

-- The first version of the panel could not be closed, which was a real complaint.
-- HIDE clears the global UI; SHOW (the new button, or the panelHide command) brings
-- it back. setUI with a single harmless element is used because there is no
-- documented "clear global UI" call.
local function panelHide()
    local ok = pcall(setUI, '<Panel id="dshHidden" width="1" height="1" color="#00000000" position="0 0 -10" />')
    return { ok = true, hidden = ok }
end

-- ------------------------------------------------------------------ notes -----
-- With setUI absent (see diag), the on-screen Notes area is the only remaining way
-- to put text in front of the player without a save/reload. These commands verify
-- and use it.

local function notesRead()
    local ok, v = pcall(function() return Notes.getNotes() end)
    if not ok then return { ok = false, err = S(v) } end
    return { ok = true, notes = S(v), chars = #S(v) }
end

-- ---------------------------------------------------------------- notebook -----
-- The dialogue channel. If the external API stays open while the game is merely
-- running (verified: it does), this reads what the player typed WITHOUT a save.
--
-- The edit index. editNotebookTab's index is the tab's POSITION in the list that
-- getNotebookTabs() returns, counting from 0 -- NOT the save file's TabStates key,
-- and NOT the `index` field that list reports. Using those was the source of a long
-- bug in which every write landed on the wrong tab (and once renamed it "Black").
-- So the position is resolved at call time instead of being hard-coded.
DSH_VERSION = 'v15-tags-snap-hand'
DSH_TAB_TITLE = DSH_TAB_TITLE or "DSH"

-- Returns the 0-based position of the dialogue tab, plus the tab itself.
local function findDialoguePos()
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok then return nil, nil, "getNotebookTabs threw: " .. S(tabs) end
    if type(tabs) ~= "table" then return nil, nil, "tabs is " .. type(tabs) end
    local titled, contented = nil, nil
    for i = 1, #tabs do
        local ti = tostring(tabs[i].title or "")
        if ti:find(DSH_TAB_TITLE, 1, true) or ti:find("对话", 1, true) then
            titled = i
            break
        end
        if contented == nil then
            local b = tostring(tabs[i].body or "")
            if b:find("DSH", 1, true) or b:find("对局记录", 1, true) then contented = i end
        end
    end
    local pos = titled or contented
    if pos == nil then
        return nil, nil, "no dialogue tab (title marker '" .. DSH_TAB_TITLE .. "') among " .. #tabs .. " tabs"
    end
    return pos, tabs[pos], nil
end

local function tabRead()
    if type(Notes) ~= "userdata" and type(Notes) ~= "table" then
        return { ok = false, err = "Notes is " .. type(Notes) }
    end
    local pos, t, err = findDialoguePos()
    if pos == nil then return { ok = false, err = err } end
    local body = tostring(t.body or "")
    return {
        ok = true,
        editIndex = pos - 1,          -- what editNotebookTab expects
        listPos = pos,
        title = tostring(t.title or ""),
        chars = #body,
        body = body,
    }
end

local function tabWrite(text)
    if text == nil then return { ok = false, err = "no text" } end
    local pos, t, err = findDialoguePos()
    if pos == nil then return { ok = false, err = err } end
    -- USE THE TAB'S OWN `index` FIELD.
    --
    -- The old code used pos-1 and every write landed on the wrong tab. Evidence:
    -- consecutive calls returned wildly different positions for the SAME tab
    -- (1, then 4, then 2), so getNotebookTabs() order is not stable and pos-1 is
    -- meaningless. The API documents getNotebookTabs() as returning
    --   { index=N, title=..., body=..., color=... }
    -- and editNotebookTab as taking that same index, so take it from the tab.
    local idx = t.index
    if idx == nil then idx = pos - 1 end
    local ok, e2 = pcall(function()
        Notes.editNotebookTab({ index = idx, body = tostring(text) })
    end)
    if not ok then return { ok = false, err = "editNotebookTab threw: " .. S(e2) } end
    local r = tabRead()
    return {
        ok = true,
        usedIndex = idx,
        listPos = pos,
        sentChars = #tostring(text),
        readbackChars = r.chars,
        titleAfter = r.title,
        verified = (r.chars == #tostring(text) and tostring(r.title or ""):find(DSH_TAB_TITLE, 1, true) ~= nil),
    }
end

-- List every tab with the index that actually edits it (position-1), so a future
-- write cannot target the wrong page.
local function tabList()
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok then return { ok = false, err = S(tabs) } end
    local out = {}
    local dshPos = (findDialoguePos())   -- take only the first return value
    for i = 1, #tabs do
        local ti = tostring(tabs[i].title or "")
        out[#out + 1] = {
            editIndex = i - 1,          -- the number editNotebookTab wants
            listPos = i,
            reportedIndex = tabs[i].index,
            chars = #tostring(tabs[i].body or ""),
            title = ti,
            isDialogue = (i == dshPos),
        }
    end
    return { ok = true, count = #tabs, dialoguePos = dshPos, tabs = out }
end

-- Can Lua touch the filesystem at all? (io and loadfile are nil, so this is checked
-- rather than assumed -- if any path works, note reading becomes unnecessary.)
-- notepush - put a message in front of the player. Three modes:
--   "notes" -> Notes.setNotes (the on-screen note pad)
--   "tab"   -> the notebook dialogue tab, located by title
--   "auto"  -> notes, and if that fails the notebook tab
-- Reports what it actually did and reads the result back, so a mis-targeted write
-- is visible immediately instead of looking like a success.
local function notesPush(m)
    if type(m) == "string" then m = { text = m } end
    if type(m) ~= "table" then m = {} end
    local text = m.text
    if text == nil then text = "DSH" end
    text = tostring(text)
    local mode = tostring(m.mode or "auto")
    local r = { ok = true, mode = mode, sentChars = #text }

    if mode == "notes" or mode == "auto" then
        if type(Notes) == "userdata" or type(Notes) == "table" then
            local ok, e = pcall(function() return Notes.setNotes(text) end)
            r.setNotes = ok and "ok" or S(e)
            if ok then
                local rok, back = pcall(function() return Notes.getNotes() end)
                r.notesVerified = (rok and S(back) == text)
            end
        else
            r.setNotes = "Notes is " .. type(Notes)
        end
        if r.notesVerified and mode == "auto" then r.done = "notes"; return r end
    end

    if mode == "tab" or mode == "auto" or (mode == "notes" and not r.notesVerified) then
        local pos, t, err = findDialoguePos()
        if pos == nil then
            r.tabErr = err
        else
            local idx = t.index
            if idx == nil then idx = pos - 1 end
            local ok, e = pcall(function()
                Notes.editNotebookTab({ index = idx, body = text })
            end)
            r.tabIndex = idx
            r.tabListPos = pos
            r.tabTitle = tostring(t.title or "")
            if ok then
                local r2 = tabRead()
                r.tabReadbackChars = r2.chars
                r.tabVerified = (r2.chars == #text)
            else
                r.tabErr = S(e)
            end
        end
    end
    return r
end
local function fsProbe()
    local r = { ok = true, io = type(io), loadfile = type(loadfile), os = type(os) }
    if type(os) == "table" and type(os.getenv) == "function" then
        local ok, v = pcall(os.getenv, "APPDATA")
        r.appdata = ok and S(v) or ("err:" .. S(v))
    end
    return r
end

local function opening()
    local msg =
        "[DSH] Nomad City -- first turn, P1 (red)\n" ..
        "1. Choose your starting resource node (the node on the green event card).\n" ..
        "2. Put the red moving city on that node's docking point.\n" ..
        "3. Write your choice in the notebook tab 'DSH dialogue channel'.\n" ..
        "Order: P1 (you) -> P2 -> P3 -> P4."
    local nres = notesPush({ text = msg, mode = "auto" })
    return {
        ok = true,
        notes = nres,
        broadcast = "not attempted (broadcastToAll is absent in this sandbox)",
    }
end

-- ------------------------------------------------------------------ probe -----
-- editNotebookTab's index does NOT match the `index` field that getNotebookTabs
-- reports, so the mapping has to be discovered empirically. This walks the index
-- space with a unique marker, reports which tab each index actually edits, and
-- restores the original body of every tab, flagging any body that no longer matches
-- what it started as (evidence that an earlier blind write damaged it).
local function runLoop()
    local MARK = "DSHPROBE"
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok then return { ok = false, err = "getNotebookTabs: " .. S(tabs) } end

    -- snapshot: pos -> {index, title, body}
    local snap = {}
    local dshPos, dshIndex = nil, nil
    for i = 1, #tabs do
        snap[i] = {
            title = tostring(tabs[i].title or ""),
            body = tostring(tabs[i].body or ""),
            index = tabs[i].index,
        }
        local ti = tostring(tabs[i].title or "")
        if ti:find("DSH", 1, true) or ti:find("对话", 1, true) then
            dshPos, dshIndex = i, tabs[i].index
        end
    end

    local results = {}
    local maxIdx = #tabs + 3

    -- 1. walk candidate indices
    for idx = 0, maxIdx do
        local okw = pcall(function()
            Notes.editNotebookTab({ index = idx, body = MARK .. "_i" .. idx })
        end)
        if okw then
            local ok2, t2 = pcall(function() return Notes.getNotebookTabs() end)
            local editedPos, editedTitle = nil, "?"
            if ok2 and type(t2) == "table" then
                for j = 1, #t2 do
                    local b = tostring(t2[j].body or "")
                    if b == MARK .. "_i" .. idx then
                        editedPos, editedTitle = j, tostring(t2[j].title or "")
                    end
                end
            end
            results[#results + 1] = {
                idx = idx,
                editedPos = editedPos,
                editedTitle = editedTitle,
                isDsh = (editedPos == dshPos),
            }
        else
            results[#results + 1] = { idx = idx, editedPos = -1, editedTitle = "CALL FAILED" }
        end
    end

    -- 2. restore every position's original body, working off the snapshot
    local restored, problems = 0, {}
    for i = 1, #snap do
        local s = snap[i]
        if s.body ~= "" then
            local okr, er = pcall(function()
                Notes.editNotebookTab({ index = s.index, body = s.body })
            end)
            if okr then restored = restored + 1 else problems[#problems + 1] = s.title .. ":restore:" .. S(er) end
        end
    end

    -- 3. verify: did every non-empty body come back?
    local ok3, t3 = pcall(function() return Notes.getNotebookTabs() end)
    local damaged, verified = {}, 0
    if ok3 and type(t3) == "table" then
        for i = 1, #snap do
            local want = snap[i].body
            if want ~= "" then
                -- find a current tab with the same title
                local found = false
                for j = 1, #t3 do
                    if tostring(t3[j].title or "") == snap[i].title then
                        if tostring(t3[j].body or "") == want then found = true; verified = verified + 1 end
                    end
                end
                if not found then damaged[#damaged + 1] = snap[i].title end
            end
        end
    end

    return {
        ok = true,
        tabCount = #tabs,
        dshPos = dshPos,
        dshIndex = dshIndex,
        snapshot = (function()
            local o = {}
            for i = 1, #snap do o[i] = { pos = i, title = snap[i].title, index = snap[i].index, chars = #snap[i].body } end
            return o
        end)(),
        probe = results,
        restored = restored,
        verified = verified,
        damaged = damaged,
        problems = problems,
    }
end

-- tabWriteProbe - find which editNotebookTab index actually edits which tab.
--
-- WHY: tabwrite reports ok but the target's body is unchanged (readback still shows
-- the old text). Either the index mapping is wrong or the write lands elsewhere. So
-- this writes a unique marker to EVERY index in turn, records where each marker
-- showed up, then restores every original body. Self-restoring, so it is safe to run.
local function tabWriteProbe()
    local ok, before = pcall(function() return Notes.getNotebookTabs() end)
    if not ok or type(before) ~= "table" then return { ok = false, err = "getNotebookTabs: " .. S(before) } end
    local snap = {}
    for i = 1, #before do
        snap[i] = {
            index = before[i].index,
            title = tostring(before[i].title or ""),
            body  = tostring(before[i].body or ""),
            color = before[i].color,
        }
    end
    local results = {}
    for idx = 0, #before - 1 do
        local mark = "ZQMARK_" .. idx
        local okw, ew = pcall(function()
            Notes.editNotebookTab({ index = idx, body = mark })
        end)
        local landedPos, landedTitle = nil, nil
        if okw then
            local ok2, t2 = pcall(function() return Notes.getNotebookTabs() end)
            if ok2 and type(t2) == "table" then
                for j = 1, #t2 do
                    if tostring(t2[j].body or "") == mark then
                        landedPos = j
                        landedTitle = tostring(t2[j].title or "")
                    end
                end
            end
        end
        results[#results + 1] = {
            wrote = idx,
            landedPos = landedPos,          -- nil = the write had NO effect anywhere
            landedTitle = landedTitle,
            reportedIndex = (landedPos and before[landedPos] and before[landedPos].index) or nil,
            err = (not okw) and S(ew) or nil,
        }
    end
    -- restore every original body by the index it USED to report
    local restored = 0
    for i = 1, #snap do
        local s = snap[i]
        local okr = pcall(function()
            Notes.editNotebookTab({ index = s.index, body = s.body, title = s.title })
        end)
        if okr then restored = restored + 1 end
    end
    local after = {}
    local ok3, t3 = pcall(function() return Notes.getNotebookTabs() end)
    if ok3 and type(t3) == "table" then
        for j = 1, #t3 do
            after[#after + 1] = { p = j, index = t3[j].index, title = tostring(t3[j].title or ""), chars = #tostring(t3[j].body or "") }
        end
    end
    local s0 = {}
    for i = 1, #snap do
        s0[#s0 + 1] = { p = i, index = snap[i].index, title = snap[i].title, chars = #snap[i].body }
    end
    return { ok = true, count = #before, before = s0, probe = results, restored = restored, after = after }
end
local DSH_PROBE_ONCE = nil
local function tabProbeOnce()
    if DSH_PROBE_ONCE ~= nil then return DSH_PROBE_ONCE end
    local ok, tabs = pcall(function() return Notes.getNotebookTabs() end)
    if not ok or type(tabs) ~= "table" then
        DSH_PROBE_ONCE = { ok = false, err = "getNotebookTabs: " .. S(tabs) }
        return DSH_PROBE_ONCE
    end
    -- describe every tab exactly as the API reports it
    local desc = {}
    for i = 1, #tabs do
        local ti = tostring(tabs[i].title or "")
        desc[#desc + 1] = {
            pos = i,
            index = tabs[i].index,
            title = ti,
            chars = #tostring(tabs[i].body or ""),
            isDsh = (ti:find("DSH", 1, true) ~= nil),
        }
    end
    -- find the dialogue tab and read its own index field
    local target, targetPos = nil, nil
    for i = 1, #tabs do
        local ti = tostring(tabs[i].title or "")
        if ti:find("DSH", 1, true) or ti:find("对话", 1, true) then target, targetPos = tabs[i], i break end
    end
    local out = { ok = true, count = #tabs, tabs = desc, targetPos = targetPos }
    if target == nil then
        out.note = "no DSH tab"
        DSH_PROBE_ONCE = out
        return out
    end
    out.targetIndex = target.index
    out.targetCharsBefore = #tostring(target.body or "")

    -- ONE write, to the index the tab itself reports
    local before = tostring(target.body or "")
    local mark = "ZQMARK_PROBE"
    local okw, ew = pcall(function()
        Notes.editNotebookTab({ index = target.index, body = mark })
    end)
    out.writeOk = okw
    out.writeErr = (not okw) and S(ew) or nil

    local ok2, t2 = pcall(function() return Notes.getNotebookTabs() end)
    out.landedPos = nil
    if ok2 and type(t2) == "table" then
        for j = 1, #t2 do
            if tostring(t2[j].body or "") == mark then
                out.landedPos = j
                out.landedIndex = t2[j].index
                out.landedTitle = tostring(t2[j].title or "")
            end
        end
    end
    -- restore
    pcall(function() Notes.editNotebookTab({ index = target.index, body = before }) end)
    DSH_PROBE_ONCE = out
    return out
end
-- ---------------------------------------------------------------------------
-- geom: one call, all the geometry that matters for putting something at a
-- chosen spot on a board.
--
-- WHY: the board's artwork resolution says nothing about its size on the table.
-- A 5000x5000 Custom_Board at scale 3 could be 50 units wide or 500, and the two
-- give completely different answers - an earlier pixel->table mapping derived
-- from the artwork's printed ruler put known cities off the board entirely. The
-- fix is not a cleverer guess: it is to ask positionToLocal/positionToWorld what
-- the mapping actually is, and to ask for it once so the reply cannot be dropped.
--
--   {cmd="geom", guids="957019"}
local function geom(guids)
    if guids == nil or guids == "" then return { ok = false, err = "no guids" } end
    local out = {}
    local n = 0
    for g in string.gmatch(tostring(guids), "[^,%s]+") do
        n = n + 1
        if n > 20 then break end
        local o = getObjectFromGUID(g)
        if o then
            local e = { g = g }
            pcall(function() local p = o.getPosition(); e.px = p.x; e.py = p.y; e.pz = p.z end)
            pcall(function() local s = o.getScale(); e.sx = s.x; e.sy = s.y; e.sz = s.z end)
            pcall(function() local r = o.getRotation(); e.ry = r.y end)
            pcall(function() local b = o.getBounds(); e.bx = b.x; e.by = b.y; e.bz = b.z end)
            -- world origin expressed in the object's own local frame: this is the
            -- offset between the board's local space and the table's.
            pcall(function()
                local l = o.positionToLocal({ 0, 0, 0 })
                e.lx = l.x; e.lz = l.z
            end)
            -- and the object's own centre converted back, which must round-trip
            pcall(function()
                local w = o.positionToWorld({ 0, 0, 0 })
                e.wx = w.x; e.wz = w.z
            end)
            -- The screen coordinate of the object's centre. This is the missing
            -- link for calibration: a screenshot gives pixel positions of visual
            -- features, world coordinates give table positions, and only
            -- getScreenPosition ties the two together without a hand-measured
            -- anchor that can be misread by a whole tile.
            pcall(function()
                local sp = o.getScreenPosition()
                if sp then e.spx = math.floor(sp.x + 0.5); e.spy = math.floor(sp.y + 0.5) end
            end)
            out[#out + 1] = e
        else
            out[#out + 1] = { g = g, err = "not found" }
        end
    end
    return { ok = true, items = out }
end

-- callFn: invoke a named function that lives in an object's own Lua script.
--
-- NOTE on the API shape: you CANNOT read the function off the object
-- (`o.customSet` raises "cannot access field customSet of userdata<LuaObject>"),
-- and `o[fname]` is no better. The supported route is Object.call(fnName), which
-- looks the name up inside that object's own script and runs it. Optional args go
-- in a second table.
local function callFn(guid, fname, args)
    if guid == nil or guid == "" then return { ok = false, err = "no guid" } end
    if fname == nil or fname == "" then return { ok = false, err = "no fn" } end
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object " .. S(guid) } end
    local ok, res
    if args ~= nil and type(args) == "table" and #args > 0 then
        ok, res = pcall(function() return o.call(tostring(fname), args) end)
    else
        ok, res = pcall(function() return o.call(tostring(fname)) end)
    end
    if not ok then return { ok = false, err = "call failed: " .. S(res), cmd = "call" } end
    return { ok = true, guid = guid, fn = tostring(fname), result = tostring(res), cmd = "call" }
end

-- setCount: force a 哥伦比亚金券 counter to show a given number.
--
-- Recipe (reverse-engineered from the counter's own script, MrStump
-- "Universal Counter Tokens"):
--   1. setDescription("<n>")   -- customSet() reads the description as the new value
--   2. call customSet()        -- sets the Lua local `count` and calls updateDisplay()
--   3. sync script_state       -- so onSave() persists the same number
--
-- Step 3 matters: script_state is what onSave writes to disk, and if it disagrees
-- with `count` the displayed number reverts on the next load. I learnt this the hard
-- way - setting script_state alone changed nothing on screen.
local function setCount(guid, value)
    if guid == nil or guid == "" then return { ok = false, err = "no guid" } end
    local n = tonumber(value)
    if n == nil then return { ok = false, err = "value not a number: " .. S(value) } end
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, err = "no object " .. S(guid) } end
    local out = { ok = true, guid = guid, want = n, cmd = "setcount" }
    local ok1, e1 = pcall(function() o.setDescription(tostring(math.floor(n))) end)
    out.desc = ok1 and tostring(math.floor(n)) or ("ERR " .. S(e1))
    -- customSet() reads the description and repaints the display button.
    local ok2, e2 = pcall(function() return o.call("customSet") end)
    out.customSet = ok2 and ("ok " .. tostring(e2)) or ("ERR " .. S(e2))
    local ok3, e3 = pcall(function() o.script_state = JSON.encode({ saved_count = math.floor(n) }) end)
    out.state = ok3 and o.script_state or ("ERR " .. S(e3))
    return out
end

-- ============================ SHARED MOVE HELPERS ============================
-- Used by BOTH draw (a deck's top card) and take (one NAMED card out of a container), so the two
-- cannot drift apart on the one thing that decides face up vs face down.
--
-- rotZ is what makes a card lie face UP or face DOWN:
--     rotZ ~   0 -> face UP    (measured: a board face and a player-flipped card sat at ~0.08)
--     rotZ ~ 180 -> face DOWN  (measured: every card still held in a hand sits at ~180)
-- NOTE: that calibration came from ONE table. On a new mod, measure a card of known orientation
-- before trusting it (tts\docs\VALIDATION.md F2).
--
-- setRotation/setPosition take POSITIONAL tables on purpose: the named-table form ({x=..,y=..,z=..})
-- is what made the generic act() path fail with "cannot convert a userdata to a clr type Vector3".
local placeFace = function(o, x, y, z, faceup)
    local rz = 180
    if faceup then rz = 0 end
    pcall(function() o.setRotation({ 0, 180, rz }) end)
    pcall(function() o.setPosition({ x, y, z }) end)
    return rz
end

-- Pull ONE card out of a Deck/Bag and lay it at (x, y, z).
--   m.deckguid  the container to take from
--   m.cardid    optional CardID (TTS assigns one to every Card); empty = the top card.
--               Pass it as a STRING: a numeric CardID can be mangled by JSON/proxy conversion.
-- WHY: a card inside a Deck is not a separate object - getObjectFromGUID cannot find it and
-- `move:` cannot reach it. Deck/hand takeObject is the only way out, and the top card is not always
-- the one wanted (reveal a named card / undo a misdeal).
DSH_takeOne = function(m)
    local deck = getObjectFromGUID(tostring(m.deckguid or ""))
    if not deck then return { ok = false, err = "no container with guid " .. S(m.deckguid) } end
    local before = nil
    pcall(function() before = deck.getQuantity() end)
    local cardId = tostring(m.cardid or "")
    local params = { smooth = false }
    if cardId ~= "" then params.guid = cardId end
    local ok, taken = pcall(function() return deck.takeObject(params) end)
    if not ok then
        return { ok = false, err = "takeObject failed: " .. S(taken), cmd = "take", cardid = cardId, remaining = before }
    end
    if taken == nil then
        return { ok = false, err = "nothing taken (empty, or no card with that CardID)",
                 cmd = "take", cardid = cardId, remaining = before }
    end
    local x, y, z = tonumber(m.x) or 0, tonumber(m.y) or 2.2, tonumber(m.z) or 0
    local faceup = tostring(m.faceup or "1") == "1"
    local rz = placeFace(taken, x, y, z, faceup)
    local after = nil
    pcall(function() after = deck.getQuantity() end)
    local g, nm = nil, ""
    pcall(function() g = taken.getGUID() end)
    pcall(function() nm = tostring(taken.getName()) end)
    return { ok = true, cmd = "take", container = m.deckguid, cardid = cardId, guid = g, name = nm,
             face = faceup and "up" or "down", rotZ = rz, remaining = after }
end

-- ============================ PLAYERS (authoritative seats) ============================
-- The bridge's one source of truth for "who is at this table, under which colour, how many cards,
-- and is it their turn". Needed because seats guessed from coordinates went wrong: nine HandTriggers
-- on one table could not be attributed to anyone, and the colour choice is a FUNCTIONAL
-- prerequisite in at least one mod (its Notecard: both sides must pick their colour or the dice
-- machine and hand display do not work).
-- NOTE: getPlayers().hand is a COUNT, not the cards. Use cmd=hand for the cards themselves, and
-- that only works for MY OWN colour (hidden-information rules in tts\docs\TTS_RULES.md).
DSH_players = function(m)
    -- A member list, not getPlayers(): that function does not exist in this TTS build.
    local seated = {}
    local okS = pcall(function() seated = getSeatedPlayers() end)
    if not okS or type(seated) ~= "table" then
        return { ok = false, cmd = "players", err = "getSeatedPlayers unavailable" }
    end
    -- ONE STRING PER SEAT, fields joined by "|". Objects would be mangled: this reply is flattened
    -- twice, and JSON.encode over the object proxies fails (measured live - see the header).
    local seats = {}
    for _, color in ipairs(seated) do
        local pl = Player[color]
        if pl ~= nil then
            local function g(fn, fallback)
                local ok, v = pcall(fn)
                if not ok or v == nil then return fallback end
                return tostring(v)
            end
            local hand = g(function() return pl.getHandCount() end, "?")
            seats[#seats + 1] = table.concat({
                tostring(color),
                g(function() return pl.steam_name end, ""),
                hand,
                g(function() return pl.host end, "?"),
                g(function() return pl.admin end, "?"),
                g(function() return pl.seated end, "?"),
                g(function() return pl.blindfolded end, "?"),
            }, "|")
        end
    end
    -- turn state, reported separately because it cannot be attached to a seat: Turns has
    -- getTurnOrder() but no getTurnColor(), and Player.turn is neither readable nor writable.
    local order = ""
    pcall(function() order = table.concat(Turns.getTurnOrder() or {}, ",") end)
    return { ok = true, cmd = "players", count = #seats, seats = seats, turn_order = order }
end

-- ============================ SPAWN / COPY / DESTROY ============================
-- The missing half of "draw": draw takes cards OFF a deck, but nothing could put a new piece ON the
-- table, so a mid-game token or a copy of a supply stack could only be placed by the human.
--   * m.type - a Built-in / Custom Game Object name; goes through spawnObject({type=...}).
--   * m.json - an OBJECT JSON STRING for full control (Name / Transform / CustomDeck ...); goes
--     through spawnObjectJSON(jsonString). This is the documented difference between the two API
--     calls, and feeding a table to spawnObjectJSON is what made the first live `spawn` fail.
--   * m.copyguid - clone an EXISTING object instead (carries its CustomDeck URLs, Lua and state).
--     Prefer this when the mod already has the piece on the table.
-- Declared as `local spawn = function`, NOT `local function spawn`, so the Lua globals
-- spawnObject / spawnObjectJSON this body calls are never shadowed.
DSH_spawn = function(m)
    -- DIAGNOSTIC (2026-10-09): entry marker. `spawn:type` answers "no reply in 25s" and diag shows
    -- __spawn_trace still nil with the object count unchanged, so the question is now "does the body
    -- run at all, and if so where does it stop". Traces at entry, after the call and before the
    -- return answer that in ONE live run: ask for cmd=diag and read spawn_trace. Remove all three
    -- once the reply lands.
    __spawn_trace = "enter " .. os.date("%H:%M:%S") .. " type=" .. tostring(m.type) ..
                    " json=" .. tostring(m.json) .. " copy=" .. tostring(m.copyguid)
    local x = tonumber(m.x) or 0
    local y = tonumber(m.y); if y == nil then y = 2 end
    local z = tonumber(m.z) or 0
    local faceup = tostring(m.faceup or "1") == "1"

    if tostring(m.copyguid or "") ~= "" then
        local src = getObjectFromGUID(tostring(m.copyguid))
        if not src then return { ok = false, cmd = "spawn", err = "no object to copy: " .. S(m.copyguid) } end
        local okc, c = pcall(function() return src.clone({ position = { x, y, z }, smooth = false }) end)
        if not okc or c == nil then return { ok = false, cmd = "spawn", mode = "copy", err = "clone failed: " .. S(c) } end
        placeFace(c, x, y, z, faceup)
        local g = nil
        pcall(function() g = c.getGUID() end)
        return { ok = true, cmd = "spawn", mode = "copy", from = m.copyguid, guid = g }
    end

    -- TWO DIFFERENT API CALLS, and mixing them up is what broke this the first time:
    --   spawnObject(name)          takes { type = "<Built-in or Custom Game Object name>", position = ... }
    --   spawnObjectJSON(jsonString) takes a JSON STRING, and is the one that carries full object data
    --                               ({ Name = ..., Transform = { posX = ... } }).
    -- The old code fed the { type = ... } table to spawnObjectJSON, which returned nil while the
    -- handler reported "needs TTS v13.2+". Measured live (2026-10-09): the call answered, the reply
    -- was this handler's own failure line, and the game went down seconds later - so it also gets
    -- probed one command at a time from now on.
    local json = m.json
    local ok, res, mode
    if json ~= nil and type(json) == "string" and json:match("^%s*{") then
        mode = "json"
        ok, res = pcall(function() return spawnObjectJSON(json) end)
    else
        local t = tostring(m.type or "")
        if t == "" then
            local dec = json
            if type(dec) == "string" then pcall(function() dec = JSON.decode(json) end) end
            if type(dec) ~= "table" then
                return { ok = false, cmd = "spawn", err = "need json (a JSON string), copyguid or type" }
            end
            t = tostring(dec.Name or dec.type or "")
            if t == "" then return { ok = false, cmd = "spawn", err = "json has neither Name nor type" } end
        end
        mode = "type"
        -- DEFERRED ON PURPOSE (2026-10-09, measured live, third attempt): calling spawnObject at all -
        -- synchronous or with callback_function, wrapped in pcall or not - stops the bridge thread
        -- before the handler can return. Evidence: the entry marker "enter ... type=Block" is written,
        -- the marker after the call never is, the caller sees "no reply in 25s", and the object count
        -- is unchanged afterwards because TTS rewinds the scripted change. The two earlier attempts
        -- only tried to protect the reply, which was never the problem.
        -- So the spawn is NOT done here. The reply goes out first (nothing can be lost after that),
        -- and the actual spawnObject runs on the NEXT message through cmd=spawn_step. That way the
        -- thread has a whole message boundary to die in, and the caller learns the outcome either way.
        __spawn_queue = { type = t, x = x, y = y, z = z, at = os.date("%H:%M:%S") }
        __spawn_trace = __spawn_trace .. " | queued type=" .. tostring(t)
        return { ok = true, cmd = "spawn", mode = "type", queued = true, type = t,
                 at = tostring(x) .. "," .. tostring(y) .. "," .. tostring(z),
                 note = "run cmd=spawn_step, then cmd=diag to read spawn_last" }
    end
    if not ok or res == nil then
        return { ok = false, cmd = "spawn", mode = mode, err = "spawn returned nothing: " .. S(res) }
    end
    -- DO NOT touch a freshly spawned object beyond reading its GUID and name.
    --
    -- Measured live (2026-10-09): `spawnObject` DID create the piece (the table went 115 -> 116
    -- objects) but the reply never reached the caller - "no reply in 25s" - while `spawn:copy`
    -- through clone() answered normally with the same placement code. The difference is that a
    -- clone is fully formed the moment it is returned, and a spawned object is still being built by
    -- TTS. The calls made here (getLuaScript, call("onLoad"), setRotation/setPosition through
    -- placeFace) run against that half-built object, and the reply is what gets lost.
    -- So: position comes from spawnObject's own `position` parameter, orientation is the caller's
    -- business (cmd=rotate on the returned guid), and the lua poke is gone. The old comment claimed
    -- the poke was needed for a spawned script's onLoad; that convenience is not worth a dead reply.
    local g, nm = nil, ""
    pcall(function() g = res.getGUID() end)
    pcall(function() nm = tostring(res.getName()) end)
    if mode == "copy" then placeFace(res, x, y, z, faceup) end
    -- DIAGNOSTIC MARKER (2026-10-09): `spawn:type` creates the piece (objects +1) and yet the caller
    -- gets "no reply in 25s", while `spawn:copy` answers normally. This records that the handler got
    -- all the way to the reply, so the next live run can tell "finished, reply lost" apart from
    -- "died mid-way": ask for cmd=diag and look at __spawn_trace. ⛔ NOT self.script_state - there is
    -- no `self` in the Global script, the assignment would just be swallowed by the pcall.
    __spawn_trace = __spawn_trace .. " | reached reply guid=" .. tostring(g)
    return { ok = true, cmd = "spawn", mode = mode, guid = g, name = nm }
end

-- Does the actual spawnObject for a queued `spawn:type`, on the message AFTER the request.
--
-- WHY THE SPLIT (measured live 2026-10-09): spawnObject stops the bridge thread before the handler
-- can return, so a request that both spawns and replies can never reply. The reply is what callers
-- depend on, so it goes first (see DSH_spawn), and the piece is built here. If this call also stops
-- the thread, it stops after the caller already has its answer, and the outcome is read back with
-- cmd=diag (spawn_last / spawn_trace). spawn:copy needs none of this - clone() returns complete.
DSH_spawnStep = function(m)
    local q = __spawn_queue
    if type(q) ~= "table" then
        return { ok = false, cmd = "spawn_step", err = "nothing queued" }
    end
    __spawn_queue = nil
    __spawn_last = nil
    __spawn_trace = tostring(__spawn_trace) .. " | step type=" .. tostring(q.type) .. " at " .. os.date("%H:%M:%S")
    local ok, res = pcall(function()
        return spawnObject({
            type = tostring(q.type),
            position = { x = tonumber(q.x) or 0, y = tonumber(q.y) or 2, z = tonumber(q.z) or 0 },
            callback_function = function(o)
                local cg = nil
                pcall(function() cg = o.getGUID() end)
                __spawn_last = tostring(cg)
            end,
        })
    end)
    if res ~= nil then
        local g = nil
        pcall(function() g = res.getGUID() end)
        __spawn_last = tostring(g)
    end
    __spawn_trace = tostring(__spawn_trace) .. " | step returned ok=" .. tostring(ok) .. " res=" .. type(res)
    return { ok = true, cmd = "spawn_step", type = tostring(q.type), called = ok, result = type(res) }
end

-- Remove an object from the table. pcall-wrapped because destroying something already gone, or
-- something TTS refuses to destroy mid-animation, must come back as a failure the caller can see -
-- never as a silent dead handler.
DSH_destroy = function(m)
    local guid = tostring(m.guid or "")
    if guid == "" then return { ok = false, cmd = "destroy", err = "no guid" } end
    local o = getObjectFromGUID(guid)
    if not o then return { ok = false, cmd = "destroy", err = "no object with guid " .. S(guid) } end
    local ok, e = pcall(function() return o.destruct() end)
    if not ok then return { ok = false, cmd = "destroy", guid = guid, err = "destruct failed: " .. S(e) } end
    return { ok = true, cmd = "destroy", guid = guid }
end

-- Draw cards OFF a deck and lay them out on the table.
--
-- WHY THIS EXISTS: a card inside a Deck is NOT a separate object. getObjectFromGUID
-- cannot find it and `move:` cannot reach it - verified the hard way when 6 cards were
-- stacked into a pile and all 7 old guids vanished. TTS's only primitive for "take the
-- top card off a deck" is Deck.takeObject(), so without this handler a deck can never be
-- drawn from. Needed for a "flip an event card" move (resource-map mods: explore onto an unmarked
-- resource point).
--
-- rotZ is what makes a card face up or face down when it lies flat:
--     rotZ ~   0 -> face UP    (verified: the 企业板 and a player-flipped 事件牌 sit at ~0.08)
--     rotZ ~ 180 -> face DOWN  (verified: every card still held in a hand sits at ~180)
--
-- setRotation/setPosition take POSITIONAL tables here on purpose: the named-table form
-- ({x=..,y=..,z=..}) is what made the generic act() path fail with
-- "cannot convert a userdata to a clr type UnityEngine.Vector3".
local function draw(m)
    local deckGuid = tostring(m.guid or "")
    local deck = getObjectFromGUID(deckGuid)
    if not deck then return { ok = false, err = "no object with guid " .. S(deckGuid) } end
    local n = tonumber(m.n) or 1
    local x = tonumber(m.x) or 0
    local y = tonumber(m.y) or 2.2
    local z = tonumber(m.z) or 0
    local step = tonumber(m.step) or 2.4
    local faceup = tostring(m.faceup or "1") == "1"
    local rz = 180
    if faceup then rz = 0 end
    local guids = {}
    for i = 1, n do
        local px = x + ((i - 1) * step)
        local ok, taken = pcall(function()
            return deck.takeObject({ position = { px, y, z }, smooth = false })
        end)
        if not ok then
            return { ok = false, err = "takeObject failed: " .. S(taken), taken = #guids, guids = guids }
        end
        if taken == nil then
            return { ok = false, err = "deck empty after " .. tostring(#guids) .. " card(s)",
                     taken = #guids, guids = guids }
        end
        -- Rotate and re-place AFTER the take, and only through the shared helper: rotZ is the whole
        -- difference between face up and face down, so draw and take must never compute it twice.
        placeFace(taken, px, y, z, faceup)
        local g = nil
        pcall(function() g = taken.getGUID() end)
        guids[#guids + 1] = g
    end
    local left = nil
    pcall(function() left = deck.getQuantity() end)
    return { ok = true, deck = deckGuid, n = #guids, guids = guids, remaining = left }
end

-- ============================ TURN TOKEN ============================
-- A clickable object whose only job is to make "the player ended the turn" VISIBLE to the bridge.
--
-- WHY: TTS's own End Turn banner (the "Player N" banner) cannot be driven by synthetic input and
-- leaves no usable state behind, so the turn had to be inferred from a foreground watcher
-- (front_watch.ps1) - which reads nothing at all while TTS sits in the background.
-- The token carries the turn number in its NICKNAME (the bulk index already emits `k`, and
-- diff_index.ps1 diffs `nick`), keeps it in script_state across saves, and toggles its rotation
-- so a rotation/position diff sees it too.
--
-- NOT spawned automatically on load: a save that gets re-baked must not grow objects merely
-- because the bridge loaded. Run cmd=turn_token once (bootstrap), then probe cmd=turn_state.
TURN_TOKEN_NAME = "DSH-TURN"

TURN_TOKEN_LUA = [==[
-- A CLICKABLE TOKEN FOR A MOD THAT HAS NO TURN TRACKER OF ITS OWN.
--
-- WHY THE UI BUTTON, NOT onClick (measured 2026-10-10): the previous version hooked the Object
-- onClick event and never fired, while this mod's own clickable pieces - a hand-counter Custom_Token
-- is the one on this table - carry XMLUI buttons and zero onClick handlers (5 object scripts scanned:
-- onClick count 0). TTS's plain onClick on a tile with no UI is not the delivery this table uses.
-- The button writes into a UI variable, onValueChanged calls dshBump, and dshBump also flips the tile
-- and broadcasts, so a click is visible on the table as well as readable from the bridge.
dshN = 0
function onSave() return JSON.encode({ n = dshN }) end
function dshRepaint()
    pcall(function() self.setNickname("DSH-TURN " .. tostring(dshN)) end)
    pcall(function() self.setVar("turnLabel", "TURN " .. tostring(dshN)) end)
end
function dshBump()
    dshN = dshN + 1
    dshRepaint()
    local ok, r = pcall(function() return self.getRotation() end)
    if ok and type(r) == "table" then
        pcall(function() self.setRotation({ x = r.x or 0, y = (r.y or 0) + 180, z = r.z or 0 }) end)
    end
    if type(broadcastToAll) == "function" then
        pcall(function() broadcastToAll("[DSH] turn " .. tostring(dshN) .. " ended") end)
    end
    return dshN
end
function onLoad(saved)
    dshN = 0
    if saved and saved ~= "" then
        local ok, t = pcall(function() return JSON.decode(saved) end)
        if ok and type(t) == "table" and tonumber(t.n) then dshN = tonumber(t.n) end
    end
    self.createButton({
        click_function = "dshOnClick", function_owner = self, label = "END TURN",
        -- ⚠️ The token sits at rotZ 180 (flipped onto its face), so a button at {0, 0.6, 0} with no
        -- rotation ends up on the UNDERSIDE with mirrored text - the player's screenshot showed exactly
        -- that. Rotate it 180 about Z so the label reads correctly on the surface they can see and click.
        position = { 0, 0.6, 0 }, rotation = { 0, 0, 180 }, width = 500, height = 260,
        font_size = 120, color = { 0.16, 0.16, 0.16 }, font_color = { 1, 1, 1 },
    })
    dshRepaint()
end
function dshOnClick(obj, color, alt)
    dshBump()
end
-- kept as a fallback: if this table does deliver plain clicks, they count too
function onClick(player_color) dshBump() end
]==]

-- Read a property of an object: try the ACCESSOR first, then the MEMBER VARIABLE.
--
-- The official Object page settles both traps this file hit (api.tabletopsimulator.com/object):
--   * `name` is "Internal resource name ... generally, you want getName()" - so the raw field holds
--     "Custom_Token"/"Custom_Tile" and the DISPLAY name only comes from getName();
--   * there is no getNickname() at all - `nickname` is a member variable. TTS answers a call to the
--     missing method with "cannot access field getNickname of userdata<LuaObject>", which reads like
--     a value if you let it through.
-- So: accessor, then variable, and never hand back an accessor's error text.
local function prop(o, method, field)
    local ok, v = pcall(function() return o[method]() end)
    if not ok then v = nil end
    if v == nil or tostring(v) == "" then
        local ok2, f = pcall(function() return o[field] end)
        if ok2 and f ~= nil then v = f end
    end
    if v == nil or (type(v) == "string" and v:find("cannot access field")) then return "" end
    return tostring(v)
end

-- Marker stored on the token's DISPLAY name (getName) and, because TTS has no nickname accessor, its
-- `nickname` member too. Either one matching is enough.
local function isTokenName(s)
    if s == nil then return false end
    s = tostring(s)
    return s ~= "" and s:sub(1, #TURN_TOKEN_NAME) == TURN_TOKEN_NAME
end

local function findTurnToken()
    local all = getObjects()
    if type(all) ~= "table" then return nil end
    for _, o in ipairs(all) do
        -- getName() is the display name (the official doc says exactly this: `name` is the internal
        -- resource name, "generally you want getName()"). `nickname` is a member variable - TTS has no
        -- getNickname method on this build. Either carrying the marker identifies our token.
        if isTokenName(prop(o, "getName", "name")) or isTokenName(prop(o, "getNickname", "nickname")) then
            return o
        end
    end
    return nil
end

-- Art for the turn token, taken from a Custom_Tile that is already on this table.
--
-- WHY (2026-10-09, both measured): spawnObject on a CUSTOM type without its content parameter makes
-- TTS put up its "自定义板块" dialog and ask for the image - that dialog is modal, so the bridge's
-- reply never comes and the scripted change is reverted (this is what made spawn:type look "hung").
-- Handing it the image up front avoids the dialog entirely. Reading it from the table rather than
-- hardcoding a URL keeps this file free of mod content, which the open-source boundary requires.
local function tokenArt()
    local all = getObjects()
    if type(all) ~= "table" then return nil end
    for _, o in ipairs(all) do
        local nm = ""
        pcall(function() nm = tostring(o.getName()) end)
        if nm == "Custom_Tile" then
            local ci = nil
            pcall(function() ci = o.getCustomObject() end)
            if type(ci) == "table" and tostring(ci.image or "") ~= "" then
                return {
                    image = tostring(ci.image),
                    image_secondary = tostring(ci.image_secondary or ""),
                    type = tonumber(ci.type) or 0,
                    thickness = tonumber(ci.thickness) or 0.2,
                    stackable = ci.stackable == true,
                }
            end
        end
    end
    return nil
end

-- Guid whose object is used as the token's art/shape source, filled in when a save is baked.
-- Empty means "find any Custom_Tile on the table", which is the normal case.
TURN_TOKEN_TEMPLATE = TURN_TOKEN_TEMPLATE or ""

-- Build the turn token WITHOUT spawnObject, by cloning a tile that is already on the table.
--
-- WHY (measured 2026-10-10): every route through spawnObject produced TTS's "自定义板块" dialog -
-- with no image parameter AND with image/image_bottom supplied - and objects baked into a save were
-- dropped by TTS at load (four different guids, all gone). clone() has neither problem: it never
-- opens the dialog and the piece persists; the player confirmed seeing clones appear on the table.
-- The clone inherits the tile's art and grid flags, so the token matches the table's own pieces.
DSH_tokenPlain = function(m)
    local existing = findTurnToken()
    local paint = function(o)
        pcall(function() o.setName(TURN_TOKEN_NAME) end)
        pcall(function() o.setScale({ 1, 1, 1 }) end)
        pcall(function() o.setLuaScript(TURN_TOKEN_LUA) end)
        -- Re-run the object's onLoad so its UI button exists for the script just installed, and so the
        -- nickname reflects the saved count. Without this an existing token keeps the old script's
        -- behaviour - measured: the clone's onClick never fired and it had no button at all.
        pcall(function() o.call("onLoad", { o.script_state or "" }) end)
        local g = nil
        pcall(function() g = o.getGUID() end)
        return tostring(g)
    end
    if existing then
        return { ok = true, cmd = "token_plain", reused = true, guid = paint(existing) }
    end
    local src = nil
    for _, o in ipairs(getObjects() or {}) do
        -- ⚠️ getObjects() entries may be PLAIN TABLES (the same trap as the 147-card container listing
        -- and the F8 investigation): calling o.getName() then throws and the pcall leaves the name
        -- empty, so this loop found nothing and token_plain answered "no Custom_Tile to clone".
        -- Read the field first, fall back to the method.
        local nm = ""
        pcall(function() if o.name ~= nil then nm = tostring(o.name) end end)
        if nm == "" or nm == "Custom_Tile" then
            pcall(function() nm = tostring(o.getName()) end)
        end
        if nm == "Custom_Tile" or nm == "Custom_Token" then src = o; break end
    end
    -- Fall back to a direct lookup of the template this bridge was baked against.
    if not src and TURN_TOKEN_TEMPLATE ~= "" then
        pcall(function() src = getObjectFromGUID(TURN_TOKEN_TEMPLATE) end)
    end
    if not src then return { ok = false, cmd = "token_plain", err = "no Custom_Tile on the table to clone" } end
    local x = tonumber(m and m.x) or 0
    local y = tonumber(m and m.y) or 1.6
    local z = tonumber(m and m.z) or 0
    local ok, c = pcall(function() return src.clone({ position = { x = x, y = y, z = z }, smooth = false }) end)
    if not ok or c == nil then return { ok = false, cmd = "token_plain", err = "clone failed: " .. S(c) } end
    -- ⛔ A CLONE INHERITS THE SOURCE'S script_state. Measured 2026-10-10: the token came out carrying
    -- the mod hand-counter's state ({"color":"Brown"}), so our onLoad saw a non-empty state, took it
    -- for "a previous turn count", decoded it, found no `n`, and left dshN = 0 - the token's own count
    -- was never written. Clear it before installing our script, then onLoad starts from a clean slate.
    pcall(function() c.script_state = "" end)
    return { ok = true, cmd = "token_plain", created = true, from = "clone", guid = paint(c), src = tostring(src.getGUID and src.getGUID() or "") }
end

local function turnToken(m)
    local o = findTurnToken()
    local created = false
    if not o then
        local art = tokenArt()
        local params = { type = "Custom_Tile", position = { x = 0, y = 3, z = 0 } }
        if art then params.image = art.image; params.image_bottom = art.image_secondary end
        local ok, res = pcall(function() return spawnObject(params) end)
        if not ok or res == nil then
            return { ok = false, cmd = "turn_token",
                     err = "spawn failed: " .. S(res) .. (art and "" or " (no Custom_Tile art found - TTS will ask for an image)") }
        end
        o = res
        created = true
        if art then
            pcall(function() o.setCustomObject({ image = art.image, image_secondary = art.image_secondary,
                                                 type = art.type, thickness = art.thickness,
                                                 stackable = art.stackable }) end)
        end
        -- scale 1 so it is big enough to see and click (table tiles are often 0.38)
        pcall(function() o.setScale({ 1, 1, 1 }) end)
    end
    local guid = o.getGUID()
    pcall(function() o.setName(TURN_TOKEN_NAME) end)
    pcall(function() o.setLuaScript(TURN_TOKEN_LUA) end)
    if created then pcall(function() o.setNickname(TURN_TOKEN_NAME .. " 0") end) end
    local nick, rot = "", ""
    pcall(function() nick = tostring(o.getNickname()) end)
    pcall(function()
        local r = o.getRotation()
        rot = string.format("%d,%d,%d", r.x or 0, r.y or 0, r.z or 0)
    end)
    return { ok = true, cmd = "turn_token", guid = guid, created = tostring(created), nick = nick, rot = rot }
end

local function turnState(m)
    local o = findTurnToken()
    if not o then
        -- diagnostic: say what the scan actually saw, rather than only "no token"
        local seen, n = {}, 0
        for _, x in ipairs(getObjects() or {}) do
            n = n + 1
            if n <= 6 then
                seen[#seen + 1] = "{" .. prop(x, "getName", "name") .. "|" .. prop(x, "getNickname", "nickname") .. "}"
            end
        end
        return { ok = false, cmd = "turn_state", err = "no turn token yet",
                 scanned = n, sample = table.concat(seen, " ") }
    end
    local nick = prop(o, "getNickname", "nickname")
    local nm = prop(o, "getName", "name")
    local guid = prop(o, "getGUID", "guid")
    local ss = ""
    pcall(function() ss = tostring(o.script_state or "") end)
    -- the number is whatever trails the display name ("DSH-TURN 3"); the nickname accessor does not
    -- exist on this build, so it is decoration only
    local n = nm:match("(%d+)%s*$") or nick:match("(%d+)%s*$") or "?"
    return { ok = true, cmd = "turn_state", guid = guid, name = nm, nick = nick, turn = n, state = ss }
end

-- The turn recorder's own read: the script's globals are the truth, the piece on the table is not.
-- Returns the committed state string too, so a caller can see WHEN the last turn was recorded.
local function turnGet(m)
    return { ok = true, cmd = "turn_get", turn = tostring(DSH_TURN_N or 0),
             state = tostring(DSH_STATE or ""), at = os.date("%H:%M:%S") }
end

local function turnEnd(m)
    local n = turnCommit(m and m.turn)
    return { ok = true, cmd = "turn_end", turn = tostring(n), state = tostring(DSH_STATE or "") }
end

-- The turn signal the PLAYER drives, and the piece they press is a real object in the save.
--
-- WHY THIS REPLACES EVERYTHING WE TRIED (measured 2026-10-10): the table carries the community
-- "Turn Tracker" Custom_Token (locked, so only its own button moves it). Pressing its End Turn button
-- teleports it between the two hand zones: z = -15 (the player's side) and z = +15 (mine), a clean
-- 30-unit jump with no other object moving. It is IN THE SAVE, so unlike a runtime-spawned token it
-- survives every reload, and it needs no button, script or state of ours at all.
-- So the whole question "whose turn is it / did the player end their turn" reduces to reading one
-- position - which is also exactly what a sentinel can watch from outside without holding a session.
TURN_TRACKER_GUID = TURN_TRACKER_GUID or "0e731f"

local function turnTrackerState()
    local o = nil
    pcall(function() o = getObjectFromGUID(TURN_TRACKER_GUID) end)
    if o == nil then
        return { ok = false, cmd = "turn_tracker", err = "no object with guid " .. tostring(TURN_TRACKER_GUID),
                 guid = TURN_TRACKER_GUID }
    end
    local pos = nil
    pcall(function() pos = o.getPosition() end)
    if type(pos) ~= "table" then
        return { ok = false, cmd = "turn_tracker", err = "no position", guid = TURN_TRACKER_GUID }
    end
    local z = tonumber(pos.z) or 0
    -- the token rests on one hand zone or the other; the sign of z is the whole answer
    local side = "unknown"
    if z > 1 then side = "mine" elseif z < -1 then side = "player" end
    return { ok = true, cmd = "turn_tracker", guid = TURN_TRACKER_GUID, side = side,
             x = string.format("%.2f", tonumber(pos.x) or 0),
             z = string.format("%.2f", z), at = os.date("%H:%M:%S") }
end

local handlers = {
    ping = function(m) return ping() end,
    -- call a function that lives in an OBJECT's own script.
    --
    -- WHY THIS EXISTS: the 哥伦比亚金券 counters are MrStump "Universal Counter
    -- Tokens". Their visible number comes from a Lua local `count` pushed to a UI
    -- button by updateDisplay(). Writing object.script_state only changes the SAVED
    -- value - the on-screen number does not move, because the running script never
    -- re-reads it. So the only correct way to change the displayed count is to invoke
    -- one of the script's own functions:
    --     customSet()  reads self.getDescription() as a number, sets count, repaints
    -- So: setDescription("<n>") then call customSet().
    call = function(m) return callFn(m.guid, m.fn) end,
    -- 2026-10-07 新增：callx —— **带参数**调用物件脚本里的函数（我的 call 只有无参版本，
    -- 而模组"选英雄"按钮的回调签名是 fn(obj, color, alt_click)，缺 color 就什么都不做）。
    -- 用法：{cmd="callx", guid="285719", fn="moon", args={"", "Blue", false}}
    -- TTS 的 Object.call(fn, table) 会把 table 的内容**展开**成位置参数，所以这里直接传 args。
    callx = function(m)
        local o = getObjectFromGUID(tostring(m.guid or ""))
        if not o then return { ok = false, err = "no object " .. tostring(m.guid) } end
        local list = m.args
        if type(list) ~= "table" then list = {} end
        local ok, res = pcall(function() return o.call(tostring(m.fn or ""), list) end)
        if not ok then return { ok = false, err = tostring(res), fn = tostring(m.fn) } end
        return { ok = true, fn = tostring(m.fn), res = VS(res) }
    end,
    setcount = function(m) return setCount(m.guid, m.value) end,
    geom = function(m) return geom(m.guids) end,
    opening = function(m) return opening() end,
    notepush = function(m) return notesPush(m) end,
    noteread = function(m) return notesRead() end,
    tabread = function(m) return tabRead() end,
    tabwrite = function(m) return tabWrite(m.text) end,
    tablist = function(m) return tabList() end,
    tabprobe = function(m) return tabProbeOnce() end,
    runloop = function(m) return runLoop() end,
    fsprobe = function(m) return fsProbe() end,
    diag = function(m) return diag() end,
    panelGet = function(m) return panelGet() end,
    panelPush = function(m) return panelPush(m.text) end,
    panelShow = function(m) return panelShow() end,
    panelHide = function(m) return panelHide() end,
    selftest = function(m) return selftest() end,
    count = function(m) return count(m.limit) end,
    find = function(m) return find(m.filter, m.limit) end,
    read = function(m) return read(m.guid) end,
    probe = function(m) return probe(m.guid) end,
    whose = function(m) return whose(m.guids) end,
    act = function(m) return act(m) end,
    env = function(m) return env(m.filter, m.limit) end,
    meta = function(m) return meta(m.guid) end,
    all = function(m) return all(m.limit, m.states == true or m.states == "true") end,
    hand = function(m) return hand(m) end,
    draw = function(m) return draw(m) end,
    write = function(m) return write(m.guid, m.value) end,
    move = function(m) return moveTo(m.guid, m.x, m.y, m.z) end,
    rotate = function(m) return rotateTo(m.guid, m.x, m.y, m.z, m.add == true or m.add == "true") end,
    flip = function(m) return rotateTo(m.guid, 0, 0, 180, true) end,
    setval = function(m) return setval(m.guid, m.value) end,
    getval = function(m) return getval(m.guid) end,
    index = function(m) return index(m.limit) end,
    run = function(m) return run(m, m.code) end,
    turn_token = function(m) return turnToken(m) end,
    -- spawnObject-free token: clones an existing tile. See DSH_tokenPlain for why.
    token_plain = function(m) return DSH_tokenPlain(m) end,
    -- THE TURN RECORDER (see the block at the top of this file): no object involved, so it survives
    -- every reload and cannot be broken by how a piece behaves. turn_end records one turn;
    -- turn_get reads the count and the timestamp of the last recording.
    turn_end = function(m) return turnEnd(m) end,
    turn_get = function(m) return turnGet(m) end,
    -- reads the table's own Turn Tracker piece: which side it sits on is whose turn it is
    turn_tracker = function(m) return turnTrackerState() end,
    -- Same shape as before plus the authoritative global numbers. The table piece - if one happens to
    -- be on the table - is reported as decoration only; a missing piece no longer means "no turn yet".
    turn_state = function(m)
        local g = turnGet(m)
        local o = findTurnToken()
        g.token = nil
        if o then
            g.token_guid = prop(o, "getGUID", "guid")
            g.token_name = prop(o, "getName", "name")
        end
        g.cmd = "turn_state"
        return g
    end,
    -- container listing: what is actually inside a Bag/Deck right now (getObjects()).
    -- Complements index/all, which only see the table, and draw/take, which pull one card.
    container = function(m)
        local o = getObjectFromGUID(tostring(m.guid or ""))
        if not o then return { ok = false, cmd = "container", err = "no object with guid " .. S(m.guid) } end
        local list = nil
        local okList = pcall(function() list = o.getObjects() end)
        if not okList or type(list) ~= "table" then return { ok = false, cmd = "container", err = "getObjects failed" } end
        -- full=1 asks for the WHOLE face text instead of a 60-char prefix. WHY: the prefix keeps a
        -- 147-card reply small, but the card library (card.ps1's cache\<game>_cards.md) needs the face
        -- text complete - and nothing else on this side carries it (obj_index.ps1 and live_index.csv
        -- stop at name/nickname/position). Measured 2026-10-09.
        local full = m.full == true or tostring(m.full or "") == "1" or tostring(m.full or "") == "true"
                local lines = {}
                for i, x in ipairs(list) do
                    -- ⚠️ getObjects() returns PLAIN TABLES, not object proxies: x.getName() and
                    -- friends are nil calls (probed live 2026-10-09, every method returned "attempt
                    -- to call a nil value" and the fields came out empty). Read the FIELDS - they
                    -- are the TTS object's serialised keys.
                    local g, nm, nk, q, ds = "", "", "", "", ""
                    if type(x) == "table" then
                        if x.guid ~= nil then g = tostring(x.guid) end
                        if x.name ~= nil then nm = tostring(x.name) end
                        if x.nickname ~= nil then nk = tostring(x.nickname) end
                        if x.quantity ~= nil then q = tostring(x.quantity) end
                        -- `description` carries the full face text of a card; keep a short prefix so
                        -- a 147-card reply stays small (full=1 gives it whole - see above).
                        if x.description ~= nil then
                            ds = tostring(x.description):gsub("[\r\n]+", " ")
                            if not full and #ds > 60 then ds = ds:sub(1, 60) .. "..." end
                        end
                    end
                    lines[#lines + 1] = g .. "|" .. nm .. "|" .. nk .. "|" .. q .. "|" .. ds
                end
                local qty = nil
                pcall(function() qty = o.getQuantity() end)
                return { ok = true, cmd = "container", guid = m.guid, count = #lines, quantity = qty, lines = lines }
    end,
    -- Added 2026-10-09 (tts\docs\VALIDATION.md F6 - the primitives a trained control layer kept
    -- missing): players = who is at the table / whose turn; take = pull ONE NAMED card out of a
    -- deck (draw could only take the top); spawn = put a new piece on the table (json, a copy of an
    -- existing object, or a plain TTS type); destroy = remove one; player = act on a player
    -- (TTS's own turn marker, blindfold, or a passthrough to hand).
    players = function(m) return DSH_players(m) end,
    take = function(m) return DSH_takeOne(m) end,
    spawn = function(m) return DSH_spawn(m) end,
    -- second half of a queued `spawn:type`; see DSH_spawnStep for why the spawn is split in two
    spawn_step = function(m) return DSH_spawnStep(m) end,
    destroy = function(m) return DSH_destroy(m) end,
    player = function(m)
        local action = tostring(m.action or "")
        if action == "" or action == "get" or action == "take" then return hand(m) end
        local color = tostring(m.player or "")
        if color == "" then return { ok = false, cmd = "player", err = "no player colour" } end
        local pl = Player[color]
        if pl == nil then return { ok = false, cmd = "player", err = "no player colour " .. color } end
        if action == "turn" then
            local ok, e = pcall(function() pl.turn = true end)
            return { ok = ok, cmd = "player", action = action, color = color, err = ok and nil or S(e) }
        elseif action == "blind" then
            local on = tostring(m.on or "true") == "true"
            local ok, e = pcall(function() pl.blindfolded = on end)
            return { ok = ok, cmd = "player", action = action, color = color, on = on, err = ok and nil or S(e) }
        end
        return { ok = false, cmd = "player", err = "unknown player action: " .. action }
    end,
}

-- ============================ THE SILENT-REPLY BUG ============================
-- `sendExternalMessage` CANNOT serialise a reply that contains a NESTED table.
-- It raises, and because the call below was not inside a pcall, the whole
-- onExternalMessage died and NOTHING was sent back. The caller then saw
-- "no reply in 25s" and could not tell it apart from "TTS is not running".
--
-- That is why every list-returning handler was silently dead:
--     find  -> items{}      hand -> items{}      draw -> guids{}
--     geom / all / whose   (same shape, presumably all dead too)
-- while every handler that returns only scalars worked fine:
--     ping / act / setcount / getState / tabread ...
--
-- THE TELL: an UNKNOWN command still answers ("no handler for cmd=X"), because
-- that reply is flat. So "known command + no reply at all" == this bug.
--
-- FIX (two parts, both needed):
--   1. flatten nested tables to JSON STRINGS before sending - a flat table of
--      strings/numbers/booleans always serialises;
--   2. keep a pcall around the send, so that if anything still refuses to
--      serialise we get a visible error instead of silence.

local function flattenReply(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return v end
    if t ~= "table" then return tostring(v) end
    if depth > 0 then return tostring(v) end
    local ok, s = pcall(function() return JSON.encode(v) end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end

function onExternalMessage(data)
    local cmd = data and data.cmd
    local reply = { ok = false, err = "no handler for cmd=" .. S(cmd) }
    if cmd and handlers[cmd] then
        local ok, res = pcall(handlers[cmd], data)
        if ok then
            reply = res
            if type(reply) == "table" then reply.cmd = cmd end
        else
            reply = { ok = false, err = "handler error: " .. S(res), cmd = cmd }
        end
    end
    local flat = {}
    if type(reply) == "table" then
        for k, v in pairs(reply) do flat[k] = flattenReply(v, 0) end
    else
        flat = { ok = true, value = tostring(reply), cmd = tostring(cmd) }
    end
    local sent, serr = pcall(function() sendExternalMessage(flat) end)
    if not sent then
        pcall(function()
            sendExternalMessage({ ok = false, cmd = tostring(cmd),
                                  err = "sendExternalMessage failed: " .. S(serr) })
        end)
    end
end

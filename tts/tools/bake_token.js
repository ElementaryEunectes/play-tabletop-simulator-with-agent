// bake_token.js - insert the turn token INTO the save's ObjectStates array.
//
// WHY BAKED AND NOT SPAWNED (measured 2026-10-09): a mod's clickable pieces work because their
// LuaScript is part of the save and initialises with the object at load. Creating a piece at runtime
// and attaching the script afterwards (turn_token did exactly that) gets reverted by TTS - object and
// all - and the bridge's `act` refuses setLuaScript outright. So the token is written into the save
// the same way the mod's own pieces are.
//
// Inputs:  <save.json> <outSave.json> <templateGuid> <resultFile>
// The token's Lua comes straight out of tts/lua/dsh_global.lua (between the TURN_TOKEN_LUA markers),
// so there is no third copy of it to drift.
// The token is a copy of an existing Custom_Tile's data (art, scale, grid flags) with its own GUID,
// a fixed position at the table centre, the DSH-TURN nickname and the token's Lua in LuaScript.
const fs = require('fs');
const path = require('path');

const [, , saveFile, outFile, templateGuid, resultFile] = process.argv;
if (!saveFile || !outFile || !templateGuid) {
    console.error('usage: node bake_token.js <save.json> <out.json> <templateGuid> [resultFile]');
    process.exit(2);
}
function finish(code, text) {
    if (resultFile) fs.writeFileSync(resultFile, text + '\n', 'utf8');
    console.log(text);
    process.exit(code);
}

const save = JSON.parse(fs.readFileSync(saveFile, 'utf8'));
const bridge = fs.readFileSync(path.join(__dirname, '..', 'lua', 'dsh_global.lua'), 'utf8').replace(/\r\n/g, '\n');
const lm = /TURN_TOKEN_LUA = \[==\[\n([\s\S]*?)\n\]==\]/.exec(bridge);
if (!lm) finish(2, 'RESULT=FAIL TURN_TOKEN_LUA not found in dsh_global.lua');
const tokenLua = lm[1];
if (tokenLua.length < 100) finish(2, 'RESULT=FAIL token lua looks empty (' + tokenLua.length + ')');

const states = save.ObjectStates || [];
const template = states.find((o) => o.GUID === templateGuid);
if (!template) finish(2, 'RESULT=FAIL template guid not found in save: ' + templateGuid);

// An 8-hex GUID in the same shape TTS uses. Collisions are checked against the whole file.
function newGuid(taken) {
    for (let i = 0; i < 500; i++) {
        const g = Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, '0').slice(0, 6);
        if (!taken.has(g)) return g;
    }
    throw new Error('could not find a free guid');
}
const taken = new Set();
const collect = (o) => { if (o && o.GUID) taken.add(o.GUID); (o && o.ContainedObjects || []).forEach(collect); };
states.forEach(collect);
const guid = newGuid(taken);

const token = JSON.parse(JSON.stringify(template));
token.GUID = guid;
// BOTH fields carry the marker. TTS stores the token's visible label in Name (a live index shows
// "DSH-TURN 0" as the object's NAME, not its nickname), so a token with Name="Custom_Tile" is
// invisible to findTurnToken - which is exactly why it kept making new tokens (2026-10-09).
token.Name = 'DSH-TURN 0';
token.Nickname = 'DSH-TURN 0';
token.Description = 'DSH turn token - click it to record a turn (nickname becomes DSH-TURN <n>)';
token.LuaScript = tokenLua;
token.LuaScriptState = '';
token.XmlUI = '';
token.Transform = Object.assign({}, template.Transform, {
    posX: 0, posY: 1.16, posZ: 0,
    rotX: 0, rotY: 180, rotZ: 180,
});
// keep the tokens/states a copy of a template would drag along out of it
delete token.ContainedObjects;
delete token.States;

states.push(token);
save.ObjectStates = states;

fs.writeFileSync(outFile, JSON.stringify(save), 'utf8');
finish(0, 'RESULT=OK guid=' + guid + ' template=' + templateGuid +
          ' objects=' + (states.length - 1) + '->' + states.length +
          ' lua=' + tokenLua.length + ' nick=' + token.Nickname);

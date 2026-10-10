// insert_token.js - put the turn token into a save by TEXT insertion, keeping TTS's own formatting.
//
// WHY NOT REPLACE THE TOKEN OBJECT (measured 2026-10-10): install_save2.ps1 re-serialises the whole
// save with PowerShell's JavaScriptSerializer, which collapses it to ONE line, while TTS writes its
// own saves one object per line (38,956 lines for this table). Tokens baked that way were present in
// the file and then simply GONE after the game loaded it - twice, with two different tokens - while
// the plain string written into TabStates survived. So this tool never re-serialises: it clones a
// template object that is already in the file, edits that JSON text, and splices it in.
//
//   node tts/tools/insert_token.js <save.json> <out.json> <templateGuid> [guid]
const fs = require('fs');
const path = require('path');

const [, , saveFile, outFile, templateGuid, wantGuid] = process.argv;
if (!saveFile || !outFile || !templateGuid) {
    console.error('usage: node insert_token.js <save.json> <out.json> <templateGuid> [guid]');
    process.exit(2);
}

const rawIn = fs.readFileSync(saveFile, 'utf8');
const save = JSON.parse(rawIn);

// TTS writes its saves one object per line; PowerShell's serializer - which the bridge installer
// uses - collapses the whole file onto one line. Re-expand it first, or the splice below has no
// per-object line to work with (and the compact form is the very shape whose tokens vanished).
let raw = rawIn;
if (rawIn.split('\n').length < 20) {
    raw = JSON.stringify(save, null, 2);
    console.log('note: input was single-line; re-expanded to TTS-style formatting');
}

// the token's Lua comes out of the bridge, so there is no second copy of it
const bridge = fs.readFileSync(path.join(__dirname, '..', 'lua', 'dsh_global.lua'), 'utf8').replace(/\r\n/g, '\n');
const lm = /TURN_TOKEN_LUA = \[==\[\n([\s\S]*?)\n\]==\]/.exec(bridge);
if (!lm) { console.error('TURN_TOKEN_LUA not found in dsh_global.lua'); process.exit(2); }

// Locate the template's own text in the file: TTS writes one object per line, indented.
const states = save.ObjectStates || [];
if (!states.some((o) => o.GUID === templateGuid)) { console.error('template not in ObjectStates: ' + templateGuid); process.exit(2); }

// IDEMPOTENT: drop any token a previous run put here. Running this twice used to leave two tokens
// on the table - the same pile-up that made an earlier bake confusing (measured 2026-10-10).
const before = states.length;
save.ObjectStates = states.filter((o) => !/^DSH-TURN/.test(String(o.Name || '')) && !/^DSH-TURN/.test(String(o.Nickname || '')));
const removed = before - save.ObjectStates.length;
if (removed > 0) console.log('note: removed ' + removed + ' existing turn token(s) before inserting');

// every guid in the file, so the new one cannot collide
const used = new Set();
(function walk(list) {
    for (const o of list || []) {
        if (o && o.GUID) used.add(o.GUID);
        walk(o && o.ContainedObjects);
        if (o && o.States) walk(Object.keys(o.States).map((k) => o.States[k]));
    }
})(states);

function pickGuid() {
    if (wantGuid && !used.has(wantGuid)) return wantGuid;
    for (let i = 0; i < 2000; i++) {
        const g = Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, '0');
        if (!used.has(g)) return g;
    }
    throw new Error('no free guid');
}
const guid = pickGuid();

// Take the template as an OBJECT from the parsed save (not from a text line: JSON.stringify with an
// indent puts every FIELD on its own line, so "one object per line" only holds for TTS's own writer).
const tpl = states.find((o) => o.GUID === templateGuid && !o.ContainedObjects && !o.States);
if (!tpl) { console.error('no such top-level template object: ' + templateGuid); process.exit(2); }

const obj = JSON.parse(JSON.stringify(tpl));
obj.GUID = guid;
obj.Name = 'DSH-TURN 0';
obj.Nickname = 'DSH-TURN 0';
obj.Description = 'DSH turn token - click it to record a turn';
obj.LuaScript = lm[1];
obj.LuaScriptState = '';
obj.XmlUI = '';
obj.Transform = Object.assign({}, obj.Transform, { posX: 0, posY: 1.16, posZ: 0, rotX: 0, rotY: 180, rotZ: 180 });
delete obj.ContainedObjects;
delete obj.States;

states.push(obj);
save.ObjectStates = states;
// Write the whole save back in TTS's own shape (2-space indent). Never the compact one-line form:
// that is the shape whose tokens disappeared on load.
fs.writeFileSync(outFile, JSON.stringify(save, null, 2), 'utf8');

// verify by re-parsing the written file
const check = JSON.parse(fs.readFileSync(outFile, 'utf8'));
const found = (check.ObjectStates || []).filter((o) => o.GUID === guid);
if (found.length !== 1) { console.error('VERIFY FAILED: token not found after write'); process.exit(1); }
console.log('RESULT=OK guid=' + guid + ' template=' + templateGuid +
            ' objects=' + states.length + ' lua=' + lm[1].length);

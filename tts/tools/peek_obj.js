// peek_obj.js - print one saved object entry from a TTS save so a token can be modelled on it.
// WHY: the turn token has to be BAKED into the save (its LuaScript must exist at load time, like a
// mod's own buttons): creating it at runtime and attaching the script gets reverted by TTS.
//   node tts/tools/peek_obj.js <save.json> [Name]
const fs = require('fs');

const file = process.argv[2];
const wantName = process.argv[3] || 'Custom_Tile';
const raw = fs.readFileSync(file, 'utf8');
const save = JSON.parse(raw);

const states = save.ObjectStates || [];
console.log('top-level ObjectStates: ' + states.length);
console.log('SaveName: ' + save.SaveName);

function keys(o) { return Object.keys(o).sort().join(','); }
const seenTypes = {};
for (const s of states) {
    const n = s.Name || '(none)';
    seenTypes[n] = (seenTypes[n] || 0) + 1;
}
console.log('Name histogram of top-level objects: ' + JSON.stringify(seenTypes));

const hit = states.find((s) => s.Name === wantName);
if (!hit) {
    console.log('no top-level object named ' + wantName + ' - showing the first one instead');
    console.log(JSON.stringify(states[0], null, 2).slice(0, 1600));
} else {
    console.log('--- ' + wantName + ' : all fields ---');
    console.log('fields: ' + keys(hit));
    console.log(JSON.stringify(hit, null, 2).slice(0, 2200));
}

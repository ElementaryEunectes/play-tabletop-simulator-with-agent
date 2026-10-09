// compare_index.js - which objects the SAVE has but the bridge's live scan does not return?
// WHY: the baked token exists (readable by guid) yet findTurnToken, which walks getObjects(), never
// sees it - and live_index counted 116 while the save holds 117. This lists the difference by guid
// and nickname so the pattern is visible instead of guessed.
//   node tts/tools/compare_index.js <save.json> <live.csv>
const fs = require('fs');

const [, , saveFile, liveCsv] = process.argv;
const save = JSON.parse(fs.readFileSync(saveFile, 'utf8'));

const saveRows = [];
function walk(list) {
    for (const o of list || []) {
        if (o && o.GUID) saveRows.push({ guid: o.GUID, name: o.Name || '', nick: o.Nickname || '' });
        walk(o.ContainedObjects);
        if (o && o.States) walk(Object.keys(o.States).map((k) => o.States[k]));
    }
}
walk(save.ObjectStates);

const live = new Set();
const csv = fs.readFileSync(liveCsv, 'utf8').split('\n').slice(1);
for (const line of csv) {
    const m = /^"?([0-9a-f]{6,8})"?/.exec(line.trim());
    if (m) live.add(m[1]);
}

const missing = saveRows.filter((r) => !live.has(r.guid));
console.log('save objects: ' + saveRows.length + ' (incl. nested), live scan saw: ' + live.size);
console.log('in the save but NOT in the live scan: ' + missing.length);
for (const m of missing.slice(0, 40)) console.log('  ' + m.guid + '  ' + m.name + '  nick=' + JSON.stringify(m.nick));

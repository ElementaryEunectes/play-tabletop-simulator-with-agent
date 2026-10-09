// script_anatomy.js - compare the scripts of the save's own objects with the baked token's.
// WHY: the baked token's onClick never fires. Before guessing, look at what the objects whose
// scripts DO run have that this one has not. Inputs: <save.json> [guidFilter]
const fs = require('fs');

const [, , saveFile, filter] = process.argv;
const save = JSON.parse(fs.readFileSync(saveFile, 'utf8'));

function walk(list, out, parent) {
    for (const o of list || []) {
        if (o) out.push({ o, parent: parent });
        walk(o.ContainedObjects, out, o.GUID || parent);
        if (o.States) walk(Object.keys(o.States).map((k) => o.States[k]), out, o.GUID || parent);
    }
}
const all = [];
walk(save.ObjectStates, all, '');
console.log('objects walked: ' + all.length);

const withScript = all.filter((e) => e.o.LuaScript && String(e.o.LuaScript).trim() !== '');
console.log('objects with a non-empty LuaScript: ' + withScript.length);

const show = (e, label) => {
    const o = e.o;
    const s = String(o.LuaScript);
    console.log('\n===== ' + label + '  name=' + o.Name + ' guid=' + o.GUID + ' nick=' + JSON.stringify(o.Nickname));
    console.log('  script chars=' + s.length + '  LuaScriptState=' + JSON.stringify(String(o.LuaScriptState || '').slice(0, 40)));
    console.log('  has onClick=' + /function\s+onClick/.test(s) + '  has onLoad=' + /function\s+onLoad/.test(s) +
                '  uses self=' + /\bself\b/.test(s) + '  XMLUI chars=' + String(o.XmlUI || '').length);
    console.log('  first line: ' + JSON.stringify(s.split('\n')[0].slice(0, 90)));
};

if (filter) {
    for (const e of all) if ((e.o.GUID || '') === filter) show(e, 'REQUESTED');
}
// a script that actually runs: the mod's hand counter is known to work
const counter = all.find((e) => e.o.Nickname && /counter/i.test(e.o.Nickname) && e.o.LuaScript);
if (counter) show(counter, 'WORKING (mod counter)');
const tok = all.find((e) => /DSH-TURN/.test(String(e.o.Nickname || '')));
if (tok) show(tok, 'OUR TOKEN');

// do any of the mod's scripts hook onClick at all?
const onClicks = withScript.filter((e) => /function\s+onClick/.test(String(e.o.LuaScript))).length;
const selfs = withScript.filter((e) => /\bself\./.test(String(e.o.LuaScript))).length;
console.log('\nof those scripts: ' + onClicks + ' define onClick, ' + selfs + ' use self.');

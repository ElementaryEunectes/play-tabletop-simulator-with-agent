// bisect_run.js - find WHERE the bridge chunk's execution jumps by throwing a marker error at
// chosen lines and seeing whether the chunk gets that far.
//
// WHY: a Lua VM running the game's own bytes reports hand=function but takeOne/players=nil, and
// checkpoints showed the chunk runs code AFTER the handler table while skipping lines BEFORE it -
// in one chunk, in order. Instead of debating Lua semantics, walk a marker down: replace line N with
// error("AT n"), run, and see whether the failure is "AT n" (reached) or something later/earlier.
// One-off: deleted after use.
const fs = require('fs');
const { execFileSync } = require('child_process');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, '..', 'tests', 'gen_bridge_alone.lua'), 'utf8');
const lines = src.split('\n');
const candidate = Number(process.argv[2] || 0);
if (!candidate) { console.error('usage: node bisect_run.js <line>'); process.exit(2); }

// only swap a line that is a plain statement at column 0 (safe to replace with a throw)
const target = lines[candidate - 1];
if (!target || /^\s/.test(target)) { console.error('line ' + candidate + ' is indented or empty: ' + JSON.stringify(target)); process.exit(2); }
const probe = lines.slice();
probe[candidate - 1] = 'error("REACHED ' + candidate + '")';
const tmp = path.join(__dirname, '..', 'tests', '_bisect.lua');
fs.writeFileSync(tmp, probe.join('\n'), 'utf8');

let out = '';
try { out = execFileSync('node', [path.join(__dirname, 'run_lua.js'), tmp], { encoding: 'utf8', timeout: 120000 }); }
catch (e) { out = String((e.stdout || '') + (e.stderr || '')); }
fs.unlinkSync(tmp);
const reached = out.includes('REACHED ' + candidate);
console.log('line ' + candidate + ' = ' + reached + '   (' + JSON.stringify(target.slice(0, 50)) + ')');
if (!reached) console.log('  chunk failed with: ' + (out.split('\n').filter((l) => l.includes('ERROR') || l.includes('error')).slice(0, 2).join(' | ')));

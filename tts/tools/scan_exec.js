// scan_exec.js - which top-level lines of the generated bridge chunk actually execute?
// WHY: F8 looks like "the definition ran but the name is nil". Marks answer the factual half:
// instrument every column-0 statement that ends a unit with a table insert, run once, print the hits.
// Reports IN and NOT-IN explicitly, because a line that merely fails to print is too easy to misread
// (that is exactly the mistake this case is made of).
//   node tts/tools/scan_exec.js [fromLine] [toLine]
// One-off helper; safe to delete.
const fs = require('fs');
const path = require('path');

const FILE = path.join(__dirname, '..', 'tests', 'gen_bridge_alone.lua');
const from = Number(process.argv[2] || 1);
const to = Number(process.argv[3] || 100000);

const src = fs.readFileSync(FILE, 'utf8').replace(/\r\n/g, '\n');
const lines = src.split('\n');
const marks = [];
// Track brace depth so we never instrument a line inside a table constructor (that produced
// "'}' expected" - the same class of self-inflicted false signal this whole case is about).
const depth = new Array(lines.length).fill(0);
let d = 0;
for (let i = 0; i < lines.length; i++) {
    depth[i] = d;
    const code = lines[i].replace(/--.*$/, '');           // drop comments (no long strings here)
    const open = (code.match(/\{/g) || []).length;
    const close = (code.match(/\}/g) || []).length;
    d += open - close;
    if (d < 0) d = 0;
}
for (let i = 0; i < lines.length; i++) {
    const n = i + 1;
    if (n < from || n > to) continue;
    const t = lines[i];
    if (/^\s/.test(t)) continue;                       // only column-0 lines
    if (/^\s*$/.test(t)) continue;
    if (/^\s*--/.test(t)) continue;
    if (depth[i] !== 0) continue;                      // inside a table constructor
    if (/^\s*(end|else|elseif|until)\b/.test(t)) continue;
    marks.push(n);
}

const probe = lines.slice();
for (const n of marks) probe[n - 1] = '__M[' + n + ']=true; ' + lines[n - 1];
// the chunk ends with os.exit; neutralise it so the report below always runs
for (let i = 0; i < probe.length; i++) probe[i] = probe[i].replace(/^(\s*)os\.exit\(([^)]*)\)/, '$1__EXITCODE = $2');
probe.unshift('__M = {}');
probe.unshift('__EXITCODE = 0');
// report from inside the chunk itself, so the answer does not depend on catching the child's stdout.
// error(msg, 0) is the channel: this VM has no io library, and the message reaches stderr, which
// run_and_capture.js mirrors into a file.
probe.push('do');
probe.push('    local __in, __notin = {}, {}');
probe.push('    for _, n in ipairs(__SCAN) do');
probe.push('        if __M[n] then __in[#__in+1] = n else __notin[#__notin+1] = n end');
probe.push('    end');
probe.push('    error("SCANRESULT IN=" .. table.concat(__in, ",") .. " NOTIN=" .. table.concat(__notin, ","), 0)');
probe.push('end');
probe.unshift('__SCAN = {' + marks.join(',') + '}');
const tmp = path.join(__dirname, '..', 'tests', '_scan.lua');
fs.writeFileSync(tmp, probe.join('\n'), 'utf8');

const outFile = path.join(__dirname, '..', '..', 'local', 'scratch', 'scan_stdout.txt');
const run = require('child_process').spawnSync(process.execPath, [path.join(__dirname, 'run_and_capture.js'), tmp, outFile], { stdio: 'ignore' });
const txt = fs.existsSync(outFile) ? fs.readFileSync(outFile, 'utf8') : '';
const hit = txt.match(/SCANRESULT IN=([\d,]*) NOTIN=([\d,]*)/);
console.log('instrumented ' + marks.length + ' column-0 statements in ' + from + '..' + to);
if (hit) {
    console.log('IN     : ' + (hit[1] || '(none)'));
    console.log('NOT-IN : ' + (hit[2] || '(none)'));
} else {
    console.log('(no SCANRESULT - the chunk died before the report; see ' + outFile + ')');
}
console.log('spawn status=' + run.status);
fs.unlinkSync(tmp);
process.exit(0);

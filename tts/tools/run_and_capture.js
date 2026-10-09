// run_and_capture.js <luaFile> <outFile> - run a Lua file under fengari and put its stdout in a file.
//
// WHY: under the DSH Windows sandbox a Node process cannot capture another process's piped stdio
// (EPERM), and `execFileSync` then throws with empty stdout AND empty stderr - which reads exactly
// like "the child printed nothing". That false signal already cost a round here. So: write results
// to a file, and never trust missing output as evidence.
// One-off helper; safe to delete.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const luaFile = process.argv[2];
const outFile = process.argv[3];
if (!luaFile || !outFile) { console.error('usage: node run_and_capture.js <luaFile> <outFile>'); process.exit(2); }

const fd = fs.openSync(outFile, 'w');
const r = spawnSync(process.execPath, [path.join(__dirname, 'run_lua.js'), luaFile], {
    stdio: ['ignore', fd, fd],   // inherit-style: no pipe, so the sandbox does not deny it
    timeout: 180000,
});
fs.closeSync(fd);
fs.appendFileSync(outFile, '\n__EXIT=' + r.status + ' err=' + (r.error ? String(r.error.code || r.error) : 'none') + '\n');
console.log('wrote ' + outFile + ' (' + fs.statSync(outFile).size + ' bytes, status=' + r.status + ')');

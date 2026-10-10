// eol_check2.js - line endings of a git blob, read from a file git wrote (no pipes: this sandbox
// cannot capture child stdout - the project's run_and_capture.js exists for the same reason).
//
//   node local/scratch/eol_check2.js <repo> <rev> <file> <outfile>
const fs = require('fs');
const { execFileSync } = require('child_process');
const [repo, rev, file, out] = process.argv.slice(2);
execFileSync('git', ['show', `${rev}:${file}`], { cwd: repo, stdio: ['ignore', fs.openSync(out, 'w'), 'ignore'] });
const buf = fs.readFileSync(out);
let crlf = 0, lf = 0;
for (let i = 0; i < buf.length; i++) if (buf[i] === 10) { if (i > 0 && buf[i - 1] === 13) crlf++; else lf++; }
const crypto = require('crypto');
const body = buf.toString('utf8').replace(/\r\n/g, '\n');
console.log(`${rev}:${file}  CRLF=${crlf} LF=${lf} len=${buf.length} hash=${crypto.createHash('sha256').update(body).digest('hex').slice(0, 12)}`);

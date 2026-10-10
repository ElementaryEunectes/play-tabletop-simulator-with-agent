// cmp_eol.js - compare a git blob against the worktree file after normalising line endings only.
// Prints both normalised hashes and whether they are identical. Uses files, not pipes (sandbox).
const fs = require('fs');
const { execFileSync } = require('child_process');
const crypto = require('crypto');
const [repo, rev, file, tmp] = process.argv.slice(2);
execFileSync('git', ['show', `${rev}:${file}`], { cwd: repo, stdio: ['ignore', fs.openSync(tmp, 'w'), 'ignore'] });
const norm = (b) => crypto.createHash('sha256').update(b.toString('utf8').replace(/\r\n/g, '\n')).digest('hex');
const a = norm(fs.readFileSync(tmp));
const b = norm(fs.readFileSync(require('path').join(repo, file)));
console.log(`${rev}: ${a}`);
console.log(`worktree: ${b}`);
console.log(a === b ? 'IDENTICAL after EOL normalisation' : 'DIFFERENT - content changed too');

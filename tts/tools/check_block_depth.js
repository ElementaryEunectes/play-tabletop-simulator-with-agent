// check_block_depth.js <file.lua> [from] [to] - is every Lua block opener matched, and at what depth
// is each column-0 line?
//
// WHY THIS EXISTS (F8, 2026-10-09): the v14 primitives block was spliced INTO setCount(), between its
// last statement and its own `return out` / `end`. One missing `end` and one stray `end` later kept
// the TOTAL balanced, so the chunk compiled and loaded happily - while 250 lines had silently become
// the body of a function that only runs when that function is called. Every registered handler name
// was then nil. Depth per line shows exactly where scope went wrong; a load-time error does not,
// because there is no load-time error.
//
// Two counts, deliberately: `then` is a reliable depth marker (every `if`/`elseif` contributes one,
// and `else` contributes none), while an `if`-based count would double-count `elseif`. When the two
// disagree, the disagreement itself is the signal.
//
// WHAT THIS CANNOT SEE: a balanced splice. F8's actual damage was one `end` too few in one place
// and one too many in another - net zero, so every count here is happy while 250 lines are nested in
// the wrong function. Unbalanced counts catch mangled edits; `verify_f8.js` catches the balanced
// kind, by asking whether each definition is reachable after load. Run both.
//
//   node tts/tools/check_block_depth.js tts/lua/dsh_global.lua 1530 1560
//   exit 0 = the chunk balances; exit 1 = an opener is never closed
const fs = require('fs');
const path = require('path');

const file = process.argv[2];
if (!file) { console.error('usage: node check_block_depth.js <file.lua> [from] [to]'); process.exit(2); }
const from = Number(process.argv[3] || 1);
const to = Number(process.argv[4] || 1e9);

let text = fs.readFileSync(file, 'utf8');
if (text[0] === '\ufeff') text = text.slice(1);
const lines = text.replace(/\r\n/g, '\n').split('\n');

// tokenise: whole words only, with quoted strings, long strings and comments removed.
// ⚠️ `[[` is only a long-string opener when nothing identifier-like precedes it: `hist[names[i]]`
// is table indexing, and treating it as a long string made this tool eat the rest of the line and
// then report a healthy file as 27 openers short. A tool that misreports poisons the judgement it
// exists to support, so the guard is written out rather than assumed.
function tokens(line) {
    const out = [];
    let i = 0;
    const s = line.replace(/--\[\[[\s\S]*?\]\]/g, ' ').replace(/--.*$/, '');
    while (i < s.length) {
        const c = s[i];
        // `i++` twice on a backslash: ONE step lands on the quote and ends the string early, and the
        // rest of the line is then read as code. "\n" alone did that. A desynced tokeniser reports a
        // healthy file as unbalanced, so this is spelled out.
        if (c === '"' || c === "'") { const q = c; i++; while (i < s.length && s[i] !== q) { if (s[i] === '\\') { i += 2; continue; } i++; } i++; continue; }
        if (s.startsWith('[[', i) && !/[\w\)\]]/.test(s[i - 1] || '')) {
            const j = s.indexOf(']]', i); i = j < 0 ? s.length : j + 2; continue;
        }
        const m = /^[A-Za-z_]\w*/.exec(s.slice(i));
        if (m) { out.push(m[0]); i += m[0].length; continue; }
        i++;
    }
    return out;
}

const tally = { function: 0, do: 0, then: 0, repeat: 0, end: 0, until: 0, ifs: 0, elseif: 0 };
let depth = 0;
const rows = [];
for (let n = 1; n <= lines.length; n++) {
    const line = lines[n - 1];
    if (n >= from && n <= to && /^[^\s]/.test(line) && line.trim() !== '' && !/^--/.test(line)) {
        rows.push([n, depth, line.slice(0, 52)]);
    }
    for (const t of tokens(line)) {
        // `then` is the depth marker for if/elseif: both carry exactly one, `else` carries none.
        if (t === 'function' || t === 'do' || t === 'then' || t === 'repeat') {
            depth++;
            tally[t]++;
        } else if (t === 'end' || t === 'until') {
            depth--;
            tally[t === 'until' ? 'until' : 'end']++;
        } else if (t === 'if') {
            tally.ifs++;
        } else if (t === 'elseif') {
            tally.elseif++;
        }
    }
    if (depth < 0) depth = 0;
}

console.log('file: ' + file + '  (' + lines.length + ' lines)');
for (const [n, d, t] of rows) console.log(String(n).padStart(5) + '  d=' + d + '  ' + t);

// An `elseif` opens with a `then` but closes with the SAME `end` as the `if` it belongs to, so a
// plain opener-minus-closer count is high by exactly the number of `elseif`s. Measured on two files
// that load and run: the raw surplus equalled the elseif count both times. Subtract it; that is the
// number that means "a block was left open".
const opens = tally.function + tally.do + tally.then + tally.repeat;
const closes = tally.end + tally.until;
const surplus = opens - closes;
const adjusted = surplus - tally.elseif;
console.log('openers: function=' + tally.function + ' do=' + tally.do + ' then=' + tally.then +
            ' repeat=' + tally.repeat + '  total=' + opens);
console.log('closers: end=' + tally.end + ' until=' + tally.until + '  total=' + closes);
console.log('if=' + tally.ifs + ' elseif=' + tally.elseif +
            '  (each elseif contributes a `then` but shares the if\'s `end`)');
console.log('surplus=' + surplus + '  minus elseif=' + tally.elseif + '  =>  unmatched openers: ' + adjusted);
console.log(adjusted === 0 ? 'BALANCED' : 'UNBALANCED: ' + adjusted + ' opener(s) never closed');
process.exit(adjusted === 0 ? 0 : 1);

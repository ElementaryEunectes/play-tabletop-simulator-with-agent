// i18n_mt_transformers.mjs - a translator for the TSV contract in tts\docs\I18N.md, backed by
// Transformers.js. Local, offline, zero token: no API, no key, nothing leaves the machine.
//
//   node i18n_mt_transformers.mjs --in text.tsv --out zh.tsv --local <modelRoot> [--model Xenova/opus-mt-en-zh] [--dtype q8] [--limit N]
//
// WHAT IT NEEDS (both outside this repository, on purpose - see I18N.md section 2):
//   * npm i @huggingface/transformers
//   * a local model directory, because huggingface.co is unreachable on some networks. Fetch it with a
//     pinned-IP downloader once, then this runs with no network at all. --local points at that root; the
//     layout is <root>/<owner>/<repo>/... which is what the fetch script writes.
//
// THE CONTRACT, HONOURED STRICTLY: read id/field/source/target; only rows whose target is EMPTY are
// translated, so a human's edits or a dictionary pass are never overwritten; every row comes back with
// its original id, field and source. Rows whose source is empty stay empty.
import fs from 'node:fs';
import path from 'node:path';
import { pipeline, env } from '@huggingface/transformers';

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : dflt;
}

const inPath = arg('in', '');
const outPath = arg('out', '');
const model = arg('model', 'Xenova/opus-mt-en-zh');
const dtype = arg('dtype', 'q8');
const localRoot = arg('local', '');
const limit = Number(arg('limit', '0'));

if (!inPath || !outPath) { console.error('usage: node i18n_mt_transformers.mjs --in <tsv> --out <tsv> [--local <dir>] [--model id] [--dtype q8] [--limit N]'); process.exit(2); }
if (!fs.existsSync(inPath)) { console.error('no such tsv: ' + inPath); process.exit(2); }

if (localRoot) {
  env.localModelPath = path.resolve(localRoot);
  env.allowRemoteModels = false;
}

const lines = fs.readFileSync(inPath, 'utf8').split(/\r?\n/);
const rows = lines.map((line) => {
  if (line === '' || line.startsWith('#')) return { raw: line };
  const c = line.split('\t');
  if (c.length < 3 || c[0] === 'id') return { raw: line };
  return { id: c[0], field: c[1], source: c[2], target: c.length >= 4 ? c[3] : '' };
});

const todo = rows.filter((r) => r.source !== undefined && r.source !== '' && r.target === '');
const work = limit > 0 ? todo.slice(0, limit) : todo;
console.log('rows ' + rows.length + ', translatable-with-empty-target ' + todo.length + (limit > 0 ? ' (limited to ' + work.length + ')' : ''));

if (work.length === 0) {
  fs.writeFileSync(outPath, lines.join('\n'), 'utf8');
  console.log('nothing to translate; copied through to ' + outPath);
  process.exit(0);
}

const t0 = Date.now();
const translator = await pipeline('translation', model, { dtype });
console.log('model ' + model + ' (' + dtype + ') ready in ' + ((Date.now() - t0) / 1000).toFixed(1) + ' s');

let done = 0;
const t1 = Date.now();
for (const r of work) {
  try {
    const out = await translator(r.source);
    const text = out[0].translation_text;
    // column 4 carries the same TSV escaping as column 3: tabs and newlines must not break the file
    r.target = text.replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\r/g, '\\r').replace(/\n/g, '\\n');
    done++;
  } catch (e) {
    console.error('  failed id ' + r.id + ': ' + String(e && e.message ? e.message : e));
  }
  if (done % 25 === 0 && done > 0) console.log('  ' + done + '/' + work.length + ' ...');
}
const secs = (Date.now() - t1) / 1000;

const outLines = rows.map((r) => {
  if (r.raw !== undefined) return r.raw;
  return r.id + '\t' + r.field + '\t' + r.source + '\t' + (r.target || '');
});
fs.writeFileSync(outPath, outLines.join('\n'), 'utf8');

console.log('translated ' + done + '/' + work.length + ' in ' + secs.toFixed(1) + ' s (' + (secs > 0 ? (done / secs).toFixed(1) : '0') + '/s, ' + (done > 0 ? Math.round(secs * 1000 / done) : 0) + ' ms each)');
console.log('wrote ' + outPath);
console.log('next  : tts\\tools\\i18n_apply.ps1 -In <that file> -Out <patched.json> [-Apply]');

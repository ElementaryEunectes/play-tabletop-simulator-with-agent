// Fetch the EMBEDDABLE Python zip - no installer, no registry, no admin, nothing outside the workspace.
//
// WHY NOT THE INSTALLER ANY MORE: python-3.12.10-amd64.exe exits with 0x80070005 (access denied) even with
// the sandbox widened - it wants to write outside the workspace and spawn helpers, and something (most
// likely the antivirus rule this repo already documents) refuses it. The embeddable zip unpacks into the
// workspace and touches nothing else.
//
// WHY THIS IS ENOUGH: measured 2026-10-14 - pypi.org answers 200 in 0.5 s, get-pip.py answers 200, so the
// OCR packages (rapidocr-onnxruntime / PaddleOCR) are reachable through it.
import https from 'node:https';
import fs from 'node:fs';

const url = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip';
const dest = 'cache/python-embed.zip';
const MB = 1048576;

function head(u) {
  return new Promise((res) => {
    https.get(u, { method: 'HEAD' }, (r) => { r.resume(); res(Number(r.headers['content-length'] || 0)); })
      .on('error', () => res(0));
  });
}

const total = await head(url);
let have = fs.existsSync(dest) ? fs.statSync(dest).size : 0;
if (have > total) { fs.unlinkSync(dest); have = 0; }
console.log('target ' + (total / MB).toFixed(2) + ' MB, starting at ' + (have / MB).toFixed(2) + ' MB');

for (let attempt = 1; attempt <= 40 && have < total; attempt++) {
  const before = have;
  await new Promise((resolve) => {
    const opts = { headers: have > 0 ? { Range: 'bytes=' + have + '-' } : {} };
    const req = https.get(url, opts, (res) => {
      if (res.statusCode !== 200 && res.statusCode !== 206) { res.resume(); resolve(); return; }
      const out = fs.createWriteStream(dest, { flags: 'a' });
      res.pipe(out);
      res.on('error', () => out.close(() => resolve()));
      out.on('finish', () => out.close(() => resolve()));
    });
    req.on('error', () => resolve());
    req.setTimeout(60000, () => { req.destroy(); resolve(); });
  });
  have = fs.existsSync(dest) ? fs.statSync(dest).size : 0;
  if (have === before) { await new Promise((r) => setTimeout(r, 1500)); }
  console.log('  attempt ' + attempt + ': ' + (have / MB).toFixed(2) + ' MB');
}
console.log(have >= total ? 'COMPLETE ' + (have / MB).toFixed(2) + ' MB' : 'INCOMPLETE ' + (have / MB).toFixed(2) + ' MB');
process.exit(have >= total ? 0 : 1);

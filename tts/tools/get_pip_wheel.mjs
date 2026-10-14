// Download the newest pip wheel (resumable) to cache/pip.whl.
//
// WHY A WHEEL: get-pip.py unpacks itself into a temp dir and hits PermissionError there - measured twice,
// including after pointing TMP/TEMP into the workspace, while plain Python file writes inside the
// workspace work fine. A wheel IS a zip, so unzip it into Lib\site-packages and pip is installed.
//
// NOTE ON THE REGEX: PyPI's simple page links carry a #sha256=... fragment, so matching href="....whl"
// with nothing after it finds ZERO entries (measured).
import https from 'node:https';
import fs from 'node:fs';

const MB = 1048576;
const dest = 'cache/pip.whl';

function head(u) {
  return new Promise((res) => {
    https.get(u, { method: 'HEAD' }, (r) => { r.resume(); res(Number(r.headers['content-length'] || 0)); })
      .on('error', () => res(0));
  });
}

const html = await (await fetch('https://pypi.org/simple/pip/', { headers: { accept: 'text/html' } })).text();
const hrefs = [...html.matchAll(/href="([^"]+\.whl)(?:#[^"]*)?"/g)].map((m) => m[1]);
console.log('pip wheels listed: ' + hrefs.length);
if (!hrefs.length) { console.log('none found'); process.exit(1); }
const url = hrefs[hrefs.length - 1];
console.log('newest: ' + url.split('/').pop());
const total = await head(url);
console.log('size: ' + (total / MB).toFixed(2) + ' MB');

let have = fs.existsSync(dest) ? fs.statSync(dest).size : 0;
if (have > total) { fs.unlinkSync(dest); have = 0; }
for (let attempt = 1; attempt <= 30 && have < total; attempt++) {
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
console.log(have >= total ? 'COMPLETE' : 'INCOMPLETE');
process.exit(have >= total ? 0 : 1);

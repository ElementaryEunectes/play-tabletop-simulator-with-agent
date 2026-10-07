// fetch_pdf.js - download a URL to a file using Node's own TLS stack.
// WHY NODE: in this sandbox curl.exe and Invoke-WebRequest both fail with TLS credential errors
// (schannel: SEC_E_NO_CREDENTIALS); Node bundles its own TLS/CA stack and works (npm proves it).
// ASCII only. Usage: node fetch_pdf.js <url> <outfile> [maxRedirects]
const https = require('https');
const fs = require('fs');
const path = require('path');

const url = process.argv[2];
const out = process.argv[3];
let hops = parseInt(process.argv[4] || '3', 10);
if (!url || !out) { console.log('usage: node fetch_pdf.js <url> <outfile> [maxRedirects]'); process.exit(2); }

function get(u, cb) {
  https.get(u, (res) => {
    if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && hops-- > 0) {
      res.resume();
      const next = new URL(res.headers.location, u).toString();
      console.log('redirect ->', next);
      return get(next, cb);
    }
    cb(res);
  }).on('error', (e) => { console.log('ERR', e.message); process.exit(1); });
}

get(url, (res) => {
  console.log('status', res.statusCode, 'type', res.headers['content-type'], 'len', res.headers['content-length']);
  if (res.statusCode !== 200) { res.resume(); console.log('FAIL non-200'); process.exit(1); }
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const f = fs.createWriteStream(out);
  res.pipe(f);
  f.on('finish', () => {
    f.close();
    const size = fs.statSync(out).size;
    const head = fs.readFileSync(out, { encoding: 'latin1', flag: 'r' }).slice(0, 8);
    console.log('saved', out, size, 'bytes  magic=', JSON.stringify(head.slice(0, 5)));
    process.exit(0);
  });
});

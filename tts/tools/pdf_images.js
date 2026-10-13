// pdf_images.js - carve the embedded JPEGs out of an image-only PDF, one file per page.
// ASCII only. WHY: one image-only board-game mod's rulebook in the TTS save has NO text layer (15 pages, 351
// characters total), so text extraction is a dead end and OCR/VLM is the expensive last resort.
// But an image-only PDF is just a container of full-page JPEGs: SOI (FFD8FF) to EOI (FFD9)
// carving gets them out losslessly, and then the agent's own image reader can look at any page.
// Usage: node pdf_images.js <in.pdf> <outDir>
const fs = require('fs');
const path = require('path');

const src = process.argv[2];
const outDir = process.argv[3];
if (!src || !outDir) { console.log('usage: node pdf_images.js <in.pdf> <outDir>'); process.exit(2); }
const buf = fs.readFileSync(src);
fs.mkdirSync(outDir, { recursive: true });

let i = 0, n = 0;
const kept = [];
while (i < buf.length - 3) {
  if (buf[i] === 0xFF && buf[i + 1] === 0xD8 && buf[i + 2] === 0xFF) {
    let j = i + 2;
    while (j < buf.length - 1 && !(buf[j] === 0xFF && buf[j + 1] === 0xD9)) j++;
    if (j < buf.length - 1) {
      const len = j + 2 - i;
      if (len > 20000) {                      // skip thumbnails and stray markers
        n++;
        const f = path.join(outDir, 'p' + String(n).padStart(2, '0') + '.jpg');
        fs.writeFileSync(f, Buffer.from(buf.slice(i, j + 2)));
        kept.push({ f: path.basename(f), kb: Math.round(len / 1024) });
      }
      i = j + 2;
      continue;
    }
  }
  i++;
}
console.log('extracted', n, 'page image(s) to', outDir);
for (const k of kept) console.log('  ', k.f, k.kb + ' KB');

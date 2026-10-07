// validate_lua.js - parse a Lua file with luaparse and report syntax errors.
// Usage: node validate_lua.js <file.lua> [...]
const fs = require('fs');
const path = require('path');
const luaparse = require(path.join('C:', 'Users', '<user>', '.dsh', 'cache', 'luaparse', 'node_modules', 'luaparse'));

const files = process.argv.slice(2);
if (files.length === 0) { console.log('no files given'); process.exit(2); }

let bad = 0;
for (const f of files) {
  let src;
  try { src = fs.readFileSync(f, 'utf8'); }
  catch (e) { console.log(`READ FAIL ${f}: ${e.message}`); bad++; continue; }
  try {
    const ast = luaparse.parse(src, { luaVersion: '5.1', comments: false, scope: false, locations: true });
    // sanity: count top-level statements and find onExternalMessage
    const names = [];
    for (const st of ast.body) {
      if (st.type === 'FunctionDeclaration' && st.identifier) names.push(st.identifier.name);
      if (st.type === 'Assignment') {
        for (const v of (st.variables || [])) {
          if (v.type === 'Identifier') names.push(v.name);
        }
      }
    }
    const hasOEM = names.includes('onExternalMessage');
    console.log(`OK    ${path.basename(f)}  chars=${src.length}  topLevelNames=${names.length}  onExternalMessage=${hasOEM}`);
  } catch (e) {
    bad++;
    console.log(`FAIL  ${path.basename(f)}  line=${e.line} col=${e.column}  ${e.message}`);
    const lines = src.split(/\r?\n/);
    for (let i = Math.max(0, (e.line || 1) - 3); i < Math.min(lines.length, (e.line || 1) + 2); i++) {
      console.log(`   ${String(i + 1).padStart(5)} | ${lines[i]}`);
    }
  }
}
process.exit(bad === 0 ? 0 : 1);

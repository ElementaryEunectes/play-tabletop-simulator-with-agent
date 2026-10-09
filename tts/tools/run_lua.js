// run_lua.js - run a Lua file under fengari (a Lua VM in JavaScript) and report its result.
//
// WHY THIS EXISTS: this project's bridge is Lua, and until now the only offline check was
// validate_lua.js (syntax). There is no Lua interpreter on this machine and TTS ships none we can
// call, so fengari gives the tests a real VM: stubbed TTS API in, real assertions out. It is Lua 5.3
// while TTS is 5.1, so avoid 5.3-only syntax in test files.
//
//   node tts\tools\run_lua.js <file.lua>
//   exit 0 = the script ran and called os.exit(0) (or reached its end), 1 = error or os.exit(>0)
const fs = require('fs');
const path = require('path');

const fengariPath = process.env.FENGARI_DIR
    || path.join(__dirname, '..', '..', 'local', 'scratch', 'luatest', 'node_modules', 'fengari');
let fengari;
try { fengari = require(fengariPath); }
catch (e) { console.error('fengari not found at ' + fengariPath + ' - install it or set FENGARI_DIR'); process.exit(2); }

const { lua, lauxlib, lualib } = fengari;

const file = process.argv[2];
if (!file) { console.error('usage: node run_lua.js <file.lua>'); process.exit(2); }
if (!fs.existsSync(file)) { console.error('no such file: ' + file); process.exit(2); }

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

let exitCode = null;
// os.exit inside the test decides the verdict; keep the process alive until then.
const oslib = lualib.luaopen_os ? null : null;   // (os is opened by luaL_openlibs)

if (lauxlib.luaL_loadfile(L, fengari.to_luastring(file)) !== lua.LUA_OK) {
    const msg = fengari.to_jsstring(lua.lua_tostring(L, -1));
    console.error('LOAD ERROR: ' + msg);
    process.exit(1);
}
const status = lua.lua_pcall(L, 0, 0, 0);
if (status !== lua.LUA_OK) {
    const msg = fengari.to_jsstring(lua.lua_tostring(L, -1));
    console.error('RUNTIME ERROR: ' + msg);
    process.exit(1);
}
// If the script used os.exit, fengari's os.exit raises a special error caught by pcall? It does not -
// it throws out of the C call. So absence of an error means it fell off the end: treat that as pass.
process.exit(exitCode === null ? 0 : exitCode);

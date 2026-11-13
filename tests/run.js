// Runs the addon files (in TOC order) inside fengari with a fake WoW client,
// then runs tests.lua. Usage: node tests/run.js
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const root = path.resolve(__dirname, '..');
const addonDir = path.join(root, 'RequiemLedger');
const toc = fs.readFileSync(path.join(addonDir, 'RequiemLedger.toc'), 'utf8');
const files = toc.split(/\r?\n/).map(l => l.trim()).filter(l => l && !l.startsWith('#'));

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function run(file, args) {
  const src = fs.readFileSync(file);
  if (lauxlib.luaL_loadbuffer(L, src, null, to_luastring('@' + path.relative(root, file))) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
  for (const a of args) a();
  if (lua.lua_pcall(L, args.length, 0, 0) !== lua.LUA_OK) {
    throw new Error(lua.lua_tojsstring(L, -1));
  }
}

try {
  run(path.join(__dirname, 'mock.lua'), []);
  lua.lua_newtable(L);
  lua.lua_setglobal(L, to_luastring('__RL'));
  for (const f of files) {
    run(path.join(addonDir, f.replace(/\\/g, '/')), [
      () => lua.lua_pushstring(L, to_luastring('RequiemLedger')),
      () => lua.lua_getglobal(L, to_luastring('__RL')),
    ]);
  }
  run(path.join(__dirname, 'tests.lua'), []);
} catch (e) {
  console.error(e.message);
  process.exit(1);
}

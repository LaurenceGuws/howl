import assert from 'node:assert/strict';
import fs from 'node:fs';

const host = fs.readFileSync('web/host.mjs', 'utf8');
const index = fs.readFileSync('web/index.html', 'utf8');
const serviceWorker = fs.readFileSync('web/sw.js', 'utf8');
const renderBuild = fs.readFileSync('build.zig', 'utf8');
const gateway = fs.readFileSync('../gateway/src/main.zig', 'utf8');

const imports = [...host.matchAll(/from\s+['"]\.\/([^'"]+)['"]/g)].map(match => match[1]);
const modules = [...new Set(['host.mjs', ...imports])].sort();
const shellBlock = serviceWorker.match(/const SHELL = \[(.*?)\];/s);
assert(shellBlock, 'service worker SHELL list is missing');
const shell = new Set([...shellBlock[1].matchAll(/'([^']+)'/g)].map(match => match[1]));

for (const module of modules) {
  const route = `/${module}`;
  assert(shell.has(route), `${module} is imported by the browser host but absent from the offline shell`);
  assert(renderBuild.includes(module), `${module} is imported by the browser host but absent from the render install graph`);
  assert(gateway.includes(`.target = "${route}"`), `${module} is imported by the browser host but absent from the gateway allowlist`);
}

assert(index.includes('id="zoom-button"'), 'browser shell must expose the native presentation zoom control');
assert(index.includes('id="selection-overlay"'), 'browser shell must expose the client-local selection overlay');
assert(index.includes('>16px</button>'), 'browser presentation zoom must boot at the normal 16px preset');
assert(host.includes('const presentationPixels = [16, 12, 9];'), 'browser presentation presets drifted from maintained native presets');
assert(host.includes("telemetry.record('presentation_zoom'"), 'browser presentation zoom must remain observable in telemetry');

for (const asset of ['nerd-font.bin', 'nerd-font-license.txt']) {
  const route = `/${asset}`;
  assert(shell.has(route), `${asset} is required by the browser host but absent from the offline shell`);
  assert(renderBuild.includes(asset), `${asset} is required by the browser host but absent from the render install graph`);
  assert(gateway.includes(`.target = "${route}"`), `${asset} is required by the browser host but absent from the gateway allowlist`);
}

console.log(JSON.stringify({status:'pass', browserModules:modules.length, offline:true, installed:true, gateway:true}));

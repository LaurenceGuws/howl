import assert from 'node:assert/strict';
import fs from 'node:fs';

const host = fs.readFileSync('web/host.mjs', 'utf8');
const index = fs.readFileSync('web/index.html', 'utf8');
const serviceWorker = fs.readFileSync('web/sw.js', 'utf8');
const frameV3 = fs.readFileSync('web/frame_v3.mjs', 'utf8');
const legacyWebgl = fs.readFileSync('web/webgl_backend.mjs', 'utf8');
const webglV3 = fs.readFileSync('web/webgl_backend_v3.mjs', 'utf8');
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

// v3 deliberately uses generation-specific module URLs. An older service
// worker may still fall back /host.mjs or /render.wasm from its shell, but it
// cannot substitute its v2 WebGL implementation for either new v3 module.
for (const route of ['/frame_v3.mjs', '/webgl_backend_v3.mjs', '/webgl_backend.mjs']) {
  assert(shell.has(route), `${route} must remain in the coherent current shell`);
  assert(renderBuild.includes(route.slice(1)), `${route} must remain in the render install graph`);
  assert(gateway.includes(`.target = "${route}"`), `${route} must remain in the gateway allowlist`);
}
assert(host.includes("from './frame_v3.mjs'"), 'v3 host must negotiate its renderer vocabulary');
assert(host.includes("from './webgl_backend_v3.mjs'"), 'v3 host must use a generation-specific WebGL module');
assert(!host.includes("from './webgl_backend.mjs'"), 'v3 host must not consume the legacy WebGL module');
assert(webglV3.includes("from './frame_v3.mjs'"), 'v3 WebGL backend must consume the shared positional contract');
assert(!legacyWebgl.includes("from './frame_v3.mjs'"), 'legacy WebGL URL must remain v2-compatible for an old host');
assert(legacyWebgl.includes('command.k'), 'legacy WebGL URL must retain the v2 object command vocabulary');
assert(frameV3.includes('rv_frame_format') && frameV3.includes('rv_set_frame_format'), 'v3 host contract must negotiate renderer format explicitly');
assert(frameV3.includes('rv_reset'), 'v3 frame mismatch must clear renderer pending-ack state');
assert(serviceWorker.includes("const CACHE = 'howl-web-canary-v44-web-frame-v3'"), 'v3 shell cache generation is not current');

assert(index.includes('id="zoom-button"'), 'browser shell must expose the native presentation zoom control');
assert(index.includes('id="selection-overlay"'), 'browser shell must expose the client-local selection overlay');
assert(index.includes('>16px</button>'), 'browser presentation zoom must boot at the normal 16px preset');
assert(host.includes('const presentationPixels = [16, 12, 9];'), 'browser presentation presets drifted from maintained native presets');
assert(host.includes('const presentationCellWidths = [10, 8, 6];'), 'browser cell widths drifted from maintained native presets');
assert(host.includes('const presentationLineHeights = [20, 15, 12];'), 'browser line heights drifted from maintained native presets');
assert(host.includes('rv_init_presentation'), 'browser renderer must expose explicit HiDPI presentation geometry');
assert(host.includes("telemetry.record('presentation_zoom'"), 'browser presentation zoom must remain observable in telemetry');

for (const asset of ['nerd-font.bin', 'nerd-font-license.txt']) {
  const route = `/${asset}`;
  assert(shell.has(route), `${asset} is required by the browser host but absent from the offline shell`);
  assert(renderBuild.includes(asset), `${asset} is required by the browser host but absent from the render install graph`);
  assert(gateway.includes(`.target = "${route}"`), `${asset} is required by the browser host but absent from the gateway allowlist`);
}

console.log(JSON.stringify({status:'pass', browserModules:modules.length, offline:true, installed:true, gateway:true}));

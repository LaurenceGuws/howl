import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {assertTextImports, createTextRuntime} from '../../text/web/runtime.mjs';
import {CommandV3Length, FRAME_SCHEMA_V3, parseRendererFrameV3, requireFrameV3, selectRendererFrameV3} from '../web/frame_v3.mjs';

const [wasmPath, primaryPath, fallbackPath, symbolPath] = process.argv.slice(2);
const binary = await readFile(wasmPath);
const module = await WebAssembly.compile(binary);
assertTextImports(module);
const [primary, fallback, symbol] = await Promise.all([
  readFile(primaryPath), readFile(fallbackPath), readFile(symbolPath),
]);
const corpus = JSON.parse(await readFile('../../howl-instance/protocol/v10-vectors.json', 'utf8'));
const vector = corpus.cases.find(value => value.id === 'snapshot_text_v1_complete');
assert.ok(vector?.hex);
const snapshot = Buffer.from(vector.hex, 'hex');
const decoder = new TextDecoder();

async function renderer() {
  const runtime = createTextRuntime({output:()=>{}});
  const instance = await WebAssembly.instantiate(module, runtime.imports);
  runtime.bind(instance.exports.memory);
  instance.exports._initialize?.();
  const w = instance.exports;
  const bytesAt = (pointer, length) => new Uint8Array(w.memory.buffer, Number(pointer), Number(length));
  for (const [font, pointer, capacity] of [
    [primary, w.rv_font_ptr(), w.rv_font_capacity()],
    [fallback, w.rv_fallback_font_ptr(), w.rv_fallback_font_capacity()],
    [symbol, w.rv_symbol_font_ptr(), w.rv_symbol_font_capacity()],
  ]) {
    assert.ok(font.length > 0 && font.length <= capacity);
    bytesAt(pointer, font.length).set(font);
  }
  assert.equal(w.rv_init(primary.length, fallback.length, symbol.length, 18), 1);
  assert.ok(snapshot.length <= w.rv_snapshot_capacity());
  return {w, bytesAt};
}

// A new renderer is deliberately backward-compatible until a new host opts in.
const legacy = await renderer();
assert.equal(legacy.w.rv_frame_format(), 2);
legacy.bytesAt(legacy.w.rv_snapshot_ptr(), snapshot.length).set(snapshot);
assert.equal(legacy.w.rv_render(snapshot.length), 1);
const v2 = JSON.parse(decoder.decode(legacy.bytesAt(legacy.w.rv_frame_ptr(), legacy.w.rv_frame_len())));
assert.equal(v2.schema, 'howl.web-frame/v2');
assert.ok(v2.commands.length > 0);
assert.ok(v2.commands.every(command => !Array.isArray(command) && Number.isInteger(command.k)));
assert.equal(legacy.w.rv_ack(), 1);
assert.equal(legacy.w.rv_set_frame_format(3), 0, 'format cannot change after the first rendered frame');

// A new host opts in before observation and receives only the compact v3 records.
const modern = await renderer();
assert.equal(modern.w.rv_frame_format(), 2);
assert.equal(modern.w.rv_set_frame_format(4), 0);
selectRendererFrameV3(modern.w);
modern.bytesAt(modern.w.rv_snapshot_ptr(), snapshot.length).set(snapshot);
assert.equal(modern.w.rv_render(snapshot.length), 1);
const v3 = requireFrameV3(JSON.parse(decoder.decode(modern.bytesAt(modern.w.rv_frame_ptr(), modern.w.rv_frame_len()))));
assert.equal(v3.schema, FRAME_SCHEMA_V3);
const widths = new Map([[0, CommandV3Length.solid], [1, CommandV3Length.alpha], [2, CommandV3Length.rgba]]);
assert.ok(v3.commands.length > 0);
for (const command of v3.commands) assert.equal(command.length, widths.get(command[0]));
assert.equal(modern.w.rv_ack(), 1);
assert.equal(modern.w.rv_reset(), 1);
assert.equal(modern.w.rv_frame_format(), 3, 'presentation reset preserves the negotiated host vocabulary');

// A new host paired with an old renderer refuses it before any render can occur.
let oldRenderCalls = 0;
assert.throws(() => selectRendererFrameV3({
  rv_render() { oldRenderCalls += 1; return 1; },
}), /does not support Web frame v3 negotiation/);
assert.equal(oldRenderCalls, 0);
assert.throws(() => requireFrameV3(v2), /incompatible Web frame schema/);
let mismatchResets = 0;
assert.throws(() => parseRendererFrameV3({rv_reset() { mismatchResets += 1; return 1; }}, JSON.stringify(v2)), /incompatible Web frame schema/);
assert.equal(mismatchResets, 1, 'schema mismatch must clear a staged renderer frame before failing');

console.log(JSON.stringify({
  status:'pass', legacyDefaultV2:true, modernOptInV3:true,
  resetPreservesV3:true, oldRendererRejectedBeforeRender:true, mismatchResets:true,
}));

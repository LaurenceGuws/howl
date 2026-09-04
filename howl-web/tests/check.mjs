// Independent byte-level assertions against the emitted Wasm boundary.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const bytes = await readFile(process.argv[2]);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const expected = ['memory', 'hw_input_ptr', 'hw_input_capacity', 'hw_output_ptr', 'hw_output_len',
  'hw_text_ptr', 'hw_text_len', 'hw_error_ptr', 'hw_error_len', 'hw_phase', 'hw_identity',
  'hw_revision', 'hw_rows', 'hw_columns', 'hw_reset', 'hw_observe', 'hw_send_text',
  'hw_feed', 'hw_finish', 'hw_canvas_check'].sort();
assert.deepEqual(WebAssembly.Module.exports(module).map(x => x.name).sort(), expected);
const w = (await WebAssembly.instantiate(module)).exports;
assert.equal(w.memory.buffer.byteLength, 32 * 1024 * 1024);
assert.throws(() => w.memory.grow(1), RangeError);
assert.equal(w.hw_canvas_check(), 0);
function feed(bytes) {
  assert.ok(bytes.length <= w.hw_input_capacity());
  new Uint8Array(w.memory.buffer, w.hw_input_ptr(), bytes.length).set(bytes);
  return w.hw_feed(bytes.length);
}
const welcome = Buffer.from('48574c530102000000000008000000000000002a', 'hex');
const hello = '48574c530101000000000000';
for (let split = 0; split <= welcome.length; split++) {
  assert.equal(w.hw_reset(), 1);
  assert.equal(Buffer.from(w.memory.buffer, w.hw_output_ptr(), w.hw_output_len()).toString('hex'), hello);
  assert.equal(feed(welcome.subarray(0, split)), 1);
  assert.equal(feed(welcome.subarray(split)), 1);
  assert.equal(w.hw_phase(), 2);
  assert.equal(w.hw_identity(), 42n);
  assert.equal(w.hw_finish(), 1);
}
w.hw_reset();
for (const byte of welcome) assert.equal(feed(Uint8Array.of(byte)), 1);
assert.equal(w.hw_identity(), 42n);
assert.equal(feed(welcome), 0); // unsolicited duplicate
assert.equal(w.hw_phase(), 99);
assert.equal(w.hw_reset(), 1);
assert.equal(w.hw_finish(), 0); // waiting for welcome is not a clean EOF
w.hw_reset();
assert.equal(feed(welcome.subarray(0, 19)), 1);
assert.equal(w.hw_finish(), 0);
for (const [offset, value] of [[0, 0], [4, 2], [6, 1]]) {
  w.hw_reset(); const bad = Buffer.from(welcome); bad[offset] = value;
  assert.equal(feed(bad), 0);
  assert.equal(w.hw_phase(), 99);
}
w.hw_reset();
const oversized = Buffer.from(welcome.subarray(0, 12));
oversized.writeUInt32BE(1024 * 1024 + 1, 8);
assert.equal(feed(oversized), 0);
w.hw_reset();
assert.equal(w.hw_feed(w.hw_input_capacity() + 1), 0);
feed(welcome);
assert.equal(w.hw_send_text(4097), 0);
new Uint8Array(w.memory.buffer, w.hw_input_ptr(), 1).set([255]);
assert.equal(w.hw_send_text(1), 0);
assert.equal(w.hw_observe(1), 1);
assert.equal(w.hw_observe(1), 0); // at most one outstanding operation
assert.equal(w.hw_send_text(1), 0);
console.log(JSON.stringify({status:'pass', wasmBytes:bytes.length, memoryBytes:w.memory.buffer.byteLength,
  imports:0, welcomeSplits:21, byteDelivery:true, rejectedInvalidFrames:true, canvasComposer:true}));

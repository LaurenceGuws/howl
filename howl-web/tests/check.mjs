// Independent byte-level assertions against the emitted Wasm boundary.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const bytes = await readFile(process.argv[2]);
const module = await WebAssembly.compile(bytes);
assert.deepEqual(WebAssembly.Module.imports(module), []);
const expected = ['memory', 'hw_input_ptr', 'hw_input_capacity', 'hw_output_ptr', 'hw_output_len',
  'hw_text_ptr', 'hw_text_len', 'hw_text_truncated', 'hw_snapshot_ptr', 'hw_snapshot_len', 'hw_error_ptr', 'hw_error_len', 'hw_phase', 'hw_identity',
  'hw_revision', 'hw_terminal_revision', 'hw_rows', 'hw_columns', 'hw_history_offset', 'hw_history_count', 'hw_history_row_base', 'hw_alternate_screen', 'hw_leader_present', 'hw_last_result_code', 'hw_control_ready', 'hw_reset', 'hw_observe', 'hw_send_text', 'hw_send_paste',
  'hw_send_named_key', 'hw_send_unicode_key', 'hw_send_focus', 'hw_send_mouse', 'hw_send_resize', 'hw_send_resize_owned',
  'hw_feed', 'hw_finish', 'hw_canvas_check'].sort();
assert.deepEqual(WebAssembly.Module.exports(module).map(x => x.name).sort(), expected);
const w = (await WebAssembly.instantiate(module)).exports;
assert.equal(w.memory.buffer.byteLength, 32 * 1024 * 1024);
assert.throws(() => w.memory.grow(1), RangeError);
assert.equal(w.hw_canvas_check(), 0);
assert.equal(w.hw_text_truncated(), 0);
assert.equal(w.hw_leader_present(), 0);
function feed(bytes) {
  assert.ok(bytes.length <= w.hw_input_capacity());
  new Uint8Array(w.memory.buffer, w.hw_input_ptr(), bytes.length).set(bytes);
  return w.hw_feed(bytes.length);
}
const welcome = Buffer.from('48574c530202000000000008000000000000002a', 'hex');
const hello = '48574c530201000000000000';
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
for (const [offset, value] of [[0, 0], [4, 1], [6, 1]]) {
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
assert.equal(w.hw_control_ready(), 1);
assert.equal(w.hw_send_text(4097), 0);
new Uint8Array(w.memory.buffer, w.hw_input_ptr(), 1).set([255]);
assert.equal(w.hw_send_text(1), 0);

const output = () => Buffer.from(w.memory.buffer, w.hw_output_ptr(), w.hw_output_len());
function frame(kind, payload) {
  const result = Buffer.alloc(12 + payload.length);
  result.write('HWLS', 0, 'ascii'); result[4] = 2; result[5] = kind;
  result.writeUInt32BE(payload.length, 8); Buffer.from(payload).copy(result, 12);
  return result;
}
const result = (requestKind, code) => frame(11, [requestKind, code]);
const ok = requestKind => result(requestKind, 0);
const inputBytes = value => {
  const encoded = new TextEncoder().encode(value);
  new Uint8Array(w.memory.buffer, w.hw_input_ptr(), encoded.length).set(encoded);
  return encoded;
};

inputBytes('é');
assert.equal(w.hw_send_text(2), 1);
assert.equal(output()[5], 7); assert.deepEqual([...output().subarray(12)], [1, 0xc3, 0xa9]);
assert.equal(w.hw_control_ready(), 0); assert.equal(feed(ok(7)), 1); assert.equal(w.hw_phase(), 6);

inputBytes('paste');
assert.equal(w.hw_send_paste(5), 1);
assert.deepEqual([...output().subarray(12)], [2, 112, 97, 115, 116, 101]);
assert.equal(feed(ok(7)), 1);

assert.equal(w.hw_send_named_key(5, 1, 5), 1); // Up + shift/control.
let payload = output().subarray(12);
assert.equal(payload[0], 3); assert.equal(payload[1], 1); assert.equal(payload[2], 1); assert.equal(payload[3], 5);
assert.equal(payload.readUInt32BE(5), 5); assert.equal(feed(ok(7)), 1);
assert.equal(w.hw_send_named_key(0, 1, 0), 0); assert.equal(w.hw_send_named_key(59, 1, 0), 0);

assert.equal(w.hw_send_unicode_key(0x03bb, 1, 4), 1);
payload = output().subarray(12);
assert.equal(payload[0], 3); assert.equal(payload[1], 2); assert.equal(payload[2], 1); assert.equal(payload[3], 4);
assert.equal(payload.readUInt32BE(5), 0x03bb); assert.equal(feed(ok(7)), 1);
assert.equal(w.hw_send_unicode_key(0xd800, 1, 0), 0);

assert.equal(w.hw_send_focus(1), 1);
assert.deepEqual([...output().subarray(12)], [5, 1]); assert.equal(feed(ok(7)), 1);
assert.equal(w.hw_send_focus(3), 0);

assert.equal(w.hw_send_mouse(3, 0, 2, 4, 7, 9, 1, 95, 123), 1);
payload = output().subarray(12);
assert.equal(payload[0], 4);
assert.deepEqual([...payload.subarray(1, 5)], [3, 0, 2, 4]);
assert.equal(payload.readInt32BE(5), 7);
assert.equal(payload.readUInt16BE(9), 9);
assert.equal(payload[11], 1);
assert.equal(payload.readUInt32BE(12), 95);
assert.equal(payload.readUInt32BE(16), 123);
assert.equal(feed(ok(7)), 1);
assert.equal(w.hw_send_mouse(0, 0, 0, 0, 0, 0, 0, 0, 0), 0);
assert.equal(w.hw_send_mouse(1, 1, 0, 8, 0, 0, 0, 0, 0), 0);
assert.equal(w.hw_send_mouse(1, 1, 0, 1, 0, 0, 0, 1, 0), 0);

assert.equal(w.hw_send_resize(20, 80), 1);
assert.equal(output()[5], 8); assert.equal(output().subarray(12).readBigUInt64BE(), 42n);
assert.equal(w.hw_control_ready(), 0);
assert.equal(feed(ok(8)), 2); // Follow-up resize frame is now ready.
assert.equal(output()[5], 9); payload = output().subarray(12);
assert.equal(payload.readUInt16BE(0), 20); assert.equal(payload.readUInt16BE(2), 80);
assert.equal(feed(ok(9)), 1); assert.equal(w.hw_phase(), 6); assert.equal(w.hw_control_ready(), 1);
assert.equal(w.hw_last_result_code(), 0);
assert.equal(w.hw_send_resize_owned(21, 81), 1);
assert.equal(output()[5], 9); payload = output().subarray(12);
assert.equal(payload.readUInt16BE(0), 21); assert.equal(payload.readUInt16BE(2), 81);
assert.equal(feed(result(9, 4)), 1); assert.equal(w.hw_phase(), 6);
assert.equal(w.hw_last_result_code(), 4); assert.equal(w.hw_control_ready(), 1);
assert.equal(w.hw_send_resize(0, 80), 0);

assert.equal(w.hw_observe(1, 37), 1);
payload = output().subarray(12); assert.equal(output()[5], 3);
assert.equal(payload.readBigUInt64BE(0), 0n); assert.equal(payload.readUInt32BE(8), 37);
assert.equal(w.hw_observe(1, 0), 0); // at most one outstanding operation
assert.equal(w.hw_send_text(1), 0);
console.log(JSON.stringify({status:'pass', wasmBytes:bytes.length, memoryBytes:w.memory.buffer.byteLength,
  imports:0, welcomeSplits:21, byteDelivery:true, rejectedInvalidFrames:true, semanticControls:true, semanticMouse:true, resizeFollowup:true, canvasComposer:true}));

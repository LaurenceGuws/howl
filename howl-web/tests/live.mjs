// Run only against the disposable echo fixture documented in README.md.
// Node hosts the real Wasm client here; this is not Safari/browser acceptance.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import net from 'node:net';

const [wasmPath, portText] = process.argv.slice(2);
if (!/^\d+$/.test(portText ?? '') || Number(portText) < 1 || Number(portText) > 65535)
  throw new Error('usage: zig build live -- ANNOUNCED_DISPOSABLE_LOOPBACK_PORT');
const module = await WebAssembly.compile(await readFile(wasmPath));
const w = (await WebAssembly.instantiate(module)).exports;
const text = () => new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.hw_text_ptr(), w.hw_text_len()));
const error = () => new TextDecoder().decode(new Uint8Array(w.memory.buffer, w.hw_error_ptr(), w.hw_error_len()));
let socket;
let pending;
let failure;
function waitFor(phase) {
  if (failure) return Promise.reject(failure);
  if (w.hw_phase() === phase) return Promise.resolve();
  assert.equal(pending, undefined);
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending = undefined;
      reject(new Error(`timeout waiting for phase ${phase}, current ${w.hw_phase()}`));
    }, 5000);
    pending = {phase, resolve:() => {clearTimeout(timer); pending=undefined; resolve();},
      reject:e => {clearTimeout(timer); pending=undefined; reject(e);}};
  });
}
function fault(e) { failure = e; pending?.reject(e); }
function send() {
  socket.write(new Uint8Array(w.memory.buffer, w.hw_output_ptr(), w.hw_output_len()));
}
async function attach() {
  assert.equal(w.hw_reset(), 1);
  failure = undefined;
  socket = net.createConnection({host:'127.0.0.1', port:Number(portText)});
  socket.on('error', fault);
  socket.on('data', bytes => {
    try {
      // Deliberate single-byte deliveries pressure header and snapshot boundaries.
      for (const byte of bytes) {
        new Uint8Array(w.memory.buffer, w.hw_input_ptr(), 1)[0] = byte;
        assert.equal(w.hw_feed(1), 1, error());
      }
      if (pending && w.hw_phase() === pending.phase) pending.resolve();
    } catch (e) { fault(e); }
  });
  await new Promise((resolve, reject) => {socket.once('connect', resolve); socket.once('error', reject);});
  send(); await waitFor(2);
  return w.hw_identity();
}
async function observe(immediate) {
  assert.equal(w.hw_observe(immediate), 1);
  send(); await waitFor(4);
}
async function untilContains(marker) {
  for (let attempt = 0; attempt < 10; attempt++) {
    await observe(attempt === 0 ? 1 : 0);
    if (text().includes(marker)) return;
  }
  throw new Error(`canonical snapshot lacks ${marker}`);
}
async function disconnect() {
  const current = socket;
  assert.equal(w.hw_finish(), 1);
  await new Promise(resolve => {current.once('close', resolve); current.destroy();});
}
try {
  const first = await attach();
  await untilContains('HOWL_WEB_ECHO_READY');
  const message = 'main canary: café λ\n';
  const encoded = new TextEncoder().encode(message);
  new Uint8Array(w.memory.buffer, w.hw_input_ptr(), encoded.length).set(encoded);
  assert.equal(w.hw_send_text(encoded.length), 1);
  send(); await waitFor(6);
  await untilContains('ACK_FROM_PTY: main canary: café λ');
  assert.equal(w.hw_rows(), 12); assert.equal(w.hw_columns(), 72);
  const before = text(), revision = w.hw_revision();
  await disconnect();
  const second = await attach();
  assert.notEqual(second, first);
  await observe(1);
  assert.equal(text(), before);
  assert.equal(w.hw_revision(), revision);
  console.log(JSON.stringify({status:'pass', firstClient:String(first), reconnectedClient:String(second),
    revision:String(revision), rows:w.hw_rows(), columns:w.hw_columns(), textBytes:w.hw_text_len(),
    realPtyEcho:true, sharedRichDecoder:true, oneByteDelivery:true, reconnect:true}));
  await disconnect();
} finally {
  socket?.destroy();
}

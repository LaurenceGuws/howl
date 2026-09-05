import {assertTextImports, createTextRuntime} from './runtime.mjs';

const status = document.querySelector('#status');
const factsNode = document.querySelector('#facts');
const terminal = document.querySelector('#terminal');
const form = document.querySelector('#input-form');
const input = document.querySelector('#committed');
const reconnect = document.querySelector('#reconnect');
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const resources = new Map();
const context = terminal.getContext('2d', {alpha: false});
context.imageSmoothingEnabled = false;

let wireModule;
let renderer;
let observer;
let control;
let previousObserverId = null;
let lastFrame = null;
let lastInput = '';

const errorText = exports => decoder.decode(new Uint8Array(
  exports.memory.buffer, exports.hw_error_ptr?.() ?? exports.rv_error_ptr(),
  exports.hw_error_len?.() ?? exports.rv_error_len()));
const bytesAt = (memory, pointer, length) => new Uint8Array(memory.buffer, Number(pointer), Number(length));
const resourceKey = q => q.map(String).join(':');
const rgba = color => `rgba(${color[0]},${color[1]},${color[2]},${color[3] / 255})`;

async function fetchBytes(path) {
  const response = await fetch(path, {cache: 'no-store'});
  if (!response.ok) throw new Error(`${path}: ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

async function load() {
  const [wireBytes, renderBytes, font] = await Promise.all([
    fetchBytes('/wire.wasm'), fetchBytes('render.wasm'), fetchBytes('font.bin'),
  ]);
  wireModule = await WebAssembly.compile(wireBytes);
  if (WebAssembly.Module.imports(wireModule).length !== 0) throw new Error('wire module gained host imports');
  const renderModule = await WebAssembly.compile(renderBytes);
  assertTextImports(renderModule);
  const runtime = createTextRuntime({output:()=>{}});
  const instance = await WebAssembly.instantiate(renderModule, runtime.imports);
  runtime.bind(instance.exports.memory);
  instance.exports._initialize?.();
  renderer = {exports: instance.exports, runtime, bytes: renderBytes.length};
  if (font.length > renderer.exports.rv_font_capacity()) throw new Error('font exceeds renderer input bound');
  bytesAt(renderer.exports.memory, renderer.exports.rv_font_ptr(), font.length).set(font);
  if (renderer.exports.rv_init(font.length) !== 1) throw new Error(errorText(renderer.exports) || 'renderer init failed');
  observer = await WireConnection.connect('observer');
  control = await WireConnection.connect('control');
  updateFacts();
}

class WireConnection {
  static async connect(role) {
    const instance = await WebAssembly.instantiate(wireModule);
    const connection = new WireConnection(role, instance.exports);
    await connection.open();
    return connection;
  }
  constructor(role, exports) {
    this.role = role;
    this.exports = exports;
    this.socket = null;
    this.clientId = null;
    this.closed = false;
  }
  async open() {
    if (this.exports.hw_reset() !== 1) throw new Error(`${this.role}: reset failed`);
    const scheme = location.protocol === 'https:' ? 'wss:' : 'ws:';
    this.socket = new WebSocket(`${scheme}//${location.host}/socket`);
    this.socket.binaryType = 'arraybuffer';
    this.socket.onmessage = event => this.onMessage(event).catch(fail);
    this.socket.onerror = () => fail(new Error(`${this.role}: websocket error`));
    this.socket.onclose = () => { this.closed = true; updateFacts(); };
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`${this.role}: open timeout`)), 5000);
      this.socket.addEventListener('open', () => { clearTimeout(timer); resolve(); }, {once:true});
      this.socket.addEventListener('error', () => { clearTimeout(timer); reject(new Error(`${this.role}: open error`)); }, {once:true});
    });
    this.sendOutput();
    await this.waitForPhase(2);
    this.clientId = this.exports.hw_identity();
    if (this.role === 'observer') this.observe(true);
  }
  sendOutput() {
    const length = Number(this.exports.hw_output_len());
    if (length === 0) throw new Error(`${this.role}: empty outgoing frame`);
    this.socket.send(bytesAt(this.exports.memory, this.exports.hw_output_ptr(), length).slice());
  }
  async onMessage(event) {
    const data = new Uint8Array(event.data);
    if (data.length > this.exports.hw_input_capacity()) throw new Error(`${this.role}: websocket fragment exceeds wire bound`);
    bytesAt(this.exports.memory, this.exports.hw_input_ptr(), data.length).set(data);
    if (this.exports.hw_feed(data.length) !== 1) throw new Error(errorText(this.exports) || `${this.role}: wire feed failed`);
    this.pulseWaiters?.();
    if (this.role === 'observer' && this.exports.hw_phase() === 4) {
      renderObserverSnapshot(this);
      this.observe(false);
    }
    if (this.role === 'control' && this.exports.hw_phase() === 6) {
      status.textContent = `Input acknowledged by canonical session${lastInput ? `: ${lastInput}` : ''}`;
      updateFacts();
    }
  }
  observe(immediate) {
    if (this.exports.hw_observe(immediate ? 1 : 0) !== 1) throw new Error(`${this.role}: observe rejected`);
    this.sendOutput();
  }
  sendLine(value) {
    const bytes = encoder.encode(`${value}\n`);
    if (bytes.length > this.exports.hw_input_capacity()) throw new Error('committed text exceeds wire input buffer');
    bytesAt(this.exports.memory, this.exports.hw_input_ptr(), bytes.length).set(bytes);
    if (this.exports.hw_send_text(bytes.length) !== 1) throw new Error(`${this.role}: committed text rejected`);
    this.sendOutput();
  }
  waitForPhase(wanted) {
    if (this.exports.hw_phase() === wanted) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const started = performance.now();
      const tick = () => {
        if (this.exports.hw_phase() === wanted) return resolve();
        if (this.exports.hw_phase() === 99) return reject(new Error(errorText(this.exports) || `${this.role}: protocol failure`));
        if (performance.now() - started > 5000) return reject(new Error(`${this.role}: phase ${wanted} timeout`));
        setTimeout(tick, 5);
      };
      tick();
    });
  }
  async closeAndWait() {
    this.closed = true;
    const socket = this.socket;
    if (!socket || socket.readyState === WebSocket.CLOSED) return;
    const closed = new Promise(resolve => socket.addEventListener('close', resolve, {once:true}));
    socket.close();
    await Promise.race([closed, new Promise((_, reject) => setTimeout(() => reject(new Error(`${this.role}: close timeout`)), 3000))]);
  }
  close() {
    this.closed = true;
    this.socket?.close();
  }
}

function renderObserverSnapshot(connection) {
  const wire = connection.exports;
  const length = Number(wire.hw_snapshot_len());
  if (length === 0 || length > renderer.exports.rv_snapshot_capacity()) throw new Error('snapshot exceeds renderer input bound');
  bytesAt(renderer.exports.memory, renderer.exports.rv_snapshot_ptr(), length)
    .set(bytesAt(wire.memory, wire.hw_snapshot_ptr(), length));
  if (renderer.exports.rv_render(length) !== 1) throw new Error(errorText(renderer.exports) || 'terminal renderer failed');
  const metadata = JSON.parse(decoder.decode(bytesAt(renderer.exports.memory, renderer.exports.rv_frame_ptr(), renderer.exports.rv_frame_len())));
  const pixelBytes = bytesAt(renderer.exports.memory, renderer.exports.rv_pixels_ptr(), renderer.exports.rv_pixels_len()).slice();
  drawFrame(metadata, pixelBytes);
  if (renderer.exports.rv_ack() !== 1) throw new Error(errorText(renderer.exports) || 'renderer frame acknowledgment failed');
  lastFrame = {...metadata, observer: String(connection.clientId ?? wire.hw_identity())};
  status.textContent = 'LIVE: canonical Howl snapshot rendered by the shared Zig pipeline';
  updateFacts();
}

function createResource(upload, framePixels) {
  const [width, height] = upload.z;
  const bytes = framePixels.slice(upload.o, upload.o + upload.n);
  const resource = {format: upload.f, width, height, stride: upload.stride, bytes};
  const image = document.createElement('canvas');
  image.width = width; image.height = height;
  const ctx = image.getContext('2d');
  const data = ctx.createImageData(width, height);
  if (upload.f === 0) {
    for (let y = 0; y < height; y += 1) for (let x = 0; x < width; x += 1) {
      const a = bytes[y * upload.stride + x];
      const p = (y * width + x) * 4;
      data.data[p] = data.data[p + 1] = data.data[p + 2] = 255;
      data.data[p + 3] = a;
    }
  } else if (upload.f === 1) {
    for (let y = 0; y < height; y += 1) {
      data.data.set(bytes.subarray(y * upload.stride, y * upload.stride + width * 4), y * width * 4);
    }
  } else throw new Error(`unsupported Canvas resource format ${upload.f}`);
  ctx.putImageData(data, 0, 0);
  resource.canvas = image;
  return resource;
}

function drawFrame(frame, framePixels) {
  for (const q of frame.removals) resources.delete(resourceKey(q));
  for (const upload of frame.uploads) resources.set(resourceKey(upload.q), createResource(upload, framePixels));
  const [width, height] = frame.surface;
  if (terminal.width !== width || terminal.height !== height) { terminal.width = width; terminal.height = height; }
  context.imageSmoothingEnabled = false;
  context.clearRect(0, 0, width, height);
  const currentResources = new Set();
  for (const command of frame.commands) {
    if (command.k !== 0) currentResources.add(resourceKey(command.q));
    if (command.k === 0) {
      context.fillStyle = rgba(command.color);
      context.fillRect(...command.r);
      continue;
    }
    const resource = resources.get(resourceKey(command.q));
    if (!resource) throw new Error(`missing backend resource ${resourceKey(command.q)}`);
    const [dx, dy, dw, dh] = command.d;
    const [cx, cy, cw, ch] = command.c;
    const [sx, sy, sw, sh] = command.s;
    context.save();
    context.beginPath(); context.rect(cx, cy, cw, ch); context.clip();
    if (command.k === 2) {
      context.drawImage(resource.canvas, sx, sy, sw, sh, dx, dy, dw, dh);
    } else if (command.k === 1) {
      const scratch = document.createElement('canvas');
      scratch.width = dw; scratch.height = dh;
      const sctx = scratch.getContext('2d');
      sctx.imageSmoothingEnabled = false;
      sctx.drawImage(resource.canvas, sx, sy, sw, sh, 0, 0, dw, dh);
      sctx.globalCompositeOperation = 'source-in';
      sctx.fillStyle = rgba(command.color);
      sctx.fillRect(0, 0, dw, dh);
      context.drawImage(scratch, dx, dy);
    } else throw new Error(`unknown Canvas command ${command.k}`);
    context.restore();
  }
  // Match Flutter's lease: every completed frame names the exact resource
  // generations it still references. Retire superseded generations here.
  for (const key of [...resources.keys()]) if (!currentResources.has(key)) resources.delete(key);
}

function updateFacts() {
  factsNode.textContent = JSON.stringify({
    observer_client: observer?.clientId ? String(observer.clientId) : null,
    previous_observer_client: previousObserverId,
    control_client: control?.clientId ? String(control.clientId) : null,
    observer_phase: observer?.exports.hw_phase() ?? null,
    control_phase: control?.exports.hw_phase() ?? null,
    render_count: renderer ? String(renderer.exports.rv_render_count()) : '0',
    renderer_memory_bytes: renderer?.exports.memory.buffer.byteLength ?? null,
    backend_resources: resources.size,
    frame: lastFrame ? {
      observation: lastFrame.observation,
      terminal: lastFrame.terminal,
      commands: lastFrame.commands.length,
      uploads: lastFrame.uploads.length,
      removals: lastFrame.removals.length,
      surface: lastFrame.surface,
    } : null,
  }, null, 2);
}

form.addEventListener('submit', event => {
  event.preventDefault();
  try {
    if (!control || control.closed) throw new Error('control connection is not available');
    if (control.exports.hw_phase() !== 2 && control.exports.hw_phase() !== 6) throw new Error('control operation still pending');
    lastInput = input.value;
    control.sendLine(input.value);
    input.value = '';
    status.textContent = 'Committed text sent; waiting for canonical PTY/VT update…';
  } catch (error) { fail(error); }
});

reconnect.addEventListener('click', async () => {
  try {
    if (observer) {
      previousObserverId = observer.clientId ? String(observer.clientId) : null;
      await observer.closeAndWait();
    }
    if (!control || control.closed) control = await WireConnection.connect('control');
    observer = await WireConnection.connect('observer');
    if (previousObserverId && String(observer.clientId) === previousObserverId) throw new Error('observer reconnect reused client identity');
    status.textContent = 'Observer reconnected; waiting for canonical snapshot…';
    updateFacts();
  } catch (error) { fail(error); }
});

function fail(error) {
  console.error(error);
  const networkFailure = /websocket|open timeout|open error/i.test(error.message);
  status.textContent = `${networkFailure ? 'DISCONNECTED' : 'FAIL'}: ${error.message}`;
  factsNode.textContent = error.stack ?? String(error);
}

load().catch(fail);
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(error => console.warn('service worker registration failed', error));
}

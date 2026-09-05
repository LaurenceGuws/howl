import {assertTextImports, createTextRuntime} from './runtime.mjs';
import {
  TerminalInputStager, guardText, namedKeyForCode, NamedKey, KeyAction,
  Modifier, modifierBits, singleScalar,
} from './input.mjs';

const main = document.querySelector('main');
const status = document.querySelector('#status');
const factsNode = document.querySelector('#facts');
const terminal = document.querySelector('#terminal');
const toolbar = document.querySelector('#toolbar');
const keyboard = document.querySelector('#keyboard');
const keyboardButton = document.querySelector('#keyboard-button');
const pasteButton = document.querySelector('#paste-button');
const reconnect = document.querySelector('#reconnect');
const decoder = new TextDecoder();
const encoder = new TextEncoder();
const resources = new Map();
const context = terminal.getContext('2d', {alpha: false});
const stager = new TerminalInputStager();
const modifiedKeys = new Map();
context.imageSmoothingEnabled = false;

let wireModule;
let renderer;
let observer;
let control;
let previousObserverId = null;
let lastFrame = null;
let lastInput = '';
let controlTail = Promise.resolve();
let modifierLatch = 0;
let compositionActive = false;
let focusState = null;
let resizeTimer = null;
let requestedGeometry = null;

const errorText = exports => decoder.decode(new Uint8Array(
  exports.memory.buffer, exports.hw_error_ptr?.() ?? exports.rv_error_ptr(),
  exports.hw_error_len?.() ?? exports.rv_error_len()));
const bytesAt = (memory, pointer, length) => new Uint8Array(memory.buffer, Number(pointer), Number(length));
const resourceKey = q => q.map(String).join(':');
const rgba = color => `rgba(${color[0]},${color[1]},${color[2]},${color[3] / 255})`;
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

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
  resetEditor();
  syncFocus();
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
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) throw new Error(`${this.role}: websocket is not open`);
    this.socket.send(bytesAt(this.exports.memory, this.exports.hw_output_ptr(), length).slice());
  }
  async onMessage(event) {
    const data = new Uint8Array(event.data);
    if (data.length > this.exports.hw_input_capacity()) throw new Error(`${this.role}: websocket fragment exceeds wire bound`);
    bytesAt(this.exports.memory, this.exports.hw_input_ptr(), data.length).set(data);
    const accepted = this.exports.hw_feed(data.length);
    if (accepted !== 1 && accepted !== 2) throw new Error(errorText(this.exports) || `${this.role}: wire feed failed`);
    if (accepted === 2) this.sendOutput();
    if (this.role === 'observer' && this.exports.hw_phase() === 4) {
      renderObserverSnapshot(this);
      this.observe(false);
    }
    if (this.role === 'control' && this.exports.hw_phase() === 6) updateFacts();
  }
  observe(immediate) {
    if (this.exports.hw_observe(immediate ? 1 : 0) !== 1) throw new Error(`${this.role}: observe rejected`);
    this.sendOutput();
  }
  stage(value) {
    const bytes = encoder.encode(value);
    if (bytes.length === 0 || bytes.length > 4096 || bytes.length > this.exports.hw_input_capacity())
      throw new Error(`${this.role}: semantic text exceeds 4096-byte request bound`);
    bytesAt(this.exports.memory, this.exports.hw_input_ptr(), bytes.length).set(bytes);
    return bytes.length;
  }
  async operation(begin, label) {
    if (this.closed || !this.socket || this.socket.readyState !== WebSocket.OPEN) throw new Error(`${this.role}: connection is not available`);
    if (this.exports.hw_control_ready() !== 1) throw new Error(`${this.role}: prior control operation is still pending`);
    if (begin() !== 1) throw new Error(`${this.role}: ${label} rejected before send`);
    this.sendOutput();
    await this.waitForPhase(6);
    lastInput = label;
    updateFacts();
  }
  committedText(value) {
    const length = this.stage(value);
    return this.operation(() => this.exports.hw_send_text(length), `commit ${JSON.stringify(value)}`);
  }
  paste(value) {
    const length = this.stage(value);
    return this.operation(() => this.exports.hw_send_paste(length), `paste ${length} bytes`);
  }
  namedKey(key, action, modifiers) {
    return this.operation(() => this.exports.hw_send_named_key(key, action, modifiers), `key ${key}/${action} mods=${modifiers}`);
  }
  unicodeKey(scalar, action, modifiers) {
    return this.operation(() => this.exports.hw_send_unicode_key(scalar, action, modifiers), `unicode U+${scalar.toString(16)} mods=${modifiers}`);
  }
  focus(value) {
    return this.operation(() => this.exports.hw_send_focus(value), `focus ${value === 1 ? 'in' : 'out'}`);
  }
  resize(rows, columns) {
    return this.operation(() => this.exports.hw_send_resize(rows, columns), `resize ${rows}x${columns}`);
  }
  waitForPhase(wanted) {
    if (this.exports.hw_phase() === wanted) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const started = performance.now();
      const tick = () => {
        if (this.exports.hw_phase() === wanted) return resolve();
        if (this.closed) return reject(new Error(`${this.role}: connection closed while waiting for phase ${wanted}`));
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

async function ensureControl() {
  if (control && !control.closed && control.socket?.readyState === WebSocket.OPEN) return control;
  control = await WireConnection.connect('control');
  focusState = null;
  return control;
}

function queueControl(run) {
  const task = controlTail.then(async () => run(await ensureControl()));
  controlTail = task.catch(fail);
  return task;
}

function utf8Chunks(value, maximum = 4096) {
  const result = [];
  let current = '';
  let bytes = 0;
  for (const scalar of value) {
    const size = encoder.encode(scalar).length;
    if (size > maximum) throw new Error('one Unicode scalar exceeds semantic request bound');
    if (bytes + size > maximum) { result.push(current); current = ''; bytes = 0; }
    current += scalar; bytes += size;
  }
  if (current) result.push(current);
  return result;
}

function queueCommitted(value) {
  if (!value) return;
  const latched = modifierLatch;
  clearModifierLatch();
  const scalar = latched ? singleScalar(value) : null;
  if (scalar != null) {
    queueKeyCycle({scalar, modifiers:latched});
    return;
  }
  for (const chunk of utf8Chunks(value)) queueControl(connection => connection.committedText(chunk));
}

function queuePaste(value) {
  if (!value) return;
  clearModifierLatch();
  if (encoder.encode(value).length > 4096) {
    fail(new Error('paste exceeds current 4096-byte semantic request bound'));
    return;
  }
  queueControl(connection => connection.paste(value));
}

function queueKeyCycle({named, scalar, modifiers = modifierLatch}) {
  clearModifierLatch();
  const operation = named != null
    ? (connection, action) => connection.namedKey(named, action, modifiers)
    : (connection, action) => connection.unicodeKey(scalar, action, modifiers);
  queueControl(connection => operation(connection, KeyAction.press));
  queueControl(connection => operation(connection, KeyAction.release));
}

function queueHardwareKey({named, scalar, action, modifiers}) {
  if (named != null) queueControl(connection => connection.namedKey(named, action, modifiers));
  else queueControl(connection => connection.unicodeKey(scalar, action, modifiers));
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
  if (requestedGeometry && metadata.surface[0] === requestedGeometry.columns * metadata.cell[0] &&
      metadata.surface[1] === requestedGeometry.rows * metadata.cell[1]) requestedGeometry = null;
  status.textContent = 'LIVE: canonical Howl snapshot rendered by the shared Zig pipeline';
  scheduleViewportResize();
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

function resetEditor() {
  stager.reset();
  keyboard.value = guardText;
  keyboard.setSelectionRange(1, 1);
}

function dispatchStaged(actions) {
  for (const action of actions) {
    if (action.kind === 'text') queueCommitted(action.text);
    else queueKeyCycle({named:action.key});
  }
}

function processEditor(composing) {
  const actions = stager.update(keyboard.value, {composing});
  if (!composing) resetEditor();
  dispatchStaged(actions);
}

function focusKeyboard() {
  keyboard.focus({preventScroll:true});
  if (!compositionActive) resetEditor();
}

keyboard.addEventListener('compositionstart', () => { compositionActive = true; });
keyboard.addEventListener('compositionend', () => {
  compositionActive = false;
  const value = keyboard.value;
  setTimeout(() => {
    if (!compositionActive && keyboard.value === value && value !== guardText) processEditor(false);
  }, 0);
});
keyboard.addEventListener('input', event => processEditor(Boolean(event.isComposing || compositionActive)));
keyboard.addEventListener('paste', event => {
  const value = event.clipboardData?.getData('text/plain');
  if (value == null) return;
  event.preventDefault();
  resetEditor();
  queuePaste(value);
});
keyboard.addEventListener('keydown', event => {
  const named = namedKeyForCode(event.code);
  const action = event.repeat ? KeyAction.repeat : KeyAction.press;
  const modifiers = modifierBits(event);
  if (named != null) {
    queueHardwareKey({named, action, modifiers});
    if (named < 15 || named > 22) event.preventDefault();
    return;
  }
  const scalar = singleScalar(event.key);
  if (scalar != null && (modifiers & (Modifier.alt | Modifier.control | Modifier.super)) !== 0) {
    modifiedKeys.set(event.code, {scalar, modifiers});
    queueHardwareKey({scalar, action, modifiers});
    event.preventDefault();
  }
});
keyboard.addEventListener('keyup', event => {
  const named = namedKeyForCode(event.code);
  if (named != null) {
    queueHardwareKey({named, action:KeyAction.release, modifiers:modifierBits(event)});
    if (named < 15 || named > 22) event.preventDefault();
    return;
  }
  const tracked = modifiedKeys.get(event.code);
  if (tracked) {
    modifiedKeys.delete(event.code);
    queueHardwareKey({...tracked, action:KeyAction.release});
    event.preventDefault();
  }
});

terminal.addEventListener('pointerdown', focusKeyboard);
keyboardButton.addEventListener('click', focusKeyboard);
pasteButton.addEventListener('click', async () => {
  try {
    if (!navigator.clipboard?.readText) throw new Error('browser clipboard read is unavailable');
    const value = await navigator.clipboard.readText();
    if (!value) {
      status.textContent = 'Clipboard is empty';
      return;
    }
    queuePaste(value);
    status.textContent = `Clipboard paste queued (${encoder.encode(value).length} bytes)`;
    focusKeyboard();
  } catch (error) {
    status.textContent = `PASTE UNAVAILABLE: ${error.message}`;
    focusKeyboard();
  }
});

function setModifierLatch(value) {
  modifierLatch = value;
  for (const button of toolbar.querySelectorAll('[data-modifier]')) {
    const bit = button.dataset.modifier === 'control' ? Modifier.control : Modifier.alt;
    button.setAttribute('aria-pressed', String((modifierLatch & bit) !== 0));
  }
  updateFacts();
}
function clearModifierLatch() { if (modifierLatch !== 0) setModifierLatch(0); }
for (const button of toolbar.querySelectorAll('[data-modifier]')) {
  button.addEventListener('click', () => {
    const bit = button.dataset.modifier === 'control' ? Modifier.control : Modifier.alt;
    setModifierLatch(modifierLatch ^ bit);
    focusKeyboard();
  });
}
for (const button of toolbar.querySelectorAll('[data-key]')) {
  button.addEventListener('click', () => {
    const key = NamedKey[button.dataset.key];
    if (key == null) return fail(new Error(`unknown toolbar key ${button.dataset.key}`));
    queueKeyCycle({named:key});
    focusKeyboard();
  });
}

function desiredFocus() { return document.visibilityState === 'visible' && document.hasFocus(); }
function syncFocus() {
  const next = desiredFocus() ? 1 : 2;
  if (focusState === next || !wireModule) return;
  focusState = next;
  queueControl(connection => connection.focus(next));
}
window.addEventListener('focus', syncFocus);
window.addEventListener('blur', syncFocus);
document.addEventListener('visibilitychange', syncFocus);

function scheduleViewportResize() {
  if (resizeTimer) clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => {
    resizeTimer = null;
    if (!lastFrame?.cell || !control || control.closed) return;
    const [cellWidth, cellHeight] = lastFrame.cell;
    if (!cellWidth || !cellHeight) return;
    const viewportHeight = Math.floor(window.visualViewport?.height ?? window.innerHeight);
    const width = Math.floor(main.clientWidth);
    const top = Math.max(0, terminal.getBoundingClientRect().top);
    const toolbarHeight = Math.ceil(toolbar.getBoundingClientRect().height);
    const columns = clamp(Math.floor(width / cellWidth), 20, 256);
    const rows = clamp(Math.floor(Math.max(cellHeight * 2, viewportHeight - top - toolbarHeight - 28) / cellHeight), 2, 128);
    const currentColumns = Math.floor(lastFrame.surface[0] / cellWidth);
    const currentRows = Math.floor(lastFrame.surface[1] / cellHeight);
    if ((rows === currentRows && columns === currentColumns) ||
        (requestedGeometry?.rows === rows && requestedGeometry?.columns === columns)) return;
    requestedGeometry = {rows, columns};
    queueControl(connection => connection.resize(rows, columns)).catch(() => { requestedGeometry = null; });
  }, 120);
}
window.addEventListener('resize', scheduleViewportResize);
window.visualViewport?.addEventListener('resize', scheduleViewportResize);

function updateFacts() {
  factsNode.textContent = JSON.stringify({
    observer_client: observer?.clientId ? String(observer.clientId) : null,
    previous_observer_client: previousObserverId,
    control_client: control?.clientId ? String(control.clientId) : null,
    observer_phase: observer?.exports.hw_phase() ?? null,
    control_phase: control?.exports.hw_phase() ?? null,
    observation_revision: observer ? String(observer.exports.hw_revision()) : null,
    terminal_revision: observer ? String(observer.exports.hw_terminal_revision()) : null,
    semantic_control_ready: control?.exports.hw_control_ready() === 1,
    modifier_latch: modifierLatch,
    focus_state: focusState,
    requested_geometry: requestedGeometry,
    last_control: lastInput || null,
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
      cell: lastFrame.cell,
    } : null,
  }, null, 2);
}

reconnect.addEventListener('click', async () => {
  try {
    if (observer) {
      previousObserverId = observer.clientId ? String(observer.clientId) : null;
      await observer.closeAndWait();
    }
    await ensureControl();
    observer = await WireConnection.connect('observer');
    if (previousObserverId && String(observer.clientId) === previousObserverId) throw new Error('observer reconnect reused client identity');
    focusState = null;
    syncFocus();
    status.textContent = 'Observer reconnected; waiting for canonical snapshot…';
    scheduleViewportResize();
    updateFacts();
  } catch (error) { fail(error); }
});

function fail(error) {
  console.error(error);
  const networkFailure = /websocket|open timeout|open error|connection closed/i.test(error.message);
  status.textContent = `${networkFailure ? 'DISCONNECTED' : 'FAIL'}: ${error.message}`;
  factsNode.textContent = error.stack ?? String(error);
}

load().catch(fail);
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('/sw.js').catch(error => console.warn('service worker registration failed', error));
}

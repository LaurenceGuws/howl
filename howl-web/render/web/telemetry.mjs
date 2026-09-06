// Bounded client-local flight recorder for browser canaries. Callers pass only
// metadata; raw terminal/input text and error strings are mechanically refused.
const forbiddenDataKeys = new Set(['text', 'value', 'content', 'message', 'label', 'payload']);

export class Telemetry {
  constructor({capacity = 768, now = () => performance.now()} = {}) {
    if (!Number.isInteger(capacity) || capacity < 32 || capacity > 4096) throw new Error('invalid telemetry capacity');
    this.capacity = capacity;
    this.now = now;
    this.started = now();
    this.buffer = new Array(capacity);
    this.head = 0;
    this.size = 0;
    this.sequence = 0;
    this.listeners = new Set();
  }

  get retained() { return this.size; }
  get events() { return this.#ordered(); }

  record(kind, data = {}) {
    for (const key of Object.keys(data)) {
      if (forbiddenDataKeys.has(key)) throw new Error(`telemetry data key ${key} is forbidden`);
    }
    const event = {
      n: ++this.sequence,
      t: Math.round((this.now() - this.started) * 10) / 10,
      k: kind,
      ...data,
    };
    if (this.size < this.capacity) {
      this.buffer[(this.head + this.size) % this.capacity] = event;
      this.size += 1;
    } else {
      this.buffer[this.head] = event;
      this.head = (this.head + 1) % this.capacity;
    }
    for (const listener of this.listeners) listener(event);
    return event;
  }

  clear() {
    this.buffer = new Array(this.capacity);
    this.head = 0;
    this.size = 0;
    this.started = this.now();
    this.sequence = 0;
    this.record('telemetry_clear');
  }

  subscribe(listener) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  export(extra = {}) {
    return {
      schema: 'howl.web-telemetry/v1',
      capacity: this.capacity,
      retained: this.size,
      ...extra,
      events: this.#ordered(),
    };
  }

  compact(extra = {}) { return JSON.stringify(this.export(extra)); }

  visibleLines(limit = 80) {
    return this.#ordered(Math.max(0, Math.min(limit, this.size))).map(event => JSON.stringify(event)).join('\n');
  }

  #ordered(limit = this.size) {
    const count = Math.min(limit, this.size);
    const start = this.size - count;
    const out = new Array(count);
    for (let index = 0; index < count; index++) {
      out[index] = {...this.buffer[(this.head + start + index) % this.capacity]};
    }
    return out;
  }
}

export function startEventLoopProbe(telemetry, {
  intervalMs = 250,
  reportLagMs = 80,
  setIntervalFn = setInterval,
  clearIntervalFn = clearInterval,
  now = () => performance.now(),
} = {}) {
  let expected = now() + intervalMs;
  const timer = setIntervalFn(() => {
    const current = now();
    const lag = current - expected;
    expected = current + intervalMs;
    if (lag >= reportLagMs) telemetry.record('event_loop_lag', {ms:Math.round(lag * 10) / 10});
  }, intervalMs);
  return () => clearIntervalFn(timer);
}

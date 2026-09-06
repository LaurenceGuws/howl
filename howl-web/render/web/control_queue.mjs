// Browser-side serializer for Howl control mutations. It preserves exact
// operation order while coalescing only adjacent committed text that is still
// waiting behind an in-flight request. No terminal semantics live here.
export class ControlQueue {
  constructor({maximumPending = 256, maximumTextBytes = 4096, onError = () => {}} = {}) {
    this.maximumPending = maximumPending;
    this.maximumTextBytes = maximumTextBytes;
    this.onError = onError;
    this.tail = Promise.resolve();
    this.pending = 0;
    this.textTail = null;
  }

  operation(run) {
    this.textTail = null;
    return this.#schedule(run);
  }

  text(value, byteLength, run) {
    if (!value || byteLength <= 0 || byteLength > this.maximumTextBytes) {
      return this.#rejected(new Error('invalid committed-text queue item'));
    }
    const tail = this.textTail;
    if (tail && tail.bytes + byteLength <= this.maximumTextBytes) {
      tail.value += value;
      tail.bytes += byteLength;
      return tail.promise;
    }
    const item = {value, bytes:byteLength, promise:null};
    this.textTail = item;
    item.promise = this.#schedule(async () => {
      if (this.textTail === item) this.textTail = null;
      await run(item.value);
    });
    return item.promise;
  }

  #schedule(run) {
    if (this.pending >= this.maximumPending) {
      return this.#rejected(new Error(`control queue exceeds ${this.maximumPending} pending operations`));
    }
    this.pending += 1;
    const task = this.tail.then(run);
    const settled = task.finally(() => { this.pending -= 1; });
    this.tail = settled.catch(error => { this.onError(error); });
    return settled;
  }

  #rejected(error) {
    this.onError(error);
    const rejected = Promise.reject(error);
    rejected.catch(() => {});
    return rejected;
  }
}

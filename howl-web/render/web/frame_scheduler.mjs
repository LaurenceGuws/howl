// Browser presentation gate: at most one callback is scheduled, and if several
// complete canonical snapshots arrive before that callback, only the newest is
// painted. Canonical observation remains outside this client-local presentation seam.
export class LatestFrameScheduler {
  constructor({schedule, draw}) {
    if (typeof schedule !== 'function' || typeof draw !== 'function') throw new Error('frame scheduler requires callbacks');
    this.schedule = schedule;
    this.draw = draw;
    this.pending = false;
    this.latest = null;
    this.cancelScheduled = null;
  }

  push(frame) {
    this.latest = frame;
    if (this.pending) return;
    this.#arm();
  }

  // Hidden browsers may suspend an already-requested animation frame forever.
  // On visible resume, re-arm presentation for the same coalesced newest frame
  // instead of waiting for that stale platform callback to wake up.
  resume() {
    if (!this.pending || this.latest == null) return false;
    this.cancelScheduled?.();
    this.pending = false;
    this.cancelScheduled = null;
    this.#arm();
    return true;
  }

  #arm() {
    this.pending = true;
    this.cancelScheduled = this.schedule(() => {
      this.pending = false;
      this.cancelScheduled = null;
      const latest = this.latest;
      this.latest = null;
      if (latest != null) this.draw(latest);
    });
  }
}

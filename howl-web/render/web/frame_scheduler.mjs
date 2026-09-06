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
  }

  push(frame) {
    this.latest = frame;
    if (this.pending) return;
    this.pending = true;
    this.schedule(() => {
      this.pending = false;
      const latest = this.latest;
      this.latest = null;
      if (latest != null) this.draw(latest);
    });
  }
}

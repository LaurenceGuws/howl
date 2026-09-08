// Browser lifecycle recovery gate. Initial transport attachment owns boot;
// focus/pageshow/visibility events cannot start a competing attach until boot completes.
export class LifecycleRecoveryPolicy {
  constructor() { this.ready = false; }

  activate() { this.ready = true; }

  decide({visible, observerOpen, controlOpen}) {
    if (!this.ready) return 'boot';
    if (!visible) return 'hidden';
    if (observerOpen && controlOpen) return 'healthy';
    return 'reconnect';
  }
}

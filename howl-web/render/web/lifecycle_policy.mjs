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

/// Manual recovery may complete a boot whose first transport attach failed.
/// Automatic lifecycle recovery remains excluded from boot so it cannot race
/// the initial attach path. A hidden page never starts transport work.
export function reconnectAllowed(decision, {manual = false} = {}) {
  if (decision === 'hidden') return false;
  if (manual) return decision === 'boot' || decision === 'healthy' || decision === 'reconnect';
  return decision === 'reconnect';
}

import assert from 'node:assert/strict';
import {LifecycleRecoveryPolicy, reconnectAllowed} from '../web/lifecycle_policy.mjs';

const policy = new LifecycleRecoveryPolicy();
assert.equal(policy.decide({visible:true, observerOpen:false, controlOpen:false}), 'boot');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:true}), 'boot');
policy.activate();
assert.equal(policy.decide({visible:false, observerOpen:false, controlOpen:false}), 'hidden');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:true}), 'healthy');
assert.equal(policy.decide({visible:true, observerOpen:false, controlOpen:true}), 'reconnect');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:false}), 'reconnect');
assert.equal(reconnectAllowed('boot'), false);
assert.equal(reconnectAllowed('boot', {manual:true}), true);
assert.equal(reconnectAllowed('hidden', {manual:true}), false);
assert.equal(reconnectAllowed('healthy'), false);
assert.equal(reconnectAllowed('healthy', {manual:true}), true);
assert.equal(reconnectAllowed('reconnect'), true);
console.log(JSON.stringify({status:'pass', bootExclusive:true, healthyStable:true, brokenReconnects:true, manualBootRecovery:true}));

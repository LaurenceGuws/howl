import assert from 'node:assert/strict';
import {LifecycleRecoveryPolicy} from '../web/lifecycle_policy.mjs';

const policy = new LifecycleRecoveryPolicy();
assert.equal(policy.decide({visible:true, observerOpen:false, controlOpen:false}), 'boot');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:true}), 'boot');
policy.activate();
assert.equal(policy.decide({visible:false, observerOpen:false, controlOpen:false}), 'hidden');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:true}), 'healthy');
assert.equal(policy.decide({visible:true, observerOpen:false, controlOpen:true}), 'reconnect');
assert.equal(policy.decide({visible:true, observerOpen:true, controlOpen:false}), 'reconnect');
console.log(JSON.stringify({status:'pass', bootExclusive:true, healthyStable:true, brokenReconnects:true}));

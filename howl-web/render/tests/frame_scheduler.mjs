import assert from 'node:assert/strict';
import {LatestFrameScheduler} from '../web/frame_scheduler.mjs';

const callbacks = [];
const painted = [];
const scheduler = new LatestFrameScheduler({schedule:callback => callbacks.push(callback), draw:frame => painted.push(frame)});
scheduler.push({revision:1});
scheduler.push({revision:2});
scheduler.push({revision:3});
assert.equal(callbacks.length, 1);
assert.equal(scheduler.pending, true);
callbacks.shift()();
assert.deepEqual(painted, [{revision:3}]);
assert.equal(scheduler.pending, false);
scheduler.push({revision:4});
assert.equal(callbacks.length, 1);
callbacks.shift()();
assert.deepEqual(painted, [{revision:3},{revision:4}]);

const resumableCallbacks = [];
let cancelled = 0;
const resumedPaints = [];
const resumable = new LatestFrameScheduler({
  schedule:callback => {
    let active = true;
    resumableCallbacks.push(() => { if (active) callback(); });
    return () => { active = false; cancelled += 1; };
  },
  draw:frame => resumedPaints.push(frame),
});
resumable.push({revision:5});
resumable.push({revision:6});
assert.equal(resumable.resume(), true);
assert.equal(cancelled, 1);
assert.equal(resumableCallbacks.length, 2);
resumableCallbacks[0]();
assert.deepEqual(resumedPaints, []);
resumableCallbacks[1]();
assert.deepEqual(resumedPaints, [{revision:6}]);
assert.equal(resumable.resume(), false);

console.log(JSON.stringify({status:'pass', latestWins:true, oneScheduled:true, visibleResume:true}));

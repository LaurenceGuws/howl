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
console.log(JSON.stringify({status:'pass', latestWins:true, oneScheduled:true}));

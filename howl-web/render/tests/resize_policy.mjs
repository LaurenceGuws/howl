import assert from 'node:assert/strict';
import {ResizePolicy} from '../web/resize_policy.mjs';

const policy = new ResizePolicy();
assert.equal(policy.decide({leaderPresent:false, controlId:'10'}), 'claim');
assert.equal(policy.decide({leaderPresent:true, controlId:'10'}), 'follow');
policy.accepted('10');
assert.equal(policy.decide({leaderPresent:true, controlId:'10'}), 'resize');
assert.equal(policy.decide({leaderPresent:false, controlId:'10'}), 'resize');
assert.equal(policy.decide({leaderPresent:true, controlId:'11'}), 'follow');
policy.rejected('11');
assert.equal(policy.owns('10'), true);
policy.rejected('10');
assert.equal(policy.decide({leaderPresent:true, controlId:'10'}), 'follow');
policy.reset();
assert.equal(policy.decide({leaderPresent:false, controlId:'12'}), 'claim');
assert.equal(policy.decide({leaderPresent:false, controlId:null}), 'wait');
console.log(JSON.stringify({status:'pass', stickyLeader:true, followerDoesNotSteal:true, rejectionDropsOwnership:true}));

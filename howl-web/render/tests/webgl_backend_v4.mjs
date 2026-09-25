import assert from 'node:assert/strict';
import {BinaryCommands} from '../web/frame_v4.mjs';
import {clippedSprite, webglFrameEligible} from '../web/webgl_backend_v4.mjs';

const solid = color => [0, 0, 0, 10, 10, ...color];
const alpha = (destination, clip = destination, source = [0, 0, 10, 10]) => [
  1, ...destination, ...clip, 1, 1, 0, 16, 16, ...source, 240, 220, 30, 255, 0,
];
const image = () => [
  2, 0, 0, 10, 10, 0, 0, 10, 10, 2, 1, 1, 10, 10, 0, 0, 10, 10,
];

function binary(list) {
  const bytes = new Uint8Array(list.length * 64);
  const view = new DataView(bytes.buffer);
  for (let i = 0; i < list.length; i += 1) {
    const command = list[i], base = i * 64, kind = command[0];
    bytes[base] = kind;
    view.setInt32(base + 4, command[1], true);
    view.setInt32(base + 8, command[2], true);
    view.setUint16(base + 12, command[3], true);
    view.setUint16(base + 14, command[4], true);
    if (kind === 0) {
      bytes.set(command.slice(5, 9), base + 60);
      continue;
    }
    view.setInt32(base + 16, command[5], true);
    view.setInt32(base + 20, command[6], true);
    view.setUint16(base + 24, command[7], true);
    view.setUint16(base + 26, command[8], true);
    view.setBigUint64(base + 32, BigInt(command[9]), true);
    view.setBigUint64(base + 40, BigInt(command[10]), true);
    bytes[base + 1] = command[11];
    view.setUint16(base + 48, command[12], true);
    view.setUint16(base + 50, command[13], true);
    view.setUint16(base + 52, command[14], true);
    view.setUint16(base + 54, command[15], true);
    view.setUint16(base + 56, command[16], true);
    view.setUint16(base + 58, command[17], true);
    if (kind === 1) {
      bytes[base + 2] = command[22] ? 1 : 0;
      bytes.set(command.slice(18, 22), base + 60);
    }
  }
  return new BinaryCommands({buffer:bytes.buffer}, 0, list.length, 64);
}
const frame = commands => ({commands:binary(commands)});

assert.equal(webglFrameEligible(frame([solid([0, 0, 0, 255])])), true);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 10, 10])])), true);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 20, 20])])), true);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 20, 20], [4, 6, 10, 8])])), true);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 15, 15])])), false);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 1001, 1001], [0, 0, 1001, 1001], [0, 0, 1000, 1000])])), false);
assert.equal(webglFrameEligible(frame([image()])), false);
assert.equal(webglFrameEligible(frame([solid([1, 2, 3, 255]), alpha([0, 0, 20, 20]), image()])), false);
assert.equal(webglFrameEligible(frame([alpha([0, 0, 20, 20], [30, 30, 2, 2])])), true);

assert.deepEqual(
  clippedSprite([0, 0, 20, 20], [4, 6, 10, 8], [0, 0, 10, 10]),
  {destination:[4, 6, 10, 8], source:[2, 3, 5, 4]},
);

console.log(JSON.stringify({status:'pass', backend:'webgl2', frame:'v4', fallback:'canvas2d'}));

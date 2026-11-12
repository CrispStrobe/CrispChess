const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');

for (const [file, load] of [
  ['lc0_onnx_bridge.js', (ctx, bytes) => ctx.lc0OnnxLoad('https://fixture/model.onnx', bytes)],
  ['searchless_onnx_bridge.js', (ctx, bytes) => ctx.searchlessOnnxLoad('fixture', 'https://fixture/model.onnx', bytes)],
]) {
  test(`${file}: shared-download views pass only their model bytes to ONNX`, async () => {
    const calls = [];
    const context = vm.createContext({
      console: { log() {}, warn() {} },
      // Loading supplied bytes must not issue another model request.
      fetch: async (url, options) => {
        assert.equal(options?.method, 'HEAD');
        return { ok: true };
      },
      ort: {
        env: { wasm: {} },
        InferenceSession: { create: async (buffer) => {
          calls.push(Array.from(new Uint8Array(buffer)));
          return { inputNames: [], outputNames: [], release: async () => {} };
        } },
      },
    });
    vm.runInContext(readFileSync(resolve(__dirname, '../web', file), 'utf8'), context);
    const backing = new Uint8Array([99, 1, 2, 3, 4, 88]);
    await load(context, backing.subarray(1, 5));
    assert.deepEqual(calls, [[1, 2, 3, 4]]);
  });
}

// THROWAWAY: controlled asynchronous callback; no native platform claims.
const fixture = { calls: 0, pending: [] };
globalThis.recordingFixture = fixture;
export function requestNative(callback) {
  fixture.calls += 1;
  fixture.pending.push(callback);
}
export function completeNative() {
  fixture.pending.shift()?.();
}

// THROWAWAY: separate browser consumer, public APIs and controlled callbacks.
import assert from "node:assert/strict";
import { writeFile } from "node:fs/promises";
import { chromium, expect } from "@playwright/test";
import { start } from "./serve.mjs";

const report = { boundary: "Chromium; synthetic time/native callback; application JSON codec", checks: [] };
const checked = name => { report.checks.push(name); console.log(`PASS ${name}`); };
const server = await start();
let browser;
try {
  browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined });
  report.browser = browser.version();
  const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
  const errors = [];
  page.on("pageerror", error => errors.push(String(error)));
  const url = `http://127.0.0.1:${server.address().port}/`;
  await page.goto(url);
  const click = name => page.getByRole("button", { name, exact: true }).click();
  await click("Increment");
  await click("No change");
  await click("Native request");
  await expect(page.locator("#recorded")).toHaveText("3");
  await expect(page.locator("#live-status")).toHaveText("pending");
  await click("Export recording");
  await expect.poll(async () => { try { return JSON.parse(await page.locator("#archive").inputValue()).entries.length; } catch { return -1; } }).toBe(3);
  const pendingArchive = await page.locator("#archive").inputValue();
  assert.ok(!pendingArchive.includes("never-captured"));
  await click("Import recording");
  await expect(page.locator("#replay-sequence")).toHaveText("3");
  await click("Toggle time travel debugger");
  await click("Previous state");
  await expect(page.locator("#replay-sequence")).toHaveText("2");
  await expect(page.locator("#replay-status")).toHaveText("ready");
  // Close the floating panel so live controls remain reachable at all sizes.
  await click("Close time travel debugger");
  await click("Complete native callback");
  await expect(page.locator("#recorded")).toHaveText("4");
  await expect(page.locator("#live-status")).toHaveText("finished");
  await expect(page.locator("#replay-sequence")).toHaveText("2");
  assert.equal(await page.evaluate(() => globalThis.recordingFixture.calls), 1);
  checked("No-op capture, safe projection and live async completion while replay is paused");

  await click("Increment");
  await click("Increment");
  await expect(page.locator("#recorded")).toHaveText("6");
  await click("Export recording");
  await expect.poll(async () => { try { return JSON.parse(await page.locator("#archive").inputValue()).entries.length; } catch { return -1; } }).toBe(6);
  const archiveText = await page.locator("#archive").inputValue();
  const archive = JSON.parse(archiveText);
  assert.equal(archive.entries.length, 6);
  await click("Import recording");
  await expect(page.locator("#window")).toHaveText("3/3");
  await expect(page.locator("#replay-sequence")).toHaveText("6");
  await click("Toggle time travel debugger");
  for (let n = 0; n < 3; n++) await click("Previous state");
  await expect(page.locator("#replay-sequence")).toHaveText("3");
  await click("BACK TO THE FUTURE");
  await expect(page.locator("#replay-sequence")).toHaveText("6");
  await expect(page.locator("#replay-points")).toHaveText("3");
  await expect(page.locator("#recorded")).toHaveText("6");
  assert.equal(await page.evaluate(() => globalThis.recordingFixture.calls), 1);
  await click("Close time travel debugger");
  checked("Configurable bounded window, absolute sequence and navigation without repeating effects");

  const invalidCases = [
    [a => a.entries.splice(1, 1), "OutOfOrder"],
    [a => a.entries.splice(1, 0, a.entries[0]), "OutOfOrder"],
    [a => a.entries[1].origin.recording_id = "other-session", "DifferentRecording"],
    [a => a.initial.origin.contract_id = "card-v2", "DifferentContract"],
    [a => a.entries[1].elapsed_ms = 0, "TimeWentBack"],
    [a => a.final.model.points = 999, "CheckpointMismatch"],
    [a => a.entries[1].event = "unknown", "Invalid archive"],
    [a => a.format = 2, "Invalid archive"],
  ];
  for (const [mutate, expected] of invalidCases) {
    const invalid = structuredClone(archive); mutate(invalid);
    await page.locator("#archive").fill(JSON.stringify(invalid));
    await click("Import recording");
    await expect(page.locator("#notice")).toContainText(expected);
    await expect(page.locator("#replay-sequence")).toHaveText("6");
  }
  await page.locator("#archive").fill(archiveText);
  await click("100 transitions");
  await click("Import recording");
  await expect(page.locator("#window")).toHaveText("6/6");
  checked("Eight malformed/incompatible histories rejected; previous viewer preserved; retry succeeds");

  // A fresh browser context imports bytes: no shared live state or callback.
  const remote = await browser.newPage();
  remote.on("pageerror", error => errors.push(String(error)));
  await remote.goto(url);
  await remote.locator("#archive").fill(archiveText);
  await remote.getByRole("button", { name: "Import recording", exact: true }).click();
  await expect(remote.locator("#replay-points")).toHaveText("3");
  await expect(remote.locator("#replay-status")).toHaveText("finished");
  await expect(remote.locator("#recorded")).toHaveText("0");
  assert.equal(await remote.evaluate(() => globalThis.recordingFixture.calls), 0);
  checked("JSON roundtrip into an independent browser context reconstructs state with zero native effects");

  assert.deepEqual(errors, []);
  await page.screenshot({ path: new URL("./recording.png", import.meta.url).pathname, fullPage: true });
  await writeFile(new URL("./report.json", import.meta.url), JSON.stringify(report, null, 2));
} finally {
  await browser?.close();
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
}

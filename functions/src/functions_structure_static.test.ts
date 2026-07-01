import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";

test("HTTP App Check verification lives outside the main functions index", async () => {
  const indexSource = await readFile(path.resolve(__dirname, "../src/index.ts"), "utf8");
  const helperSource = await readFile(path.resolve(__dirname, "../src/http_app_check.ts"), "utf8");

  assert.doesNotMatch(indexSource, /function verifyHttpAppCheck/);
  assert.match(indexSource, /from "\.\/http_app_check"/);
  assert.match(helperSource, /export async function verifyHttpAppCheck/);
});

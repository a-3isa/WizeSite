import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";

test("functions do not log payment amounts or metric deltas", async () => {
  const source = await readFile(path.resolve(__dirname, "../src/index.ts"), "utf8");

  assert.doesNotMatch(source, /\[payment\.create\./);
  assert.doesNotMatch(source, /\[metrics\.applyDelta\.tx\]/);
});

test("transcription provider error logs do not include response bodies", async () => {
  const source = await readFile(
    path.resolve(__dirname, "../src/voice/services/transcription.service.ts"),
    "utf8",
  );

  assert.doesNotMatch(source, /console\.error\([^)]*bodyText/s);
  assert.doesNotMatch(source, /console\.error\([^)]*body=/s);
});

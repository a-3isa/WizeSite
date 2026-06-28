import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import path from "node:path";
import test from "node:test";

test("storage rules enforce upload size and content type server-side", async () => {
  const rules = await readFile(
    path.resolve(__dirname, "../../storage.rules"),
    "utf8",
  );

  assert.match(rules, /request\.resource\.size\s*<=\s*10\s*\*\s*1024\s*\*\s*1024/);
  assert.match(rules, /request\.resource\.contentType\.matches/);
  assert.match(rules, /audio\/\(wav\|mpeg\|aac\|webm\|mp4\)/);
});

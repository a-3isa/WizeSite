import assert from "node:assert/strict";
import { test } from "node:test";

import { loadConfig } from "../../src/config";

const base = {
  DATABASE_URL: "postgres://u:p@localhost:5432/db",
  FILES_ROOT: "/tmp/files",
  FILES_SIGNING_KEY: "k",
  PUBLIC_API_URL: "https://api.example.com/",
};

test("loadConfig applies defaults and trims trailing slash", () => {
  const config = loadConfig(base);
  assert.equal(config.firebaseProjectId, "wize-site");
  assert.equal(config.port, 8080);
  assert.equal(config.publicApiUrl, "https://api.example.com");
});

test("loadConfig fails fast on a missing required variable", () => {
  assert.throws(() => loadConfig({ ...base, DATABASE_URL: "" }), /DATABASE_URL/);
});

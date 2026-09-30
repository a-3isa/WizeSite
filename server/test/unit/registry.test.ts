/**
 * T079: the RPC registry covers every callable the Cloud Functions export (except the `*Http`
 * twins, Firestore triggers and the webhook, which the contract removes or moves), plus the new
 * RPCs that replace direct client writes (contracts/rpc-api.md).
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";

import { buildRegistry } from "../../src/rpc/registry";

/** Not ported yet; each entry names the task that removes it from this list. */
const PENDING: Record<string, string> = {
  processVoiceExpense: "T076",
};

const NEW_RPCS = [
  "upsertEntity",
  "archiveEntity",
  "deleteEntity",
  "touchEntityLastUsed",
  "upsertWorkerAccountingRecord",
  "upsertContractorAccountingRecord",
  "upsertEquipmentAccountingRecord",
  "upsertTransportProviderAccountingRecord",
  "markNotificationsRead",
  "restoreMembership",
];

function firebaseCallables(): string[] {
  const source = readFileSync(path.resolve(__dirname, "../../../../functions/src/index.ts"), "utf8");
  const onCall = [...source.matchAll(/^export const (\w+) = onCall\(/gm)].map((m) => m[1]);
  const reExported = [...source.matchAll(/^export \{([^}]+)\} from/gm)]
    .flatMap((m) => m[1].split(","))
    .map((name) => name.trim())
    .filter((name) => name.length > 0 && !name.endsWith("Http"));
  return [...new Set([...onCall, ...reExported])].sort();
}

test("every Firebase callable and every new RPC is registered (pending ones listed with their task)", () => {
  const registry = buildRegistry({ files: { root: "/tmp", signingKey: "k", publicUrl: "https://api.test" } });
  const callables = firebaseCallables();
  assert.ok(callables.length >= 30, `parsed only ${callables.length} callables`);
  const missing = [...callables, ...NEW_RPCS].filter((name) => !(name in registry) && !(name in PENDING));
  assert.deepEqual(missing, []);
  for (const name of Object.keys(PENDING)) {
    assert.ok(!(name in registry), `${name} is registered now: remove it from PENDING`);
  }
});

test("every mutating RPC is marked mutating (idempotency key + one transaction)", () => {
  const registry = buildRegistry({ files: { root: "/tmp", signingKey: "k", publicUrl: "https://api.test" } });
  const readOnly = Object.entries(registry)
    .filter(([, fn]) => !fn.mutating)
    .map(([name]) => name)
    .sort();
  assert.deepEqual(readOnly, ["checkLimit", "getAttachmentDownloadUrl"]);
});

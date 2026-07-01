import assert from "node:assert/strict";
import test from "node:test";
import { buildEntityLastUsedAtBackfillPatch } from "./entity_last_used_backfill";

test("entity lastUsedAt backfill prefers createdAt then updatedAt then epoch", () => {
  const created = buildEntityLastUsedAtBackfillPatch("entity_created", {
    name: "Steel Supplier",
    createdAt: new Date(Date.UTC(2026, 5, 1)),
  });
  assert.equal(created?.id, "entity_created");
  assert.equal(created?.normalizedName, "steel supplier");
  assert.deepEqual(created?.lastUsedAt, new Date(Date.UTC(2026, 5, 1)));

  const updated = buildEntityLastUsedAtBackfillPatch("entity_updated", {
    name: "Updated Supplier",
    updatedAt: new Date(Date.UTC(2026, 5, 2)),
  });
  assert.deepEqual(updated?.lastUsedAt, new Date(Date.UTC(2026, 5, 2)));

  const epoch = buildEntityLastUsedAtBackfillPatch("entity_epoch", {
    name: "No Dates",
  });
  assert.deepEqual(epoch?.lastUsedAt, new Date(0));
});

test("entity lastUsedAt backfill is idempotent for already-normalized records", () => {
  const patch = buildEntityLastUsedAtBackfillPatch("entity_ready", {
    id: "entity_ready",
    name: "Ready Supplier",
    normalizedName: "ready supplier",
    createdAt: new Date(Date.UTC(2026, 5, 1)),
    lastUsedAt: new Date(Date.UTC(2026, 5, 3)),
  });

  assert.equal(patch, null);
});

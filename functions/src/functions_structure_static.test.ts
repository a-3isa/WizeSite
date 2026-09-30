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
  assert.match(indexSource, /onCall\(\{\s*enforceAppCheck:\s*true/);
  assert.match(indexSource, /export const deleteOwnAccount = onCall/);
  assert.match(indexSource, /from "\.\/idempotency"/);
  assert.match(indexSource, /commitIdempotentCreate/);
  assert.match(indexSource, /deleteUserStorage/);
  assert.match(indexSource, /assertCanMutateMoney/);
  assert.match(indexSource, /assertCanManageProject/);
  assert.match(indexSource, /quota:\s*\{/);
  const createProjectSource = indexSource.slice(
    indexSource.indexOf("export async function createProjectWithQuotaForUser"),
    indexSource.indexOf("export const createProjectWithQuota ="),
  );
  assert.match(createProjectSource, /quota:\s*\{/);
  assert.match(createProjectSource, /field:\s*"activeProjectsCount"/);
  assert.match(createProjectSource, /\$\{workspaceId\}_projects/);
  assert.doesNotMatch(
    createProjectSource,
    /getCurrentUsage\(workspaceId, "activeProjects"\)/,
  );
  assert.match(
    indexSource,
    /async function getCurrentUsage[\s\S]*_projects[\s\S]*activeProjectsCount/,
  );
  const globalOptions = indexSource.match(
    /setGlobalOptions\(\{[\s\S]*?\}\);/,
  )?.[0] ?? "";
  assert.doesNotMatch(globalOptions, /enforceAppCheck/);
});

test("every onCall enforces App Check", async () => {
  const files = ["index.ts", "voice/process_voice_expense.ts"];
  for (const rel of files) {
    const source = await readFile(path.resolve(__dirname, `../src/${rel}`), "utf8");
    const onCalls = source.match(/onCall\(/g) ?? [];
    const enforced = source.match(/enforceAppCheck:\s*true/g) ?? [];
    assert.equal(
      onCalls.length,
      enforced.length,
      `${rel} onCall count must match enforceAppCheck: true`,
    );
  }
});

test("quota HTTP twins stay paired with callables", async () => {
  const indexSource = await readFile(path.resolve(__dirname, "../src/index.ts"), "utf8");
  const twins: Array<[string, string]> = [
    ["createProjectWithQuota", "createProjectWithQuotaHttp"],
    ["createExpenseWithQuota", "createExpenseWithQuotaHttp"],
    ["createPaymentWithQuota", "createPaymentWithQuotaHttp"],
    ["createWorkerEntryWithQuota", "createWorkerEntryWithQuotaHttp"],
    ["archiveExpenseWithQuotaRefund", "archiveExpenseWithQuotaRefundHttp"],
    ["archivePaymentWithQuotaRefund", "archivePaymentWithQuotaRefundHttp"],
    ["archiveWorkerEntryWithQuotaRefund", "archiveWorkerEntryWithQuotaRefundHttp"],
  ];
  for (const [callable, http] of twins) {
    assert.match(indexSource, new RegExp(`export const ${callable} = onCall`));
    assert.match(indexSource, new RegExp(`export const ${http} = onRequest`));
  }
});

import assert from "node:assert/strict";
import test from "node:test";
import { classifyProjectRisk } from "../../src/domain/accounting";

/**
 * Risk classification for projects with and without a Contract Value.
 *
 * Runs without the Firestore emulator, deliberately: this rule decides whether
 * a notification is pushed to every member with risk alerts enabled, and it
 * used to fire on both of its arms for any project that had expenses and no
 * contract. Leaving it covered only by emulator-gated tests would mean it ships
 * unverified in most environments.
 */

test("a project with no contract value receives no verdict at all", () => {
  const verdict = classifyProjectRisk({
    contractValue: null,
    netProfit: -5000,
    expectedFinalCost: 5000,
  });

  // Null, not "low": the project is unrated, not certified healthy.
  assert.equal(verdict.riskLevel, null);
  assert.equal(verdict.healthStatus, null);
});

test("the negative-net rule alone cannot flag a contract-less project", () => {
  // This is the case that made the original rule misfire. An expense-only
  // project always has netProfit < 0 once it records anything, so suppressing
  // only the contract comparison would have flagged every one as "losing".
  const verdict = classifyProjectRisk({
    contractValue: null,
    netProfit: -1,
    expectedFinalCost: 1,
  });

  assert.equal(verdict.riskLevel, null);
  assert.notEqual(verdict.riskLevel, "high");
});

test("a contract-less project stays unrated no matter how large the spend", () => {
  const verdict = classifyProjectRisk({
    contractValue: null,
    netProfit: -10_000_000,
    expectedFinalCost: 10_000_000,
  });

  assert.equal(verdict.riskLevel, null);
  assert.equal(verdict.healthStatus, null);
});

test("a healthy contract-bearing project is unchanged", () => {
  const verdict = classifyProjectRisk({
    contractValue: 100_000,
    netProfit: 20_000,
    expectedFinalCost: 50_000,
  });

  assert.equal(verdict.riskLevel, "low");
  assert.equal(verdict.healthStatus, "healthy");
});

test("a contract-bearing project nearing its contract warns", () => {
  const verdict = classifyProjectRisk({
    contractValue: 100_000,
    netProfit: 5_000,
    expectedFinalCost: 95_000,
  });

  assert.equal(verdict.riskLevel, "medium");
  assert.equal(verdict.healthStatus, "warning");
});

test("a contract-bearing project running at a loss is still high risk", () => {
  const verdict = classifyProjectRisk({
    contractValue: 100_000,
    netProfit: -1,
    expectedFinalCost: 10_000,
  });

  assert.equal(verdict.riskLevel, "high");
  assert.equal(verdict.healthStatus, "losing");
});

test("a contract-bearing project overrunning its contract is high risk", () => {
  const verdict = classifyProjectRisk({
    contractValue: 100_000,
    netProfit: 1_000,
    expectedFinalCost: 120_000,
  });

  assert.equal(verdict.riskLevel, "high");
  assert.equal(verdict.healthStatus, "losing");
});

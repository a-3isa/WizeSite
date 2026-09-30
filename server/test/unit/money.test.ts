import assert from "node:assert/strict";
import test from "node:test";
import {
  canCreateProject,
  canDeleteProjectCascade,
  canMutateMoneyViaCallable,
  canUpdateProject,
  cashCollectedAmount,
  archivePaymentCashDelta,
  isAllowedExpenseCategory,
  normalizeExpenseCategory,
  parsePaymentStatus,
  roundMoney,
} from "../../src/domain/money";

test("missing payment status counts as paid cash", () => {
  assert.equal(cashCollectedAmount({amount: 1500}), 1500);
});

test("unpaid payments do not count as cash collected", () => {
  assert.equal(
    cashCollectedAmount({amount: 3000, paymentStatus: "unpaid"}),
    0,
  );
});

test("archiving an unpaid payment does not change cash metrics", () => {
  assert.equal(
    archivePaymentCashDelta({amount: 3000, paymentStatus: "unpaid"}),
    0,
  );
});

test("archiving a paid payment subtracts cash collected", () => {
  assert.equal(
    archivePaymentCashDelta({amount: 1500, paymentStatus: "paid"}),
    -1500,
  );
});

test("roundMoney uses two decimal places", () => {
  assert.equal(roundMoney(10.129), 10.13);
  assert.equal(cashCollectedAmount({amount: 10.129, paymentStatus: "paid"}), 10.13);
});

test("partial with paidAmount counts only the paid split", () => {
  assert.equal(
    cashCollectedAmount({
      amount: 2000,
      paymentStatus: "partial",
      paidAmount: 750,
    }),
    750,
  );
});

test("legacy labor category is stored as worker", () => {
  assert.equal(normalizeExpenseCategory("labor"), "worker");
  assert.equal(isAllowedExpenseCategory("worker"), true);
  assert.equal(isAllowedExpenseCategory("labor"), true);
});

test("parsePaymentStatus falls back when the value is junk", () => {
  assert.equal(parsePaymentStatus("nope", "unpaid"), "unpaid");
  assert.equal(parsePaymentStatus("paid", "unpaid"), "paid");
});

test("admins and accounting can create projects; entryOnly cannot", () => {
  assert.equal(canCreateProject("admin"), true);
  assert.equal(canCreateProject("accountingApproved"), true);
  assert.equal(canCreateProject("entryOnly"), false);
  assert.equal(canUpdateProject("member"), true);
  assert.equal(canUpdateProject("entryOnly"), false);
});

test("only owner and admin may cascade-delete a project", () => {
  assert.equal(canDeleteProjectCascade("owner"), true);
  assert.equal(canDeleteProjectCascade("member"), false);
  assert.equal(canDeleteProjectCascade("entryOnly"), false);
});

test("entryOnly cannot mutate money through callables", () => {
  assert.equal(canMutateMoneyViaCallable("member"), true);
  assert.equal(canMutateMoneyViaCallable("entryOnly"), false);
});

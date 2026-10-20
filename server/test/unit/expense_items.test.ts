/** Feature 005: expense line items (contracts/rpc-expense-items.md §1, data-model.md §2). */
import assert from "node:assert/strict";
import test from "node:test";

import { assertAmountMatchesItems, parseExpenseItems } from "../../src/rpc/expense_items";

const item = (over: Record<string, unknown> = {}) => ({ id: "item_a1", name: "حنفية", amount: 100, ...over });

function rejects(fn: () => unknown, message: string) {
  assert.throws(fn, (error: { code?: string; message?: string }) => {
    assert.equal(error.code, "invalid-argument");
    assert.equal(error.message, message);
    return true;
  });
}

test("absent items means a legacy write", () => {
  assert.equal(parseExpenseItems({}), null);
  assert.equal(parseExpenseItems({ items: null }), null);
});

test("valid items are normalized in order and totalled", () => {
  const parsed = parseExpenseItems({
    items: [
      item({ id: "item_a1", name: "  حنفية ", amount: 100 }),
      item({ id: "item_b2", name: "جلبه", amount: "50", quantity: 2, note: " كبيرة " }),
      item({ id: "item_c3", name: "ماسورة", amount: 90 }),
    ],
  });
  assert.ok(parsed);
  assert.equal(parsed.total, 240);
  assert.deepEqual(parsed.items, [
    { id: "item_a1", name: "حنفية", amount: 100, quantity: null, note: "" },
    { id: "item_b2", name: "جلبه", amount: 50, quantity: 2, note: "كبيرة" },
    { id: "item_c3", name: "ماسورة", amount: 90, quantity: null, note: "" },
  ]);
});

test("missing ids are generated; duplicate ids are rejected", () => {
  const parsed = parseExpenseItems({ items: [{ name: "رمل", amount: 10 }, { name: "زلط", amount: 20 }] });
  assert.ok(parsed);
  assert.match(parsed.items[0].id, /^[A-Za-z0-9_-]{6,36}$/);
  assert.notEqual(parsed.items[0].id, parsed.items[1].id);
  rejects(() => parseExpenseItems({ items: [item(), item()] }), "Item 2: duplicate id");
  rejects(() => parseExpenseItems({ items: [item({ id: "bad id!" })] }), "Item 1: invalid id");
});

test("each invalid field is rejected with a 1-based item message", () => {
  rejects(() => parseExpenseItems({ items: [item({ name: "   " })] }), "Item 1: name is required");
  rejects(() => parseExpenseItems({ items: [item(), item({ id: "item_b2", name: "x".repeat(121) })] }), "Item 2: name is too long");
  rejects(() => parseExpenseItems({ items: [item({ amount: 0 })] }), "Item 1: amount must be greater than zero");
  rejects(() => parseExpenseItems({ items: [item({ amount: -5 })] }), "Item 1: amount must be greater than zero");
  rejects(() => parseExpenseItems({ items: [item({ amount: "abc" })] }), "Item 1: amount must be greater than zero");
  rejects(() => parseExpenseItems({ items: [item({ amount: 1.005 })] }), "Item 1: amount can have at most 2 decimal places");
  rejects(() => parseExpenseItems({ items: [item({ quantity: 0 })] }), "Item 1: quantity must be greater than zero");
  rejects(() => parseExpenseItems({ items: [item({ note: "n".repeat(201) })] }), "Item 1: note is too long");
  rejects(() => parseExpenseItems({ items: ["x"] }), "Item 1: name is required");
});

test("item count must be between 1 and 100", () => {
  rejects(() => parseExpenseItems({ items: [] }), "Expense must have between 1 and 100 items");
  rejects(() => parseExpenseItems({ items: "nope" }), "Expense must have between 1 and 100 items");
  const many = Array.from({ length: 101 }, (_, i) => item({ id: `item_${i}xx`, amount: 1 }));
  rejects(() => parseExpenseItems({ items: many }), "Expense must have between 1 and 100 items");
  assert.equal(parseExpenseItems({ items: many.slice(0, 100) })?.items.length, 100);
});

test("totals are summed in piastres, so float noise never breaks equality", () => {
  const parsed = parseExpenseItems({
    items: [item({ id: "item_a1", amount: 0.1 }), item({ id: "item_b2", amount: 0.2 })],
  });
  assert.ok(parsed);
  assert.equal(parsed.total, 0.3);
  assert.doesNotThrow(() => assertAmountMatchesItems(0.3, parsed.total));
  assert.doesNotThrow(() => assertAmountMatchesItems(null, parsed.total));
  rejects(() => assertAmountMatchesItems(0.31, parsed.total), "Amount must equal the sum of items");
});

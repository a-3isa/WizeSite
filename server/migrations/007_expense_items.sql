-- Up Migration
-- Feature 005 (multi-item expenses, data-model.md §1). An expense is one receipt with ordered line
-- items. Items live on the expense row so the expense and its items are always written and synced
-- as one unit. `amount` stays the total read by every recompute; it must equal the item sum.
-- Existing rows keep items = '[]' (legacy expenses, read with a one-item fallback): no backfill,
-- no money value changes.

-- Sum of item amounts, exact in NUMERIC. IMMUTABLE so it can back a CHECK constraint.
CREATE FUNCTION expense_items_total(items jsonb) RETURNS numeric
LANGUAGE sql IMMUTABLE STRICT AS $$
  SELECT COALESCE(SUM((elem ->> 'amount')::numeric), 0)
  FROM jsonb_array_elements(items) AS elem
$$;

ALTER TABLE expenses
  ADD COLUMN items JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD CONSTRAINT expenses_items_is_array CHECK (jsonb_typeof(items) = 'array'),
  ADD CONSTRAINT expenses_items_max CHECK (jsonb_array_length(items) <= 100),
  ADD CONSTRAINT expenses_amount_matches_items
    CHECK (items = '[]'::jsonb OR amount = expense_items_total(items));

-- Down Migration
ALTER TABLE expenses
  DROP CONSTRAINT expenses_amount_matches_items,
  DROP CONSTRAINT expenses_items_max,
  DROP CONSTRAINT expenses_items_is_array,
  DROP COLUMN items;
DROP FUNCTION expense_items_total(jsonb);

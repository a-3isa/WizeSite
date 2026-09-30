-- Up Migration
-- A worker entry's total cost is days worked x daily wage, both entered with up to 2 decimals, so
-- it needs up to 4 (1.25 x 75.25 = 94.0625). NUMERIC(14,2) would round it silently (Constitution
-- II), while Firestore kept the exact product. Widen the scale; existing values are unchanged.

ALTER TABLE worker_entries ALTER COLUMN total_cost TYPE NUMERIC(18, 4);

-- Down Migration

ALTER TABLE worker_entries ALTER COLUMN total_cost TYPE NUMERIC(14, 2);

-- Up Migration
-- completion_percentage is a progress figure, not money: the app stores arbitrary doubles
-- (e.g. 32.80725319006043) and the cost-at-completion estimate divides by it, so NUMERIC(5,2)
-- would either reject real data at migration or shift derived estimates. Store it exactly, as
-- Firestore did (spec 004, T056 staging finding).

ALTER TABLE projects
  ALTER COLUMN completion_percentage TYPE DOUBLE PRECISION
  USING completion_percentage::double precision;

-- Down Migration

ALTER TABLE projects
  ALTER COLUMN completion_percentage TYPE NUMERIC(5, 2)
  USING round(completion_percentage::numeric, 2);

-- Migration 027: users add assets to the shared catalog
--
-- POST /assets adds a stock, ETF or USD crypto pair that Yahoo quotes, with no
-- category. added_by is who added it, NULL for the assets seeded in 026.
--
-- Assets waiting for a category:
--   SELECT symbol, name, type, added_by, created_at FROM assets WHERE category IS NULL;
-- Setting one (only users who add it afterwards are subscribed to the category):
--   UPDATE assets SET category = 'Software' WHERE symbol = 'XYZ';

ALTER TABLE assets ADD COLUMN added_by UUID REFERENCES users(id) ON DELETE SET NULL;

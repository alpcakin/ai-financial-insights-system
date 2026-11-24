-- Migration 033: daily closes of held assets, shared by every user
--
-- Home draws each user's portfolio value over the last 30 days. The closes come
-- from Yahoo once per asset (services/price_history_service.py, on a schedule and
-- when an asset is first held), not once per user, and every user's line is
-- computed from this table (DEVELOPMENT_JOURNAL.md 2.96). Crypto closes are the
-- last hourly price of each UTC day, as in the volatility measurement (2.92),
-- because Yahoo rounds the daily bars of coins worth a fraction of a cent.
-- A renamed asset keeps its closes under the new symbol.
--
-- Reached only through the service role, like assets: RLS is on with no policies.
-- Apply before starting the new backend: the price history job writes here.

CREATE TABLE asset_closes (
    symbol TEXT NOT NULL REFERENCES assets(symbol) ON UPDATE CASCADE ON DELETE CASCADE,
    close_date DATE NOT NULL,
    price DOUBLE PRECISION NOT NULL CHECK (price > 0),
    PRIMARY KEY (symbol, close_date)
);

ALTER TABLE asset_closes ENABLE ROW LEVEL SECURITY;

-- Migration 026: Asset catalog in the database
--
-- The catalog moves from code (services/asset_catalog.py) to a table, so it can
-- grow and be corrected while the system runs.
--
-- 1. assets: every asset that is not inactive goes into the analysis prompt
--    with its name, whether anyone holds it or not, so the search screen can
--    show news about any of them. status:
--      active        normal.
--      needs_review  the daily Yahoo check could not confirm the symbol and
--                    found no single replacement. It stays in the prompt, but
--                    its price alerts stop until it is resolved by hand.
--      inactive      Yahoo returned no data for three checks in a row. Left out
--                    of the prompt and of new portfolio and watchlist adds.
--    yahoo_name is Yahoo's name for the symbol when it was last confirmed; the
--    check compares against it. previous_symbols keeps the symbols an asset had
--    before a rename: stored analyses are never rewritten, so the search looks
--    for all of them.
-- 2. The 148 assets of the code catalog. Two names follow Yahoo's (IBM, Polygon),
--    otherwise the first check could not confirm them.
-- 3. rename_asset moves an asset to a new symbol, with the portfolio, watchlist
--    and alert setting rows that use it. Alerts already sent keep the old symbol.
--    Resolving a review by hand, with the names from review_note:
--      SELECT rename_asset('OLD-USD', 'NEW-USD', 'New name', 'Yahoo name of NEW-USD');
--    or, when the symbol turns out to be right:
--      UPDATE assets SET status = 'active', review_note = NULL,
--          yahoo_name = 'Yahoo name from the note' WHERE symbol = 'OLD-USD';
-- 4. asset_news takes the current and previous symbols of the asset.
--
-- assets is reached only through the service role, like articles: RLS is on
-- with no policies.
--
-- Apply with the backend stopped and start the matching backend version after it.

BEGIN;

CREATE TABLE assets (
    symbol TEXT PRIMARY KEY CHECK (symbol = upper(symbol)),
    name TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('stock', 'etf', 'crypto', 'commodity')),
    category TEXT REFERENCES categories(name) ON UPDATE CASCADE ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'needs_review', 'inactive')),
    yahoo_name TEXT,
    previous_symbols TEXT[] NOT NULL DEFAULT '{}',
    review_note TEXT,
    missed_checks SMALLINT NOT NULL DEFAULT 0,
    checked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE assets ENABLE ROW LEVEL SECURITY;

INSERT INTO assets (symbol, name, type, category) VALUES
    ('AAPL', 'Apple Inc.', 'stock', 'Consumer Electronics'),
    ('MSFT', 'Microsoft Corporation', 'stock', 'Software'),
    ('GOOGL', 'Alphabet Inc.', 'stock', 'Software'),
    ('ORCL', 'Oracle Corporation', 'stock', 'Software'),
    ('CRM', 'Salesforce Inc.', 'stock', 'Software'),
    ('NOW', 'ServiceNow Inc.', 'stock', 'Software'),
    ('ADBE', 'Adobe Inc.', 'stock', 'Software'),
    ('ZM', 'Zoom Video Communications', 'stock', 'Software'),
    ('IBM', 'International Business Machines (IBM)', 'stock', 'Software'),
    ('NVDA', 'NVIDIA Corporation', 'stock', 'Semiconductors'),
    ('AMD', 'Advanced Micro Devices', 'stock', 'Semiconductors'),
    ('INTC', 'Intel Corporation', 'stock', 'Semiconductors'),
    ('AVGO', 'Broadcom Inc.', 'stock', 'Semiconductors'),
    ('QCOM', 'Qualcomm Incorporated', 'stock', 'Semiconductors'),
    ('TXN', 'Texas Instruments Inc.', 'stock', 'Semiconductors'),
    ('MU', 'Micron Technology Inc.', 'stock', 'Semiconductors'),
    ('AMAT', 'Applied Materials Inc.', 'stock', 'Semiconductors'),
    ('ARM', 'Arm Holdings plc', 'stock', 'Semiconductors'),
    ('CRWD', 'CrowdStrike Holdings', 'stock', 'Cybersecurity'),
    ('PANW', 'Palo Alto Networks Inc.', 'stock', 'Cybersecurity'),
    ('NET', 'Cloudflare Inc.', 'stock', 'Cybersecurity'),
    ('FTNT', 'Fortinet Inc.', 'stock', 'Cybersecurity'),
    ('PLTR', 'Palantir Technologies', 'stock', 'AI & Machine Learning'),
    ('SNOW', 'Snowflake Inc.', 'stock', 'Cloud & Infrastructure'),
    ('CSCO', 'Cisco Systems Inc.', 'stock', 'Cloud & Infrastructure'),
    ('JPM', 'JPMorgan Chase & Co.', 'stock', 'Banking'),
    ('BAC', 'Bank of America Corp.', 'stock', 'Banking'),
    ('GS', 'Goldman Sachs Group Inc.', 'stock', 'Banking'),
    ('MS', 'Morgan Stanley', 'stock', 'Banking'),
    ('WFC', 'Wells Fargo & Company', 'stock', 'Banking'),
    ('C', 'Citigroup Inc.', 'stock', 'Banking'),
    ('V', 'Visa Inc.', 'stock', 'Fintech'),
    ('MA', 'Mastercard Inc.', 'stock', 'Fintech'),
    ('AXP', 'American Express Company', 'stock', 'Fintech'),
    ('PYPL', 'PayPal Holdings Inc.', 'stock', 'Fintech'),
    ('BRK-B', 'Berkshire Hathaway B', 'stock', 'Investment'),
    ('BLK', 'BlackRock Inc.', 'stock', 'Investment'),
    ('SCHW', 'Charles Schwab Corporation', 'stock', 'Investment'),
    ('UNH', 'UnitedHealth Group Inc.', 'stock', 'Insurance'),
    ('XOM', 'Exxon Mobil Corporation', 'stock', 'Oil & Gas'),
    ('CVX', 'Chevron Corporation', 'stock', 'Oil & Gas'),
    ('NEE', 'NextEra Energy Inc.', 'stock', 'Renewable Energy'),
    ('DUK', 'Duke Energy Corporation', 'stock', 'Utilities'),
    ('SO', 'Southern Company', 'stock', 'Utilities'),
    ('TSLA', 'Tesla Inc.', 'stock', 'Electric Vehicles'),
    ('RIVN', 'Rivian Automotive Inc.', 'stock', 'Electric Vehicles'),
    ('NIO', 'NIO Inc.', 'stock', 'Electric Vehicles'),
    ('F', 'Ford Motor Company', 'stock', 'Traditional Auto'),
    ('GM', 'General Motors Company', 'stock', 'Traditional Auto'),
    ('LLY', 'Eli Lilly and Company', 'stock', 'Pharmaceuticals'),
    ('JNJ', 'Johnson & Johnson', 'stock', 'Pharmaceuticals'),
    ('MRK', 'Merck & Co. Inc.', 'stock', 'Pharmaceuticals'),
    ('ABBV', 'AbbVie Inc.', 'stock', 'Pharmaceuticals'),
    ('BMY', 'Bristol-Myers Squibb Company', 'stock', 'Pharmaceuticals'),
    ('PFE', 'Pfizer Inc.', 'stock', 'Pharmaceuticals'),
    ('NVO', 'Novo Nordisk A/S', 'stock', 'Pharmaceuticals'),
    ('CVS', 'CVS Health Corporation', 'stock', 'Pharmaceuticals'),
    ('MRNA', 'Moderna Inc.', 'stock', 'Biotechnology'),
    ('REGN', 'Regeneron Pharmaceuticals', 'stock', 'Biotechnology'),
    ('GILD', 'Gilead Sciences Inc.', 'stock', 'Biotechnology'),
    ('AMGN', 'Amgen Inc.', 'stock', 'Biotechnology'),
    ('MDT', 'Medtronic plc', 'stock', 'Medical Devices'),
    ('ABT', 'Abbott Laboratories', 'stock', 'Medical Devices'),
    ('SYK', 'Stryker Corporation', 'stock', 'Medical Devices'),
    ('ISRG', 'Intuitive Surgical Inc.', 'stock', 'Medical Devices'),
    ('AMZN', 'Amazon.com Inc.', 'stock', 'E-Commerce'),
    ('ABNB', 'Airbnb Inc.', 'stock', 'E-Commerce'),
    ('BKNG', 'Booking Holdings Inc.', 'stock', 'E-Commerce'),
    ('PG', 'Procter & Gamble Co.', 'stock', 'Food & Beverage'),
    ('KO', 'The Coca-Cola Company', 'stock', 'Food & Beverage'),
    ('PEP', 'PepsiCo Inc.', 'stock', 'Food & Beverage'),
    ('MCD', 'McDonald''s Corporation', 'stock', 'Food & Beverage'),
    ('SBUX', 'Starbucks Corporation', 'stock', 'Food & Beverage'),
    ('CMG', 'Chipotle Mexican Grill Inc.', 'stock', 'Food & Beverage'),
    ('META', 'Meta Platforms Inc.', 'stock', 'Media & Entertainment'),
    ('NFLX', 'Netflix Inc.', 'stock', 'Media & Entertainment'),
    ('DIS', 'The Walt Disney Company', 'stock', 'Media & Entertainment'),
    ('SPOT', 'Spotify Technology S.A.', 'stock', 'Media & Entertainment'),
    ('SNAP', 'Snap Inc.', 'stock', 'Media & Entertainment'),
    ('WMT', 'Walmart Inc.', 'stock', 'Retail'),
    ('COST', 'Costco Wholesale Corporation', 'stock', 'Retail'),
    ('HD', 'The Home Depot Inc.', 'stock', 'Retail'),
    ('NKE', 'Nike Inc.', 'stock', 'Retail'),
    ('TGT', 'Target Corporation', 'stock', 'Retail'),
    ('LULU', 'Lululemon Athletica Inc.', 'stock', 'Retail'),
    ('HON', 'Honeywell International Inc.', 'stock', 'Aerospace & Defense'),
    ('RTX', 'RTX Corporation', 'stock', 'Aerospace & Defense'),
    ('LMT', 'Lockheed Martin Corporation', 'stock', 'Aerospace & Defense'),
    ('BA', 'The Boeing Company', 'stock', 'Aerospace & Defense'),
    ('GE', 'GE Aerospace', 'stock', 'Aerospace & Defense'),
    ('UBER', 'Uber Technologies Inc.', 'stock', 'Transportation & Logistics'),
    ('FDX', 'FedEx Corporation', 'stock', 'Transportation & Logistics'),
    ('UPS', 'United Parcel Service Inc.', 'stock', 'Transportation & Logistics'),
    ('CAT', 'Caterpillar Inc.', 'stock', 'Transportation & Logistics'),
    ('DE', 'Deere & Company', 'stock', 'Transportation & Logistics'),
    ('AMT', 'American Tower Corporation', 'stock', 'REITs'),
    ('PLD', 'Prologis Inc.', 'stock', 'REITs'),
    ('EQIX', 'Equinix Inc.', 'stock', 'REITs'),
    ('SPY', 'SPDR S&P 500 ETF Trust', 'etf', 'Investment'),
    ('VOO', 'Vanguard S&P 500 ETF', 'etf', 'Investment'),
    ('VTI', 'Vanguard Total Stock Market ETF', 'etf', 'Investment'),
    ('IWM', 'iShares Russell 2000 ETF', 'etf', 'Investment'),
    ('VEA', 'Vanguard Developed Markets ETF', 'etf', 'Investment'),
    ('EEM', 'iShares MSCI Emerging Markets ETF', 'etf', 'Investment'),
    ('TLT', 'iShares 20+ Year Treasury ETF', 'etf', 'Investment'),
    ('SCHD', 'Schwab US Dividend Equity ETF', 'etf', 'Investment'),
    ('JEPI', 'JPMorgan Equity Premium Income ETF', 'etf', 'Investment'),
    ('BND', 'Vanguard Total Bond Market ETF', 'etf', 'Investment'),
    ('XLF', 'Financial Select Sector SPDR', 'etf', 'Banking'),
    ('QQQ', 'Invesco QQQ Trust', 'etf', 'Software'),
    ('XLK', 'Technology Select Sector SPDR', 'etf', 'Software'),
    ('ARKK', 'ARK Innovation ETF', 'etf', 'AI & Machine Learning'),
    ('XLE', 'Energy Select Sector SPDR', 'etf', 'Oil & Gas'),
    ('XLV', 'Health Care Select Sector SPDR', 'etf', 'Pharmaceuticals'),
    ('XLY', 'Consumer Discret. Select Sector SPDR', 'etf', 'Retail'),
    ('VNQ', 'Vanguard Real Estate ETF', 'etf', 'REITs'),
    ('GLD', 'SPDR Gold Shares', 'etf', 'Precious Metals'),
    ('IBIT', 'iShares Bitcoin Trust ETF', 'etf', 'Bitcoin'),
    ('BTC-USD', 'Bitcoin', 'crypto', 'Bitcoin'),
    ('ETH-USD', 'Ethereum', 'crypto', 'Altcoins'),
    ('BNB-USD', 'BNB', 'crypto', 'Altcoins'),
    ('SOL-USD', 'Solana', 'crypto', 'Altcoins'),
    ('XRP-USD', 'XRP', 'crypto', 'Altcoins'),
    ('ADA-USD', 'Cardano', 'crypto', 'Altcoins'),
    ('AVAX-USD', 'Avalanche', 'crypto', 'Altcoins'),
    ('DOGE-USD', 'Dogecoin', 'crypto', 'Altcoins'),
    ('DOT-USD', 'Polkadot', 'crypto', 'Altcoins'),
    ('ATOM-USD', 'Cosmos', 'crypto', 'Altcoins'),
    ('LTC-USD', 'Litecoin', 'crypto', 'Altcoins'),
    ('FIL-USD', 'Filecoin', 'crypto', 'Altcoins'),
    ('SHIB-USD', 'Shiba Inu', 'crypto', 'Altcoins'),
    ('TRX-USD', 'TRON', 'crypto', 'Altcoins'),
    ('TON-USD', 'Toncoin', 'crypto', 'Altcoins'),
    ('POL28321-USD', 'Polygon (prev. MATIC)', 'crypto', 'DeFi'),
    ('LINK-USD', 'Chainlink', 'crypto', 'DeFi'),
    ('UNI7083-USD', 'Uniswap', 'crypto', 'DeFi'),
    ('OP-USD', 'Optimism', 'crypto', 'DeFi'),
    ('ARB-USD', 'Arbitrum', 'crypto', 'DeFi'),
    ('GC=F', 'Gold Futures', 'commodity', 'Precious Metals'),
    ('SI=F', 'Silver Futures', 'commodity', 'Precious Metals'),
    ('PL=F', 'Platinum Futures', 'commodity', 'Precious Metals'),
    ('PA=F', 'Palladium Futures', 'commodity', 'Precious Metals'),
    ('CL=F', 'Crude Oil Futures', 'commodity', 'Oil & Gas'),
    ('NG=F', 'Natural Gas Futures', 'commodity', 'Oil & Gas'),
    ('HG=F', 'Copper Futures', 'commodity', 'Base Metals'),
    ('ZW=F', 'Wheat Futures', 'commodity', 'Agriculture'),
    ('ZC=F', 'Corn Futures', 'commodity', 'Agriculture'),
    ('ZS=F', 'Soybean Futures', 'commodity', 'Agriculture');

CREATE FUNCTION rename_asset(p_old TEXT, p_new TEXT, p_name TEXT, p_yahoo_name TEXT)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM assets WHERE symbol = p_new OR p_new = ANY (previous_symbols)) THEN
        RAISE EXCEPTION 'asset % is already in the catalog', p_new;
    END IF;

    UPDATE assets
    SET symbol = p_new,
        name = p_name,
        yahoo_name = p_yahoo_name,
        previous_symbols = array_append(previous_symbols, p_old),
        status = 'active',
        review_note = NULL,
        missed_checks = 0,
        checked_at = NOW()
    WHERE symbol = p_old;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'asset % is not in the catalog', p_old;
    END IF;

    UPDATE portfolio SET asset_symbol = p_new WHERE asset_symbol = p_old;
    UPDATE watchlist SET asset_symbol = p_new WHERE asset_symbol = p_old;
    UPDATE asset_alert_settings SET asset_symbol = p_new WHERE asset_symbol = p_old;
END;
$$;

REVOKE EXECUTE ON FUNCTION rename_asset(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION rename_asset(TEXT, TEXT, TEXT, TEXT) TO service_role;

DROP FUNCTION asset_news(UUID, TEXT, BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, INTEGER);

-- p_provider_order is the fallback order for shared stories, p_model_order for
-- the user's own: their own models only.
CREATE FUNCTION asset_news(
    p_user_id UUID,
    p_symbols TEXT[],
    p_package BOOLEAN,
    p_manual BOOLEAN,
    p_provider_order TEXT[],
    p_model_order TEXT[],
    p_limit INTEGER,
    p_offset INTEGER
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    url TEXT,
    source TEXT,
    published_at TIMESTAMPTZ,
    owner_id UUID,
    provider TEXT,
    provider_label TEXT,
    summary TEXT,
    sentiment_label TEXT,
    severity SMALLINT,
    related_categories TEXT[],
    related_assets TEXT[],
    asset_impacts JSONB,
    read BOOLEAN,
    total BIGINT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
    WITH shown AS (
        SELECT DISTINCT ON (an.article_id) an.*
        FROM article_analyses an
        JOIN articles a ON a.id = an.article_id
        WHERE an.related_assets && p_symbols
          AND (
              (a.owner_id IS NULL AND p_package)
              OR (a.owner_id = p_user_id AND p_manual)
          )
          AND (
              an.provider = (CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END)[1]
              OR NOT EXISTS (
                  SELECT 1 FROM article_analyses own
                  WHERE own.article_id = an.article_id
                    AND own.provider = (CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END)[1]
              )
          )
        ORDER BY
            an.article_id,
            array_position(CASE WHEN a.owner_id IS NULL THEN p_provider_order ELSE p_model_order END, an.provider) NULLS LAST,
            an.provider
    )
    SELECT
        a.id, a.title, a.url, a.source, a.published_at, a.owner_id,
        s.provider, s.provider_label, s.summary, s.sentiment_label, s.severity,
        s.related_categories, s.related_assets, s.asset_impacts,
        COALESCE(f.read, FALSE),
        COUNT(*) OVER ()
    FROM shown s
    JOIN articles a ON a.id = s.article_id
    LEFT JOIN user_news_feed f ON f.article_id = a.id AND f.user_id = p_user_id
    ORDER BY a.processed_at DESC, a.id
    LIMIT p_limit OFFSET p_offset;
$$;

REVOKE EXECUTE ON FUNCTION asset_news(UUID, TEXT[], BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, INTEGER)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION asset_news(UUID, TEXT[], BOOLEAN, BOOLEAN, TEXT[], TEXT[], INTEGER, INTEGER)
    TO service_role;

COMMIT;

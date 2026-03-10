-- =============================================================================
-- AI Financial Insights System — Complete Database Schema
-- Run this file on a fresh Supabase project to set up the entire schema.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Extensions
-- -----------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";


-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    notification_preferences JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    parent_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    level SMALLINT NOT NULL CHECK (level IN (1, 2, 3)),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE portfolio (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_symbol TEXT NOT NULL,
    asset_type TEXT CHECK (asset_type IN ('stock', 'etf', 'crypto', 'bond', 'commodity', 'other')),
    category TEXT,
    quantity NUMERIC NOT NULL,
    purchase_price NUMERIC NOT NULL,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, asset_symbol)
);

CREATE TABLE watchlist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_symbol TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (asset_type IN ('stock', 'etf', 'crypto', 'bond', 'commodity', 'other')),
    category TEXT,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, asset_symbol)
);

CREATE TABLE followed_topics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    source TEXT NOT NULL CHECK (source IN ('auto', 'manual')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, category_id)
);

CREATE TABLE articles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    url TEXT UNIQUE NOT NULL,
    source TEXT,
    summary TEXT,
    sentiment_label TEXT CHECK (sentiment_label IN ('positive', 'negative', 'neutral')),
    severity SMALLINT CHECK (severity BETWEEN 1 AND 10),
    related_categories TEXT[] DEFAULT '{}',
    related_assets TEXT[] DEFAULT '{}',
    published_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_news_feed (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    read BOOLEAN DEFAULT FALSE,
    bookmarked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, article_id)
);

CREATE TABLE alerts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    article_id UUID REFERENCES articles(id) ON DELETE SET NULL,
    asset_symbol TEXT,
    alert_type TEXT NOT NULL CHECK (alert_type IN ('impact', 'volatility')),
    severity SMALLINT CHECK (severity BETWEEN 1 AND 10),
    message TEXT,
    notification_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    report_type TEXT NOT NULL CHECK (report_type IN ('daily', 'weekly')),
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    content TEXT,
    generated_at TIMESTAMPTZ DEFAULT NOW()
);


-- -----------------------------------------------------------------------------
-- Indexes
-- -----------------------------------------------------------------------------

CREATE INDEX idx_articles_related_assets ON articles USING GIN (related_assets);
CREATE INDEX idx_articles_related_categories ON articles USING GIN (related_categories);
CREATE INDEX idx_articles_published_at ON articles (published_at DESC);
CREATE INDEX idx_user_news_feed_user_created ON user_news_feed (user_id, created_at DESC);
CREATE INDEX idx_alerts_user_created ON alerts (user_id, created_at DESC);
CREATE INDEX idx_reports_user_generated ON reports (user_id, generated_at DESC);
CREATE INDEX idx_watchlist_user ON watchlist (user_id);


-- -----------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE portfolio ENABLE ROW LEVEL SECURITY;
ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE followed_topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_news_feed ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_self ON users
    FOR ALL USING (auth.uid() = id);

CREATE POLICY portfolio_owner ON portfolio
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY watchlist_owner ON watchlist
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY followed_topics_owner ON followed_topics
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY user_news_feed_owner ON user_news_feed
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY alerts_owner ON alerts
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY reports_owner ON reports
    FOR ALL USING (auth.uid() = user_id);


-- -----------------------------------------------------------------------------
-- Seed: Categories (Level 1)
-- -----------------------------------------------------------------------------

INSERT INTO categories (name, parent_id, level, description) VALUES
    ('Technology',    NULL, 1, NULL),
    ('Finance',       NULL, 1, NULL),
    ('Energy',        NULL, 1, NULL),
    ('Automotive',    NULL, 1, NULL),
    ('Healthcare',    NULL, 1, NULL),
    ('Consumer',      NULL, 1, NULL),
    ('Industrials',   NULL, 1, NULL),
    ('Real Estate',   NULL, 1, NULL),
    ('Commodities',   NULL, 1, NULL),
    ('Cryptocurrency',NULL, 1, NULL);


-- -----------------------------------------------------------------------------
-- Seed: Categories (Level 2)
-- -----------------------------------------------------------------------------

INSERT INTO categories (name, parent_id, level, description)
SELECT t.name, c.id, 2, t.description
FROM (VALUES
    ('Software',               'Technology',    NULL),
    ('Semiconductors',         'Technology',    NULL),
    ('Cybersecurity',          'Technology',    NULL),
    ('Gaming',                 'Technology',    NULL),
    ('AI & Machine Learning',  'Technology',    NULL),
    ('Consumer Electronics',   'Technology',    'Hardware devices sold to end consumers (smartphones, tablets, wearables)'),
    ('Cloud & Infrastructure', 'Technology',    'Cloud platforms, CDN, networking and data-center infrastructure'),
    ('Banking',                'Finance',       NULL),
    ('Fintech',                'Finance',       NULL),
    ('Investment',             'Finance',       NULL),
    ('Insurance',              'Finance',       NULL),
    ('Oil & Gas',              'Energy',        NULL),
    ('Renewable Energy',       'Energy',        NULL),
    ('Utilities',              'Energy',        NULL),
    ('Electric Vehicles',      'Automotive',    NULL),
    ('Traditional Auto',       'Automotive',    NULL),
    ('Auto Parts',             'Automotive',    NULL),
    ('Pharmaceuticals',        'Healthcare',    NULL),
    ('Biotechnology',          'Healthcare',    NULL),
    ('Medical Devices',        'Healthcare',    NULL),
    ('E-Commerce',             'Consumer',      NULL),
    ('Food & Beverage',        'Consumer',      NULL),
    ('Media & Entertainment',  'Consumer',      NULL),
    ('Retail',                 'Consumer',      'Brick-and-mortar and omnichannel retail chains'),
    ('Aerospace & Defense',    'Industrials',   NULL),
    ('Transportation & Logistics', 'Industrials', NULL),
    ('REITs',                  'Real Estate',   'Publicly traded real estate investment trusts'),
    ('Precious Metals',        'Commodities',   NULL),
    ('Agriculture',            'Commodities',   NULL),
    ('Base Metals',            'Commodities',   NULL),
    ('Bitcoin',                'Cryptocurrency',NULL),
    ('Altcoins',               'Cryptocurrency',NULL),
    ('DeFi',                   'Cryptocurrency',NULL)
) AS t(name, parent_name, description)
JOIN categories c ON c.name = t.parent_name;


-- -----------------------------------------------------------------------------
-- Seed: Categories (Level 3)
-- -----------------------------------------------------------------------------

INSERT INTO categories (name, parent_id, level, description)
SELECT t.name, c.id, 3, NULL
FROM (VALUES
    ('SaaS',                       'Software'),
    ('Enterprise Software',        'Software'),
    ('Mobile Applications',        'Software'),
    ('GPU & Chips',                'Semiconductors'),
    ('Memory & Storage',           'Semiconductors'),
    ('Network Security',           'Cybersecurity'),
    ('Cloud Security',             'Cybersecurity'),
    ('Mobile Gaming',              'Gaming'),
    ('Console Gaming',             'Gaming'),
    ('PC Gaming',                  'Gaming'),
    ('Large Language Models',      'AI & Machine Learning'),
    ('Computer Vision',            'AI & Machine Learning'),
    ('Retail Banking',             'Banking'),
    ('Investment Banking',         'Banking'),
    ('Central Banking',            'Banking'),
    ('Payments',                   'Fintech'),
    ('Digital Lending',            'Fintech'),
    ('Solar Energy',               'Renewable Energy'),
    ('Wind Energy',                'Renewable Energy'),
    ('Hydrogen Energy',            'Renewable Energy'),
    ('EV Battery Technology',      'Electric Vehicles'),
    ('EV Charging Infrastructure', 'Electric Vehicles'),
    ('EV Policy & Subsidies',      'Electric Vehicles'),
    ('Clinical Trials',            'Pharmaceuticals'),
    ('Drug Approvals',             'Pharmaceuticals'),
    ('Gene Therapy',               'Biotechnology'),
    ('Online Retail',              'E-Commerce'),
    ('Marketplace Platforms',      'E-Commerce'),
    ('Streaming Services',         'Media & Entertainment'),
    ('Gold & Silver',              'Precious Metals'),
    ('Bitcoin Mining',             'Bitcoin'),
    ('Bitcoin ETF',                'Bitcoin'),
    ('Stablecoins',                'DeFi'),
    ('Yield Farming',              'DeFi')
) AS t(name, parent_name)
JOIN categories c ON c.name = t.parent_name;

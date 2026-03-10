CREATE TABLE watchlist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_symbol TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (asset_type IN ('stock', 'etf', 'crypto', 'bond', 'commodity', 'other')),
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, asset_symbol)
);

CREATE INDEX idx_watchlist_user ON watchlist (user_id);

ALTER TABLE watchlist ENABLE ROW LEVEL SECURITY;

CREATE POLICY watchlist_owner ON watchlist
    FOR ALL USING (auth.uid() = user_id);

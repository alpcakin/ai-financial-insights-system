-- Migration 028: topics matched by Snap
--
-- Categories leave the analysis prompt. SubQ Snap decides which categories and
-- user topics each new story relates to (DEVELOPMENT_JOURNAL.md 2.71).
--
-- 1. categories.kind: 'category' for the fixed list, 'topic' for a text a user
--    added. A topic has no level or parent; created_by is who first added it.
--    Names are unique ignoring case, so typing "banking" finds Banking. The 34
--    level-3 categories were never asked about or followable; they become
--    ready-made topics ("Stablecoins", "Bitcoin ETF"), so typing one finds it.
-- 2. topic_checks: Snap's one-time check of a new topic text (an instruction?
--    offensive?), keyed by the text in lower case so no text is asked twice.
-- 3. article_topics: every topic asked about a story, with Snap's probability
--    and whether it counts as a match. matched_by is 'snap' or the id of the
--    user's model that matched it (no probability then).
-- 4. articles.topics_pending_since: set when matching failed. Later cycles ask
--    Snap again, without analyzing the story again, for up to 24 hours.
-- 5. user_news_feed.topic_ids: the followed topics that brought the story to
--    the user, kept as they were when it was delivered.
-- 6. users.manual_topic_model_id: in manual mode, the user's model that matches
--    topics; NULL means Snap.
--
-- Apply before starting the new backend: it reads users.manual_topic_model_id.

ALTER TABLE categories
    ADD COLUMN kind TEXT NOT NULL DEFAULT 'category' CHECK (kind IN ('category', 'topic')),
    ADD COLUMN created_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE categories ALTER COLUMN level DROP NOT NULL;
UPDATE categories SET kind = 'topic', level = NULL, parent_id = NULL WHERE level = 3;
ALTER TABLE categories ADD CONSTRAINT categories_topic_shape
    CHECK ((kind = 'category') = (level IS NOT NULL) AND (kind = 'category' OR parent_id IS NULL));
CREATE UNIQUE INDEX categories_name_lower ON categories (lower(name));

CREATE TABLE topic_checks (
    text_key TEXT PRIMARY KEY,
    accepted BOOLEAN NOT NULL,
    instruction_probability REAL NOT NULL,
    offensive_probability REAL NOT NULL,
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE topic_checks ENABLE ROW LEVEL SECURITY;

CREATE TABLE article_topics (
    article_id UUID NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
    topic_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    probability REAL,
    matched BOOLEAN NOT NULL,
    matched_by TEXT NOT NULL,
    PRIMARY KEY (article_id, topic_id)
);
CREATE INDEX idx_article_topics_matched ON article_topics (topic_id) WHERE matched;
ALTER TABLE article_topics ENABLE ROW LEVEL SECURITY;

ALTER TABLE articles ADD COLUMN topics_pending_since TIMESTAMPTZ;
CREATE INDEX idx_articles_topics_pending ON articles (topics_pending_since) WHERE topics_pending_since IS NOT NULL;

ALTER TABLE user_news_feed ADD COLUMN topic_ids UUID[] NOT NULL DEFAULT '{}';

ALTER TABLE users ADD COLUMN manual_topic_model_id UUID REFERENCES user_models(id) ON DELETE SET NULL;

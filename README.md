# AI-Powered Personalized Financial Insights and Alert System

A Flutter-based Android application that monitors investment portfolios and delivers personalized financial news with AI-driven analysis. News articles are collected from a fixed list of RSS feeds, grouped so that one event reported by several outlets becomes one story, analyzed centrally by every enabled AI provider for sentiment, importance level, and per-asset impact, then distributed to users based on their portfolio holdings, followed topics, and the AI model each user has chosen.

## Architecture

- **Mobile**: Flutter (Android) with Riverpod state management
- **Backend**: Python 3.12 FastAPI with an in-process APScheduler for the news, volatility, report, and cleanup jobs
- **Database**: Supabase (PostgreSQL) with GIN indexes on array columns and pgvector for story matching
- **AI**: pluggable providers behind one interface. OpenAI GPT (`gpt-6-luna`), Google Gemini (`gemini-3.5-flash-lite`), and Anthropic Claude (`claude-haiku-5-5`) ship out of the box; model names are set in `.env`
- **Notifications**: Firebase Cloud Messaging

## AI providers

Analysis is centralized: one prompt, one JSON schema, one validation routine, shared by every provider (`backend/app/services/ai_service.py`). A provider only implements the transport call (`backend/app/services/ai/`).

- A provider is enabled when its API key is set in `.env`. `DEFAULT_AI_PROVIDER` names the one used for new accounts and as the fallback.
- Each new story is analyzed by all enabled providers in parallel. Every result is stored in `article_analyses`, including the raw response and latency, so providers can be compared on the same articles.
- Users pick a provider in the app's profile screen (`PATCH /users/me` with `ai_provider`; `GET /users/ai-providers` lists the options). Their feed and impact alerts are built from that provider's analysis. If it produced nothing for an article, the default provider's analysis is served and flagged as a fallback.
- Every article card and alert shows a badge naming the model that analyzed it.

Each request has a timeout of `AI_REQUEST_TIMEOUT_SECONDS` (60), so a provider that hangs cannot stall the news cycle.

To add a provider: subclass `AIProvider` with a `complete(system_prompt, user_prompt)` method, register it in `build_registry`, and add its display name to `DISPLAY_NAMES`.

## News pipeline

Every `NEWS_FETCH_INTERVAL_MINUTES` (15 is a good value) the backend runs one cycle (`backend/app/tasks/news_tasks.py`):

1. **Fetch** (`news_service.py`): the feeds in `FEEDS` are read with conditional requests, so an unchanged feed costs a 304. Items older than 24 hours, sponsored items and non-web links are dropped; URLs are normalized so the same article reached through two feeds is seen once.
2. **Group** (`dedup_service.py`): each new article is embedded (`text-embedding-3-small`) and compared with the first article ("lead") of every stored story, and with stories started earlier in the same cycle. All leads at or above `DEDUP_CANDIDATE_THRESHOLD` (0.50) whose publication time is within `DEDUP_WINDOW_HOURS` (48) of the new article go to SubQ Snap (`subq-snap-1.1`, key in `SUBQ_API_KEY`). Each candidate is a separate request that returns the probability of the same event; the highest one at or above `DEDUP_MATCH_PROBABILITY` (0.936) joins the story, and a failed request counts as "not the same". Similarity alone never joins a story: recurring reports such as daily roundups read almost the same from one day to the next. Users' own API keys are never used here; manual mode can only turn this step on or off.
3. **Analyze**: a new story is analyzed once by every provider. Reports of it that arrived in the same cycle go into the same prompt. Reports that arrive later are attached as extra sources: no new analysis, no new notification. At the same time SubQ Snap decides which categories and followed topics the story relates to (see Topics).
4. **Distribute**: stories rated medium or above reach users through their portfolio, watchlist and followed topics. Stories rated low are stored and reach only users who chose to see low stories (`feed_level` in the notification preferences, "Show in feed" in the app); they never raise an alert.

The feed returns every outlet that reported a story (`sources`), and `GET /feed/sources` lists the feeds for the app's News Sources screen.

Once a day, feed entries and alerts older than `RETENTION_DAYS` (30) are deleted, together with stories no feed entry points to any more (`purge_old_data`, migrations 015 and 019).

## Topics

Categories are not in the analysis prompt. For every new story, SubQ Snap answers one yes/no question per topic, "Is this news article related to the topic ...?", with no further definition: how wide a topic is comes from its name ("New York" against "New York elections"). The 33 fixed categories go in one request, the topics users follow in requests of their own, and every request ends with a fixed question whose answer is ignored, because Snap inflates the last question of a request. A topic matches at `TOPIC_MATCH_THRESHOLD` (0.5). The question, the layout and the threshold come from the topic test (`DEVELOPMENT_JOURNAL.md` 2.71); `app/services/topic_matching.py` and `story_topics.py`.

- Every asked topic is stored with its probability (`article_topics`); a feed entry keeps the followed topics that brought the story (`topic_ids`), shown on the card.
- When Snap cannot answer, the story is stored and delivered by its assets, and later cycles ask Snap again, without analyzing it again, for up to 24 hours.
- A user adds a topic by name (`POST /topics`). An existing category or topic is followed as it is; existing ones are suggested while typing (`GET /topics/search`). A new text first goes through one Snap request that rejects instructions and offensive text; the answer is kept per text, so the same text is never asked twice. Up to 10 own topics per user; at most 2 to 40 letters, digits, spaces and `& + - . , ' ( ) /`.
- In manual mode Snap is asked about the 33 categories and the user's own topics only, on the user's own stories. The user can pick one of their models for this instead (`topic_model_id` in `/manual/settings`); it gets one shared prompt in `ai_service.py`, and Snap answers when it fails.

## Company changes

The models do not know acquisitions, mergers and renames that happened after their training data ends. The `company_changes` table (migration 029) keeps those that involve a catalog asset, and a story that names one of a record's keywords gets that record as one line in the analysis prompt, for example "Dominion Energy: NextEra Energy Inc. (NEE) agreed on 2026-05-18 to acquire it; the deal has not closed." Keywords match as whole words; one written in capitals (a ticker) matches only in capitals. Stories that name no record get the unchanged prompt (`app/services/company_changes.py`).

- With `CHANGE_MODEL` set (`claude-haiku-5-5` was tested on 30 chosen stories, all right; on `ANTHROPIC_API_KEY`), a package story that reads like a deal or a rename is checked after the cycle's new stories by that model with web search. It records changes through a fixed schema with two sources from different sites; the code checks every field before writing. A pending deal is updated when news of its closing or termination arrives. Records are never edited: `replace_company_change` stores a new version and closes the old one.
- Manual-mode stories read the table but never write it.

## Asset news

The feed is a stored log: an entry is written when a story arrives and is not rewritten later, so nothing appears between entries the user has read, and adding or removing an asset or changing the model only affects what comes next. To read about any catalog asset, the app calls `GET /feed/asset-news?symbol=XOM`, which reads stored analyses on demand (last 30 days, the user's model, low importance included) through the `asset_news` function and makes no AI call. The asset can be added to the watchlist from that screen. `GET /feed/{article_id}/analyses` returns every model's analysis of one story, so models can be compared on the same article.

## Manual mode

A user can read their own RSS feeds with their own API keys, in a workspace no one else sees, instead of or alongside the shared package (`/manual/*`, `backend/app/tasks/manual_tasks.py`). Portfolio, watchlist and topics are shared by both modes.

- **Sources:** up to 20 RSS or Atom addresses, each checked when added and read at its own interval (at least 5 minutes). One URL is fetched once however many users follow it. What a feed holds when it is added or switched back on counts as seen; only what arrives later is analyzed.
- **Models:** OpenAI, Gemini, Claude or an OpenAI-compatible https address. Adding one makes one test call that has to pass the shared validation. Every working model analyzes every new story with the shared prompt; the feed and alerts use the one the user picked, and fall back only among their own models, flagged.
- **Grouping:** off by default, so every article is its own card. Turning it on runs the same frozen system as the package (system keys, embedding and Snap), comparing only within the user's own articles. If it cannot run, the user's articles wait for the next fetch instead of being analyzed one by one.
- **Failures:** a rejected key or an empty account stops that model until the user tries it again, with a notification; with no working model left, fetching stops. Rate limits and outages wait for the next fetch. A story every model failed on alone appears marked "Analysis failed".
- **Isolation:** `articles.owner_id` is NULL for the package and the owner otherwise. The seen check, candidate search, distribution and `asset_news` all stay inside one workspace, and deleting the account removes the workspace.
- **Security:** user-supplied addresses go through `core/safe_http.py`: http(s) only, no credentials, every request and redirect resolves the host, refuses non-public addresses and connects to the address it checked, with size and time limits. Keys are encrypted with `USER_KEY_ENCRYPTION_KEY` (`core/key_vault.py`), are never returned (only the last 4 characters), and only the error type and status of a user model are logged.

To run it, set `USER_KEY_ENCRYPTION_KEY` and `MANUAL_CHECK_INTERVAL_MINUTES` (see `.env.example`), and serve the backend over HTTPS before anyone enters a real key: the app warns when its connection is not encrypted. Back up the encryption key outside the database; if it is lost, users have to enter their keys again.

## Assets and accounts

- Portfolio and watchlist accept only the symbols in the asset catalog, the `assets` table (migration 026). The app loads the list from `GET /assets`, and asset type and category are taken from the catalog, not from the request. Every asset in the catalog goes into the analysis prompt with its name, whether anyone holds it or not.
- A user adds a missing asset from the asset browser: `GET /assets/search` searches Yahoo, and `POST /assets` checks the chosen symbol on Yahoo again and adds it to the shared catalog with no category (`asset_search_service.py`, migration 027). Only stocks, ETFs and crypto paired with USD can be added. A symbol that a catalog asset had before a rename is refused, and another listing of a catalog asset with the same name (Apple in Frankfurt) leads to the catalog asset. Categories of added assets are set by hand (the SQL is in migration 027). Yahoo searches are limited to 30 per 10 minutes per user.
- With `ASSET_CHECK_INTERVAL_HOURS` set, a daily check confirms each symbol against Yahoo (`asset_check_service.py`). When Yahoo gives a symbol to another instrument and exactly one instrument of the same type and name is found, the asset moves to it with its portfolio, watchlist and alert setting rows, and searches still find its stories under the old symbol. Otherwise the asset is marked `needs_review` and its price alerts stop until it is resolved by hand (the SQL is in migration 026).
- Passwords are hashed with bcrypt. Refresh, email verification and password reset tokens are stored as SHA-256 hashes. The app renews its access token five minutes before it expires and when it returns to the foreground. Changing or resetting the password deletes every refresh token, so other phones are logged out at their next renewal.
- Login (10 attempts per 15 minutes), registration and password reset (5 per hour) are rate limited per client IP.
- Portfolio and watchlist assets are treated the same for news matching and alerts; only the weekly report is portfolio-only.
- Volatility alerts fire when an asset moves at least 2.58 times its usual daily move (RiskMetrics volatility, λ = 0.94). Stocks, ETFs and commodities are measured against the previous close, crypto over the last 24 hours. Each move is alerted once (migration 020). Per asset, a user can replace the default with a fixed percentage (1-50%) or turn price alerts off (`/alerts/settings`, migration 021).
- The notification settings turn off the push for impact or volatility alerts; the alerts are still listed in the app.

## Project Structure

```
├── backend/          # FastAPI backend
│   ├── app/
│   │   ├── core/     # Config, security, database, encrypted keys, guarded HTTP
│   │   ├── models/   # Pydantic request/response models
│   │   ├── routers/  # API route handlers
│   │   ├── services/ # Business logic; ai/ holds one transport per AI provider
│   │   └── tasks/    # Scheduled news cycle, manual mode cycle and weekly report
│   ├── tests/        # pytest suite
│   └── requirements.txt
├── mobile/           # Flutter Android application
│   ├── lib/
│   │   ├── core/     # Constants
│   │   ├── data/     # Models and repositories
│   │   ├── providers/ # Riverpod state providers
│   │   ├── screens/  # UI screens
│   │   ├── services/ # Push notifications
│   │   └── widgets/  # Shared widgets
│   └── test/         # Flutter tests
└── database/
    └── migrations/   # PostgreSQL schema and seed data
```

## Setup

### Backend

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env   # Fill in your API keys; set NEWS_FETCH_INTERVAL_MINUTES=15 to start the news cycle
.venv/bin/uvicorn app.main:app --reload
```

API documentation available at `http://localhost:8000/docs` after startup.

Tests run without a `.env` file and never call a real API:

```bash
cd backend && .venv/bin/pip install -r requirements-test.txt && .venv/bin/python -m pytest -q
cd mobile && flutter analyze && flutter test
```

### Mobile

Requires Android Studio with an Android emulator (API 26+).

```bash
cd mobile
flutter pub get
flutter run
```

The app connects to the backend at `http://10.0.2.2:8000` (Android emulator localhost).  
For a physical device, pass `--dart-define=BASE_URL=http://<your-machine-ip>:8000`.

## Database

Run the migration files in order against your Supabase project. The number prefix is the order:

| File | Adds |
|---|---|
| `001_initial_schema.sql` | users, categories, portfolio, followed_topics, articles, user_news_feed, alerts, reports; GIN indexes; RLS |
| `002_seed_categories.sql` | 3-level category hierarchy (10 → 29 → 34 categories) |
| `003_watchlist.sql` | watchlist table |
| `004_new_categories.sql`, `005_asset_category_column.sql`, `006_add_category_columns.sql` | category refinements and asset category mapping |
| `007_add_article_asset_impacts.sql` | per-asset impact objects on articles |
| `008_email_verification.sql` | email verification and password reset columns |
| `009_performance_indexes.sql` | indexes for alert deduplication and category lookups |
| `010_add_alerts_is_read.sql` | unread flag on alerts |
| `011_add_refresh_tokens.sql` | refresh_tokens table |
| `012_ai_providers.sql` | article_analyses table, per-user provider choice, backfill of existing analyses under `openai` |
| `013_security_and_index_review.sql` | RLS on reference tables, foreign key indexes, policy tuning from the Supabase linter |
| `014_rss_stories.sql` | pgvector, article descriptions and embeddings, story grouping columns, `match_story_leads` function |
| `015_retention.sql` | `purge_old_data` function for the daily cleanup of old feed entries, alerts and stories |
| `016_hash_one_time_tokens.sql` | hashes pending email verification and password reset tokens in place (data only, no schema change) |
| `017_feed_fallback_flag.sql` | `is_fallback` on feed entries, set at delivery; backfills existing entries |
| `018_story_leads_published_at.sql` | `match_story_leads` also returns `published_at` for the same-event judge (apply with the backend stopped) |
| `019_remove_bookmarks.sql` | drops the never-used `user_news_feed.bookmarked`; the cleanup no longer keeps bookmarked entries |
| `020_volatility_alert_session.sql` | alerts record the trading session of a move, one volatility alert per asset and session |
| `021_asset_alert_settings.sql` | per-asset volatility alert settings for portfolio and watchlist assets |
| `022_importance_levels.sql` | importance levels 1-4 instead of 1-10 scores; users on Grok move to the default provider |
| `023_snap_candidates.sql` | `match_story_leads` returns every lead above a similarity threshold within a publication window, for the Snap judge (apply with the backend stopped) |
| `024_asset_news.sql` | `asset_news` function: an asset's recent stored news, read on demand |
| `025_manual_mode.sql` | manual mode: mode settings on users, `user_sources`, `user_models`, `articles.owner_id` with one URL per workspace, `provider_label`, `model_stopped` alerts; `match_story_leads` and `asset_news` scoped to a workspace (apply with the backend stopped) |
| `026_asset_catalog.sql` | the asset catalog moves from code to the `assets` table with the 148 assets; `rename_asset`; `asset_news` also searches an asset's previous symbols (apply with the backend stopped) |
| `027_asset_added_by.sql` | `assets.added_by`: who added an asset to the catalog |
| `028_topics.sql` | topics: `categories.kind` (fixed category or user topic; level-3 categories become topics), `topic_checks`, `article_topics`, `articles.topics_pending_since`, `user_news_feed.topic_ids`, `users.manual_topic_model_id` (apply before starting the new backend) |
| `029_company_changes.sql` | company changes: `company_changes` with 84 seed records, `replace_company_change`, `articles.changes_pending_since` (apply before starting the new backend) |

Row-level security is enabled on every user-owned table. The backend connects with the service role key and is therefore not restricted by those policies; access control is enforced in the API layer through JWT authentication. RLS exists as a second line of defence so that a leaked anon key, or any client talking to Supabase directly, can only reach the rows of the authenticated user.

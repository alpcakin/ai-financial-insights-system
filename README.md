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
3. **Analyze**: a new story is analyzed once by every provider. Reports of it that arrived in the same cycle go into the same prompt. Reports that arrive later are attached as extra sources: no new analysis, no new notification.
4. **Distribute**: stories rated medium or above reach users through their portfolio and followed topics. Stories below that are stored but not shown.

The feed returns every outlet that reported a story (`sources`), and `GET /feed/sources` lists the feeds for the app's News Sources screen.

Once a day, feed entries and alerts older than `RETENTION_DAYS` (30) are deleted, together with stories no feed entry points to any more (`purge_old_data`, migrations 015 and 019).

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

- Portfolio and watchlist accept only the symbols in the asset catalog (`backend/app/services/asset_catalog.py`). The app loads the list from `GET /assets`, and asset type and category are taken from the catalog, not from the request.
- Passwords are hashed with bcrypt. Refresh, email verification and password reset tokens are stored as SHA-256 hashes. Changing or resetting the password ends every session.
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

Row-level security is enabled on every user-owned table. The backend connects with the service role key and is therefore not restricted by those policies; access control is enforced in the API layer through JWT authentication. RLS exists as a second line of defence so that a leaked anon key, or any client talking to Supabase directly, can only reach the rows of the authenticated user.

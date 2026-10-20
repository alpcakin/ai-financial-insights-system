# AI-Powered Personalized Financial Insights and Alert System

A Flutter-based Android application that monitors investment portfolios and delivers personalized financial news with AI-driven analysis. News articles are collected from a fixed list of RSS feeds, grouped so that one event reported by several outlets becomes one story, analyzed centrally by every enabled AI provider for sentiment, severity, and per-asset impact, then distributed to users based on their portfolio holdings, followed topics, and the AI model each user has chosen.

## Architecture

- **Mobile**: Flutter (Android) with Riverpod state management
- **Backend**: Python FastAPI with an in-process APScheduler for the news, volatility, and report jobs
- **Database**: Supabase (PostgreSQL) with GIN indexes on array columns and pgvector for story matching
- **AI**: pluggable providers behind one interface. OpenAI GPT (gpt-6-luna), Google Gemini, xAI Grok, and Anthropic Claude ship out of the box
- **Notifications**: Firebase Cloud Messaging

## AI providers

Analysis is centralized: one prompt, one JSON schema, one validation routine, shared by every provider (`backend/app/services/ai_service.py`). A provider only implements the transport call (`backend/app/services/ai/`).

- A provider is enabled when its API key is set in `.env`. `DEFAULT_AI_PROVIDER` names the one used for new accounts and as the fallback.
- Each new story is analyzed by all enabled providers in parallel. Every result is stored in `article_analyses`, including the raw response and latency, so providers can be compared on the same articles.
- Users pick a provider in the app's profile screen (`PATCH /users/me` with `ai_provider`; `GET /users/ai-providers` lists the options). Their feed and impact alerts are built from that provider's analysis. If it produced nothing for an article, the default provider's analysis is served and flagged as a fallback.
- Every article card and alert shows a badge naming the model that analyzed it.

To add a provider: subclass `AIProvider` with a `complete(system_prompt, user_prompt)` method, register it in `build_registry`, and add its display name to `DISPLAY_NAMES`.

## News pipeline

Every `NEWS_FETCH_INTERVAL_MINUTES` (15 is a good value) the backend runs one cycle (`backend/app/tasks/news_tasks.py`):

1. **Fetch** (`news_service.py`): the feeds in `FEEDS` are read with conditional requests, so an unchanged feed costs a 304. Items older than 24 hours, sponsored items and non-web links are dropped; URLs are normalized so the same article reached through two feeds is seen once.
2. **Group** (`dedup_service.py`): each new article is embedded (`text-embedding-3-small`) and compared with the first article ("lead") of every story stored in the last 48 hours, and with stories started earlier in the same cycle. Similarity at or above `DEDUP_AUTO_THRESHOLD` (0.85) joins a story outright; between `DEDUP_CANDIDATE_THRESHOLD` (0.65) and that, the default provider is asked which of the three closest stories, if any, reports the same event.
3. **Analyze**: a new story is analyzed once by every provider. Reports of it that arrived in the same cycle go into the same prompt. Reports that arrive later are attached as extra sources: no new analysis, no new notification.
4. **Distribute**: stories with severity 4 or above reach users through their portfolio and followed topics. Stories below that are stored but not shown.

The feed returns every outlet that reported a story (`sources`), and `GET /feed/sources` lists the feeds for the app's News Sources screen.

Once a day, feed entries and alerts older than `RETENTION_DAYS` (30) are deleted, except bookmarked entries, together with stories no feed entry points to any more (`purge_old_data`, migration 015).

## Project Structure

```
├── backend/          # FastAPI backend
│   ├── app/
│   │   ├── core/     # Config, security, database
│   │   ├── models/   # Pydantic request/response models
│   │   ├── routers/  # API route handlers
│   │   └── services/ # Business logic
│   └── requirements.txt
├── mobile/           # Flutter Android application
│   └── lib/
│       ├── core/     # Constants
│       ├── data/     # Models and repositories
│       ├── providers/ # Riverpod state providers
│       └── screens/  # UI screens
└── database/
    └── migrations/   # PostgreSQL schema and seed data
```

## Setup

### Backend

```bash
cd backend
pip install -r requirements.txt
cp .env.example .env   # Fill in your API keys
uvicorn app.main:app --reload
```

API documentation available at `http://localhost:8000/docs` after startup.

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

`database/schema_complete.sql` contains the same end state for a fresh project.

Row-level security is enabled on every user-owned table. The backend connects with the service role key and is therefore not restricted by those policies; access control is enforced in the API layer through JWT authentication. RLS exists as a second line of defence so that a leaked anon key, or any client talking to Supabase directly, can only reach the rows of the authenticated user.

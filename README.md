# AI-Powered Personalized Financial Insights and Alert System

A Flutter-based Android application that monitors investment portfolios and delivers personalized financial news with AI-driven analysis. News articles are collected from MediaStack API, analyzed centrally by GPT-4o-mini for sentiment, severity, and per-asset impact, then distributed to users based on their portfolio holdings and followed topics.

## Architecture

- **Mobile**: Flutter (Android) with Riverpod state management
- **Backend**: Python FastAPI with Celery background workers
- **Database**: Supabase (PostgreSQL) with GIN indexes on array columns
- **Cache / Queue**: Redis
- **AI**: OpenAI GPT-4o-mini
- **Notifications**: Firebase Cloud Messaging

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

Run the migration files in order against your Supabase project:

1. `database/migrations/001_initial_schema.sql` — all 8 tables, GIN indexes, RLS policies
2. `database/migrations/002_seed_categories.sql` — 3-level category hierarchy (10 → 29 → 34 categories)

from contextlib import asynccontextmanager
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, portfolio, watchlist, users
from app.routers import feed, alerts, reports, topics

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from apscheduler.schedulers.background import BackgroundScheduler
    from app.core.database import get_db
    from app.tasks.news_tasks import process_news_cycle
    from app.tasks.report_tasks import generate_weekly_reports
    from app.services.alert_service import generate_volatility_alerts
    from app.services.ai import get_registry

    get_registry()

    scheduler = BackgroundScheduler()

    if settings.news_fetch_interval_minutes > 0:
        scheduler.add_job(
            process_news_cycle,
            "interval",
            minutes=settings.news_fetch_interval_minutes,
            misfire_grace_time=60,
        )
        logger.info("News cycle scheduled every %d min", settings.news_fetch_interval_minutes)

    if settings.volatility_check_interval_minutes > 0:
        def _volatility():
            try:
                generate_volatility_alerts(get_db())
            except Exception as e:
                logger.error("Volatility check failed: %s", e)

        scheduler.add_job(
            _volatility,
            "interval",
            minutes=settings.volatility_check_interval_minutes,
            misfire_grace_time=60,
        )
        logger.info("Volatility check scheduled every %d min", settings.volatility_check_interval_minutes)

    scheduler.add_job(
        generate_weekly_reports,
        "cron",
        day_of_week="sun",
        hour=20,
        minute=0,
        misfire_grace_time=300,
    )
    logger.info("Weekly reports scheduled for Sunday 20:00")

    scheduler.start()
    yield
    scheduler.shutdown()


app = FastAPI(title="AI Financial Insights API", version="1.0.0", lifespan=lifespan)

# The only client is the native Android app, which is not subject to the
# browser same-origin policy, so CORS is left open. Restrict allow_origins
# before serving a web client from this API.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(portfolio.router)
app.include_router(watchlist.router)
app.include_router(feed.router)
app.include_router(alerts.router)
app.include_router(reports.router)
app.include_router(topics.router)


@app.get("/health")
def health():
    return {"status": "ok"}

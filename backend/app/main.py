from contextlib import asynccontextmanager
from datetime import datetime
import logging

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, portfolio, watchlist, users
from app.routers import feed, alerts, manual, reports, topics, assets

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    from apscheduler.schedulers.background import BackgroundScheduler
    from app.core.database import get_db
    from app.tasks.manual_tasks import process_manual_cycle, shutdown_manual_workers
    from app.tasks.news_tasks import process_news_cycle, stop_requested
    from app.tasks.report_tasks import generate_weekly_reports
    from app.services.alert_service import generate_volatility_alerts
    from app.services.asset_check_service import run_asset_check
    from app.services.manual_service import refresh_package_sources
    from app.services.price_history_service import refresh_closes
    from app.services.report_service import REPORT_HOUR
    from app.services.retention_service import purge_old_data
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

    if settings.manual_check_interval_minutes > 0:
        def _refresh_followed_feeds():
            try:
                refresh_package_sources(get_db())
            except Exception as e:
                logger.error("Refreshing the app's feeds for followers failed: %s", e)

        # Once at startup: FEEDS lives in code, so it only changes with a restart.
        scheduler.add_job(_refresh_followed_feeds)
        scheduler.add_job(
            process_manual_cycle,
            "interval",
            minutes=settings.manual_check_interval_minutes,
            misfire_grace_time=60,
        )
        logger.info("Manual mode sources checked every %d min", settings.manual_check_interval_minutes)

    if settings.asset_check_interval_hours > 0:
        def _asset_check():
            try:
                run_asset_check(get_db())
            except Exception as e:
                logger.error("Asset check failed: %s", e)

        # Runs at startup too; assets checked in the last 20 hours are skipped.
        scheduler.add_job(
            _asset_check,
            "interval",
            hours=settings.asset_check_interval_hours,
            next_run_time=datetime.now(),
            misfire_grace_time=3600,
        )
        logger.info("Asset check scheduled every %d h", settings.asset_check_interval_hours)

    if settings.price_history_interval_hours > 0:
        def _price_history():
            try:
                refresh_closes(get_db())
            except Exception as e:
                logger.error("Refreshing daily closes failed: %s", e)

        scheduler.add_job(
            _price_history,
            "interval",
            hours=settings.price_history_interval_hours,
            next_run_time=datetime.now(),
            misfire_grace_time=3600,
        )
        logger.info("Daily closes refreshed every %d h", settings.price_history_interval_hours)

    if settings.retention_days > 0:
        def _retention():
            try:
                purge_old_data(get_db())
            except Exception as e:
                logger.error("Retention cleanup failed: %s", e)

        # Runs at startup as well, because a backend on a laptop is rarely up
        # at a fixed hour every night.
        scheduler.add_job(
            _retention,
            "interval",
            hours=24,
            next_run_time=datetime.now(),
            misfire_grace_time=3600,
        )
        logger.info("Retention cleanup scheduled daily, keeping %d days", settings.retention_days)

    # Also at startup and with no grace limit: a backend that was down or asleep on
    # Sunday evening still makes that week's report when it comes back.
    scheduler.add_job(
        generate_weekly_reports,
        "cron",
        day_of_week="sun",
        hour=REPORT_HOUR,
        minute=0,
        next_run_time=datetime.now(),
        misfire_grace_time=None,
    )
    logger.info("Weekly reports scheduled for Sunday %d:00 and checked at startup", REPORT_HOUR)

    scheduler.start()
    yield
    stop_requested.set()
    scheduler.shutdown()
    shutdown_manual_workers()


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
app.include_router(assets.router)
app.include_router(manual.router)


@app.get("/health")
def health():
    return {"status": "ok"}

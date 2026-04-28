from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, portfolio, watchlist
from app.routers import news, feed, alerts, reports, topics

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    jobs_scheduled = False

    if settings.news_fetch_interval_minutes > 0 or settings.volatility_check_interval_minutes > 0:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
        from app.core.database import get_db
        from app.tasks.news_tasks import process_news_cycle
        from app.services.alert_service import generate_volatility_alerts

        scheduler = AsyncIOScheduler()

        if settings.news_fetch_interval_minutes > 0:
            scheduler.add_job(
                process_news_cycle.delay,
                "interval",
                minutes=settings.news_fetch_interval_minutes,
            )
            logger.info("News cycle scheduled every %d min", settings.news_fetch_interval_minutes)

        if settings.volatility_check_interval_minutes > 0:
            def _run_volatility():
                generate_volatility_alerts(get_db())

            scheduler.add_job(
                _run_volatility,
                "interval",
                minutes=settings.volatility_check_interval_minutes,
            )
            logger.info("Volatility check scheduled every %d min", settings.volatility_check_interval_minutes)

        scheduler.start()
        jobs_scheduled = True
        yield
        scheduler.shutdown()
    else:
        logger.info("APScheduler disabled. Use POST /news/trigger and POST /alerts/volatility-check.")
        yield


app = FastAPI(title="AI Financial Insights API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(portfolio.router)
app.include_router(watchlist.router)
app.include_router(news.router)
app.include_router(feed.router)
app.include_router(alerts.router)
app.include_router(reports.router)
app.include_router(topics.router)


@app.get("/health")
def health():
    return {"status": "ok"}

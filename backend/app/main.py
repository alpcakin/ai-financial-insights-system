from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.routers import auth, portfolio, watchlist
from app.routers import news, feed

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.news_fetch_interval_minutes > 0:
        from apscheduler.schedulers.asyncio import AsyncIOScheduler
        from app.tasks.news_tasks import process_news_cycle

        scheduler = AsyncIOScheduler()
        scheduler.add_job(
            process_news_cycle.delay,
            "interval",
            minutes=settings.news_fetch_interval_minutes,
        )
        scheduler.start()
        logger.info(
            "APScheduler started — news cycle every %d min",
            settings.news_fetch_interval_minutes,
        )
        yield
        scheduler.shutdown()
    else:
        logger.info("APScheduler disabled (NEWS_FETCH_INTERVAL_MINUTES=0). Use POST /news/trigger.")
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


@app.get("/health")
def health():
    return {"status": "ok"}

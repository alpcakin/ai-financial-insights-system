from celery import Celery
from app.core.config import settings

celery = Celery(
    "ai_financial_insights",
    broker=settings.redis_url,
    include=["app.tasks.news_tasks"],
)

celery.conf.update(
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],
    timezone="UTC",
    enable_utc=True,
    task_track_started=True,
)

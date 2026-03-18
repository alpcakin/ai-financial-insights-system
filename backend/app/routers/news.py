from fastapi import APIRouter, Depends
from app.dependencies import get_current_user
from app.tasks.news_tasks import process_news_cycle

router = APIRouter(prefix="/news", tags=["news"])


@router.post("/trigger")
def trigger_news_cycle(current_user: dict = Depends(get_current_user)):
    task = process_news_cycle.delay()
    return {"status": "queued", "task_id": task.id}

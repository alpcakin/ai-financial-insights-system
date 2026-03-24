from fastapi import APIRouter, Depends
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.feed import FeedResponse
from app.services.feed_service import get_feed, mark_read

router = APIRouter(prefix='/feed', tags=['feed'])


@router.get('', response_model=FeedResponse)
def list_feed(
    limit: int = 20,
    offset: int = 0,
    category: str | None = None,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_feed(db, current_user['id'], limit, offset, category)


@router.patch('/{article_id}/read')
def read_article(
    article_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    mark_read(db, current_user['id'], article_id)
    return {"ok": True}

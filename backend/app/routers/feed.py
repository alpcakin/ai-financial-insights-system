from uuid import UUID

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.feed import ArticleAnalysesResponse, FeedArticle, FeedResponse, NewsSourcesResponse
from app.services.feed_service import get_article_analyses, get_asset_news, get_feed, get_feed_article, mark_read
from app.services.news_service import FEEDS

router = APIRouter(prefix='/feed', tags=['feed'])


@router.get('', response_model=FeedResponse)
def list_feed(
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    category: str | None = Query(None, max_length=100),
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_feed(db, current_user['id'], limit, offset, category)


@router.get('/sources', response_model=NewsSourcesResponse)
def list_sources(current_user: dict = Depends(get_current_user)):
    return {"sources": [{"outlet": f.outlet, "section": f.section} for f in FEEDS]}


@router.get('/asset-news', response_model=FeedResponse)
def list_asset_news(
    symbol: str = Query(..., min_length=1, max_length=20),
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_asset_news(db, current_user, symbol, limit, offset)


# Declared after /sources and /asset-news, so those paths are not read as an id.
@router.get('/{article_id}', response_model=FeedArticle)
def read_feed_article(
    article_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_feed_article(db, current_user['id'], str(article_id))


@router.get('/{article_id}/analyses', response_model=ArticleAnalysesResponse)
def list_article_analyses(
    article_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_article_analyses(db, current_user, str(article_id))


@router.patch('/{article_id}/read')
def read_article(
    article_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    mark_read(db, current_user['id'], article_id)
    return {"ok": True}

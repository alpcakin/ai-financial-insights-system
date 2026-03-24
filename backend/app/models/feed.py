from pydantic import BaseModel
from typing import Any


class ArticleImpact(BaseModel):
    symbol: str
    impact: str
    severity: int
    reason: str


class FeedArticle(BaseModel):
    id: str
    title: str
    url: str
    source: str | None
    summary: str | None
    sentiment_label: str | None
    severity: int | None
    related_categories: list[str] | None
    related_assets: list[str] | None
    asset_impacts: list[Any] | None
    published_at: str | None
    read: bool
    bookmarked: bool


class FeedResponse(BaseModel):
    articles: list[FeedArticle]
    total: int
    offset: int
    limit: int

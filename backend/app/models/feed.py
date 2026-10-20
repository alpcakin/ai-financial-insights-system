from pydantic import BaseModel
from typing import Any


class ArticleImpact(BaseModel):
    symbol: str
    impact: str
    severity: int
    reason: str


class ArticleSource(BaseModel):
    title: str
    url: str
    source: str | None
    published_at: str | None


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
    analyzed_by: str | None = None
    analyzed_by_name: str | None = None
    is_fallback: bool = False
    read: bool
    bookmarked: bool
    sources: list[ArticleSource] = []


class FeedResponse(BaseModel):
    articles: list[FeedArticle]
    total: int
    offset: int
    limit: int


class NewsSource(BaseModel):
    outlet: str
    section: str


class NewsSourcesResponse(BaseModel):
    sources: list[NewsSource]

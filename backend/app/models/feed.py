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
    sources: list[ArticleSource] = []
    mode: str = "package"
    analysis_failed: bool = False
    # The reader's followed topics that brought the story, kept from its delivery.
    matched_topics: list[str] = []


class FeedCategory(BaseModel):
    name: str
    followed: bool


class FeedResponse(BaseModel):
    articles: list[FeedArticle]
    total: int
    offset: int
    limit: int
    # Every category in the user's feed, followed ones first; on the feed's first page only.
    categories: list[FeedCategory] | None = None
    # Unread entries in the whole view (the feed or the chosen category); first page only.
    unread: int | None = None


class ArticleAnalysis(BaseModel):
    provider: str
    provider_name: str
    summary: str | None
    sentiment_label: str | None
    severity: int | None
    related_categories: list[str] | None
    related_assets: list[str] | None
    asset_impacts: list[Any] | None


class ArticleAnalysesResponse(BaseModel):
    analyses: list[ArticleAnalysis]


class NewsSource(BaseModel):
    outlet: str
    section: str


class NewsSourcesResponse(BaseModel):
    sources: list[NewsSource]

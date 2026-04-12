from pydantic import BaseModel


class ReportContent(BaseModel):
    top_articles: list[dict]
    portfolio_performance: list[dict]
    total_value_now: float
    total_value_7d_ago: float
    total_change_pct: float


class ReportResponse(BaseModel):
    id: str
    user_id: str
    report_type: str
    period_start: str
    period_end: str
    content: ReportContent | None
    generated_at: str


class ReportsListResponse(BaseModel):
    reports: list[ReportResponse]
    total: int
    offset: int
    limit: int

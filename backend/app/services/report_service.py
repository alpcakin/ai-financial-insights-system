import json
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, time, timedelta, timezone

import yfinance as yf
from supabase import Client

logger = logging.getLogger(__name__)

# Reports are made on Sundays at this hour, server time.
REPORT_HOUR = 20


def latest_report_sunday(now: datetime) -> date:
    """The last Sunday whose report hour has passed. ``now`` is naive local time."""
    sunday = now.date() - timedelta(days=(now.weekday() + 1) % 7)
    if sunday == now.date() and now.hour < REPORT_HOUR:
        sunday -= timedelta(days=7)
    return sunday


def report_window(sunday: date) -> tuple[datetime, datetime]:
    """From the previous Sunday's report hour to this Sunday's, in UTC."""
    start = datetime.combine(sunday - timedelta(days=7), time(REPORT_HOUR)).astimezone(timezone.utc)
    end = datetime.combine(sunday, time(REPORT_HOUR)).astimezone(timezone.utc)
    return start, end


def generate_weekly_report(db: Client, user_id: str, sunday: date) -> dict:
    period_end = sunday
    period_start = period_end - timedelta(days=7)
    window_start, window_end = report_window(sunday)

    existing = (
        db.table("reports")
        .select("*")
        .eq("user_id", user_id)
        .eq("report_type", "weekly")
        .eq("period_start", str(period_start))
        .execute()
    )
    if existing.data:
        row = existing.data[0]
        return {
            "id": row["id"],
            "user_id": row["user_id"],
            "report_type": row["report_type"],
            "period_start": str(row["period_start"]),
            "period_end": str(row["period_end"]),
            "content": json.loads(row["content"]),
            "generated_at": str(row["generated_at"]),
        }

    feed_result = (
        db.table("user_news_feed")
        .select("articles(id, title, source, published_at), article_analyses(severity, sentiment_label, summary)")
        .eq("user_id", user_id)
        .gte("created_at", window_start.isoformat())
        .lt("created_at", window_end.isoformat())
        .limit(1000)
        .execute()
    )

    articles_raw = [
        {**row["articles"], **(row.get("article_analyses") or {})}
        for row in (feed_result.data or [])
        if row.get("articles")
    ]
    articles_raw.sort(key=lambda a: (a.get("severity") or 0, a.get("published_at") or ""), reverse=True)

    top_articles = [
        {
            "id": a.get("id"),
            "title": a.get("title"),
            "source": a.get("source"),
            "severity": a.get("severity"),
            "sentiment_label": a.get("sentiment_label"),
            "summary": a.get("summary"),
            "published_at": str(a.get("published_at")) if a.get("published_at") else None,
        }
        for a in articles_raw[:5]
    ]

    portfolio_result = (
        db.table("portfolio")
        .select("asset_symbol, quantity")
        .eq("user_id", user_id)
        .execute()
    )

    def _fetch_asset_history(asset: dict) -> dict | None:
        symbol = asset["asset_symbol"]
        quantity = float(asset["quantity"])
        try:
            # The last close on or before each Sunday: Friday to Friday for stocks,
            # Sunday to Sunday for crypto. A late report still uses that week's prices.
            hist = yf.Ticker(symbol).history(
                start=period_start - timedelta(days=7), end=period_end + timedelta(days=1),
            )
            if hist.empty:
                return None
            closes = [(ts.date(), float(close)) for ts, close in hist["Close"].items()]
            before = [close for day, close in closes if day <= period_start]
            if not before or closes[-1][0] <= period_start:
                return None
            price_now = closes[-1][1]
            price_7d_ago = before[-1]
            if price_7d_ago == 0:
                return None
            change_pct = (price_now - price_7d_ago) / price_7d_ago * 100
            return {
                "symbol": symbol,
                "quantity": quantity,
                "price_now": round(price_now, 4),
                "price_7d_ago": round(price_7d_ago, 4),
                "change_pct": round(change_pct, 2),
                "value_now": round(price_now * quantity, 4),
                "value_7d_ago": price_7d_ago * quantity,
            }
        except Exception:
            logger.warning("yfinance error for %s, skipping", symbol)
            return None

    assets = portfolio_result.data or []
    portfolio_performance = []
    total_value_now = 0.0
    total_value_7d_ago = 0.0

    if assets:
        with ThreadPoolExecutor(max_workers=min(len(assets), 10)) as executor:
            futures = {executor.submit(_fetch_asset_history, a): a for a in assets}
            for future in as_completed(futures):
                entry = future.result()
                if entry:
                    total_value_now += entry["value_now"]
                    total_value_7d_ago += entry.pop("value_7d_ago")
                    portfolio_performance.append(entry)

    if total_value_7d_ago == 0:
        total_change_pct = 0.0
    else:
        total_change_pct = (total_value_now - total_value_7d_ago) / total_value_7d_ago * 100

    content = {
        "top_articles": top_articles,
        "portfolio_performance": portfolio_performance,
        "total_value_now": round(total_value_now, 4),
        "total_value_7d_ago": round(total_value_7d_ago, 4),
        "total_change_pct": round(total_change_pct, 2),
    }

    insert_result = (
        db.table("reports")
        .insert({
            "user_id": user_id,
            "report_type": "weekly",
            "period_start": str(period_start),
            "period_end": str(period_end),
            "content": json.dumps(content),
        })
        .execute()
    )

    if not insert_result.data:
        from fastapi import HTTPException
        raise HTTPException(status_code=500, detail="Failed to save report")

    row = insert_result.data[0]
    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "report_type": row["report_type"],
        "period_start": str(row["period_start"]),
        "period_end": str(row["period_end"]),
        "content": content,
        "generated_at": str(row["generated_at"]),
    }


def get_reports(db: Client, user_id: str, limit: int, offset: int) -> dict:
    result = (
        db.table("reports")
        .select("*", count="exact")
        .eq("user_id", user_id)
        .order("generated_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )

    reports = []
    for row in result.data or []:
        try:
            content = json.loads(row["content"]) if row.get("content") else None
        except Exception:
            content = None

        reports.append({
            "id": row["id"],
            "user_id": row["user_id"],
            "report_type": row["report_type"],
            "period_start": str(row["period_start"]),
            "period_end": str(row["period_end"]),
            "content": content,
            "generated_at": str(row["generated_at"]),
        })

    return {
        "reports": reports,
        "total": result.count or 0,
        "offset": offset,
        "limit": limit,
    }


def get_report(db: Client, user_id: str, report_id: str) -> dict | None:
    result = (
        db.table("reports")
        .select("*")
        .eq("id", report_id)
        .eq("user_id", user_id)
        .execute()
    )

    if not result.data:
        return None

    row = result.data[0]
    try:
        content = json.loads(row["content"]) if row.get("content") else None
    except Exception:
        content = None

    return {
        "id": row["id"],
        "user_id": row["user_id"],
        "report_type": row["report_type"],
        "period_start": str(row["period_start"]),
        "period_end": str(row["period_end"]),
        "content": content,
        "generated_at": str(row["generated_at"]),
    }

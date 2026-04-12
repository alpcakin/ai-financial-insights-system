import json
import logging
from datetime import date, timedelta

import yfinance as yf
from supabase import Client

logger = logging.getLogger(__name__)


def generate_weekly_report(db: Client, user_id: str) -> dict:
    period_end = date.today()
    period_start = period_end - timedelta(days=7)

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
        .select("*, articles(*)")
        .eq("user_id", user_id)
        .gte("created_at", str(period_start))
        .execute()
    )

    articles_raw = []
    for row in feed_result.data or []:
        article = row.get("articles")
        if article:
            articles_raw.append(article)

    articles_raw.sort(key=lambda a: a.get("severity") or 0, reverse=True)
    top_5 = articles_raw[:5]

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
        for a in top_5
    ]

    portfolio_result = (
        db.table("portfolio")
        .select("asset_symbol, quantity")
        .eq("user_id", user_id)
        .execute()
    )

    portfolio_performance = []
    total_value_now = 0.0
    total_value_7d_ago = 0.0

    for asset in portfolio_result.data or []:
        symbol = asset["asset_symbol"]
        quantity = float(asset["quantity"])

        try:
            hist = yf.Ticker(symbol).history(period="8d")
            if len(hist) < 2:
                logger.warning("Insufficient history for %s, skipping", symbol)
                continue

            price_now = float(hist["Close"].iloc[-1])
            price_7d_ago = float(hist["Close"].iloc[0])

            if price_7d_ago == 0:
                continue

            change_pct = (price_now - price_7d_ago) / price_7d_ago * 100
            value_now = price_now * quantity
            value_7d_ago = price_7d_ago * quantity

            portfolio_performance.append({
                "symbol": symbol,
                "quantity": quantity,
                "price_now": round(price_now, 4),
                "price_7d_ago": round(price_7d_ago, 4),
                "change_pct": round(change_pct, 2),
                "value_now": round(value_now, 4),
            })

            total_value_now += value_now
            total_value_7d_ago += value_7d_ago

        except Exception:
            logger.warning("yfinance error for %s, skipping", symbol)
            continue

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

import logging
from datetime import date

import yfinance as yf
from supabase import Client

from app.services.notification_service import notify_alert

logger = logging.getLogger(__name__)


def generate_impact_alerts(
    db: Client,
    article_id: str,
    user_ids: set[str],
    asset_impacts: list[dict],
) -> int:
    if not asset_impacts or not user_ids:
        return 0

    impact_map = {a["symbol"]: a for a in asset_impacts}
    created = 0

    for user_id in user_ids:
        existing = (
            db.table("alerts")
            .select("id")
            .eq("user_id", user_id)
            .eq("article_id", article_id)
            .eq("alert_type", "impact")
            .execute()
        )
        if existing.data:
            continue

        portfolio_result = (
            db.table("portfolio")
            .select("asset_symbol")
            .eq("user_id", user_id)
            .execute()
        )
        user_assets = {row["asset_symbol"] for row in portfolio_result.data}

        matched = [
            impact_map[sym]
            for sym in user_assets
            if sym in impact_map and impact_map[sym].get("severity", 0) >= 7
        ]

        if not matched:
            continue

        top = max(matched, key=lambda a: a.get("severity", 0))
        message = f"{top['symbol']}: {top.get('reason', 'High-impact event detected')}"

        try:
            insert = db.table("alerts").insert({
                "user_id": user_id,
                "article_id": article_id,
                "asset_symbol": top["symbol"],
                "alert_type": "impact",
                "severity": top.get("severity", 7),
                "message": message,
            }).execute()

            if insert.data:
                alert_id = insert.data[0]["id"]
                notify_alert(
                    db, user_id, alert_id,
                    f"High Impact: {top['symbol']}",
                    message,
                )
                created += 1
        except Exception as e:
            logger.error("Failed to create impact alert for user %s: %s", user_id, e)

    logger.info("Created %d impact alerts for article %s", created, article_id)
    return created


def _severity_from_change(pct: float) -> int:
    pct = abs(pct)
    if pct >= 20:
        return 10
    if pct >= 15:
        return 9
    if pct >= 10:
        return 8
    return 7


def generate_volatility_alerts(db: Client) -> int:
    portfolio_result = db.table("portfolio").select("asset_symbol, user_id").execute()
    if not portfolio_result.data:
        return 0

    asset_users: dict[str, set[str]] = {}
    for row in portfolio_result.data:
        asset_users.setdefault(row["asset_symbol"], set()).add(row["user_id"])

    created = 0

    for symbol, user_ids in asset_users.items():
        try:
            ticker = yf.Ticker(symbol)
            hist = ticker.history(period="2d")

            if len(hist) < 2:
                continue

            close_prev = hist["Close"].iloc[-2]
            close_curr = hist["Close"].iloc[-1]

            if close_prev == 0:
                continue

            change_pct = (close_curr - close_prev) / close_prev * 100

            if abs(change_pct) < 7:
                continue

            severity = _severity_from_change(change_pct)
            direction = "up" if change_pct > 0 else "down"
            message = f"{symbol} moved {direction} {abs(change_pct):.1f}% in 24 hours"

            today = date.today().isoformat()
            for user_id in user_ids:
                try:
                    existing = (
                        db.table("alerts")
                        .select("id")
                        .eq("user_id", user_id)
                        .eq("asset_symbol", symbol)
                        .eq("alert_type", "volatility")
                        .gte("created_at", today)
                        .execute()
                    )
                    if existing.data:
                        continue

                    insert = db.table("alerts").insert({
                        "user_id": user_id,
                        "asset_symbol": symbol,
                        "alert_type": "volatility",
                        "severity": severity,
                        "message": message,
                    }).execute()

                    if insert.data:
                        alert_id = insert.data[0]["id"]
                        notify_alert(
                            db, user_id, alert_id,
                            f"Volatility Alert: {symbol}",
                            message,
                        )
                        created += 1
                except Exception as e:
                    logger.error("Failed to create volatility alert for user %s, %s: %s", user_id, symbol, e)

        except Exception as e:
            logger.error("Failed to fetch price for %s: %s", symbol, e)

    logger.info("Created %d volatility alerts", created)
    return created


def get_alerts(db: Client, user_id: str, limit: int, offset: int) -> dict:
    result = (
        db.table("alerts")
        .select("*", count="exact")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )

    return {
        "alerts": result.data,
        "total": result.count or 0,
        "offset": offset,
        "limit": limit,
    }

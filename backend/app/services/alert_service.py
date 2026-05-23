import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date

import yfinance as yf
from supabase import Client

from app.services.notification_service import batch_fetch_fcm_tokens, notify_alert_with_token

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

    already_alerted = {
        row["user_id"]
        for row in (
            db.table("alerts")
            .select("user_id")
            .in_("user_id", list(user_ids))
            .eq("article_id", article_id)
            .eq("alert_type", "impact")
            .execute()
        ).data
    }

    portfolio_rows = (
        db.table("portfolio")
        .select("user_id, asset_symbol")
        .in_("user_id", list(user_ids))
        .execute()
    ).data
    user_portfolio_map: dict[str, set[str]] = {}
    for row in portfolio_rows:
        user_portfolio_map.setdefault(row["user_id"], set()).add(row["asset_symbol"])

    fcm_tokens = batch_fetch_fcm_tokens(db, user_ids)

    created = 0
    for user_id in user_ids:
        if user_id in already_alerted:
            continue

        user_assets = user_portfolio_map.get(user_id, set())
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
                fcm_token = fcm_tokens.get(user_id)
                if fcm_token:
                    notify_alert_with_token(db, alert_id, fcm_token, f"High Impact: {top['symbol']}", message)
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


def _fetch_volatility_data(symbol: str) -> tuple[str, float | None]:
    try:
        hist = yf.Ticker(symbol).history(period="2d")
        if len(hist) < 2:
            return symbol, None
        close_prev = hist["Close"].iloc[-2]
        close_curr = hist["Close"].iloc[-1]
        if close_prev == 0:
            return symbol, None
        return symbol, float((close_curr - close_prev) / close_prev * 100)
    except Exception as e:
        logger.error("Failed to fetch price for %s: %s", symbol, e)
        return symbol, None


def generate_volatility_alerts(db: Client) -> int:
    portfolio_result = db.table("portfolio").select("asset_symbol, user_id").execute()
    if not portfolio_result.data:
        return 0

    asset_users: dict[str, set[str]] = {}
    for row in portfolio_result.data:
        asset_users.setdefault(row["asset_symbol"], set()).add(row["user_id"])

    symbols = list(asset_users.keys())
    change_map: dict[str, float] = {}
    with ThreadPoolExecutor(max_workers=min(len(symbols), 10)) as executor:
        futures = {executor.submit(_fetch_volatility_data, sym): sym for sym in symbols}
        for future in as_completed(futures):
            sym, change_pct = future.result()
            if change_pct is not None and abs(change_pct) >= 7:
                change_map[sym] = change_pct

    today = date.today().isoformat()
    created = 0

    all_user_ids: set[str] = set()
    for user_ids in asset_users.values():
        all_user_ids.update(user_ids)
    fcm_tokens = batch_fetch_fcm_tokens(db, all_user_ids)

    for symbol, change_pct in change_map.items():
        user_ids = asset_users[symbol]
        severity = _severity_from_change(change_pct)
        direction = "up" if change_pct > 0 else "down"
        message = f"{symbol} moved {direction} {abs(change_pct):.1f}% in 24 hours"

        already_alerted = {
            row["user_id"]
            for row in (
                db.table("alerts")
                .select("user_id")
                .in_("user_id", list(user_ids))
                .eq("asset_symbol", symbol)
                .eq("alert_type", "volatility")
                .gte("created_at", today)
                .execute()
            ).data
        }

        for user_id in user_ids:
            if user_id in already_alerted:
                continue
            try:
                insert = db.table("alerts").insert({
                    "user_id": user_id,
                    "asset_symbol": symbol,
                    "alert_type": "volatility",
                    "severity": severity,
                    "message": message,
                }).execute()

                if insert.data:
                    alert_id = insert.data[0]["id"]
                    fcm_token = fcm_tokens.get(user_id)
                    if fcm_token:
                        notify_alert_with_token(db, alert_id, fcm_token, f"Volatility Alert: {symbol}", message)
                    created += 1
            except Exception as e:
                logger.error("Failed to create volatility alert for user %s, %s: %s", user_id, symbol, e)

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


def mark_alerts_read(db: Client, user_id: str) -> int:
    result = (
        db.table("alerts")
        .update({"is_read": True})
        .eq("user_id", user_id)
        .eq("is_read", False)
        .execute()
    )
    return len(result.data) if result.data else 0

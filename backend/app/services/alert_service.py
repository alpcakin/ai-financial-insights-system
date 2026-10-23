import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone

import pandas as pd
import yfinance as yf
from fastapi import HTTPException, status
from supabase import Client

from app.models.alert import AlertSettingRequest
from app.services.asset_catalog import get_asset
from app.services.notification_service import batch_fetch_fcm_tokens, notify_alert_with_token
from app.services.tracked_assets import tracked_assets

logger = logging.getLogger(__name__)

#: A volatility alert fires when a move reaches this many times the asset's
#: usual daily move: the two-sided 1% critical value of the normal distribution
#: (DEVELOPMENT_JOURNAL.md 2.40-2.42).
VOLATILITY_SIGMA = 2.58
#: RiskMetrics decay for daily volatility: each day the newest squared return
#: gets weight 1 - 0.94 (J.P. Morgan/Reuters 1996).
EWMA_LAMBDA = 0.94
#: Daily returns needed before the volatility estimate is used.
MIN_RETURNS = 60
HISTORY_PERIOD = "6mo"
#: Severity 7 at the threshold, then the steps of the former fixed thresholds
#: (7%, 10%, 15%, 20%) as multiples of it.
_SEVERITY_STEPS = ((20 / 7, 10), (15 / 7, 9), (10 / 7, 8))


def generate_impact_alerts(
    db: Client,
    article_id: str,
    user_ids: set[str],
    asset_impacts: list[dict],
    ai_provider: str | None = None,
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

    user_assets_map: dict[str, set[str]] = {}
    for user_id, symbol in tracked_assets(db, user_ids=list(user_ids)):
        user_assets_map.setdefault(user_id, set()).add(symbol)

    fcm_tokens = batch_fetch_fcm_tokens(db, user_ids, "impact_alerts")

    created = 0
    for user_id in user_ids:
        if user_id in already_alerted:
            continue

        user_assets = user_assets_map.get(user_id, set())
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
                "ai_provider": ai_provider,
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


@dataclass(frozen=True)
class VolatilityMove:
    change_pct: float
    #: The move in units of the asset's usual daily move.
    z: float
    #: Stocks, ETFs and commodities: the session that moved. Crypto: the UTC day of the check.
    session: date
    rolling_24h: bool


def _ewma_sigma(closes: pd.Series) -> float | None:
    returns = closes.pct_change().dropna()
    if len(returns) < MIN_RETURNS:
        return None
    variance = float((returns ** 2).ewm(alpha=1 - EWMA_LAMBDA, adjust=False).mean().iloc[-1])
    return variance ** 0.5 if variance > 0 else None


def _session_move(symbol: str) -> VolatilityMove | None:
    """Latest session against the previous close, sigma from the sessions before it."""
    closes = yf.Ticker(symbol).history(period=HISTORY_PERIOD)["Close"].dropna()
    if len(closes) < MIN_RETURNS + 2 or closes.iloc[-2] == 0:
        return None
    sigma = _ewma_sigma(closes.iloc[:-1])
    if sigma is None:
        return None
    change = closes.iloc[-1] / closes.iloc[-2] - 1
    return VolatilityMove(float(change * 100), float(abs(change) / sigma), closes.index[-1].date(), False)


def _rolling_24h_move(symbol: str) -> VolatilityMove | None:
    """Crypto has no close: last price against the price 24 hours earlier, sigma from
    daily (00:00 UTC to 00:00 UTC) returns before today."""
    ticker = yf.Ticker(symbol)
    hourly = ticker.history(period="2d", interval="1h")["Close"].dropna()
    daily = ticker.history(period=HISTORY_PERIOD)["Close"].dropna()
    if hourly.empty or len(daily) < MIN_RETURNS + 2:
        return None
    now = hourly.index[-1]
    earlier = hourly[hourly.index <= now - pd.Timedelta(hours=24)]
    if earlier.empty or earlier.iloc[-1] == 0:
        return None
    sigma = _ewma_sigma(daily.iloc[:-1])
    if sigma is None:
        return None
    change = hourly.iloc[-1] / earlier.iloc[-1] - 1
    return VolatilityMove(
        float(change * 100), float(abs(change) / sigma), now.tz_convert("UTC").date(), True,
    )


def _fetch_volatility_move(symbol: str) -> VolatilityMove | None:
    asset = get_asset(symbol)
    try:
        if asset is not None and asset["type"] == "crypto":
            return _rolling_24h_move(symbol)
        return _session_move(symbol)
    except Exception as e:
        logger.error("Failed to fetch prices for %s: %s", symbol, e)
        return None


def _severity_from_z(z: float) -> int:
    for multiple, severity in _SEVERITY_STEPS:
        if z >= VOLATILITY_SIGMA * multiple:
            return severity
    return 7


def _wants_alert(setting: dict | None, move: VolatilityMove) -> bool:
    """A user's own choice for the asset, or the default threshold when there is none."""
    if setting is None:
        return move.z >= VOLATILITY_SIGMA
    if setting["mode"] == "off":
        return False
    return abs(move.change_pct) >= float(setting["threshold_pct"])


def generate_volatility_alerts(db: Client) -> int:
    asset_users: dict[str, set[str]] = {}
    for user_id, symbol in tracked_assets(db):
        asset_users.setdefault(symbol, set()).add(user_id)
    if not asset_users:
        return 0

    settings = {
        (row["user_id"], row["asset_symbol"]): row
        for row in db.table("asset_alert_settings").select("user_id, asset_symbol, mode, threshold_pct").execute().data
    }

    moves: dict[str, VolatilityMove] = {}
    with ThreadPoolExecutor(max_workers=min(len(asset_users), 10)) as executor:
        futures = {executor.submit(_fetch_volatility_move, sym): sym for sym in asset_users}
        for future in as_completed(futures):
            move = future.result()
            if move is not None:
                moves[futures[future]] = move

    created = 0

    all_user_ids: set[str] = set()
    for user_ids in asset_users.values():
        all_user_ids.update(user_ids)
    fcm_tokens = batch_fetch_fcm_tokens(db, all_user_ids, "volatility_alerts")

    for symbol, move in moves.items():
        user_ids = {u for u in asset_users[symbol] if _wants_alert(settings.get((u, symbol)), move)}
        if not user_ids:
            continue
        severity = _severity_from_z(move.z)
        direction = "up" if move.change_pct > 0 else "down"
        window = "in 24 hours" if move.rolling_24h else "since the previous close"
        message = f"{symbol} moved {direction} {abs(move.change_pct):.1f}% {window}"

        # One alert per move. For a session, keyed by the session and not the calendar
        # day: between sessions the last two bars stay the same, and a per-day check
        # alerted the move again every night, weekend and holiday. A 24-hour crypto
        # move stays in the window for up to a day, so crypto allows one per 24 hours.
        query = (
            db.table("alerts")
            .select("user_id")
            .in_("user_id", list(user_ids))
            .eq("asset_symbol", symbol)
            .eq("alert_type", "volatility")
        )
        if move.rolling_24h:
            query = query.gte("created_at", (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat())
        else:
            query = query.eq("session_date", move.session.isoformat())
        already_alerted = {row["user_id"] for row in query.execute().data}

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
                    "session_date": move.session.isoformat(),
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


def get_alert_settings(db: Client, user_id: str) -> dict:
    rows = (
        db.table("asset_alert_settings")
        .select("asset_symbol, mode, threshold_pct")
        .eq("user_id", user_id)
        .execute()
    ).data
    return {"settings": rows}


def set_alert_setting(db: Client, user_id: str, symbol: str, request: AlertSettingRequest) -> dict:
    symbol = symbol.strip().upper()
    if not tracked_assets(db, user_ids=[user_id], symbols=[symbol]):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Asset is not in your portfolio or watchlist",
        )
    if request.mode == "auto":
        db.table("asset_alert_settings").delete().eq("user_id", user_id).eq("asset_symbol", symbol).execute()
    else:
        db.table("asset_alert_settings").upsert(
            {
                "user_id": user_id,
                "asset_symbol": symbol,
                "mode": request.mode,
                "threshold_pct": request.threshold_pct,
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="user_id,asset_symbol",
        ).execute()
    return {"asset_symbol": symbol, "mode": request.mode, "threshold_pct": request.threshold_pct}


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

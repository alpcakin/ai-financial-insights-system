import math

from fastapi import HTTPException, status
from supabase import Client
import yfinance as yf

from app.models.watchlist import AddWatchlistRequest, WatchlistItemResponse
from app.services.portfolio_service import _auto_subscribe, _auto_unsubscribe


def _get_price_info(symbol: str) -> tuple[float | None, float | None, float | None]:
    try:
        fast_info = yf.Ticker(symbol).fast_info
        price = fast_info.last_price
        prev_close = fast_info.previous_close

        if price is None or math.isnan(price):
            return None, None, None

        price = float(price)
        change: float | None = None
        change_pct: float | None = None

        if prev_close and not math.isnan(prev_close) and prev_close > 0:
            change = price - float(prev_close)
            change_pct = (change / float(prev_close)) * 100

        return price, change, change_pct
    except Exception:
        return None, None, None


def _build_response(row: dict) -> WatchlistItemResponse:
    price, change, change_pct = _get_price_info(row['asset_symbol'])
    return WatchlistItemResponse(
        id=row['id'],
        user_id=row['user_id'],
        asset_symbol=row['asset_symbol'],
        asset_type=row['asset_type'],
        current_price=price,
        price_change=change,
        price_change_pct=change_pct,
        added_at=str(row['added_at']),
    )


def get_watchlist(db: Client, user_id: str) -> list[WatchlistItemResponse]:
    result = db.table('watchlist').select('*').eq('user_id', user_id).execute()
    return [_build_response(row) for row in result.data]


def add_item(db: Client, user_id: str, request: AddWatchlistRequest) -> WatchlistItemResponse:
    symbol = request.asset_symbol.upper()

    existing = (
        db.table('watchlist')
        .select('id')
        .eq('user_id', user_id)
        .eq('asset_symbol', symbol)
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Asset already in watchlist',
        )

    result = db.table('watchlist').insert({
        'user_id': user_id,
        'asset_symbol': symbol,
        'asset_type': request.asset_type,
        'category': request.category,
    }).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Failed to add to watchlist',
        )

    _auto_subscribe(db, user_id, request.category)
    return _build_response(result.data[0])


def delete_item(db: Client, user_id: str, item_id: str) -> None:
    ownership = (
        db.table('watchlist')
        .select('id, category')
        .eq('id', item_id)
        .eq('user_id', user_id)
        .execute()
    )
    if not ownership.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Item not found',
        )

    category = ownership.data[0].get('category')
    db.table('watchlist').delete().eq('id', item_id).execute()
    _auto_unsubscribe(db, user_id, category)

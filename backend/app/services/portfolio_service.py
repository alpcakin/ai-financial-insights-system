import math

from fastapi import HTTPException, status
from supabase import Client
import yfinance as yf

from app.models.portfolio import AddAssetRequest, AssetResponse, PortfolioResponse, UpdateAssetRequest
from app.services.topic_service import auto_subscribe, auto_unsubscribe


def _get_current_price(symbol: str) -> float | None:
    try:
        price = yf.Ticker(symbol).fast_info.last_price
        if price is None or price == 0 or math.isnan(price):
            return None
        return float(price)
    except Exception:
        return None


def _get_current_prices(symbols: list[str]) -> dict[str, float | None]:
    if not symbols:
        return {}
    try:
        tickers = yf.Tickers(" ".join(symbols))
        result = {}
        for sym in symbols:
            try:
                price = tickers.tickers[sym].fast_info.last_price
                if price is None or price == 0 or math.isnan(price):
                    result[sym] = None
                else:
                    result[sym] = float(price)
            except Exception:
                result[sym] = None
        return result
    except Exception:
        return {sym: None for sym in symbols}


def _get_prices_and_daily_changes(symbols: list[str]) -> dict[str, dict]:
    if not symbols:
        return {}
    result = {}
    for sym in symbols:
        try:
            hist = yf.Ticker(sym).history(period="2d", interval="1d", auto_adjust=False)
            if len(hist) == 0:
                result[sym] = {'price': None, 'daily_change': None, 'daily_change_pct': None}
            elif len(hist) == 1:
                result[sym] = {'price': float(hist["Close"].iloc[-1]), 'daily_change': None, 'daily_change_pct': None}
            else:
                curr = float(hist["Close"].iloc[-1])
                prev = float(hist["Close"].iloc[-2])
                if prev == 0:
                    result[sym] = {'price': curr, 'daily_change': None, 'daily_change_pct': None}
                else:
                    change = curr - prev
                    result[sym] = {
                        'price': curr,
                        'daily_change': round(change, 4),
                        'daily_change_pct': round(change / prev * 100, 2),
                    }
        except Exception:
            result[sym] = {'price': None, 'daily_change': None, 'daily_change_pct': None}
    return result


def get_portfolio(db: Client, user_id: str) -> PortfolioResponse:
    result = db.table('portfolio').select('*').eq('user_id', user_id).execute()

    symbols = [row['asset_symbol'] for row in result.data]
    price_data = _get_prices_and_daily_changes(symbols)

    assets = []
    total_value = 0.0
    total_cost = 0.0
    total_daily_change = 0.0
    total_prev_value = 0.0

    for row in result.data:
        data = price_data.get(row['asset_symbol'], {})
        price = data.get('price')
        daily_change = data.get('daily_change')
        daily_change_pct = data.get('daily_change_pct')
        quantity = row['quantity']

        value = price * quantity if price is not None else None
        cost = row['purchase_price'] * quantity

        if value is not None:
            total_value += value
        total_cost += cost

        if daily_change is not None and price is not None:
            prev_price = price - daily_change
            total_daily_change += daily_change * quantity
            total_prev_value += prev_price * quantity

        assets.append(AssetResponse(
            id=row['id'],
            user_id=row['user_id'],
            asset_symbol=row['asset_symbol'],
            asset_type=row['asset_type'],
            quantity=quantity,
            purchase_price=row['purchase_price'],
            current_price=price,
            current_value=value,
            daily_change=daily_change,
            daily_change_pct=daily_change_pct,
            added_at=str(row['added_at']),
        ))

    total_pnl = total_value - total_cost
    total_pnl_pct = (total_pnl / total_cost * 100) if total_cost > 0 else 0.0
    total_daily_change_pct = (total_daily_change / total_prev_value * 100) if total_prev_value > 0 else 0.0

    return PortfolioResponse(
        assets=assets,
        total_value=total_value,
        total_pnl=round(total_pnl, 2),
        total_pnl_pct=round(total_pnl_pct, 2),
        total_daily_change=round(total_daily_change, 2),
        total_daily_change_pct=round(total_daily_change_pct, 2),
    )


def add_asset(db: Client, user_id: str, request: AddAssetRequest) -> AssetResponse:
    symbol = request.asset_symbol.upper()
    price = _get_current_price(symbol)

    existing = (
        db.table('portfolio')
        .select('id')
        .eq('user_id', user_id)
        .eq('asset_symbol', symbol)
        .execute()
    )
    if existing.data:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Asset already exists in portfolio',
        )

    result = db.table('portfolio').insert({
        'user_id': user_id,
        'asset_symbol': symbol,
        'asset_type': request.asset_type,
        'quantity': request.quantity,
        'purchase_price': request.purchase_price,
        'category': request.category,
    }).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Failed to add asset',
        )

    row = result.data[0]
    value = price * request.quantity if price is not None else None

    auto_subscribe(db, user_id, request.category)

    return AssetResponse(
        id=row['id'],
        user_id=row['user_id'],
        asset_symbol=row['asset_symbol'],
        asset_type=row['asset_type'],
        quantity=row['quantity'],
        purchase_price=row['purchase_price'],
        current_price=price,
        current_value=value,
        daily_change=None,
        daily_change_pct=None,
        added_at=str(row['added_at']),
    )


def update_asset(db: Client, user_id: str, asset_id: str, request: UpdateAssetRequest) -> AssetResponse:
    ownership = (
        db.table('portfolio')
        .select('*')
        .eq('id', asset_id)
        .eq('user_id', user_id)
        .execute()
    )
    if not ownership.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Asset not found',
        )

    result = db.table('portfolio').update({
        'quantity': request.quantity,
        'purchase_price': request.purchase_price,
    }).eq('id', asset_id).execute()

    if not result.data:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Failed to update asset',
        )

    row = result.data[0]
    price = _get_current_price(row['asset_symbol'])
    value = price * row['quantity'] if price is not None else None

    return AssetResponse(
        id=row['id'],
        user_id=row['user_id'],
        asset_symbol=row['asset_symbol'],
        asset_type=row['asset_type'],
        quantity=row['quantity'],
        purchase_price=row['purchase_price'],
        current_price=price,
        current_value=value,
        daily_change=None,
        daily_change_pct=None,
        added_at=str(row['added_at']),
    )


def delete_asset(db: Client, user_id: str, asset_id: str) -> None:
    ownership = (
        db.table('portfolio')
        .select('id, category')
        .eq('id', asset_id)
        .eq('user_id', user_id)
        .execute()
    )
    if not ownership.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Asset not found',
        )

    category = ownership.data[0].get('category')
    db.table('portfolio').delete().eq('id', asset_id).execute()
    auto_unsubscribe(db, user_id, category)

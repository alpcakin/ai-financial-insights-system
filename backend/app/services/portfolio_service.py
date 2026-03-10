import math

from fastapi import HTTPException, status
from supabase import Client
import yfinance as yf

from app.models.portfolio import AddAssetRequest, AssetResponse, PortfolioResponse, UpdateAssetRequest


def _get_current_price(symbol: str) -> float | None:
    try:
        price = yf.Ticker(symbol).fast_info.last_price
        if price is None or price == 0 or math.isnan(price):
            return None
        return float(price)
    except Exception:
        return None


def _auto_subscribe(db: Client, user_id: str, category_name: str | None) -> None:
    if not category_name:
        return

    cat_result = (
        db.table('categories')
        .select('id')
        .eq('name', category_name)
        .execute()
    )
    if not cat_result.data:
        return

    category_id = cat_result.data[0]['id']
    db.table('followed_topics').upsert(
        {'user_id': user_id, 'category_id': category_id, 'source': 'auto'},
        on_conflict='user_id,category_id',
    ).execute()


def _auto_unsubscribe(db: Client, user_id: str, category_name: str | None) -> None:
    if not category_name:
        return

    remaining_portfolio = (
        db.table('portfolio')
        .select('id')
        .eq('user_id', user_id)
        .eq('category', category_name)
        .execute()
    )
    remaining_watchlist = (
        db.table('watchlist')
        .select('id')
        .eq('user_id', user_id)
        .eq('category', category_name)
        .execute()
    )
    if remaining_portfolio.data or remaining_watchlist.data:
        return

    cat_result = (
        db.table('categories')
        .select('id')
        .eq('name', category_name)
        .execute()
    )
    if not cat_result.data:
        return

    category_id = cat_result.data[0]['id']
    db.table('followed_topics').delete().eq('user_id', user_id).eq('category_id', category_id).eq('source', 'auto').execute()


def get_portfolio(db: Client, user_id: str) -> PortfolioResponse:
    result = db.table('portfolio').select('*').eq('user_id', user_id).execute()
    assets = []
    total_value = 0.0

    for row in result.data:
        price = _get_current_price(row['asset_symbol'])
        value = price * row['quantity'] if price is not None else None
        if value is not None:
            total_value += value

        assets.append(AssetResponse(
            id=row['id'],
            user_id=row['user_id'],
            asset_symbol=row['asset_symbol'],
            asset_type=row['asset_type'],
            quantity=row['quantity'],
            purchase_price=row['purchase_price'],
            current_price=price,
            current_value=value,
            added_at=str(row['added_at']),
        ))

    return PortfolioResponse(assets=assets, total_value=total_value)


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
    value = price * request.quantity

    _auto_subscribe(db, user_id, request.category)

    return AssetResponse(
        id=row['id'],
        user_id=row['user_id'],
        asset_symbol=row['asset_symbol'],
        asset_type=row['asset_type'],
        quantity=row['quantity'],
        purchase_price=row['purchase_price'],
        current_price=price,
        current_value=value,
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
    _auto_unsubscribe(db, user_id, category)

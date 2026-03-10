from typing import Literal

from pydantic import BaseModel


class AddWatchlistRequest(BaseModel):
    asset_symbol: str
    asset_type: Literal['stock', 'etf', 'crypto', 'bond', 'commodity', 'other']
    category: str | None = None


class WatchlistItemResponse(BaseModel):
    id: str
    user_id: str
    asset_symbol: str
    asset_type: str
    current_price: float | None
    price_change: float | None
    price_change_pct: float | None
    added_at: str

from typing import Annotated

from pydantic import BaseModel, StringConstraints


class AddWatchlistRequest(BaseModel):
    asset_symbol: Annotated[str, StringConstraints(min_length=1, max_length=20, strip_whitespace=True)]


class WatchlistItemResponse(BaseModel):
    id: str
    user_id: str
    asset_symbol: str
    asset_type: str
    current_price: float | None
    price_change: float | None
    price_change_pct: float | None
    added_at: str

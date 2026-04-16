from typing import Literal

from pydantic import BaseModel, field_validator


class AddAssetRequest(BaseModel):
    asset_symbol: str
    asset_type: Literal['stock', 'etf', 'crypto', 'bond', 'commodity', 'other']
    quantity: float
    purchase_price: float
    category: str | None = None

    @field_validator('quantity', 'purchase_price')
    @classmethod
    def must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError('must be greater than 0')
        return v


class UpdateAssetRequest(BaseModel):
    quantity: float
    purchase_price: float

    @field_validator('quantity', 'purchase_price')
    @classmethod
    def must_be_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError('must be greater than 0')
        return v


class AssetResponse(BaseModel):
    id: str
    user_id: str
    asset_symbol: str
    asset_type: str
    quantity: float
    purchase_price: float
    current_price: float | None
    current_value: float | None
    daily_change: float | None
    daily_change_pct: float | None
    added_at: str


class PortfolioResponse(BaseModel):
    assets: list[AssetResponse]
    total_value: float
    total_pnl: float
    total_pnl_pct: float
    total_daily_change: float
    total_daily_change_pct: float

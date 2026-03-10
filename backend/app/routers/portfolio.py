from fastapi import APIRouter, Depends, Response, status
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.portfolio import AddAssetRequest, AssetResponse, PortfolioResponse, UpdateAssetRequest
from app.services.portfolio_service import add_asset, delete_asset, get_portfolio, update_asset

router = APIRouter(prefix='/portfolio', tags=['portfolio'])


@router.get('', response_model=PortfolioResponse)
def list_portfolio(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_portfolio(db, current_user['id'])


@router.post('', response_model=AssetResponse, status_code=201)
def create_asset(
    request: AddAssetRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return add_asset(db, current_user['id'], request)


@router.put('/{asset_id}', response_model=AssetResponse)
def edit_asset(
    asset_id: str,
    request: UpdateAssetRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return update_asset(db, current_user['id'], asset_id, request)


@router.delete('/{asset_id}', status_code=204)
def remove_asset(
    asset_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    delete_asset(db, current_user['id'], asset_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

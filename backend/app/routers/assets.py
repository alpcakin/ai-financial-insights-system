from typing import Annotated

from fastapi import APIRouter, Depends, Query
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.asset import AddCatalogAssetRequest
from app.services.asset_catalog import asset_info, listed_assets
from app.services.asset_search_service import add_to_catalog, search_assets

router = APIRouter(prefix="/assets", tags=["assets"])


@router.get("")
def list_assets(current_user: dict = Depends(get_current_user), db: Client = Depends(get_db)):
    return {"assets": [asset_info(asset) for asset in listed_assets(db)]}


@router.get("/search")
def search(
    q: Annotated[str, Query(min_length=1, max_length=50)],
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return {"results": search_assets(db, current_user["id"], q)}


@router.post("")
def add(
    request: AddCatalogAssetRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return add_to_catalog(db, current_user["id"], request.symbol)

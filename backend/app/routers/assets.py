from fastapi import APIRouter, Depends

from app.dependencies import get_current_user
from app.services.asset_catalog import ASSETS

router = APIRouter(prefix="/assets", tags=["assets"])


@router.get("")
def list_assets(current_user: dict = Depends(get_current_user)):
    return {"assets": ASSETS}

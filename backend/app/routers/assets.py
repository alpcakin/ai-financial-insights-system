from fastapi import APIRouter, Depends
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.services.asset_catalog import listed_assets

router = APIRouter(prefix="/assets", tags=["assets"])

_FIELDS = ("symbol", "name", "type", "category")


@router.get("")
def list_assets(current_user: dict = Depends(get_current_user), db: Client = Depends(get_db)):
    return {"assets": [{key: asset[key] for key in _FIELDS} for asset in listed_assets(db)]}

from fastapi import APIRouter, Depends, Response, status
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.watchlist import AddWatchlistRequest, WatchlistItemResponse
from app.services.watchlist_service import add_item, delete_item, get_watchlist

router = APIRouter(prefix='/watchlist', tags=['watchlist'])


@router.get('', response_model=list[WatchlistItemResponse])
def list_watchlist(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_watchlist(db, current_user['id'])


@router.post('', response_model=WatchlistItemResponse, status_code=201)
def create_item(
    request: AddWatchlistRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return add_item(db, current_user['id'], request)


@router.delete('/{item_id}', status_code=204)
def remove_item(
    item_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    delete_item(db, current_user['id'], item_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

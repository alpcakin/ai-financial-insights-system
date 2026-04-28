from fastapi import APIRouter, Depends, Response
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.services.topic_service import follow_topic, get_topics_with_status, unfollow_topic

router = APIRouter(prefix="/topics", tags=["topics"])


@router.get("")
def list_topics(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_topics_with_status(db, current_user["id"])


@router.post("/{category_id}/follow")
def follow(
    category_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    follow_topic(db, current_user["id"], category_id)
    return {"ok": True}


@router.delete("/{category_id}/follow", status_code=204)
def unfollow(
    category_id: str,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    unfollow_topic(db, current_user["id"], category_id)
    return Response(status_code=204)

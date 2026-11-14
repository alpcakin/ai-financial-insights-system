from fastapi import APIRouter, Depends, Query, Response
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.topic import AddTopicRequest, TopicResponse
from app.services.topic_service import (
    add_topic,
    follow_topic,
    get_topics_with_status,
    search_topics,
    unfollow_topic,
)

router = APIRouter(prefix="/topics", tags=["topics"])


@router.get("", response_model=list[TopicResponse])
def list_topics(
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return get_topics_with_status(db, current_user["id"])


@router.get("/search", response_model=list[TopicResponse])
def search(
    q: str = Query("", max_length=100),
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return search_topics(db, current_user["id"], q)


@router.post("", response_model=TopicResponse, status_code=201)
def add(
    request: AddTopicRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return add_topic(db, current_user, request.name)


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

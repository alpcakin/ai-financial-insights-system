from uuid import UUID

from fastapi import APIRouter, Depends, Response, status
from supabase import Client

from app.core.database import get_db
from app.dependencies import get_current_user
from app.models.manual import (
    AddModelRequest,
    AddSourceRequest,
    ManualSettingsResponse,
    ModelResponse,
    SourceResponse,
    UpdateManualSettingsRequest,
    UpdateSourceRequest,
)
from app.services import manual_service

router = APIRouter(prefix='/manual', tags=['manual'])


@router.get('/settings', response_model=ManualSettingsResponse)
def get_settings(current_user: dict = Depends(get_current_user)):
    return manual_service.get_settings(current_user)


@router.patch('/settings', response_model=ManualSettingsResponse)
def update_settings(
    request: UpdateManualSettingsRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return manual_service.update_settings(db, current_user, request)


@router.get('/sources', response_model=list[SourceResponse])
def list_sources(current_user: dict = Depends(get_current_user), db: Client = Depends(get_db)):
    return manual_service.list_sources(db, current_user['id'])


@router.post('/sources', response_model=SourceResponse, status_code=201)
def add_source(
    request: AddSourceRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return manual_service.add_source(db, current_user, request)


@router.patch('/sources/{source_id}', response_model=SourceResponse)
def update_source(
    source_id: UUID,
    request: UpdateSourceRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return manual_service.update_source(db, current_user, str(source_id), request)


@router.delete('/sources/{source_id}', status_code=204)
def delete_source(
    source_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    manual_service.delete_source(db, current_user, str(source_id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get('/models', response_model=list[ModelResponse])
def list_models(current_user: dict = Depends(get_current_user), db: Client = Depends(get_db)):
    return manual_service.list_models(db, current_user['id'])


@router.post('/models', response_model=ModelResponse, status_code=201)
def add_model(
    request: AddModelRequest,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return manual_service.add_model(db, current_user, request)


@router.post('/models/{model_id}/retry', response_model=ModelResponse)
def retry_model(
    model_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    return manual_service.retry_model(db, current_user, str(model_id))


@router.delete('/models/{model_id}', status_code=204)
def delete_model(
    model_id: UUID,
    current_user: dict = Depends(get_current_user),
    db: Client = Depends(get_db),
):
    manual_service.delete_model(db, current_user, str(model_id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)

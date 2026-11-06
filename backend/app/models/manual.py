from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, Field, StringConstraints

Url = Annotated[str, StringConstraints(min_length=1, max_length=2000, strip_whitespace=True)]
ShortText = Annotated[str, StringConstraints(min_length=1, max_length=100, strip_whitespace=True)]
ModelKind = Literal["openai", "gemini", "claude", "compatible"]


class ManualSettingsResponse(BaseModel):
    package_enabled: bool
    manual_enabled: bool
    grouping_enabled: bool
    selected_model_id: str | None
    can_store_keys: bool


class UpdateManualSettingsRequest(BaseModel):
    package_enabled: bool | None = None
    manual_enabled: bool | None = None
    grouping_enabled: bool | None = None
    selected_model_id: UUID | None = None


class SourceResponse(BaseModel):
    id: str
    url: str
    name: str
    fetch_interval_minutes: int
    enabled: bool
    last_fetched_at: str | None
    last_error: str | None
    created_at: str


class AddSourceRequest(BaseModel):
    url: Url
    name: ShortText | None = None
    fetch_interval_minutes: int = Field(default=15, ge=5, le=1440)


class UpdateSourceRequest(BaseModel):
    name: ShortText | None = None
    fetch_interval_minutes: int | None = Field(default=None, ge=5, le=1440)
    enabled: bool | None = None


class ModelResponse(BaseModel):
    id: str
    kind: str
    model: str
    label: str
    base_url: str | None
    key_last4: str
    stopped_reason: str | None
    created_at: str


class AddModelRequest(BaseModel):
    kind: ModelKind
    model: ShortText
    api_key: Annotated[str, StringConstraints(min_length=8, max_length=500, strip_whitespace=True)]
    label: ShortText | None = None
    base_url: Url | None = None

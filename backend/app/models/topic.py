from typing import Literal

from pydantic import BaseModel, Field


class TopicResponse(BaseModel):
    id: str
    name: str
    level: int | None
    parent_id: str | None
    kind: Literal["category", "topic"]
    followed: bool


class AddTopicRequest(BaseModel):
    name: str = Field(min_length=1, max_length=200)

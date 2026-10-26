from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RoomCreate(StrictModel):
    source_language: str = Field(pattern=r"^[a-z]{2,3}$")
    target_language: str = Field(pattern=r"^[a-z]{2,3}$")


class RoomJoin(RoomCreate):
    code: str = Field(pattern=r"^[A-HJ-NP-Z2-9]{16}$")


class SessionRequest(StrictModel):
    conversation_id: UUID
    consent_to_processing: bool

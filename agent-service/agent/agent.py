"""LangChain agent with validated read and action tools."""

from typing import Annotated

import httpx
from pydantic import BaseModel, Field


class CreateLoadInput(BaseModel):
    customer_id: Annotated[str, Field(description="Customer ID")]
    route_id: Annotated[str, Field(description="Route ID")]
    load_type: Annotated[str, Field(description="Load type")]
    weight_lbs: Annotated[int, Field(description="Weight in lbs", ge=1)]
    pieces: Annotated[int, Field(description="Pieces", ge=1)]
    revenue: Annotated[float, Field(description="Revenue", ge=0)]

    model_config = {"extra": "forbid"}


def create_load(
    inp: CreateLoadInput, base_url: str = "http://api-service:8080", timeout: float = 5.0
) -> dict:
    import uuid

    headers = {
        "Idempotency-Key": str(uuid.uuid4()),
        "X-Actor": "agent",
        "X-Trace-Id": str(uuid.uuid4()),
    }
    with httpx.Client(timeout=timeout) as client:
        r = client.post(f"{base_url}/v1/loads", json=inp.model_dump(), headers=headers)
        r.raise_for_status()
        return r.json()

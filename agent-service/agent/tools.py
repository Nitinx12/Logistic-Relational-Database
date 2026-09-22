"""Read-only tools for customer and order lookups."""

from typing import Annotated

from pydantic import BaseModel, Field


class GetCustomerSummaryInput(BaseModel):
    customer_id: Annotated[str, Field(description="Customer ID like CUST00001")]

    model_config = {"extra": "forbid"}


class ListLoadsInput(BaseModel):
    customer_id: Annotated[str, Field(description="Customer ID")] = Field(default="")
    status: Annotated[str, Field(description="Load status filter")] = Field(default="")
    since: Annotated[str, Field(description="ISO date lower bound")] = Field(default="")

    model_config = {"extra": "forbid"}


def get_customer_summary(inp: GetCustomerSummaryInput) -> dict:
    return {"tool": "get_customer_summary", "input": inp.model_dump()}


def list_loads(inp: ListLoadsInput) -> dict:
    return {"tool": "list_loads", "input": inp.model_dump()}

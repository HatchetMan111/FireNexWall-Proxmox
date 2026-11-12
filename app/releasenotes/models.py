from __future__ import annotations

import re
from datetime import date
from typing import Literal
from urllib.parse import urlparse

from pydantic import BaseModel, ConfigDict, Field, field_validator

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
Status = Literal["stable", "rc", "beta", "alpha", "security"]


class Download(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    label: str = Field(min_length=1, max_length=120)
    url: str = Field(min_length=1, max_length=2000)
    platform: str | None = Field(default=None, max_length=60)
    sha256: str | None = Field(default=None, max_length=128)

    @field_validator("url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        parsed = urlparse(value)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise ValueError("url must be an absolute http(s) URL")
        return value


class ReleaseIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    version: str = Field(min_length=1, max_length=64)
    slug: str | None = Field(default=None, max_length=64)
    title: str = Field(default="", max_length=200)
    status: Status = "stable"
    release_date: date
    summary: str = Field(default="", max_length=500)
    body_md: str = ""
    known_issues_md: str = ""
    downloads: list[Download] = Field(default_factory=list)
    published: bool = True

    @field_validator("slug")
    @classmethod
    def validate_slug(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().lower()
        if not SLUG_RE.match(normalized):
            raise ValueError("slug must match ^[a-z0-9][a-z0-9._-]*$")
        return normalized


class ReleaseOut(ReleaseIn):
    slug: str
    id: int
    status: Status
    created_at: str
    updated_at: str


class LoginIn(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)

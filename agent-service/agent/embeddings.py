"""Embeds new or changed chunks to pgvector via Ollama."""

import hashlib
import os
from collections.abc import Iterable

import httpx


def chunk_text(text: str, size: int = 500, overlap: int = 50) -> list[str]:
    if not text:
        return []
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(len(text), start + size)
        chunks.append(text[start:end])
        if end == len(text):
            break
        start = end - overlap
    return chunks


def content_hash(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:32]


def embed_texts(
    texts: list[str], model: str | None = None, host: str | None = None, timeout: float = 30.0
) -> list[list[float]]:
    m = model or os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
    h = (host or os.getenv("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")
    url = f"{h}/api/embeddings"
    out: list[list[float]] = []
    with httpx.Client(timeout=timeout) as client:
        for t in texts:
            r = client.post(url, json={"model": m, "prompt": t})
            r.raise_for_status()
            j = r.json()
            out.append(j.get("embedding", []))
    return out


def upsert_needed(existing_hashes: set[str], chunks: Iterable[str]) -> list[str]:
    return [c for c in chunks if content_hash(c) not in existing_hashes]

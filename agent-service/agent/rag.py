"""RAG search over pgvector doc_chunks."""

import os

import httpx
import psycopg2
from psycopg2.extras import RealDictCursor


def search_docs(query: str, k: int = 5, timeout: float = 10.0) -> list[dict]:
    ollama_host = os.getenv("OLLAMA_HOST", "http://localhost:11434").rstrip("/")
    model = os.getenv("OLLAMA_EMBED_MODEL", "nomic-embed-text")
    with httpx.Client(timeout=timeout) as client:
        r = client.post(f"{ollama_host}/api/embeddings", json={"model": model, "prompt": query})
        r.raise_for_status()
        vec = r.json().get("embedding", [])
    dsn = f"host={os.getenv('POSTGRES_HOST', 'localhost')} port={os.getenv('POSTGRES_PORT', '5432')} dbname={os.getenv('POSTGRES_DATABASE', 'LRDB')} user={os.getenv('POSTGRES_USERNAME', 'postgres')} password={os.getenv('POSTGRES_PASSWORD', 'postgres')}"
    conn = psycopg2.connect(dsn)
    try:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT chunk_id, content, source FROM serving.doc_chunks ORDER BY embedding <=> %s::vector LIMIT %s",
                (vec, k),
            )
            return cur.fetchall()
    finally:
        conn.close()

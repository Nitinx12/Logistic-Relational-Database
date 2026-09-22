"""Refreshes pgvector doc_chunks for new or changed content."""

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "agent-service"))

import psycopg2
from agent.embeddings import chunk_text, content_hash, embed_texts
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parents[1] / ".env")


def fetch_existing_hashes(conn) -> set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT content_hash FROM serving.doc_chunks")
        return {r[0] for r in cur.fetchall()}


def main() -> None:
    pg_host = os.getenv("POSTGRES_HOST", "localhost")
    pg_port = os.getenv("POSTGRES_PORT", "5432")
    pg_db = os.getenv("POSTGRES_DATABASE", "LRDB")
    pg_user = os.getenv("POSTGRES_USERNAME", "postgres")
    pg_pass = os.getenv("POSTGRES_PASSWORD", "postgres")
    dsn = f"host={pg_host} port={pg_port} dbname={pg_db} user={pg_user} password={pg_pass}"
    source = os.getenv("EMBED_SOURCE_DIR", "testdata/docs")
    texts: list[str] = []
    src = Path(source)
    if src.exists():
        for p in src.rglob("*.md"):
            texts.extend(chunk_text(p.read_text(encoding="utf-8", errors="ignore")))
    else:
        texts = chunk_text("LRDB logistics policies and product info for RAG.")

    try:
        conn = psycopg2.connect(dsn)
    except Exception as e:  # noqa: BLE001
        print(f"postgres connect failed {e}, skipping embeddings")
        return
    try:
        try:
            existing = fetch_existing_hashes(conn)
        except Exception as e:  # noqa: BLE001
            print(f"fetch hashes failed {e}, assuming 0 existing")
            existing = set()
        to_embed = [t for t in texts if content_hash(t) not in existing]
        if not to_embed:
            print("no new chunks")
            return
        try:
            vectors = embed_texts(to_embed)
        except Exception as e:  # noqa: BLE001
            print(f"embed failed {e}, skipping")
            return
        with conn.cursor() as cur:
            for txt, vec in zip(to_embed, vectors):
                cur.execute(
                    "INSERT INTO serving.doc_chunks(chunk_id, source, content, content_hash, embedding) VALUES (%s,%s,%s,%s,%s) ON CONFLICT (chunk_id) DO UPDATE SET content=EXCLUDED.content, embedding=EXCLUDED.embedding, updated_at=now()",
                    (content_hash(txt), source, txt, content_hash(txt), vec),
                )
        conn.commit()
        print(f"upserted {len(to_embed)} chunks")
    finally:
        conn.close()


if __name__ == "__main__":
    main()

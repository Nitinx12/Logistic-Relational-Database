#!/usr/bin/env python3
"""
tests.py — Run all PL/pgSQL stored-procedure tests found in the project's
`tests/` folder, using the project's own utils.engine / utils.logger for
the DB connection and logging.

Location:   <project_root>/scripts/tests.py
Tests dir:  <project_root>/tests/*.sql
Logs dir:   <project_root>/logs/tests/tests-log_<timestamp>.log

CONVENTION
----------
Every *.sql file under tests/ is treated as one independent test case.
  - PASS = the file executes with no error.
  - FAIL = it raises an error (e.g. RAISE EXCEPTION on a failed
    assertion inside a DO block / stored-procedure call, or any SQL error).

Example test file:

    -- tests/001_add_user.sql
    DO $$
    DECLARE
        v_count int;
    BEGIN
        RAISE NOTICE 'creating user alice';
        CALL sp_add_user('alice', 'alice@example.com');

        SELECT count(*) INTO v_count FROM users WHERE username = 'alice';
        RAISE NOTICE 'found % matching rows', v_count;
        IF v_count <> 1 THEN
            RAISE EXCEPTION 'expected 1 user named alice, got %', v_count;
        END IF;
    END $$;

OUTPUT
------
Whatever the procedure/DO block "prints" via RAISE NOTICE / RAISE INFO /
RAISE WARNING while it runs is captured from the connection and shown
right under that test's PASS/FAIL line — the same messages you'd see
running the file in psql. If the file's final statement is a SELECT (or
a CALL with OUT parameters), those result rows are shown too.

Each test runs inside its own transaction, taken straight from the
underlying psycopg2 connection (engine.raw_connection()) rather than
through SQLAlchemy's text() layer, so PL/pgSQL syntax like `::int` casts
or `v := 1;` assignments never get misread as bind parameters. Every
transaction is rolled back afterwards (pass or fail), so no test leaves
data behind or affects another test.

USAGE
-----
    python scripts/tests.py
    python scripts/tests.py --tests-dir ../tests
    python scripts/tests.py -v      # also print full error detail to console
"""

import argparse
import sys
import time
from pathlib import Path

# Make the project root importable so `utils.*` resolves regardless of cwd.
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(PROJECT_ROOT))

from utils.engine import postgres_engine
from utils.logger import get_logger

logger = get_logger("tests", "tests-log")


def find_test_files(tests_dir: Path):
    if not tests_dir.is_dir():
        return []
    return sorted(tests_dir.glob("*.sql"))


def _dbapi_connection(raw_conn):
    """Get the real psycopg2 connection out of SQLAlchemy's pool proxy,
    across both the 2.0-style (`dbapi_connection`) and 1.4-style
    (`connection`) attribute names."""
    return getattr(raw_conn, "dbapi_connection", None) or getattr(raw_conn, "connection", raw_conn)


def run_test(engine, sql_path: Path):
    """Run one test file in its own transaction; always rolled back.

    Returns (passed, error, elapsed_seconds, output_lines) where
    output_lines holds any RAISE NOTICE/INFO/WARNING text plus any
    returned rows, in the order they were emitted.
    """
    sql = sql_path.read_text()
    start = time.perf_counter()
    output = []

    try:
        raw_conn = engine.raw_connection()
    except Exception as exc:
        return False, f"could not acquire connection: {exc}", time.perf_counter() - start, output

    dbapi_conn = _dbapi_connection(raw_conn)
    try:
        dbapi_conn.notices.clear()
    except Exception:
        pass

    passed, error = True, None
    try:
        cursor = raw_conn.cursor()
        try:
            cursor.execute(sql)

            # Any rows returned (a SELECT, or a CALL with OUT parameters)
            if cursor.description is not None:
                try:
                    rows = cursor.fetchall()
                    cols = [d[0] for d in cursor.description]
                    output.append(f"columns: {cols}")
                    output.extend(f"row: {row}" for row in rows)
                except Exception:
                    pass
        except Exception as exc:
            passed, error = False, str(exc).strip()
        finally:
            # RAISE NOTICE / INFO / WARNING messages emitted while it ran,
            # placed before any row output so they read in chronological order.
            try:
                output = [n.strip() for n in dbapi_conn.notices] + output
            except Exception:
                pass
            raw_conn.rollback()
            cursor.close()
    finally:
        raw_conn.close()

    return passed, error, time.perf_counter() - start, output


def main():
    parser = argparse.ArgumentParser(description="Run PL/pgSQL stored-procedure tests.")
    parser.add_argument(
        "--tests-dir",
        default=None,
        help="Path to the tests folder (default: <project_root>/tests)",
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Also print full error detail to console for failures (always logged to file regardless)"
    )
    args = parser.parse_args()

    tests_dir = Path(args.tests_dir).resolve() if args.tests_dir else PROJECT_ROOT / "tests"
    test_files = find_test_files(tests_dir)

    if not test_files:
        logger.error(f"No .sql test files found in: {tests_dir}")
        sys.exit(1)

    try:
        engine = postgres_engine()
    except Exception as exc:
        logger.error(f"Could not create Postgres engine: {exc}")
        sys.exit(1)

    logger.info(f"Found {len(test_files)} test(s) in {tests_dir}")

    results = []
    for sql_path in test_files:
        name = sql_path.stem
        passed, error, elapsed, output = run_test(engine, sql_path)
        results.append((name, passed, error, elapsed))

        status = "PASS" if passed else "FAIL"
        logger.info(f"[{status}] {name} ({elapsed:.3f}s)")

        for line in output:
            logger.info(f"    | {line}")

        if not passed:
            logger.debug(f"{name} error detail: {error}")
            if args.verbose:
                print(f"        -> {error}")

    engine.dispose()

    total = len(results)
    passed_count = sum(1 for _, ok, _, _ in results if ok)
    failed_count = total - passed_count
    total_time = sum(t for _, _, _, t in results)

    summary_lines = [
        "=" * 50,
        "TEST SUMMARY",
        "=" * 50,
        f"Total:   {total}",
        f"Passed:  {passed_count}",
        f"Failed:  {failed_count}",
        f"Time:    {total_time:.3f}s",
    ]

    if failed_count:
        summary_lines.append("")
        summary_lines.append("Failed tests:")
        for name, ok, error, _ in results:
            if not ok:
                summary_lines.append(f"  - {name}: {error}")

    summary_lines.append("=" * 50)
    logger.info("\n" + "\n".join(summary_lines))

    sys.exit(1 if failed_count else 0)


if __name__ == "__main__":
    main()
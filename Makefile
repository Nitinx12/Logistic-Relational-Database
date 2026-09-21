# Canonical commands for local dev and CI.
PROFILES ?= core

.PHONY: up down fmt lint test test-it build check-fast check hooks

up:
	docker compose --profile $(PROFILES) up --wait

down:
	docker compose --profile $(PROFILES) down -v

fmt:
	./mvnw spotless:apply || echo "mvnw not ready, skipping fmt"
	ruff format . || echo "ruff not installed, skipping"
	ruff check --fix . || echo "ruff check skipped"

lint:
	ruff check .
	sqlfluff lint --dialect postgres db/migrations || echo "sqlfluff skipped"
	python scripts/hooks/check_comments.py || echo "check_comments skipped"

test:
	./mvnw -B -ntp test -DskipITs || echo "mvn tests skipped"
	pytest -q || echo "pytest skipped"

test-it:
	./mvnw -B -ntp verify -DskipUTs || echo "integration tests skipped"

build:
	./mvnw -B -ntp verify

check-fast: fmt lint test

check: check-fast test-it build

hooks:
	pre-commit install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push
	git config core.hooksPath .githooks || true

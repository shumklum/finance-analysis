#!/bin/sh
# The CI gates, inside the test image:
#   docker compose --profile test run --rm test            # backend + frontend
#   docker compose --profile test run --rm test e2e        # + Playwright e2e
set -eu
cd /app

echo "== backend: ruff + pytest"
ruff check backend
pytest -q

echo "== frontend: lint + i18n keys + vitest"
cd frontend
npm run lint
python3 ../.claude/scripts/check_i18n_keys.py
npm test

if [ "${1:-}" = "e2e" ]; then
  echo "== e2e: Playwright against a throwaway backend"
  export FAD_USER_DIR="$(mktemp -d)"
  (cd /app && uvicorn backend.main:app --port 8000 >/tmp/backend.log 2>&1 &)
  npx vite preview --port 5173 --strictPort >/tmp/frontend.log 2>&1 &
  # A curl loop instead of CI's `npx -y wait-on` (an unpinned download).
  for url in http://localhost:8000/openapi.json http://localhost:5173; do
    i=0; until curl -fs "$url" >/dev/null; do
      i=$((i + 1)); [ "$i" -lt 60 ] || { echo "timeout: $url" >&2; exit 1; }; sleep 1
    done
  done
  npx playwright test
fi

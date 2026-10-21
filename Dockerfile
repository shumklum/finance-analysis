# Self-hosted server image (the upstream app is a desktop app; this runs the
# same backend + built SPA as one container). See docker/README.md.
#
# Targets:
#   app   the server: uvicorn + frontend/dist + Google Chrome (scrapers) + Xvfb
#   test  app + dev deps + Node, for pytest / vitest / Playwright e2e

ARG PYTHON_VERSION=3.12
ARG NODE_VERSION=22

# ---------------------------------------------------------------- frontend --
FROM node:${NODE_VERSION}-bookworm-slim AS frontend
WORKDIR /src/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# -------------------------------------------------------------------- base --
FROM python:${PYTHON_VERSION}-slim-bookworm AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH \
    PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright

# Xvfb + x11vnc: a display for headed scrapes (FAD_SCRAPER_SHOW_BROWSER=1) and a
# way to watch them. Culmus/Noto: Hebrew glyphs for bank pages and screenshots.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      tini xvfb x11vnc culmus fonts-noto-core ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml poetry.lock ./
RUN python -m venv /opt/poetry \
 && /opt/poetry/bin/pip install poetry==2.3.3 \
 && python -m venv /opt/venv \
 && /opt/poetry/bin/poetry install --no-root --only main --no-interaction \
 && pip install keyrings.cryptfile==1.3.9

# The scrapers launch channel="chrome" (real Google Chrome, not Playwright's
# Chromium build) — install it through Playwright so the version is one
# Playwright supports.
RUN playwright install --with-deps chrome

RUN useradd --create-home --uid 1000 app \
 && mkdir -p /data && chown app:app /data

# --------------------------------------------------------------------- app --
FROM base AS app
COPY alembic.ini ./
COPY backend/ backend/
COPY scraper/ scraper/
COPY --from=frontend /src/frontend/dist frontend/dist
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/fa_keyring.py /opt/fa/fa_keyring.py

USER app
ENV FAD_USER_DIR=/data \
    PYTHONPATH=/opt/fa \
    KEYRING_CRYPTFILE_PATH=/data/keyring/cryptfile_pass.cfg \
    PYTHON_KEYRING_BACKEND=fa_keyring.EnvCryptFileKeyring \
    ENVIRONMENT=production \
    DISPLAY=:99
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s \
  CMD curl -fsS http://127.0.0.1:8080/api/version >/dev/null || exit 1
ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8080"]

# -------------------------------------------------------------------- test --
FROM base AS test
ARG NODE_VERSION
COPY --from=node:22-bookworm-slim /usr/local/bin/node /usr/local/bin/node
COPY --from=node:22-bookworm-slim /usr/local/lib/node_modules /usr/local/lib/node_modules
# git: tests/scripts/test_prod_server.py builds throwaway repos.
RUN apt-get update && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* \
 && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
 && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
 && /opt/poetry/bin/poetry install --no-root --with dev --no-interaction
COPY --from=frontend /src/frontend/node_modules frontend/node_modules
COPY . .
COPY --from=frontend /src/frontend/dist frontend/dist
RUN cd frontend && npx playwright install --with-deps --only-shell chromium
# CI's choice: a plaintext keyring is fine for throwaway test data.
ENV PYTHON_KEYRING_BACKEND=keyrings.alt.file.PlaintextKeyring \
    CI=true
CMD ["docker/run-tests.sh"]

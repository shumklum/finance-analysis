# Running Finance Analysis in Docker (self-hosted)

The upstream app is a desktop app (localhost, OS keyring, `start.sh prod`
auto-pulling new commits). This fork adds a server setup: one container serving
the API + built SPA, Google Chrome for the scrapers, data on a volume. It does
**not** auto-update: you pull upstream on purpose (see Updating).

## First run

```bash
cp docker/env.template .env && chmod 600 .env
# fill FAD_API_TOKEN and KEYRING_CRYPTFILE_PASSWORD (openssl rand -base64 32)
docker compose build
docker compose up -d
```

Ports bind to the host's loopback only. From another machine:

```bash
ssh -L 8090:127.0.0.1:8090 <host>
# then open once, the SPA keeps the token:
open "http://localhost:8090/?apiToken=$FAD_API_TOKEN"
```

Try **Demo Mode** (sidebar toggle) first: sample data, no real accounts.

## Tests

```bash
docker compose --profile test build test
docker compose --profile test run --rm test        # ruff + pytest, eslint + i18n keys + vitest
docker compose --profile test run --rm test e2e    # + Playwright e2e
```

## What lives where

| Path in `${FAD_DATA_DIR}` | What |
| --- | --- |
| `*.db` | SQLite database (back this up) |
| `keyring/` | encrypted keyring file: bank passwords + the DB field-encryption key, unlocked by `KEYRING_CRYPTFILE_PASSWORD` |
| `browser-profiles/<provider>-<hash>/` | persistent Chrome profiles (bank device trust) |
| `api_token` | unused when `FAD_API_TOKEN` is set |

Lose `KEYRING_CRYPTFILE_PASSWORD` and the stored credentials can't be decrypted
(re-enter them). Back up `.env` separately from the data dir.

## Fork additions (scrapers)

| Env | Default here | Effect |
| --- | --- | --- |
| `FAD_SCRAPER_PROFILE_DIR` | `/data/browser-profiles` | keep one Chrome profile per bank login, so device-trust banks (Hapoalim) ask for the SMS code once, not every run. Unset = upstream behaviour (fresh browser). |
| `FAD_SCRAPER_SHOW_BROWSER` | `1` | run Chrome headed on the container's Xvfb display: a genuine `Chrome/…` agent (headless announces `HeadlessChrome/…`) and real rendering |
| `FAD_SCRAPER_NATIVE_UA` | `1` | when headed, keep Chrome's real (Linux) user agent instead of upstream's fixed macOS one, which contradicts the browser's other signals. Headless always uses the fixed one. |

**Watching a scrape:** set `VNC_PASSWORD` in `.env`, `docker compose up -d`,
then `ssh -L 5909:127.0.0.1:5909 <host>` and open `vnc://localhost:5909`
(macOS Screen Sharing). Handy for a first Hapoalim login.

**Never retry a failed bank login in a loop**: wrong codes or passwords can
lock the account or arm the bank's 24h OTP block.

## Updating from upstream

```bash
git fetch upstream
git log --oneline main..upstream/main     # read what changed
git diff main upstream/main -- backend scraper frontend/package-lock.json poetry.lock
git checkout main && git merge upstream/main && git push
git checkout docker && git rebase main
docker compose build && docker compose up -d
```

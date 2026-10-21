#!/bin/sh
# Container entrypoint: an X display for headed scrapes, an optional VNC view of
# it, then the server (CMD).
set -eu

mkdir -p "$FAD_USER_DIR" "$(dirname "$KEYRING_CRYPTFILE_PATH")"
chmod 700 "$(dirname "$KEYRING_CRYPTFILE_PATH")"

if [ -z "${KEYRING_CRYPTFILE_PASSWORD:-}" ]; then
  echo "KEYRING_CRYPTFILE_PASSWORD is not set: refusing to start (bank credentials" >&2
  echo "are encrypted with it). Set it in .env — see docker/README.md." >&2
  exit 1
fi

# Xvfb always runs: headless scrapes ignore it, headed ones
# (FAD_SCRAPER_SHOW_BROWSER=1) draw on it.
Xvfb :99 -screen 0 1366x900x24 -nolisten tcp >/dev/null 2>&1 &

# x11vnc only when a password is given. -noshm: MIT-SHM is refused across the
# user boundary in containers (same fix as the home-browser stack).
if [ -n "${VNC_PASSWORD:-}" ]; then
  mkdir -p "$HOME/.vnc"
  x11vnc -storepasswd "$VNC_PASSWORD" "$HOME/.vnc/passwd" >/dev/null 2>&1
  x11vnc -display :99 -rfbport 5900 -rfbauth "$HOME/.vnc/passwd" \
    -forever -shared -noshm -quiet >/dev/null 2>&1 &
fi

exec "$@"

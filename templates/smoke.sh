#!/usr/bin/env bash
# Smoke check after a deploy: a few requests that a working site answers in a known way.
# Copy to scripts/smoke.sh, make it executable, and list the application's own checks at the bottom.
# Usage: scripts/smoke.sh https://test.example.com
set -euo pipefail

base="${1:?usage: scripts/smoke.sh <base URL>}"
base="${base%/}"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT
failures=0

# Prints the HTTP status of a GET and keeps the body. Network errors and 5xx answers are retried.
status() {
  curl -sS -o "$body" -w '%{http_code}' --max-time 15 --retry 4 --retry-delay 5 --retry-all-errors "$base$1" || true
}

# expect <path> <status> [text the body must contain]
expect() {
  local path="$1" code="$2" text="${3:-}" got
  got="$(status "$path")"
  if [ "$got" != "$code" ]; then
    echo "::error::$path answered $got, expected $code ($base)"
    failures=$((failures + 1))
  elif [ -n "$text" ] && ! grep -qF "$text" "$body"; then
    echo "::error::$path answered $code but without \"$text\" ($base)"
    failures=$((failures + 1))
  else
    echo "ok  $path $got"
  fi
}

# The application's own checks. For example: the app shell, and an API that refuses without a session.
expect / 200 '<div id="root">'
# expect /api/some-route 401

if [ "$failures" -gt 0 ]; then
  echo "Smoke check on $base: $failures failure(s)."
  exit 1
fi
echo "Smoke check on $base: all good."

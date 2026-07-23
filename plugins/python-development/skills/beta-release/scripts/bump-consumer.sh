#!/usr/bin/env bash
# Bumps a git+https-pinned shared-library dependency in requirements.txt to a
# new tag, reinstalls it, and optionally rebuilds a docker compose service.
# Run from the consumer repo root (e.g. core-api, driver-api, a job repo).
#
# Usage:
#   bump-consumer.sh <new-tag> [--package <name>] [--service <docker-compose-service>] [--file <requirements-file>]
#
# --package defaults to "common-structure-library". Pass a different one for
# other shared libs pinned the same way (telemetry-kit-library, voltop-bi-library,
# voltop-python-logger-library, ai-toolkit-library, ...).
# --service is opt-in: pass it only when this consumer actually has a docker
# compose service to rebuild (e.g. the api). Job-style consumers usually don't.
set -euo pipefail

log() { echo "[bump-consumer] $*"; }
die() { echo "[bump-consumer] ERROR: $*" >&2; exit 1; }

NEW_TAG=""
PACKAGE="common-structure-library"
SERVICE=""
REQ_FILE="requirements.txt"

while [ $# -gt 0 ]; do
  case "$1" in
    --package) PACKAGE="$2"; shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    --file) REQ_FILE="$2"; shift 2 ;;
    -*) die "unknown flag: $1" ;;
    *)
      [ -z "$NEW_TAG" ] || die "unexpected extra argument: $1"
      NEW_TAG="$1"; shift ;;
  esac
done
[ -n "$NEW_TAG" ] || die "usage: bump-consumer.sh <new-tag> [--package <name>] [--service <name>] [--file <path>]"

[ -f "$REQ_FILE" ] || die "$REQ_FILE not found in $(pwd)"

if ! grep -q "/${PACKAGE}\.git@" "$REQ_FILE"; then
  die "no line in $REQ_FILE pins github.com/<org>/${PACKAGE}.git@<tag> — check --package"
fi

log "bumping ${PACKAGE} pin in ${REQ_FILE} to ${NEW_TAG}"
awk -v pkg="$PACKAGE" -v tag="$NEW_TAG" '
  {
    pattern = "/" pkg "\\.git@[^#[:space:]]+"
    if ($0 ~ pattern) { gsub(pattern, "/" pkg ".git@" tag) }
    print
  }
' "$REQ_FILE" > "${REQ_FILE}.tmp" && mv "${REQ_FILE}.tmp" "$REQ_FILE"

if [ -x ./.venv/bin/pip3 ]; then
  PIP=./.venv/bin/pip3
elif command -v pip3 >/dev/null 2>&1; then
  PIP=pip3
else
  PIP=pip
fi
log "installing with $PIP..."
"$PIP" install -r "$REQ_FILE"

if [ -n "$SERVICE" ]; then
  if [ -f docker-compose.yml ] || [ -f docker-compose.yaml ] || [ -f compose.yml ] || [ -f compose.yaml ]; then
    log "rebuilding docker compose service '$SERVICE'..."
    docker compose build "$SERVICE"
  else
    die "--service '$SERVICE' given but no docker-compose.yml/compose.yaml found in $(pwd)"
  fi
else
  log "no --service given, skipping docker compose build"
fi

log "done: ${PACKAGE} -> ${NEW_TAG}"

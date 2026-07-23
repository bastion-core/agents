#!/usr/bin/env bash
# Publishes (or bumps) a beta prerelease for the Python library in the current
# directory, tagged v.<setup.py version>.beta.<n>. Run from the library repo root,
# on the feature branch, with all changes already committed.
#
# What it does:
#   1. Refuses to run on main/master, or with an unclean working tree.
#   2. Pushes the current branch.
#   3. Detects the package version (literal VERSION= in setup.py, or a
#      _version.py's __version__ as a fallback).
#   4. Finds the highest existing v.<version>.beta.<n> tag, if any. Deletes it
#      (GitHub release + tag) and creates v.<version>.beta.<n+1>; otherwise
#      creates v.<version>.beta.1.
#   5. Pushes the new tag and creates a GitHub prerelease for it.
set -euo pipefail

log() { echo "[publish-beta] $*"; }
die() { echo "[publish-beta] ERROR: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"
command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required — https://cli.github.com"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated — run 'gh auth login' first"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$ROOT"

BRANCH="$(git branch --show-current)"
[ -n "$BRANCH" ] || die "detached HEAD — checkout a branch first"
case "$BRANCH" in
  main|master) die "refusing to publish a beta from '$BRANCH' — checkout your feature branch" ;;
esac

[ -z "$(git status --porcelain)" ] || die "working tree is not clean — commit your changes first"

detect_version() {
  local v vf
  if [ -f setup.py ]; then
    v=$(grep -E "^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" setup.py | head -1 \
        | sed -E "s/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")
    [ -n "$v" ] && { echo "$v"; return 0; }
  fi
  vf=$(find . -name "_version.py" -not -path "./.venv/*" -not -path "*/node_modules/*" | head -1)
  if [ -n "$vf" ]; then
    v=$(grep -E "__version__[[:space:]]*=[[:space:]]*['\"][^'\"]+['\"]" "$vf" | head -1 \
        | sed -E "s/.*__version__[[:space:]]*=[[:space:]]*['\"]([^'\"]+)['\"].*/\1/")
    [ -n "$v" ] && { echo "$v"; return 0; }
  fi
  return 1
}

VERSION="$(detect_version)" || die "could not detect the package version (no literal VERSION in setup.py, no _version.py __version__)"
log "detected version: $VERSION"

log "running test suite..."
if [ -f Makefile ] && grep -qE '^test:' Makefile; then
  make test
elif command -v pytest >/dev/null 2>&1; then
  pytest
else
  die "no 'make test' target and no pytest on PATH — install test deps first"
fi

log "pushing branch '$BRANCH'..."
git push origin "$BRANCH"

next_beta_tag() {
  local matches old_tag old_n new_n
  matches=$(git tag -l "v.${VERSION}.beta.*")
  if [ -z "$matches" ]; then
    echo "v.${VERSION}.beta.1|"
    return 0
  fi
  old_tag=$(echo "$matches" | sed -E 's/.*\.beta\.([0-9]+)$/\1 &/' | sort -n | tail -1 | cut -d' ' -f2-)
  old_n=$(echo "$old_tag" | sed -E 's/.*\.beta\.([0-9]+)$/\1/')
  new_n=$((old_n + 1))
  echo "v.${VERSION}.beta.${new_n}|${old_tag}"
}

RESULT="$(next_beta_tag)"
NEW_TAG="${RESULT%%|*}"
OLD_TAG="${RESULT##*|}"

if [ -n "$OLD_TAG" ]; then
  log "replacing existing prerelease $OLD_TAG with $NEW_TAG"
  if gh release view "$OLD_TAG" >/dev/null 2>&1; then
    gh release delete "$OLD_TAG" --yes --cleanup-tag
  else
    git push origin --delete "$OLD_TAG" 2>/dev/null || true
  fi
  git tag -d "$OLD_TAG" 2>/dev/null || true
else
  log "creating first prerelease for $VERSION: $NEW_TAG"
fi

git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin "$NEW_TAG"

SHORT_SHA="$(git rev-parse --short HEAD)"
gh release create "$NEW_TAG" \
  --prerelease \
  --title "$NEW_TAG" \
  --notes "Beta build from branch \`$BRANCH\` @ $SHORT_SHA"

log "done: $NEW_TAG"

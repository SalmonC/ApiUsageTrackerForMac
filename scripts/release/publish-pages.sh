#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
APPCAST_PATH="${APPCAST_PATH:-$PROJECT_ROOT/Artifacts/release/appcast.xml}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
PAGES_SUBDIR="${PAGES_SUBDIR:-.}"
COMMIT_MESSAGE="${COMMIT_MESSAGE:-chore(release): update appcast}"

if [[ ! -f "$APPCAST_PATH" ]]; then
  echo "Appcast not found: $APPCAST_PATH" >&2
  exit 1
fi

if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $PROJECT_ROOT" >&2
  exit 1
fi

WORKTREE_DIR="$(mktemp -d /tmp/quotapulse-pages.XXXXXX)"
cleanup() {
  git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

echo "[pages] Preparing worktree for branch: $PAGES_BRANCH"
git -C "$PROJECT_ROOT" fetch origin "$PAGES_BRANCH":"$PAGES_BRANCH" >/dev/null 2>&1 || true
git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" "$PAGES_BRANCH"

TARGET_DIR="$WORKTREE_DIR/$PAGES_SUBDIR"
mkdir -p "$TARGET_DIR"
cp "$APPCAST_PATH" "$TARGET_DIR/appcast.xml"

if [[ -n "$(git -C "$WORKTREE_DIR" status --porcelain)" ]]; then
  git -C "$WORKTREE_DIR" add "$TARGET_DIR/appcast.xml"
  git -C "$WORKTREE_DIR" commit -m "$COMMIT_MESSAGE"
  git -C "$WORKTREE_DIR" push origin "$PAGES_BRANCH"
  echo "[pages] Published appcast.xml to $PAGES_BRANCH/$PAGES_SUBDIR"
else
  echo "[pages] No appcast changes to publish."
fi

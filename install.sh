#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${DONT_SINK_REPO:-https://github.com/realjules/DONT-SINK-YR-SHIP}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "Error: git is required but not installed." >&2
  exit 1
fi

echo "Cloning $REPO_URL"
git clone --depth 1 "$REPO_URL" "$TMP_DIR/repo"

mkdir -p "$SKILLS_DIR"

install_skill() {
  local src="$1" name="$2"
  local dest="$SKILLS_DIR/$name"
  if [ -e "$dest" ] && [ ! -d "$dest" ]; then
    echo "Error: $dest exists and is not a directory" >&2
    exit 1
  fi
  rm -rf "$dest"
  cp -r "$src" "$dest"
  echo "Installed $name -> $dest"
}

install_skill "$TMP_DIR/repo/audit" "dont-sink-yr-ship"
install_skill "$TMP_DIR/repo/fix"   "dont-sink-yr-ship-fix"

COMMIT_SHA=$(git -C "$TMP_DIR/repo" rev-parse --short HEAD)
echo ""
echo "Installed at commit $COMMIT_SHA."
echo ""
echo "Start a new Claude Code session and run:"
echo "  /dont-sink-yr-ship           # audit"
echo "  /dont-sink-yr-ship-fix       # apply fixes after the audit"

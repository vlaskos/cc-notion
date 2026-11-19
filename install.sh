#!/bin/bash
# Usage: NGROK_DOMAIN=xxx.ngrok-free.app NOTION_USER_ID=... ./install.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
: "${NGROK_DOMAIN:?export NGROK_DOMAIN=your-domain.ngrok-free.app}"
NOTION_USER_ID="${NOTION_USER_ID:-}"
ALLOWED_TOOLS="${ALLOWED_TOOLS:-mcp__notion}"

NODE="$(command -v node)"     || { echo "node not found"; exit 1; }
CLAUDE="$(command -v claude)" || { echo "claude not found"; exit 1; }
NGROK="$(command -v ngrok)"   || { echo "ngrok not found (brew install ngrok)"; exit 1; }
PATHS="$(dirname "$NODE"):$(dirname "$CLAUDE"):/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$DIR/logs" "$DIR/data" "$HOME/Library/LaunchAgents"
# First run: seed the local rules file from the example. Your edits to CLAUDE.md stay local (gitignored).
[ -f "$DIR/workspace/CLAUDE.md" ] || cp "$DIR/workspace/CLAUDE.example.md" "$DIR/workspace/CLAUDE.md"

for name in com.cc-notion.listener com.cc-notion.ngrok; do
  dst="$HOME/Library/LaunchAgents/$name.plist"
  sed -e "s|__DIR__|$DIR|g" -e "s|__NODE__|$NODE|g" -e "s|__CLAUDE__|$CLAUDE|g" \
      -e "s|__NGROK__|$NGROK|g" -e "s|__NGROK_DOMAIN__|$NGROK_DOMAIN|g" \
      -e "s|__NOTION_USER_ID__|$NOTION_USER_ID|g" -e "s|__ALLOWED_TOOLS__|$ALLOWED_TOOLS|g" \
      -e "s|__PATH__|$PATHS|g" "$DIR/launchd/$name.plist" > "$dst"
  launchctl bootout "gui/$(id -u)/$name" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$dst"
  echo "loaded $name"
done
sleep 2
curl -fsS http://127.0.0.1:8787/health && echo " <- listener ok"

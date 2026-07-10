#!/usr/bin/env bash
#
# Apply the user-scope MCP servers declared in servers.json to Claude Code.
#
# User-scope MCP servers live in ~/.claude.json, which is machine-specific and
# full of private data, so it can't be symlinked like the rest of the dotfiles.
# Instead we keep the declarations in servers.json and push them in via the
# official `claude mcp add-json` command. Re-running is safe (idempotent):
# each server is removed and re-added so servers.json stays the source of truth.
#
# Usage: ~/dotfiles/claude/mcp/apply.sh   (or: make claude-mcp)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/servers.json"

command -v claude >/dev/null 2>&1 || { echo "error: 'claude' CLI not found on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not found on PATH (brew install jq)" >&2; exit 1; }

names=$(jq -r '.mcpServers | keys[]' "$CONFIG")

if [ -z "$names" ]; then
  echo "No MCP servers declared in $CONFIG — nothing to apply."
  exit 0
fi

while IFS= read -r name; do
  [ -z "$name" ] && continue
  config=$(jq -c --arg n "$name" '.mcpServers[$n]' "$CONFIG")
  echo "Applying MCP server: $name"
  # Remove first so the declaration in servers.json always wins (ignore if absent).
  claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
  claude mcp add-json "$name" "$config" --scope user
done <<< "$names"

echo "Done. Current user-scope MCP servers:"
claude mcp list

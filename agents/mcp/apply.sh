#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/servers.json"
CLIENT="${1:-all}"

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not found on PATH (brew install jq)" >&2; exit 1; }

case "$CLIENT" in
  all|claude|opencode) ;;
  *) echo "usage: $0 [all|claude|opencode]" >&2; exit 2 ;;
esac

apply_claude() {
  command -v claude >/dev/null 2>&1 || { echo "error: 'claude' CLI not found on PATH" >&2; return 1; }

  while IFS= read -r name; do
    config=$(jq -c --arg name "$name" '.mcpServers[$name]' "$CONFIG")
    echo "Applying Claude MCP server: $name"
    claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
    claude mcp add-json "$name" "$config" --scope user
  done < <(jq -r '.mcpServers | keys[]' "$CONFIG")
}

apply_opencode() {
  command -v opencode >/dev/null 2>&1 || { echo "error: 'opencode' CLI not found on PATH" >&2; return 1; }

  # opencode has no `mcp remove`, but `mcp add` overwrites an existing entry, so
  # re-running is idempotent. Servers are written to ~/.config/opencode config.
  while IFS= read -r name; do
    type=$(jq -r --arg name "$name" '.mcpServers[$name].type // "stdio"' "$CONFIG")
    echo "Applying opencode MCP server: $name"

    if [ "$type" = "http" ] || [ "$type" = "sse" ] || [ "$type" = "remote" ]; then
      url=$(jq -r --arg name "$name" '.mcpServers[$name].url' "$CONFIG")
      command=(opencode mcp add "$name" --url "$url")
      while IFS= read -r header; do
        command+=(--header "$header")
      done < <(jq -r --arg name "$name" '.mcpServers[$name].headers // {} | to_entries[] | "\(.key)=\(.value)"' "$CONFIG")
      "${command[@]}"
      continue
    fi

    executable=$(jq -r --arg name "$name" '.mcpServers[$name].command' "$CONFIG")
    command=(opencode mcp add "$name")
    while IFS= read -r env; do
      command+=(--env "$env")
    done < <(jq -r --arg name "$name" '.mcpServers[$name].env // {} | to_entries[] | "\(.key)=\(.value)"' "$CONFIG")
    command+=(-- "$executable")
    while IFS= read -r arg; do
      command+=("$arg")
    done < <(jq -r --arg name "$name" '.mcpServers[$name].args // [] | .[]' "$CONFIG")
    "${command[@]}"
  done < <(jq -r '.mcpServers | keys[]' "$CONFIG")
}

if [ "$CLIENT" = "all" ] || [ "$CLIENT" = "opencode" ]; then
  apply_opencode
fi

if [ "$CLIENT" = "all" ] || [ "$CLIENT" = "claude" ]; then
  apply_claude
fi

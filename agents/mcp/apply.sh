#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/servers.json"
CLIENT="${1:-all}"

command -v jq >/dev/null 2>&1 || { echo "error: 'jq' not found on PATH (brew install jq)" >&2; exit 1; }

case "$CLIENT" in
  all|claude|opencode|pi) ;;
  *) echo "usage: $0 [all|claude|opencode|pi]" >&2; exit 2 ;;
esac

apply_pi() {
  # Pi reads a plain JSON file. pi/mcp.json is stowed to ~/.pi/agent/mcp.json,
  # so writing the repo file keeps the live config in sync. Pi rejects the
  # "remote" and "sse" transport types, so drop `type` for those (a `url`
  # selects streamable HTTP on its own).
  local out="$SCRIPT_DIR/../../pi/mcp.json"
  echo "Applying pi MCP servers -> $out"
  jq '{mcpServers: (.mcpServers | map_values(
        if (.type == "remote" or .type == "sse") then del(.type) else . end))}' \
    "$CONFIG" > "$out"
}

apply_claude() {
  command -v claude >/dev/null 2>&1 || { echo "error: 'claude' CLI not found on PATH" >&2; return 1; }

  while IFS= read -r name; do
    # Claude's add-json rejects `type: "remote"`/`"sse"` and the `oauth` block
    # (it negotiates OAuth interactively), so normalize before adding.
    config=$(jq -c --arg name "$name" '.mcpServers[$name]
      | if (.type == "remote" or .type == "sse") then .type = "http" else . end
      | del(.oauth)' "$CONFIG")
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

if [ "$CLIENT" = "all" ] || [ "$CLIENT" = "pi" ]; then
  apply_pi
fi

if [ "$CLIENT" = "all" ] || [ "$CLIENT" = "opencode" ]; then
  apply_opencode
fi

if [ "$CLIENT" = "all" ] || [ "$CLIENT" = "claude" ]; then
  apply_claude
fi

// notify.ts — play the shared agent notification sounds for opencode.
//
// Mirrors the Claude Code hooks (see ~/.claude/settings.json) and Codex hooks
// (see ~/.codex/config.toml) so all three agents chime identically:
//   * input needed  -> Ping.aiff   (a permission/approval prompt is shown)
//   * turn finished  -> Glass.aiff  (the session goes idle, awaiting the user)
//
// Both sounds are produced by ~/.tmux/agents.sh, the single source of truth for
// agent notifications. Calls are fire-and-forget so they never delay opencode.

import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join } from "node:path"

const SCRIPT = join(homedir(), ".tmux", "agents.sh")

export const NotifyPlugin: Plugin = async ({ $ }) => {
  const notify = (mode: "input" | "ready") => {
    // .quiet() suppresses output, .nothrow() keeps a missing script/afplay from
    // rejecting the promise. Intentionally not awaited: the script backgrounds
    // afplay and returns immediately, so there is nothing to wait on.
    void $`bash ${SCRIPT} notify ${mode}`.quiet().nothrow()
  }

  return {
    // A permission/approval prompt means opencode needs the user to act.
    "permission.ask": async () => {
      notify("input")
    },
    // session.idle fires when the turn ends and opencode is awaiting input.
    event: async ({ event }) => {
      if (event.type === "session.idle") notify("ready")
    },
  }
}

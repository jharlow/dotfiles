// notify.ts — play the shared agent notification sounds for opencode.
//
// Mirrors the Claude Code hooks (see ~/.claude/settings.json) and Codex hooks
// (see ~/.codex/config.toml) so all three agents chime identically:
//   * input needed  -> Ping.aiff   (a permission/approval prompt is shown)
//   * turn finished  -> Glass.aiff  (the session goes idle, awaiting the user)
//
// Both sounds are produced by ~/.tmux/agents.sh, the single source of truth for
// agent notifications. Calls are fire-and-forget so they never delay opencode.

import { Plugin } from "@opencode/plugin"
import { spawn } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const SCRIPT = join(homedir(), ".tmux", "agents.sh")

export default Plugin.define({
  id: "notify",
  async setup(ctx) {
    const notify = (mode: "input" | "ready") => {
      try {
        // detached + ignore: the script backgrounds afplay and returns at once,
        // so nothing needs to be awaited and the child never holds opencode
        // open on exit. The error listener keeps a missing script/afplay from
        // becoming an unhandled rejection.
        // Run the script directly so it uses its own shebang instead of
        // assuming a particular shell is on PATH.
        const child = spawn(SCRIPT, ["notify", mode], {
          stdio: "ignore",
          detached: true,
        })
        child.on("error", () => {})
        child.unref()
      } catch {
        // Notifications are best-effort decoration; never break the session.
      }
    }

    // The evaluate hook runs after the configured rules resolve. An "ask"
    // effect means opencode is about to show the user a permission prompt.
    await ctx.permission.hook("evaluate", (event) => {
      if (event.effect === "ask") notify("input")
    })

    // session.idle fires when the turn ends and opencode is awaiting input.
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({
          types: ["session.idle"],
          signal: controller.signal,
        })) {
          notify("ready")
        }
      } catch {
        // Aborting the subscription during unload is expected.
      }
    })()

    return () => controller.abort()
  },
})

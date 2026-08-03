// status.ts — publish this opencode instance's live status for ~/.tmux/agents.sh.
//
// agents.sh has to guess at each agent's state by grepping the pane's rendered
// screen (see STATUS_* in that script). That works for claude/codex, but
// opencode's footer strings change often and a scrollback line can easily look
// like a spinner, so the guess is frequently wrong. This plugin removes the
// guess: opencode already knows whether it is busy, blocked on a permission, or
// idle, so we write that fact to a small file and let agents.sh read it.
//
// Contract with agents.sh (keep the two in sync):
//   path    $XDG_STATE_HOME/opencode/agents/<pid>.state   (default ~/.local/state)
//   format  key=value, one per line, values contain no '='
//   keys    pid    the opencode process that owns the file
//           pane   $TMUX_PANE at startup, or empty when not under tmux
//           state  awaiting | working | idle
//           since  epoch seconds of the last state change
//           dir    worktree the instance was launched in
//
// Liveness is the reader's job: a hard kill (SIGKILL, panic, closed terminal)
// skips our cleanup, so agents.sh must confirm `pid` is still alive before
// trusting a file. Files are written atomically (tmp + rename) so a reader can
// never observe a half-written line.

import type { Plugin } from "@opencode-ai/plugin"
import { mkdirSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const STATE_DIR = join(
  process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"),
  "opencode",
  "agents",
)
const STATE_FILE = join(STATE_DIR, `${process.pid}.state`)

type Status = "awaiting" | "working" | "idle"

export const StatusPlugin: Plugin = async ({ worktree, directory }) => {
  // Sessions report busy/idle independently, and subagents get their own
  // session, so "is this instance working?" is "is any session still busy?".
  const busy = new Set<string>()
  // Permission prompts are keyed by id because several can queue up; the pane
  // is only unblocked once every one of them has been answered.
  const asked = new Set<string>()

  let current: Status | undefined
  let cleaned = false

  const derive = (): Status =>
    // Awaiting outranks working: a session stays busy while it blocks on a
    // permission, and "needs you" is the more useful thing to surface.
    asked.size > 0 ? "awaiting" : busy.size > 0 ? "working" : "idle"

  const publish = () => {
    const next = derive()
    if (next === current || cleaned) return
    current = next

    const body =
      [
        `pid=${process.pid}`,
        `pane=${process.env.TMUX_PANE ?? ""}`,
        `state=${next}`,
        `since=${Math.floor(Date.now() / 1000)}`,
        `dir=${worktree || directory}`,
      ].join("\n") + "\n"

    try {
      mkdirSync(STATE_DIR, { recursive: true })
      // rename(2) is atomic within a filesystem, so agents.sh either sees the
      // whole previous file or the whole new one.
      const tmp = `${STATE_FILE}.${Date.now()}.tmp`
      writeFileSync(tmp, body)
      renameSync(tmp, STATE_FILE)
    } catch {
      // Status reporting is best-effort decoration; never break the session
      // over a read-only home directory or a racing cleanup.
    }
  }

  const cleanup = () => {
    if (cleaned) return
    cleaned = true
    try {
      rmSync(STATE_FILE, { force: true })
    } catch {}
  }

  // Only the clean-exit path is hooked. Deliberately no signal handlers: opencode
  // installs its own SIGINT/SIGTERM handling, and re-raising a signal after ours
  // ran would deliver it to those handlers twice. Signal deaths therefore leave
  // the file behind, which is safe — agents.sh ignores files whose pid is gone,
  // and sweep() below reaps them on the next launch.
  process.once("exit", cleanup)

  // Drop files left by instances that died without running cleanup, so the
  // directory stays roughly the size of the running agent count.
  const sweep = () => {
    try {
      for (const name of readdirSync(STATE_DIR)) {
        const pid = Number(name.replace(/\.state$/, ""))
        if (!Number.isInteger(pid) || pid === process.pid) continue
        try {
          // Signal 0 performs the permission/existence check without delivering.
          process.kill(pid, 0)
        } catch {
          rmSync(join(STATE_DIR, name), { force: true })
        }
      }
    } catch {}
  }

  sweep()
  publish()

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.status": {
          const { sessionID, status } = event.properties
          // "retry" is a backoff between attempts — still working, not idle.
          if (status.type === "idle") busy.delete(sessionID)
          else busy.add(sessionID)
          break
        }
        // session.idle is the authoritative end-of-turn signal; session.status
        // alone can leave a session marked busy if its idle event is missed.
        case "session.idle":
          busy.delete(event.properties.sessionID)
          break
        case "session.deleted":
          busy.delete(event.properties.info.id)
          break
        case "session.error":
          if (event.properties.sessionID) busy.delete(event.properties.sessionID)
          break
        // permission.updated fires only when opencode actually needs the user
        // to answer; auto-allowed permissions never reach it.
        case "permission.updated":
          asked.add(event.properties.id)
          break
        case "permission.replied":
          asked.delete(event.properties.permissionID)
          break
        default:
          return
      }
      publish()
    },
  }
}

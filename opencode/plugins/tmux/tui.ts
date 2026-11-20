// tmux/tui.ts — publish this TUI's open session tabs for ~/.tmux/agents.sh.
//
// In V2 server plugins run inside the shared background service, which knows
// nothing about tmux. TUI plugins run in each terminal client instead, so this
// is the one place that knows both "which pane am I in" ($TMUX_PANE) and "which
// sessions are open here" (ui.tabs). We write that to a small file per TUI and
// let the `prefix + a` picker read it.
//
// Contract with agents.sh (keep the two in sync):
//   dir      $XDG_STATE_HOME/opencode/tui                 (default ~/.local/state)
//   <pid>.tsv    written by us, one line per open session tab:
//                pane  sessionID  active(1|0)  state  dir  title
//                state is awaiting | error | done | working | idle
//   <pid>.focus  written by the picker, holds one sessionID; we focus that tab
//                and delete the file.
//
// Liveness is the reader's job: a hard kill skips our cleanup, so agents.sh must
// confirm the pid is alive and the pane still exists before trusting a file.
// Files are written atomically (tmp + rename).

import { Plugin } from "@opencode/plugin/tui"
import { mkdirSync, readdirSync, readFileSync, renameSync, rmSync, watch, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

const STATE_DIR = join(process.env.XDG_STATE_HOME || join(homedir(), ".local", "state"), "opencode", "tui")
const STATE_FILE = join(STATE_DIR, `${process.pid}.tsv`)
const FOCUS_FILE = `${process.pid}.focus`

// Tab open/close/focus changes are client-side and emit no server event, so a
// cheap poll catches them; server events below just make status changes prompt.
const POLL_MS = 500

// Tabs and newlines would break the TSV row; titles are free text.
const clean = (value: string) => value.replace(/[\t\r\n]+/g, " ").trim()

export default Plugin.define({
  id: "tmux",
  setup(context) {
    const pane = process.env.TMUX_PANE
    if (!pane) return

    let last = ""
    let cleaned = false

    const dirOf = (sessionID: string) =>
      context.data.session.get(sessionID)?.location?.directory ?? context.location?.directory ?? ""

    const rows = () => {
      const ui = context.ui
      if (ui.tabs.enabled()) {
        return ui.tabs.list().map((tab) => {
          // Needing you outranks everything; an unseen finish/failure outranks
          // plain busy/idle because it is what you would want to jump to.
          const state = tab.attention
            ? "awaiting"
            : tab.unread === "error"
              ? "error"
              : tab.busy
                ? "working"
                : tab.unread === "activity"
                  ? "done"
                  : "idle"
          const title = tab.title || context.data.session.get(tab.sessionID)?.title || ""
          return [pane, tab.sessionID, tab.active ? "1" : "0", state, dirOf(tab.sessionID), clean(title)]
        })
      }
      // Tabs off: the TUI shows one session at a time, from the router.
      const route = ui.router.current()
      if (route.type !== "session") return []
      const state = context.data.session.status(route.sessionID) === "running" ? "working" : "idle"
      const title = context.data.session.get(route.sessionID)?.title ?? ""
      return [[pane, route.sessionID, "1", state, dirOf(route.sessionID), clean(title)]]
    }

    const publish = () => {
      if (cleaned) return
      let body: string
      try {
        body = rows()
          .map((row) => row.join("\t") + "\n")
          .join("")
      } catch {
        return
      }
      if (body === last) return
      last = body
      try {
        mkdirSync(STATE_DIR, { recursive: true })
        const tmp = `${STATE_FILE}.${Date.now()}.tmp`
        writeFileSync(tmp, body)
        renameSync(tmp, STATE_FILE)
      } catch {
        // Best-effort decoration; never break the TUI over the state dir.
      }
    }

    const focus = () => {
      const path = join(STATE_DIR, FOCUS_FILE)
      let sessionID: string
      try {
        sessionID = readFileSync(path, "utf8").trim()
        rmSync(path, { force: true })
      } catch {
        return
      }
      if (!sessionID) return
      if (!context.ui.tabs.focus(sessionID)) context.ui.router.navigate({ type: "session", sessionID })
      publish()
    }

    const cleanup = () => {
      if (cleaned) return
      cleaned = true
      for (const path of [STATE_FILE, join(STATE_DIR, FOCUS_FILE)]) {
        try {
          rmSync(path, { force: true })
        } catch {}
      }
    }

    // Drop files left by TUIs that died without running cleanup.
    const sweep = () => {
      try {
        for (const name of readdirSync(STATE_DIR)) {
          const pid = Number(name.split(".")[0])
          // pid 0 would signal our own process group, so skip non-pid names.
          if (!Number.isInteger(pid) || pid <= 0 || pid === process.pid) continue
          try {
            process.kill(pid, 0)
          } catch {
            rmSync(join(STATE_DIR, name), { force: true })
          }
        }
      } catch {}
    }

    mkdirSync(STATE_DIR, { recursive: true })
    sweep()
    publish()
    focus()

    process.once("exit", cleanup)
    const timer = setInterval(publish, POLL_MS)
    const stopEvents = context.data.listen(() => publish())
    const watcher = watch(STATE_DIR, (_event, name) => {
      if (name === FOCUS_FILE) focus()
    })

    return () => {
      clearInterval(timer)
      stopEvents()
      watcher.close()
      cleanup()
    }
  },
})

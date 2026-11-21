// tui.tsx — close the session tabs the agent asked to close with session_close.
//
// A request arrives while the session is still busy (the tool call is part of
// its turn), so it waits here until the session goes idle and then closes the
// tab, letting the final reply land first. With tabs off, the TUI shows one
// session at a time, so "closing" it means going back home.

import { Plugin } from "@opencode/plugin/tui"

// The close event of the Sessions RPC (rpc.ts), as the event stream names it:
// prefixed with the RPC's id.
const CLOSE_EVENT = "rpc.sessions.close"

// Tab state changes are client-side and emit no server event, so a cheap poll
// backs up the server events that usually trigger the check.
const POLL_MS = 500

export default Plugin.define({
  id: "sessions.tui",
  setup(context) {
    const pending = new Set<string>()

    const busy = (sessionID: string) => {
      if (context.data.session.status(sessionID) === "running") return true
      return context.ui.tabs.enabled() && context.ui.tabs.list().some((tab) => tab.sessionID === sessionID && tab.busy)
    }

    const close = (sessionID: string) => {
      if (context.ui.tabs.enabled()) {
        if (context.ui.tabs.list().some((tab) => tab.sessionID === sessionID)) context.ui.tabs.close(sessionID)
        return
      }
      const route = context.ui.router.current()
      if (route.type === "session" && route.sessionID === sessionID) context.ui.router.navigate({ type: "home" })
    }

    const settle = () => {
      for (const sessionID of pending) {
        if (busy(sessionID)) continue
        pending.delete(sessionID)
        close(sessionID)
      }
    }

    // Read close requests off the TUI's shared event stream rather than
    // context.client.rpc(Sessions).events: that subscription is live-only and
    // isn't re-established when the background service restarts, so a TUI
    // that outlived a restart would silently stop closing tabs. The shared
    // stream reconnects on its own.
    const stopEvents = context.data.listen(({ details }) => {
      const event = details as { type: string; data?: unknown }
      if (event.type === CLOSE_EVENT) pending.add((event.data as { sessionID: string }).sessionID)
      settle()
    })
    const timer = setInterval(() => pending.size > 0 && settle(), POLL_MS)

    return () => {
      clearInterval(timer)
      stopEvents()
    }
  },
})

// tui.tsx — close the session tabs the agent asked to close with session_close.
//
// A request arrives while the session is still busy (the tool call is part of
// its turn), so it waits here until the session goes idle and then closes the
// tab, letting the final reply land first. With tabs off, the TUI shows one
// session at a time, so "closing" it means going back home.

import { Plugin } from "@opencode/plugin/tui"
import { Sessions } from "./rpc"

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

    const stopClose = context.client.rpc(Sessions).events.on("close", (event) => {
      pending.add((event.data as { sessionID: string }).sessionID)
      settle()
    })
    const stopEvents = context.data.listen(() => settle())
    const timer = setInterval(() => pending.size > 0 && settle(), POLL_MS)

    return () => {
      clearInterval(timer)
      stopEvents()
      stopClose()
    }
  },
})

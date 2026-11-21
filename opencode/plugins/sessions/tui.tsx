// tui.tsx — open the session tabs the agent started with session_open, and
// close the ones it asked to close with session_close.
//
// A new tab opens in the TUIs showing the session that opened it, right after
// the opener's tab; without an opener (an HTTP call that didn't name one),
// every TUI opens it. With tabs off, the TUI shows one session at a time, so a
// focused open navigates there and a background one only shows a toast.
//
// A close request arrives while the session is still busy (the tool call is
// part of its turn), so it waits here until the session goes idle and then
// closes the tab, letting the final reply land first. With tabs off, "closing"
// means going back home.

import { Plugin } from "@opencode/plugin/tui"

// The events of the Sessions RPC (rpc.ts), as the event stream names them:
// prefixed with the RPC's id.
const OPEN_EVENT = "rpc.sessions.open"
const CLOSE_EVENT = "rpc.sessions.close"

// Tab state changes are client-side and emit no server event, so a cheap poll
// backs up the server events that usually trigger the check.
const POLL_MS = 500

type Open = { sessionID: string; openerID?: string; focus: boolean }

export default Plugin.define({
  id: "sessions.tui",
  setup(context) {
    const pending = new Set<string>()

    const showing = (sessionID: string) => {
      if (context.ui.tabs.enabled()) return context.ui.tabs.list().some((tab) => tab.sessionID === sessionID)
      const route = context.ui.router.current()
      return route.type === "session" && route.sessionID === sessionID
    }

    const busy = (sessionID: string) => {
      if (context.data.session.status(sessionID) === "running") return true
      return context.ui.tabs.enabled() && context.ui.tabs.list().some((tab) => tab.sessionID === sessionID && tab.busy)
    }

    const open = async ({ sessionID, openerID, focus }: Open) => {
      if (openerID && !showing(openerID)) return
      await context.data.session.sync(sessionID)
      if (!context.ui.tabs.enabled()) {
        if (focus) context.ui.router.navigate({ type: "session", sessionID })
        else context.ui.toast.show({ message: `Started "${context.data.session.get(sessionID)?.title ?? sessionID}"` })
        return
      }
      if (focus) context.ui.tabs.focus(sessionID)
      else context.ui.tabs.open(sessionID)
      const tabs = context.ui.tabs.list()
      const after = tabs.findIndex((tab) => tab.sessionID === openerID)
      const index = tabs.findIndex((tab) => tab.sessionID === sessionID)
      if (after >= 0 && index >= 0) context.ui.tabs.move(sessionID, index > after ? after + 1 : after)
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

    // Read requests off the TUI's shared event stream rather than
    // context.client.rpc(Sessions).events: that subscription is live-only and
    // isn't re-established when the background service restarts, so a TUI
    // that outlived a restart would silently stop opening and closing tabs.
    // The shared stream reconnects on its own.
    const stopEvents = context.data.listen(({ details }) => {
      const event = details as { type: string; data?: unknown }
      if (event.type === OPEN_EVENT) {
        open(event.data as Open).catch((error) =>
          context.ui.toast.show({ message: `Couldn't open session tab: ${error}`, variant: "error" }),
        )
      }
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

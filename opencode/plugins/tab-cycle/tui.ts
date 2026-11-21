// tab-cycle/tui.ts — repeatable leader tab cycling, like tmux's `bind -r`.
//
// `<leader>ctrl+]` / `<leader>ctrl+[` switch to the next / previous session tab
// and open a short repeat window. Inside it, bare `ctrl+]` / `ctrl+[` keep
// cycling without pressing the leader again; each press restarts the window.
//
// These replace the `<leader>ctrl+[`/`]` alternatives of the built-in
// session.tab.next/previous in cli.json, so keep those out of there or both
// bindings would claim the key.

import { Plugin } from "@opencode/plugin/tui"
import { createSignal } from "solid-js"

// How long the bare keys keep cycling after the last tab switch.
const REPEAT_MS = 1000

export default Plugin.define({
  id: "tab-cycle",
  setup(context) {
    const [armed, setArmed] = createSignal(false)
    let timer: ReturnType<typeof setTimeout> | undefined

    const disarm = () => {
      clearTimeout(timer)
      timer = undefined
      setArmed(false)
    }

    const cycle = (direction: "next" | "previous") => {
      context.keymap.dispatch(`session.tab.${direction}`)
      clearTimeout(timer)
      timer = setTimeout(disarm, REPEAT_MS)
      setArmed(true)
    }

    context.keymap.layer(() => ({
      mode: "global",
      priority: 10,
      enabled: () => context.ui.tabs.enabled(),
      commands: [
        { id: "tab-cycle.next", title: "Next tab (repeatable)", group: "Session", bind: "<leader>ctrl+]", run: () => cycle("next") },
        { id: "tab-cycle.previous", title: "Previous tab (repeatable)", group: "Session", bind: "<leader>ctrl+[", run: () => cycle("previous") },
      ],
      bindings: ["tab-cycle.next", "tab-cycle.previous"],
    }))

    context.keymap.layer(() => ({
      mode: "global",
      priority: 10,
      enabled: armed,
      commands: [
        { id: "tab-cycle.repeat.next", title: "Next tab", group: "Session", bind: "ctrl+]", run: () => cycle("next") },
        { id: "tab-cycle.repeat.previous", title: "Previous tab", group: "Session", bind: "ctrl+[", run: () => cycle("previous") },
      ],
      bindings: ["tab-cycle.repeat.next", "tab-cycle.repeat.previous"],
    }))

    return disarm
  },
})

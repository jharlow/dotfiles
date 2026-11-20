// rpc.ts — the contract shared by the sessions server plugin (index.ts) and the
// TUI part (tui.tsx) that acts on it.
//
// Tabs are client-side state: the server can't close one, and a TUI plugin
// can't give the agent a tool. So the agent's session_close tool only announces
// the request with `close`, and every TUI showing that session closes its tab.

import { Rpc } from "@opencode/plugin/rpc"

export const Sessions = Rpc.define({
  id: "sessions",
  methods: {},
  events: {
    close: {
      schema: {
        type: "object",
        properties: { sessionID: { type: "string" } },
        required: ["sessionID"],
      },
    },
  },
})

// rpc.ts — the contract shared by the sessions server plugin (index.ts) and the
// TUI part (tui.tsx) that acts on it.
//
// Tabs are client-side state: the server can't close one, and a TUI plugin
// can't give the agent a tool. So the agent's session_close tool only announces
// the request with `close`, and every TUI showing that session closes its tab.
//
// The `close` method does the same over HTTP, for agents whose harness doesn't
// expose plugin tools:
//   opencode api post "/api/rpc/sessions/close?location[directory]=$PWD" \
//     -d '{"input":{"sessionID":"'"$OPENCODE_SESSION_ID"'"}}'
// HTTP calls carry no caller session, so unlike the tool it can't check that
// the target is the caller's own session.

import { Rpc } from "@opencode/plugin/rpc"

export const Sessions = Rpc.define({
  id: "sessions",
  methods: {
    close: {
      input: {
        type: "object",
        properties: { sessionID: { type: "string" } },
        required: ["sessionID"],
      },
      output: {
        type: "object",
        properties: { sessionID: { type: "string" } },
        required: ["sessionID"],
      },
    },
  },
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

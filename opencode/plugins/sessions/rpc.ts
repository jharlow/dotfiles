// rpc.ts — the contract shared by the sessions server plugin (index.ts) and the
// TUI part (tui.tsx) that acts on it.
//
// Tabs are client-side state: the server can't open or close one, and a TUI
// plugin can't give the agent a tool. So the agent's session_open and
// session_close tools do the server-side work and announce the tab change with
// the `open` and `close` events, which every TUI acts on.
//
// The `open` and `close` methods do the same over HTTP, for agents whose
// harness doesn't expose plugin tools:
//   opencode api post "/api/rpc/sessions/open?location[directory]=$PWD" \
//     -d '{"input":{"prompt":"Complete ticket ZONE-14","skills":["complete-ticket"],"openerID":"'"$OPENCODE_SESSION_ID"'"}}'
//   opencode api post "/api/rpc/sessions/close?location[directory]=$PWD" \
//     -d '{"input":{"sessionID":"'"$OPENCODE_SESSION_ID"'"}}'
// HTTP calls carry no caller session, so unlike the tools they can't check that
// a close targets the caller's own session, and an open only lands next to the
// opener's tab when openerID is passed.

import { Rpc } from "@opencode/plugin/rpc"

const sessionID = {
  type: "object",
  properties: { sessionID: { type: "string" } },
  required: ["sessionID"],
}

// The session_open tool's input, plus the opener that the tool reads from its
// call context.
export const OpenInput = {
  type: "object",
  properties: {
    prompt: { type: "string", description: "The first user message of the new session." },
    title: { type: "string", description: "Session title. Omit to let OpenCode generate one from the prompt." },
    directory: {
      type: "string",
      description: "Directory to run the session in, absolute or relative to the opener's directory. Supports ~. Defaults to the opener's directory.",
    },
    files: {
      type: "array",
      items: { type: "string" },
      description: "Files to attach: paths (absolute or relative to the session's directory) or http(s) URLs.",
    },
    skills: {
      type: "array",
      items: { type: "string" },
      description: "Skill IDs to load with the prompt, e.g. complete-ticket.",
    },
    agent: { type: "string", description: "Agent to run the session with. Defaults to the default agent." },
    model: {
      type: "string",
      description: "Model as providerID/modelID, optionally with #variant. Defaults to the configured model.",
    },
    focus: { type: "boolean", description: "Switch to the new tab. Defaults to false: it opens in the background." },
    openerID: { type: "string", description: "Session asking for the tab. Its TUIs open the new tab beside it." },
  },
  required: ["prompt"],
  additionalProperties: false,
}

export const Sessions = Rpc.define({
  id: "sessions",
  methods: {
    open: { input: OpenInput, output: sessionID },
    close: { input: sessionID, output: sessionID },
  },
  events: {
    open: {
      schema: {
        type: "object",
        properties: {
          sessionID: { type: "string" },
          openerID: { type: "string" },
          focus: { type: "boolean" },
        },
        required: ["sessionID", "focus"],
      },
    },
    close: { schema: sessionID },
  },
})

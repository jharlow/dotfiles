// rpc.ts — the contract shared by the links server plugin (index.ts) and its
// sidebar (tui.tsx).
//
// The server owns the list: it is the only writer, so the agent's tools and the
// TUI's /link and /unlink commands can't race each other. The TUI reads through
// `list` and stays live through the `updated` event, which always carries the
// full list rather than a delta so a missed event can't leave it stale.

import { Rpc } from "@opencode/plugin/rpc"

// Display order in the sidebar and in the agent's context block.
export const KINDS = ["ticket", "pr", "issue", "doc", "design", "deploy", "other"] as const
export type Kind = (typeof KINDS)[number]

export interface Link {
  url: string
  kind: Kind
  title: string
  note?: string
  // Epoch ms of the first add; re-adding a URL updates it in place.
  added: number
}

const link = {
  type: "object",
  properties: {
    url: { type: "string" },
    kind: { type: "string", enum: KINDS },
    title: { type: "string" },
    note: { type: "string" },
    added: { type: "number" },
  },
  required: ["url", "kind", "title", "added"],
} as const

const list = {
  type: "object",
  properties: { links: { type: "array", items: link } },
  required: ["links"],
} as const

// A rejected change, e.g. a non-http(s) URL or removing an untracked link.
const errors = {
  invalid: {
    type: "object",
    properties: { message: { type: "string" } },
    required: ["message"],
  },
} as const

export const Links = Rpc.define({
  id: "links",
  methods: {
    list: {
      input: {
        type: "object",
        properties: { sessionID: { type: "string" } },
        required: ["sessionID"],
      },
      output: list,
    },
    add: {
      input: {
        type: "object",
        properties: {
          sessionID: { type: "string" },
          url: { type: "string" },
          kind: { type: "string", enum: KINDS },
          title: { type: "string" },
          note: { type: "string" },
        },
        required: ["sessionID", "url", "kind", "title"],
      },
      output: list,
      errors,
    },
    remove: {
      input: {
        type: "object",
        properties: { sessionID: { type: "string" }, url: { type: "string" } },
        required: ["sessionID", "url"],
      },
      output: list,
      errors,
    },
  },
  events: {
    updated: {
      schema: {
        type: "object",
        properties: { sessionID: { type: "string" }, links: { type: "array", items: link } },
        required: ["sessionID", "links"],
      },
    },
  },
})

// Best-effort default for the TUI's /link kind picker. The agent always passes
// kind explicitly; this only pre-selects an option for a human.
export function guessKind(url: string): Kind {
  if (/github\.com\/[^/]+\/[^/]+\/pull\/\d+/.test(url)) return "pr"
  if (/github\.com\/[^/]+\/[^/]+\/issues\/\d+/.test(url)) return "issue"
  if (/linear\.app\/[^/]+\/issue\//.test(url)) return "ticket"
  if (/figma\.com\//.test(url)) return "design"
  return "other"
}

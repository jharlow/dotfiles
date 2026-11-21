// index.ts — track the tickets, PRs and other key artifacts a session is about.
//
// The agent registers links explicitly with the links_add / links_remove tools
// (nothing is scraped from the transcript), and the user can do the same from
// the TUI with /link and /unlink. Each change does three things:
//   * persists the list in plugin storage, keyed by root session
//   * mirrors it into the session's instructions as <context key="links">, so
//     the model keeps seeing it after compaction
//   * emits rpc.links.updated so the sidebar (tui.tsx) redraws
//
// Lists live on the root session: a subagent that opens a PR files it under the
// conversation the user is looking at, not its own throwaway child session.

import { Plugin } from "@opencode/plugin"
import { KINDS, Links, type Kind, type Link } from "./rpc"

const ENTRY = "links"

const isKind = (value: unknown): value is Kind => KINDS.includes(value as Kind)

// Reject anything that isn't an absolute http(s) URL, so a bare "ENG-123" or a
// local path never becomes a dead sidebar link. Returns the normalised form so
// trailing-slash variants of one URL don't become two entries.
function normalise(raw: string): string {
  if (!URL.canParse(raw.trim())) throw new Error(`links: "${raw}" is not an absolute URL`)
  const url = new URL(raw.trim())
  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new Error(`links: only http(s) URLs can be tracked, got ${url.protocol}`)
  }
  url.hash = ""
  return url.toString().replace(/\/$/, "")
}

function sorted(links: Link[]): Link[] {
  return links.toSorted((a, b) => KINDS.indexOf(a.kind) - KINDS.indexOf(b.kind) || a.added - b.added)
}

// The text the model sees. Kept short: it is re-sent with every request.
function render(links: Link[]): string {
  const lines = sorted(links).map((link) => {
    const note = link.note ? ` (${link.note})` : ""
    return `- [${link.kind}] ${link.title}: ${link.url}${note}`
  })
  return [
    "Links tracked for this session. Shown to the user in the sidebar. Keep it current with links_add and links_remove.",
    ...lines,
  ].join("\n")
}

export default Plugin.define({
  id: "links",
  async setup(ctx) {
    const key = (sessionID: string) => `session/${sessionID}`

    const root = async (sessionID: string) => {
      let id = sessionID
      // Bounded so a malformed parent chain can't spin forever.
      for (let depth = 0; depth < 32; depth++) {
        const session = await ctx.session.get({ sessionID: id })
        if (!session.parentID) return id
        id = session.parentID
      }
      return id
    }

    const read = async (sessionID: string): Promise<Link[]> => {
      const value = await ctx.storage.get(key(sessionID))
      return Array.isArray(value) ? (value as unknown as Link[]) : []
    }

    // Parallel tool calls (or a tool call racing /link) would otherwise
    // read-modify-write the same list and drop an entry, so changes to one
    // session run one at a time.
    const queues = new Map<string, Promise<unknown>>()
    const serial = <T>(sessionID: string, work: () => Promise<T>): Promise<T> => {
      const run = (queues.get(sessionID) ?? Promise.resolve()).then(work, work)
      queues.set(
        sessionID,
        run.catch(() => {}),
      )
      return run
    }

    let emit: (sessionID: string, links: Link[]) => Promise<void> = async () => {}

    const write = async (sessionID: string, links: Link[]) => {
      if (links.length > 0) {
        await ctx.storage.set(key(sessionID), links as never)
        await ctx.session.instructions.entry.put({ sessionID, key: ENTRY, value: render(links) })
      } else {
        await ctx.storage.remove(key(sessionID))
        await ctx.session.instructions.entry.remove({ sessionID, key: ENTRY }).catch(() => {})
      }
      await emit(sessionID, links)
    }

    const add = (sessionID: string, input: { url: string; kind: Kind; title: string; note?: string }) =>
      serial(sessionID, async () => {
        const url = normalise(input.url)
        const title = input.title.trim() || url
        const note = input.note?.trim()
        const links = await read(sessionID)
        const existing = links.find((link) => link.url === url)
        // Build without an undefined `note` key: it would fail the RPC's
        // output schema, and storage should only hold JSON anyway.
        const entry: Link = { url, kind: input.kind, title, added: existing?.added ?? Date.now(), ...(note ? { note } : {}) }
        const next = existing ? links.map((link) => (link === existing ? entry : link)) : [...links, entry]
        await write(sessionID, next)
        return sorted(next)
      })

    const remove = (sessionID: string, raw: string) =>
      serial(sessionID, async () => {
        const url = normalise(raw)
        const links = await read(sessionID)
        const next = links.filter((link) => link.url !== url)
        if (next.length === links.length) throw new Error(`links: ${url} is not tracked in this session`)
        await write(sessionID, next)
        return sorted(next)
      })

    const summary = (links: Link[]) =>
      links.length === 0 ? "No links tracked." : `Tracking ${links.length} link(s):\n${render(links)}`

    await ctx.tool.transform((editor) => {
      editor.add({
        name: "links_add",
        description: [
          "Track a ticket, PR or other key artifact for this session. It appears in the user's sidebar and stays in",
          "your context as <context key=\"links\">, including after compaction.",
          "Call it when an artifact becomes central to the work: a ticket you are working on, a PR you open or review,",
          "an issue you are fixing, a design or spec you are implementing, a deploy you are verifying.",
          "Don't track pages you only consulted, such as search results, docs or dependencies.",
          "Re-adding a tracked URL updates its kind, title and note in place, for example after a PR is retitled.",
        ].join(" "),
        input: {
          type: "object",
          properties: {
            url: { type: "string", description: "Absolute http(s) URL of the artifact." },
            kind: { type: "string", enum: KINDS, description: "What the artifact is." },
            title: {
              type: "string",
              description: "Very short label. The kind is shown alongside it, so don't repeat it: when the artifact has an identifier, use just that, e.g. 'ENG-123' for a ticket or '#1234' for a PR or issue. Otherwise use a short description, e.g. 'Reference video' for other. Put status or role in note.",
            },
            note: { type: "string", description: "Optional one-line status or role, e.g. 'draft' or 'blocks ENG-120'." },
          },
          required: ["url", "kind", "title"],
          additionalProperties: false,
        },
        options: { codemode: false },
        execute: async (input, context) => {
          const { url, kind, title, note } = input as Record<string, unknown>
          if (typeof url !== "string" || typeof title !== "string" || !isKind(kind)) {
            throw new Error("links_add: url, title and a valid kind are required")
          }
          const links = await add(await root(context.sessionID), {
            url,
            kind,
            title,
            note: typeof note === "string" ? note : undefined,
          })
          return { content: summary(links) }
        },
      })

      editor.add({
        name: "links_remove",
        description:
          "Stop tracking a link in this session, e.g. a ticket that turned out to be unrelated or a PR that was closed in favour of another.",
        input: {
          type: "object",
          properties: { url: { type: "string", description: "The tracked URL, as listed in <context key=\"links\">." } },
          required: ["url"],
          additionalProperties: false,
        },
        options: { codemode: false },
        execute: async (input, context) => {
          const { url } = input as Record<string, unknown>
          if (typeof url !== "string") throw new Error("links_remove: url is required")
          return { content: summary(await remove(await root(context.sessionID), url)) }
        },
      })
    })

    // Surface our own validation messages (bad URL, unknown link) to the TUI
    // instead of a generic "RPC call failed".
    const invalid = (error: unknown) => ({ message: error instanceof Error ? error.message : String(error) })

    const registration = await ctx.rpc.register(Links, {
      list: async (input) => {
        const { sessionID } = input as { sessionID: string }
        return { links: sorted(await read(await root(sessionID))) }
      },
      add: async (input, context) => {
        const { sessionID, ...link } = input as { sessionID: string; url: string; kind: Kind; title: string; note?: string }
        try {
          return { links: await add(await root(sessionID), link) }
        } catch (error) {
          return context.error("invalid", invalid(error).message, invalid(error))
        }
      },
      remove: async (input, context) => {
        const { sessionID, url } = input as { sessionID: string; url: string }
        try {
          return { links: await remove(await root(sessionID), url) }
        } catch (error) {
          return context.error("invalid", invalid(error).message, invalid(error))
        }
      },
    })

    emit = (sessionID, links) =>
      registration.events.emit("updated", { sessionID, links: sorted(links) } as never).catch(() => {})

    // Drop a deleted session's list so storage doesn't grow with every session
    // ever opened. The instruction entry goes with the session itself.
    const controller = new AbortController()
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ types: ["session.deleted"], signal: controller.signal })) {
          await ctx.storage.remove(key(event.data.sessionID)).catch(() => {})
        }
      } catch {
        // Aborting the subscription during unload is expected.
      }
    })()

    return async () => {
      controller.abort()
      await registration.dispose()
    }
  },
})

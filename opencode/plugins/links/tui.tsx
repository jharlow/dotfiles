// tui.tsx — show the session's tracked links in the sidebar, and add or remove
// them by hand with /link and /unlink.
//
// The server plugin (index.ts) owns the list; this side only reads it over RPC
// and listens for rpc.links.updated. Links render as OSC 8 hyperlinks, so they
// open with cmd-click like links in the transcript. Under tmux that needs
// `terminal-features ...:hyperlinks` (see ~/.tmux.conf).

import { Plugin } from "@opencode/plugin/tui"
import { createEffect, createMemo, For, Show } from "solid-js"
import { guessKind, KINDS, Links, type Kind, type Link } from "./rpc"

// The updated event of the Links RPC (rpc.ts), as the event stream names it:
// prefixed with the RPC's id.
const UPDATED_EVENT = "rpc.links.updated"

const LABELS: Record<Kind, string> = {
  ticket: "ticket",
  pr: "PR",
  issue: "issue",
  doc: "doc",
  design: "design",
  deploy: "deploy",
  other: "link",
}

function SidebarLinks(props: { context: Plugin.Context; sessionID: string; load: (sessionID: string) => void; links: Record<string, Link[]> }) {
  const [view, updateView] = props.context.storage.store("view", { initial: { open: true } })
  const theme = props.context.theme
  const rootID = createMemo(() => props.context.data.session.root(props.sessionID))
  const list = createMemo(() => props.links[rootID()] ?? [])

  createEffect(() => props.load(rootID()))

  return (
    <Show when={list().length > 0}>
      <box>
        <box
          flexDirection="row"
          gap={1}
          onMouseDown={() => {
            if (list().length <= 2) return
            void updateView((draft) => {
              draft.open = !draft.open
            }).catch((error) => console.error("Failed to persist links sidebar state", error))
          }}
        >
          <Show when={list().length > 2}>
            <text fg={theme.text.base}>{view.open ? "▼" : "▶"}</text>
          </Show>
          <text fg={theme.text.base}>
            <b>Links</b>
            <Show when={!view.open}>
              <span style={{ fg: theme.text.muted }}> ({list().length})</span>
            </Show>
          </text>
        </box>
        <Show when={list().length <= 2 || view.open}>
          <For each={list()}>
            {(item) => (
              <box flexDirection="row" gap={1} minWidth={0}>
                <text flexShrink={0} fg={theme.text.muted}>
                  •
                </text>
                <text fg={theme.text.base} wrapMode="none" truncate flexGrow={1} flexShrink={1} minWidth={0}>
                  <a href={item.url}>{item.title}</a>
                </text>
                <text fg={theme.text.muted} wrapMode="none" flexShrink={0}>
                  {LABELS[item.kind]}
                </text>
              </box>
            )}
          </For>
        </Show>
      </box>
    </Show>
  )
}

export default Plugin.define({
  id: "links.tui",
  setup(context) {
    // Lists by root session. Memory storage survives plugin hot reloads; the
    // server is the source of truth, so nothing needs to outlive the TUI.
    const [state, update] = context.storage.memory("links", {
      initial: { bySession: {} as Record<string, Link[]> },
    })
    const set = (sessionID: string, links: Link[]) =>
      update((draft) => {
        draft.bySession[sessionID] = links
      })

    // The plugin instance that owns a session's list runs at that session's
    // location, so every call is routed there.
    const call = (sessionID: string) => {
      const directory = context.data.session.get(sessionID)?.location.directory
      return { rpc: context.client.rpc(Links), options: directory ? { location: { directory } } : undefined }
    }

    const loaded = new Set<string>()
    const load = (sessionID: string) => {
      if (loaded.has(sessionID)) return
      loaded.add(sessionID)
      const { rpc, options } = call(sessionID)
      rpc
        .list({ sessionID }, options)
        .then((result) => set(sessionID, (result as { links: Link[] }).links))
        .catch((error) => {
          // Let the next render retry, e.g. once the server plugin has loaded.
          loaded.delete(sessionID)
          console.error("links: failed to load", error)
        })
    }

    // Read updates off the TUI's shared event stream rather than
    // context.client.rpc(Links).events: that subscription is live-only and
    // isn't re-established when the background service restarts, so the
    // sidebar would stop updating. The shared stream reconnects on its own.
    const stop = context.data.listen(({ details }) => {
      const event = details as { type: string; data?: unknown }
      if (event.type !== UPDATED_EVENT) return
      const { sessionID, links } = event.data as { sessionID: string; links: Link[] }
      loaded.add(sessionID)
      set(sessionID, links)
    })

    const current = () => {
      const route = context.ui.router.current()
      return route.type === "session" ? context.data.session.root(route.sessionID) : undefined
    }

    const fail = (error: unknown) =>
      context.ui.toast.show({
        title: "Links",
        message: error instanceof Error ? error.message : String(error),
        variant: "error",
      })

    const link = async (input?: string) => {
      const sessionID = current()
      if (!sessionID) return context.ui.toast.show({ title: "Links", message: "Open a session first", variant: "warning" })

      const [first, ...rest] = (input ?? "").trim().split(/\s+/).filter(Boolean)
      const url = first ?? (await context.ui.dialog.prompt({ title: "Link URL", placeholder: "https://…" }))?.trim()
      if (!url) return
      const title =
        rest.join(" ") || (await context.ui.dialog.prompt({ title: "Link title", placeholder: "ENG-123" }))?.trim()
      if (title === undefined) return
      const kind = await context.ui.dialog.select<Kind>({
        title: "Link kind",
        current: guessKind(url),
        options: KINDS.map((value) => ({ title: LABELS[value], value })),
      })
      if (!kind) return

      const { rpc, options } = call(sessionID)
      await rpc.add({ sessionID, url, kind, title: title || url }, options).catch(fail)
    }

    const unlink = async () => {
      const sessionID = current()
      if (!sessionID) return context.ui.toast.show({ title: "Links", message: "Open a session first", variant: "warning" })
      const links = state.bySession[sessionID] ?? []
      if (links.length === 0) return context.ui.toast.show({ title: "Links", message: "No links tracked in this session" })

      const url = await context.ui.dialog.select<string>({
        title: "Remove link",
        options: links.map((item) => ({ title: item.title, value: item.url, description: item.url, category: LABELS[item.kind] })),
      })
      if (!url) return
      const { rpc, options } = call(sessionID)
      await rpc.remove({ sessionID, url }, options).catch(fail)
    }

    context.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "links.add",
          title: "Track a link in this session",
          group: "Links",
          palette: true,
          slash: { name: "link", arguments: true },
          run: (input) => link(input).catch(fail),
        },
        {
          id: "links.remove",
          title: "Stop tracking a link in this session",
          group: "Links",
          palette: true,
          slash: { name: "unlink" },
          run: () => unlink().catch(fail),
        },
      ],
    }))

    context.ui.slot({
      append: "sidebar.content",
      render: (props) => <SidebarLinks context={context} sessionID={props.sessionID} load={load} links={state.bySession} />,
    })

    return () => stop()
  },
})

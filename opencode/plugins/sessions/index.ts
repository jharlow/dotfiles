// index.ts — let the agent open new session tabs with session_open and close
// its own with session_close.
//
// session_open starts an independent top-level session (not a subagent) with a
// prompt, optional file attachments and skills, then asks the TUI (tui.tsx) to
// open a tab for it. The session runs on the server whether or not a TUI shows
// it.
//
// Closing a tab doesn't delete or stop anything: the session stays in the
// session list and can be reopened. The TUI waits for the session to go idle
// before closing, so the agent can call this mid-turn and still finish its
// reply.
//
// An agent may close its own session or one it spawned (a descendant), never a
// parent or an unrelated session the user has open.

import { existsSync, statSync } from "node:fs"
import { homedir } from "node:os"
import { isAbsolute, resolve } from "node:path"
import { pathToFileURL } from "node:url"
import { Plugin } from "@opencode/plugin"
import { OpenInput, Sessions } from "./rpc"

type Open = {
  prompt: string
  title?: string
  directory?: string
  files?: string[]
  skills?: string[]
  agent?: string
  model?: string
  focus?: boolean
  openerID?: string
}

// Resolve `path` against `base`, expanding a leading ~.
const expand = (path: string, base: string) => {
  if (path === "~" || path.startsWith("~/")) return resolve(homedir(), path.slice(2))
  return isAbsolute(path) ? path : resolve(base, path)
}

const strings = (value: unknown, field: string) => {
  if (value === undefined) return undefined
  if (!Array.isArray(value) || value.some((item) => typeof item !== "string")) {
    throw new Error(`session_open: ${field} must be an array of strings`)
  }
  return value as string[]
}

const parse = (input: unknown): Open => {
  const raw = input as Record<string, unknown>
  if (typeof raw.prompt !== "string" || raw.prompt.trim() === "") throw new Error("session_open: prompt is required")
  for (const field of ["title", "directory", "agent", "model", "openerID"]) {
    if (raw[field] !== undefined && typeof raw[field] !== "string") throw new Error(`session_open: ${field} must be a string`)
  }
  if (raw.focus !== undefined && typeof raw.focus !== "boolean") throw new Error("session_open: focus must be a boolean")
  return { ...(raw as Open), files: strings(raw.files, "files"), skills: strings(raw.skills, "skills") }
}

// "provider/model#variant" → a Model.Ref.
const model = (value: string) => {
  const [ref, variant] = value.split("#", 2)
  const slash = ref.indexOf("/")
  if (slash <= 0 || slash === ref.length - 1) throw new Error(`session_open: model must be providerID/modelID, got ${value}`)
  return { providerID: ref.slice(0, slash), id: ref.slice(slash + 1), ...(variant ? { variant } : {}) }
}

// A path or URL → a prompt file attachment.
const attachment = (file: string, directory: string) => {
  if (/^https?:\/\//.test(file)) return { uri: file }
  const path = file.startsWith("file://") ? new URL(file).pathname : expand(file, directory)
  if (!existsSync(path)) throw new Error(`session_open: no file at ${path}`)
  return { uri: pathToFileURL(path).href }
}

export default Plugin.define({
  id: "sessions",
  async setup(ctx) {
    // True when `sessionID` is `ancestorID` or sits below it.
    const within = async (sessionID: string, ancestorID: string) => {
      let id: string | undefined = sessionID
      // Bounded so a malformed parent chain can't spin forever.
      for (let depth = 0; id && depth < 32; depth++) {
        if (id === ancestorID) return true
        id = (await ctx.session.get({ sessionID: id })).parentID
      }
      return false
    }

    let close: (sessionID: string) => Promise<void> = async () => {}
    let announce: (event: { sessionID: string; openerID?: string; focus: boolean }) => Promise<void> = async () => {}

    const open = async (input: Open) => {
      const opener = input.openerID ? await ctx.session.get({ sessionID: input.openerID }) : undefined
      const base = opener?.location.directory ?? ctx.location.directory
      const directory = input.directory ? expand(input.directory, base) : base
      if (!existsSync(directory) || !statSync(directory).isDirectory()) {
        throw new Error(`session_open: ${directory} is not a directory`)
      }
      // Resolve everything that can fail before creating the session, so a bad
      // input doesn't leave an empty session behind.
      const files = (input.files ?? []).map((file) => attachment(file, directory))
      const ref = input.model ? model(input.model) : undefined

      const session = await ctx.session.create({
        location: { directory },
        ...(input.title ? { title: input.title } : {}),
        ...(input.agent ? { agent: input.agent } : {}),
        ...(ref ? { model: ref } : {}),
        ...(opener ? { metadata: { openedBy: opener.id } } : {}),
      } as never)
      try {
        await ctx.session.prompt({
          sessionID: session.id,
          text: input.prompt,
          ...(files.length > 0 ? { files } : {}),
          ...(input.skills?.length ? { skills: input.skills.map((id) => ({ id })) } : {}),
        } as never)
      } catch (error) {
        // An unknown skill or unreadable file fails admission: don't leave an
        // empty session behind.
        await ctx.session.remove({ sessionID: session.id }).catch(() => {})
        throw error
      }
      await announce({ sessionID: session.id, openerID: opener?.id, focus: input.focus ?? false })
      return { sessionID: session.id, directory }
    }

    const registration = await ctx.rpc.register(Sessions, {
      open: async (input) => ({ sessionID: (await open(parse(input))).sessionID }),
      close: async (input) => {
        const { sessionID } = input as { sessionID: string }
        await close(sessionID)
        return { sessionID }
      },
    })

    close = (sessionID) => registration.events.emit("close", { sessionID } as never)
    announce = (event) => registration.events.emit("open", event as never)

    const { openerID: _, ...openProperties } = OpenInput.properties

    await ctx.tool.transform((editor) => {
      editor.add({
        name: "session_open",
        description: [
          "Start a new, independent session with a prompt and open it in a new tab in the user's terminal UI. Use it",
          "when the user asks to start, open or kick off work in a new session or tab, e.g. 'start a new session to",
          "complete ZONE-14'. Write the prompt as the user would, and pass skills it should load and files it should",
          "see. Unlike a subagent, the new session doesn't report back to you. It opens in the background unless",
          "focus is true. Returns the new session's ID.",
        ].join(" "),
        input: { ...OpenInput, properties: openProperties },
        options: { codemode: false },
        execute: async (input, context) => {
          const opened = await open({ ...parse(input), openerID: context.sessionID })
          return { content: `Opened session ${opened.sessionID} in ${opened.directory}.` }
        },
      })
      editor.add({
        name: "session_close",
        description: [
          "Close a session's tab in the user's terminal UI once the session is idle. Nothing is deleted: the session",
          "stays in the session list and can be reopened. Omit sessionID to close the current session; otherwise pass",
          "a session you spawned. Only call it when the user asks you to close the session or a workflow you are",
          "following says to, and make it the last thing you do, after your final message.",
        ].join(" "),
        input: {
          type: "object",
          properties: {
            sessionID: {
              type: "string",
              description: "Session to close. Omit for the current session. Must be the current session or one it spawned.",
            },
          },
          additionalProperties: false,
        },
        options: { codemode: false },
        execute: async (input, context) => {
          const { sessionID: requested } = input as Record<string, unknown>
          if (requested !== undefined && typeof requested !== "string") throw new Error("session_close: sessionID must be a string")
          const sessionID = requested ?? context.sessionID
          if (!(await within(sessionID, context.sessionID))) {
            throw new Error(`session_close: ${sessionID} is not this session or one it spawned`)
          }
          await close(sessionID)
          return { content: `Session ${sessionID} will close in the TUI once it is idle.` }
        },
      })
    })

    return () => registration.dispose()
  },
})

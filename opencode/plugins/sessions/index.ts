// index.ts — let the agent close its own session tabs with session_close.
//
// Closing a tab doesn't delete or stop anything: the session stays in the
// session list and can be reopened. The TUI (tui.tsx) waits for the session to
// go idle before closing, so the agent can call this mid-turn and still finish
// its reply.
//
// An agent may close its own session or one it spawned (a descendant), never a
// parent or an unrelated session the user has open.

import { Plugin } from "@opencode/plugin"
import { Sessions } from "./rpc"

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

    const registration = await ctx.rpc.register(Sessions, {
      close: async (input) => {
        const { sessionID } = input as { sessionID: string }
        await close(sessionID)
        return { sessionID }
      },
    })

    close = (sessionID) => registration.events.emit("close", { sessionID } as never)

    await ctx.tool.transform((editor) => {
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

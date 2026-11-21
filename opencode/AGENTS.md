## Browser use

In general, use `agent-browser` by default for all coding tasks. Use the `browser` MCP tools as a fallback.

For non-coding tasks, inverse the order. Use the `browser` MCP tools by default, and use `agent-browser` as a fallback.

## Session links

Keep the session's key artifacts tracked with `links_add` and `links_remove`. They appear in my sidebar and stay in your context as `<context key="links">`, even after compaction.

- Track a link as soon as it becomes central to the work: the ticket you're working on, a PR you open or review, an issue you're fixing, a design or spec you're implementing, a deploy you're verifying. This includes links I paste and ones you create, such as a new PR.
- Don't track pages you only consulted, like search results, docs or dependencies' repos.
- Keep titles very short, and don't repeat the kind since it's shown alongside. When the artifact matches a kind and has an identifier, like a ticket number or a PR or issue number, the title is just the bare identifier with no prefix, e.g. `ENG-123` (not `Ticket ENG-123`) with kind `ticket`, or `#1234` (not `PR #1234`) with kind `pr`. Otherwise use a short description, e.g. `Reference video` with kind `other`. Put any status or role in the note instead.
- Re-add a link to update it when its title or status changes, and remove it when it no longer applies.

## Opening sessions

When I ask you to start work in a new session or tab (e.g. "start a new session to complete ZONE-14"), use `session_open`. Write the prompt as I would, and pass the skills it should load (e.g. `complete-ticket`) and any files it should see. Use `directory` to start it somewhere other than the current directory, such as a worktree. It opens in the background unless I ask to switch to it. If you don't have that tool, run this instead:

```sh
opencode api post "/api/rpc/sessions/open?location[directory]=$PWD" -d '{"input":{"prompt":"Complete ticket ZONE-14","skills":["complete-ticket"],"openerID":"'"$OPENCODE_SESSION_ID"'"}}'
```

## Closing sessions

When I ask you to close the session, close its tab with `session_close` (or a session you spawned, by passing its `sessionID`). If you don't have that tool, run this instead:

```sh
opencode api post "/api/rpc/sessions/close?location[directory]=$PWD" -d '{"input":{"sessionID":"'"$OPENCODE_SESSION_ID"'"}}'
```

Either way the tab closes once the session is idle, so your final reply still lands, and nothing is deleted. Only close a session when I ask or a workflow you're following says to, never one you didn't start, and make it the last thing you do.

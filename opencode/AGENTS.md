## Browser use

In general, use `agent-browser` by default for all coding tasks. Use the `browser` MCP tools as a fallback.

For non-coding tasks, inverse the order. Use the `browser` MCP tools by default, and use `agent-browser` as a fallback.

## Closing sessions

When I ask you to close the session, close its tab with `session_close` (or a session you spawned, by passing its `sessionID`). If you don't have that tool, run this instead:

```sh
opencode api post "/api/rpc/sessions/close?location[directory]=$PWD" -d '{"input":{"sessionID":"'"$OPENCODE_SESSION_ID"'"}}'
```

Either way the tab closes once the session is idle, so your final reply still lands, and nothing is deleted. Only close a session when I ask or a workflow you're following says to, never one you didn't start, and make it the last thing you do.

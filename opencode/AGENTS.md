## Browser use

In general, use `agent-browser` by default for all coding tasks. Use the `browser` MCP tools as a fallback.

For non-coding tasks, inverse the order. Use the `browser` MCP tools by default, and use `agent-browser` as a fallback.

## Closing sessions

You can close your own session's tab with `session_close` (or a session you spawned, by passing its `sessionID`). It waits until the session is idle, so the final reply still lands, and nothing is deleted. Only use it when I ask you to close the session or a workflow you're following says to, and make it the last thing you do.

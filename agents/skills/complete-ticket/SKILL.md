---
name: complete-ticket
description: >
  Take a Linear ticket from reference to merged PR. Reads the ticket,
  creates a git worktree and branch named after the ticket, plans the
  work in the plan agent, then either resolves ambiguities with the user
  or, when the remaining ones are minor, proceeds and reports its
  assumptions at the end (very large tickets are split into sub-tickets
  that each go through the same flow), does
  the work, keeps the ticket's status, assignee, labels and a work-log comment thread
  updated throughout, opens a PR with iOS and web screenshots and demos and a detailed description,
  self-reviews the PR, responds to its own review comments, runs the
  full test suite, starts a preview of the work on web and the iOS
  simulator, then asks the user for approval to merge and cleans up the
  worktree. Use when the user says "complete ticket ENG-123",
  "work on LIN-45", "pick up this ticket", or passes a Linear issue
  identifier or URL and wants it implemented end to end.
metadata:
  argument-hint: <linear-ticket-id-or-url>
---

# Complete Ticket

Drive one Linear ticket from reference to merged PR. Work through the
phases in order and don't skip any. You stop for the user at most at
two points: plan approval in phase 3, which you skip when the plan has
only minor ambiguities (see "Decide whether the plan needs approval"),
and merge approval in phase 9, which you never skip. If the user asks
for changes at phase 9, loop back to phase 3. If phase 3
finds that the ticket is very large, it can be split into sub-tickets
that each run through this flow. See "Decide whether to break the
ticket down".

If the user gave no ticket reference, ask for one before doing anything.

## Set the session title

Before anything else, title the session after the ticket, so the user
can tell sessions apart at a glance. Use the ticket identifier and,
once you've fetched the ticket with `get_issue`, a plain three- or
four-word summary of its subject, such as `ENG-123 Fix login redirect`.
If you don't have the subject yet, set the identifier alone, then add
the summary after `get_issue`. Use the harness's own way of renaming
the session, and skip this if it has none.

## Keeping the ticket updated

Keep the Linear ticket current as you go, so anyone looking at it can
see where the work stands without asking. Each phase below ends with a
**Linear** note saying what to update. Use these tools:

- **Status**: `save_issue` with `id` and `state`. Statuses differ by
  team, so in phase 1 call `list_issue_statuses` for the ticket's team
  and map these roles to the team's actual statuses:
  - **in progress**: a `started` status, usually "In Progress"
  - **in review**: a `started` status named like "In Review", if the
    team has one. If it doesn't, leave the ticket in progress.
  - **done**: the team's main `completed` status, usually "Done"

  Before changing the status, check the current one with `get_issue`.
  Linear's GitHub integration may already have moved it, for example
  when the PR opens or merges. Don't set it again, and never move a
  ticket out of a `completed` or `canceled` status.
- **Comments**: post one root comment titled **Agent work log** with
  `save_comment` (`issueId`, `body`) when work starts. Post every later
  update as a reply in that thread (`parentId` set to the root comment's
  ID), so the updates don't bury the rest of the discussion. Record the
  root comment ID next to your other noted values.
- **Assignee**: `save_issue` with `id` and `assignee`. `"me"` is the
  authenticated user.
- **Labels**: `save_issue` with `id` and `addLabels` or `removeLabels`.
  Never pass `labels`, which replaces the ticket's whole label set.
  Labels differ by team, so in phase 1 call `list_issue_labels` for the
  ticket's team and use only labels that already exist.

Write comments for the people following the ticket: short, plain and
specific, with links to the PR and commits where relevant. Put long
detail, such as the full plan or test output, in a collapsible section
at the end of the comment:

```markdown
+++ Full implementation plan

...

+++
```

Only change the assignee and labels as phase 4 describes. Don't change
the priority or description unless the user asks.

## Tracking links

If the harness has a `links_add` tool (OpenCode does), use it to keep
the work's key links in the user's sidebar. The kind is shown alongside
the title, so the title is just the bare identifier with no prefix or
ticket/PR title (`ENG-123`, not `ENG-123: <ticket title>`; `#1234`, not
`<repo>#1234: <PR title>`). Put any status in `note`.

- **Phase 1**: add the ticket (`kind: "ticket"`, title `ENG-123`),
  plus any parent ticket or linked design the work depends on.
- **Phase 3**: if you create sub-tickets, add each one.
- **Phase 6**: add the PR as soon as it opens (`kind: "pr"`, title
  `#<number>`).
- **Phase 9**: once it's merged, re-add the PR with `note: "merged"`.

Skip this if the harness has no such tool.

## 1. Read the ticket

Use the Linear MCP tools. They accept identifiers like `ENG-123`
directly. If the user pasted a URL, pull the identifier out of it.

1. `get_issue`: title, description, labels, project, priority, and
   linked issues or parent issue.
2. `list_comments`: the description is never the whole story. Read the
   discussion, including inline comments.
3. `extract_images`: view any screenshots or mockups embedded in the
   description or comments. Use `get_attachment` for attachments.
4. If the ticket has a parent or related issues, skim them for context.

From this, write a short working brief for yourself: what has to change,
the acceptance criteria (stated or implied), and whether the work
touches UI. Don't ask questions yet. Collect them for the plan in
phase 3, once you've read the code.

Call `list_issue_statuses` for the ticket's team and map the status
roles described in "Keeping the ticket updated". Call
`list_issue_labels` for the team too, and note the labels you'll use in
phase 4.

**Linear**: set the status to *in progress*. Post the **Agent work
log** root comment saying you've started, with a one-line summary of
your understanding of the ticket.

## 2. Create the worktree and branch

Run this from the repository the user is in. **Record the absolute path
of this original checkout.** You return to it in phase 10.

```bash
ORIGINAL_REPO=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$ORIGINAL_REPO")
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
TICKET=eng-123                       # lowercased ticket identifier
BRANCH="$TICKET-short-kebab-summary" # e.g. eng-123-fix-login-redirect
WORKTREE="$(dirname "$ORIGINAL_REPO")/$REPO_NAME.worktrees/$TICKET"

git -C "$ORIGINAL_REPO" fetch origin "$DEFAULT_BRANCH"
git -C "$ORIGINAL_REPO" worktree add -b "$BRANCH" "$WORKTREE" "origin/$DEFAULT_BRANCH"
cd "$WORKTREE"
```

- The branch name must start with the ticket identifier. Linear uses it
  to link the PR to the ticket automatically. Keep the summary to a few
  words.
- If the branch or worktree already exists, the ticket may already be in
  progress. Inspect it and ask the user whether to resume or start
  fresh. Never delete it without asking.
- Put the worktree outside the repo, as above, so it never shows up as
  untracked files in the original checkout.
- A new worktree has no installed dependencies and no gitignored files.
  Install dependencies with the project's package manager (check the
  lockfile). If the app needs local env files such as `.env.local`, copy
  them over from `$ORIGINAL_REPO`. Never commit them.
- Find the repo's preview command: the command that runs the app from
  one worktree so someone can try it. Look in `AGENTS.md`, `CLAUDE.md`
  and the README, then in `package.json` scripts or a `Makefile` for
  names like `preview`. For example, a repo might document a
  `pnpm preview` that starts this worktree's web app, API and database
  on their own ports and opens the iOS simulator pointed at them. Note
  what it prints (URLs, ports, sign-in details), how to deep-link to a
  screen, and how to clean up after it, such as dropping a per-worktree
  database.
- If the repo has no preview command, you'll fall back to its dev server
  on free ports, web only. Tell the user now that the review in phase 9
  will be web only, with no simulator.

All work from here happens inside `$WORKTREE`. Shell variables often
don't survive between tool calls, so note the literal values of
`ORIGINAL_REPO`, `DEFAULT_BRANCH`, `BRANCH` and `WORKTREE`, and the
preview command and its cleanup command, and use those in later
commands.

## 3. Plan

Don't write any code until this phase is finished: the full plan is
written, and either the user has approved it or you've decided it
doesn't need their approval.

### Switch to the plan agent

Switch to the harness's read-only planning mode before you start:

- **OpenCode**: switch this session to the `plan` agent. The change
  applies from your next turn.

  ```bash
  opencode api post "/api/session/$OPENCODE_SESSION_ID/agent" --data '{"agent":"plan"}'
  ```

- **Claude Code**: call `EnterPlanMode`.
- **Any other harness**: if it has no plan mode, stay read-only until
  this phase is finished. Don't edit files or run commands that change
  anything.

### Investigate

Read the code thoroughly, not just enough to start:

- Read the repo's agent instructions (`AGENTS.md`, `CLAUDE.md`,
  `CONTRIBUTING.md`) and note any conventions that apply.
- Read every file you expect to edit, in full. Also read its callers,
  the code it calls, its types, and its existing tests.
- Find the existing patterns for this kind of change, such as similar
  components, endpoints or migrations, and plan to follow them.
- Load any skills relevant to the stack, such as framework or design
  skills.
- Check the acceptance criteria against what the code actually does.

Then ask yourself: **do the ticket and the user's instructions tell me
everything I need to implement this?** Treat each of these as an
ambiguity to raise:

- an acceptance criterion that's missing, vague or contradictory
- a product or UX decision the ticket doesn't make, such as copy,
  empty and error states, or edge-case behaviour
- more than one reasonable implementation with real trade-offs
- a change to a public API, data model or migration, or other
  behaviour users rely on
- scope that looks bigger or smaller than the ticket implies
- conflicts with existing code, or a mismatch between the ticket and
  how the code works

Don't raise questions you can answer by reading more code. Make minor
decisions yourself and list them as assumptions in the plan.

### Decide whether to break the ticket down

Almost every ticket should go through as a single PR. Only propose
breaking it into sub-tickets when it's **very large**, meaning several
of these are clearly true:

- One PR would be too big to review well: thousands of lines, or many
  unrelated areas.
- The ticket contains several parts that could each ship and be
  verified on their own.
- It spans several subsystems or layers that are normally changed
  separately, such as a schema migration, a backend API and a new UI
  flow.
- It would take an engineer several days or more.

Being merely fiddly, touching a handful of files, or needing a
migration plus code doesn't count. When in doubt, don't split.

If it does qualify, propose the breakdown as your plan instead of a
single implementation plan:

- **Condensed version**: the list of sub-tickets, one line each.
- **Full version**: for each sub-ticket, give a title, the scope, the
  acceptance criteria, what it depends on, and roughly which files it
  touches. Also give the order you'll work in and why splitting is
  better than one PR.

Put any ambiguities to the user as usual, then ask them to approve the
breakdown, with options to approve it, change it, or do the ticket as a
single PR. **Don't create sub-tickets without that approval.**

Once the user approves:

1. Switch back to the build agent.
2. Create each sub-ticket with `save_issue`: `team` set to the parent's
   team, `parentId` set to the parent ticket, and a description written
   for people that covers the scope and acceptance criteria. Put the
   files and approach notes in a collapsible "Agent notes" section. Add
   `blockedBy` relations where one sub-ticket depends on another.
3. **Linear**: reply in the parent's work log with the breakdown and
   links to the sub-tickets. Leave the parent *in progress*.
4. Remove the parent's worktree and branch from phase 2. Nothing was
   written there, and each sub-ticket gets its own.
5. Run this whole skill on each sub-ticket in turn, from phase 1 to
   phase 10, in dependency order: its own worktree, plan, PR, review,
   tests, merge approval and Linear updates. Start each one only after
   the previous one has merged, so it branches from a default branch
   that already includes the earlier work. Don't break sub-tickets down
   any further.
6. After each sub-ticket merges, reply in the parent's work log with
   its PR and what's left. If what you learned changes the remaining
   sub-tickets, update them and tell the user before you continue.
7. When every sub-ticket is done, set the parent to *done*, unless
   Linear has already moved it. Post a final summary in the parent's
   work log that links every sub-ticket and PR. Then tell the user the
   whole ticket is complete.

The parent ticket never gets its own PR.

### Write the plan

Always write out both versions of the plan in full, condensed first,
whether or not you'll ask the user to approve it:

1. **Condensed plan**: three to five bullet points covering what will
   change and how.
2. **Full implementation plan**:
   - your understanding of the ticket and the acceptance criteria
   - files to change or create, with what changes in each and why
   - the approach and any alternatives you rejected
   - tests to add or update
   - which UI states you'll screenshot on each platform, and which
     flows you'll record as demos, if any
   - the assumptions you made
   - every open ambiguity, with the option you'd pick and why
   - risks and anything out of scope

### Decide whether the plan needs approval

Once the plan is written, stop and think it through before going on:
**are the open ambiguities worth a round trip to the user?** Asking
costs the user a cycle. Proceeding on a wrong guess costs a rework
round in phase 9. Weigh the two.

Proceed without asking only when all of these are true:

- The change is small and well contained, such as a bug fix, a copy
  change or a tweak to one screen or function.
- Every open ambiguity has an option you'd clearly recommend, and
  picking the other one would mean a small, local change later.
- Nothing in the plan changes a public API, a data model or migration,
  security or permissions, or anything else that's costly to undo once
  merged.
- The scope matches what the ticket implies.

Ask the user when any of these are true:

- An ambiguity is a real product or UX decision with no clear default,
  or the options lead to noticeably different implementations.
- A wrong guess would mean redoing a large part of the work.
- The plan touches anything costly to undo, as listed above.
- You're splitting the ticket into sub-tickets. That always needs
  approval.
- The user asked to review the plan.

When in doubt, ask.

#### If the ambiguities are minor: proceed

Don't call the question tool. Tell the user in a few lines that you're
going ahead without asking, list the ambiguities and the choice you
made for each, then switch back to the build agent and go on to
phase 4. Keep the list of choices: you report them again in phase 9, so
the user can ask for tweaks in the same round as the merge approval.

In Claude Code, `ExitPlanMode` always asks the user, so present the
plan through it without asking any `AskUserQuestion` questions first.

#### If the ambiguities are significant: ask

Use the harness's question tool to put every open ambiguity to the
user. That's `question` in OpenCode and `AskUserQuestion` in Claude
Code. Ask them all in one call: one question per ambiguity, with
concrete options, your recommendation first and marked
"(Recommended)", and a short description of each option's trade-off.
Always end with a question asking the user to approve the plan or
request changes. In Claude Code, `ExitPlanMode` handles plan approval,
so ask your ambiguity questions with `AskUserQuestion` first, then
present the final plan through `ExitPlanMode`.

If the answers change the plan significantly, show the updated plan and
ask again. Repeat until the user approves.

**Linear**: once you've switched back to the build agent (below), reply
in the work log with the plan: the condensed bullets, the decision on
each ambiguity and who made it (the user, or you without asking), and
the full plan in a collapsible section. On later loops, title it
"Rework plan, round N" and say which feedback it addresses.

### Switch back to the build agent

Once the user approves the plan, or you've decided it doesn't need
approval:

- **OpenCode**: switch back to `build`.

  ```bash
  opencode api post "/api/session/$OPENCODE_SESSION_ID/agent" --data '{"agent":"build"}'
  ```

- **Claude Code**: approving `ExitPlanMode` returns you to normal mode.

Then go on to phase 4.

## 4. Do the work

Before you write any code, bring the ticket up to date. Check its
current values with `get_issue` first, and make all three changes in
one `save_issue` call:

- **Status**: make sure it's *in progress*. Follow the rules in
  "Keeping the ticket updated".
- **Assignee**: if the ticket is unassigned, assign it to `"me"`. If
  someone else is already assigned, ask the user before you reassign
  it. Leave it alone if it's already assigned to the user.
- **Labels**: use `addLabels` to add the team's labels that describe
  the plan, such as its type of work (bug, feature,
  improvement) or the areas it touches. If an existing label clearly
  contradicts the plan, for example "Bug" on what turned out to be a
  new feature, remove it with `removeLabels`. Keep every other label.
  Don't create new labels. If none of the team's labels fit, change
  nothing.

On rework loops, check the labels again in case the scope changed.

Then do the work:

- Follow the plan. If you find something it didn't anticipate that
  changes the approach or the scope, stop and check with the user
  rather than improvising. This applies even when you went ahead
  without asking for approval: a surprise that big means the
  ambiguities weren't minor after all.
- Match the existing conventions you found while planning.
- Meet every acceptance criterion from your brief. Don't expand scope.
  Note follow-up ideas for the PR description instead of building them.
- Add or update tests for the behaviour you changed.
- Run targeted tests, lint and type checks as you go.
- Make focused commits with clear messages, following the repo's commit
  style.

**Linear**: if you had to stop and check with the user because the plan
didn't hold, reply in the work log with what changed and why. Otherwise
there's nothing to post until the PR is open.

## 5. Capture UI screenshots and demos

Skip this phase only if the change has no visible UI effect. Then say
so in the PR's Screenshots section.

Capture every platform the app ships on and the change affects. For an
app that runs on iOS and web, that means both, every time. Follow any
rules on screenshots in the repo's agent instructions too.

1. Start the app from the worktree. Use the preview command from
   phase 2 if the repo has one. It already keeps this worktree's ports
   and data apart from the original checkout, and opens the iOS
   simulator on them. Otherwise start the dev server on a free port so
   it doesn't clash with a server running from the original checkout.
   On a rework round, the preview may already be running from phase 9.
   Use that one.
2. **Web**: use the `agent-browser` skill to open every screen the
   change affects and capture the relevant states: default, hover or
   focus, error, empty, and mobile width if the layout is responsive.
3. **iOS**: on the simulator the preview opened, go to each affected
   screen (deep links with `xcrun simctl openurl <udid> <url>` are
   quickest) and capture the same states with
   `xcrun simctl io <udid> screenshot <file>.png`. Use the simulator's
   UDID from the preview's output, not whichever one is booted.
4. **Demos**: when the change is a flow rather than a single screen,
   such as a multi-step form, a sheet or an animation, also record a
   short demo of it on each platform. On iOS, run
   `xcrun simctl io <udid> recordVideo --codec h264 <file>.mp4`, go
   through the flow, then stop the recording with Ctrl+C (SIGINT). On
   web, use `agent-browser`'s video recording. Keep each recording under
   about 30 seconds and 10 MB, so GitHub accepts the upload.
5. When you're changing existing UI, capture **before** shots too,
   from `origin/$DEFAULT_BRANCH` or the original checkout, on both
   platforms.
6. Save everything **outside the repo** in `/tmp/$TICKET-pr/`, with
   names that give the screen, platform and state, like
   `login-error-ios-after.png` or `invite-flow-web.mp4`. Never save
   screenshots or recordings in the worktree, and never commit them.
7. Stop the app when you're done, unless it's the preview left running
   from phase 9.

The images and recordings are uploaded to GitHub as PR attachments in phase 6. They're
hosted at `github.com/user-attachments/assets/...` like drag-and-drop
uploads, are never added to Git, and get the same visibility as the
repository.

## 6. Open or update the PR

Write the PR body to `/tmp/$TICKET-pr/body.md`, next to the screenshots.
Reference each screenshot by its local path, e.g.
`![Login error, iOS, after](./login-error-ios-after.png)`. Put each
recording's local path on a line of its own, e.g.
`./invite-flow-ios.mp4`. GitHub plays a video URL on its own line
inline. Then push the branch and open the PR against the default
branch, passing every screenshot and recording with `--attach`:

```bash
git push -u origin "$BRANCH"
gh pr create --base "$DEFAULT_BRANCH" --title "<TICKET-ID>: <summary>" \
  --body-file /tmp/$TICKET-pr/body.md \
  --attach /tmp/$TICKET-pr/login-error-ios-before.png \
  --attach /tmp/$TICKET-pr/login-error-ios-after.png \
  --attach /tmp/$TICKET-pr/login-error-web-before.png \
  --attach /tmp/$TICKET-pr/login-error-web-after.png \
  --attach /tmp/$TICKET-pr/invite-flow-ios.mp4
```

`gh` uploads each attached file and replaces its local path in the body
with the hosted URL. Any attached file the body doesn't reference gets
appended to the end. This needs `gh` v2.99.0 or later and push access to
the repo.

After creating the PR, run `gh pr view --json body -q .body` and check
that every image and recording reference is a `user-attachments` URL
and no local paths are left. If `gh` printed a PR URL but exited
non-zero, some uploads failed. Retry those files with `gh pr edit
<number> --body-file /tmp/$TICKET-pr/body.md --attach ...`, attaching
every file again. If a recording is too large, record a shorter one or
re-encode it smaller rather than dropping it.

Don't fall back to committing images or recordings, or to third-party
hosts. If uploads keep failing, tell the user and leave the Screenshots
section saying screenshots are pending.

Use the repo's PR template if it has one (`.github/pull_request_template.md`).
Otherwise structure the body like this:

```markdown
Closes <TICKET-ID>: <link to Linear ticket>

## Summary
What this PR does and why, in two or three sentences.

## Changes
- Each meaningful change, grouped by area, with the reasoning behind
  any non-obvious decisions.

## Screenshots
| Screen | Platform | Before | After |
| --- | --- | --- | --- |
| Login error | iOS | ![...](...) | ![...](...) |
| Login error | Web | ![...](...) | ![...](...) |

### Demos
**Invite flow, iOS**

./invite-flow-ios.mp4

**Invite flow, web**

./invite-flow-web.mp4

## How to review
How to run it: the preview command, or the dev server command.
1. **<Acceptance criterion>**: go to <screen or URL path>, do <action>,
   expect <result>.

## Testing
- Tests added or updated, and what they cover.
- Manual verification steps you performed.

## Notes
Trade-offs, known limitations, and follow-ups left out of scope.
```

If there's no UI change, keep the Screenshots section and write "No
visible change." in it. Otherwise include a row for each platform for
every affected screen, and leave out Before only for new screens. Leave
out Demos when nothing changed is a flow. Write one
"How to review" step for each acceptance criterion. Use URL paths rather
than local URLs with ports, so the steps still work after your preview
stops. Be detailed:
a reviewer should understand the work without reading the ticket.

**Later loops**: if the PR already exists because you're back here after
feedback in phase 9, don't open a new one. Push the new commits. Update
`body.md` so it describes the PR as it now stands, not as a changelog of
the rounds. Then run
`gh pr edit <number> --body-file /tmp/$TICKET-pr/body.md --attach ...`,
attaching every image and recording the body references.

**Linear**: set the status to *in review*. Reply in the work log with
the PR link and the PR's summary. On later loops, link the new commits
and say what changed in this round. Linear's GitHub integration usually
attaches the PR to the ticket by itself. If the PR doesn't show on the
ticket, the branch name or the "Closes" line is probably wrong.

## 7. Review your own PR and respond

Review the PR as a skeptical senior reviewer seeing it for the first
time, not as its author.

1. Read the full diff: `gh pr diff`.
2. Check it against the ticket's acceptance criteria. Look for bugs,
   unhandled edge cases, missing tests, security problems, performance
   problems, accessibility issues in UI, dead code, naming, and drift
   from repo conventions.
3. Submit the findings as **one native GitHub review**, with each
   finding as an inline comment on the exact line or line range it's
   about. Don't post findings as plain PR comments (`gh pr comment`) or
   as one big summary. GitHub won't let you approve or request changes
   on your own PR, so the review's event is `COMMENT`. Submit the whole
   review in a single API call:

   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/reviews --input /tmp/$TICKET-pr/review.json
   ```

   ```json
   {
     "commit_id": "<head SHA from gh pr view --json headRefOid>",
     "event": "COMMENT",
     "body": "Overall summary of the review.",
     "comments": [
       { "path": "src/auth/login.ts", "line": 42, "side": "RIGHT",
         "body": "This throws when `user` is null. Guard it, or narrow the type upstream." },
       { "path": "src/auth/login.ts", "start_line": 50, "line": 58, "side": "RIGHT",
         "body": "This block duplicates `validateSession`. Reuse it?" }
     ]
   }
   ```

   - `line` and `start_line` are line numbers in the file on the PR
     branch (`side: RIGHT`). Use `side: LEFT` for deleted lines. Every
     line must fall inside a diff hunk, or GitHub rejects the whole
     review with a 422 error.
   - Make each comment specific and actionable: what's wrong, why it
     matters, and the fix. Use a GitHub ```` ```suggestion ```` block
     when the fix is a small, self-contained replacement.
   - If you find nothing substantive, submit the review with a summary
     and no inline comments. Don't invent nitpicks.
4. Respond to every inline comment in its own thread:
   - **Fix it**: make the change, commit, push, then reply with what
     changed and the commit SHA.
   - **Decline it**: reply with the reasoning if the comment turns out
     not to warrant a change.

   ```bash
   # list the review's comments and their IDs
   gh api repos/{owner}/{repo}/pulls/<number>/comments --jq '.[] | {id, path, line, body}'
   # reply in the thread
   gh api repos/{owner}/{repo}/pulls/<number>/comments/<comment-id>/replies -f body="Fixed in abc1234: ..."
   ```

   After replying, resolve each thread you fixed or declined. Thread IDs
   come from GraphQL:

   ```bash
   gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved comments(first:1){nodes{databaseId}}}}}}}' -F o=<owner> -F r=<repo> -F n=<number>
   gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id=<thread-id>
   ```

5. If a fix changes the UI, retake the affected screenshots and demos
   on every platform, in `/tmp/$TICKET-pr/`. Update `body.md` and run
   `gh pr edit <number> --body-file /tmp/$TICKET-pr/body.md --attach ...`,
   attaching every image and recording the body references.
6. Also respond to any comments other reviewers or bots (CI, linters,
   code-review bots) have left by now.

**Linear**: reply in the work log with a link to the review, how many
findings it had, and what you fixed and declined, with a one-line reason
for each one you declined.

## 8. Run the full test suite

Run the **entire** suite, not only the tests you touched. Find the
canonical commands in the CI config (`.github/workflows/`), then
`package.json` scripts, `Makefile`, or the README. Run what CI runs:
unit, integration, end-to-end, lint, type check and build.

- If anything fails, fix it, commit, push, and rerun until it all
  passes.
- If a failure also happens on `origin/$DEFAULT_BRANCH` and has nothing
  to do with your change, don't fix it here. Record it in the PR's
  Notes section and tell the user.
- Check remote CI too: `gh pr checks --watch`.

**Linear**: reply in the work log with the results: which suites ran,
pass or fail for each, the CI status, and any failures that already
happen on the default branch. Put the command output in a collapsible
section if it's useful.

## 9. Ask the user to approve the merge

### Start the preview

Get the finished work running before you ask, so the user can try it
straight away. Skip this only if the change has nothing a person can
try in the app.

1. Start the preview command from phase 2 in `$WORKTREE`, in the
   background so it keeps running after your command returns. In
   OpenCode, use the shell tool's `background` option. In Claude Code,
   use Bash with `run_in_background`. If the repo has no preview
   command, start the dev server on free ports instead, web only.
2. Read its output for the web URL, the API URL and any sign-in
   details. Wait until the web URL and the API both respond, for
   example by polling them with `curl` until they return a success.
   If they don't come up, read the output, fix the cause and start
   again. Don't ask for approval with a broken preview.
3. Open the app on the iOS simulator, if the preview supports it. Many
   preview commands open it themselves. Deep-link to the screen the
   ticket changed if the app supports links, for example
   `xcrun simctl openurl <udid> "<scheme>://<path>"`, with the
   simulator's UDID from the preview's output. Use `booted` only when
   the preview has no simulator of its own.
4. Take one quick screenshot of the changed screen, on the simulator
   (`xcrun simctl io <udid> screenshot /tmp/$TICKET-pr/preview-check.png`)
   or on web with `agent-browser`. Check that it shows this branch's
   code, not the original checkout's. This is only a check. Don't add
   it to the PR.

Leave the preview running while you wait for the user.

### Ask for approval

Stop here and notify the user. Include:

- the PR URL
- a short summary of what changed
- a **Try it** section:
  - web URLs that deep-link to each affected screen
  - a note that the simulator is already open on the change, if it is
  - sign-in details from the preview's output, if the app needs them
  - short review steps for each acceptance criterion, from the PR's
    "How to review" section: go here, do this, expect that
  - if there's no preview command, say the preview is web only
- the self-review results: what you found, what you fixed, and what you
  declined and why
- the test suite and CI results, including any failures you couldn't
  resolve
- if you went ahead in phase 3 without asking, a **Decisions I made**
  section listing each ambiguity, the choice you made, the alternative,
  and what switching would involve, so the user can ask for tweaks
  instead of approving
- any other uncertainties: anything you're unsure about and anything
  that needs their judgement

Then ask for explicit approval to merge. **Never merge without it.**
Approval for one PR doesn't carry over to another.

**Linear**: reply in the work log saying the PR is ready and waiting
for merge approval. Don't post local preview URLs or sign-in details.
They only work on this machine.

When the user approves, squash-merge:

```bash
gh pr merge <number> --squash --delete-branch
```

If the user says they merged it themselves, confirm with
`gh pr view <number> --json state` that the state is `MERGED`.

### If the user gives feedback instead

If the user requests changes, or gives feedback that implies changes,
don't patch it in directly. **Go back to phase 3 and run the whole loop
again**. Number the rounds, starting at round 2.

**Linear**: before replanning, set the status back to *in progress*.
Reply in the work log with "Rework round N" and a summary of the
feedback. Each phase in the loop then posts its usual Linear update.

Keep the preview running through the loop. Hot reload picks up most
changes. Restart it if the changes touch the API, the database schema
or native code, since those don't reload.

1. **Phase 3, plan**: switch to the plan agent. Read the code the
   feedback touches, and present a condensed plan and a full plan for
   the changes. Decide whether the plan needs approval as before. Small,
   clear feedback usually doesn't. Then switch back to the build agent.
2. **Phase 4, work**: implement the changes in the same worktree and
   branch.
3. **Phase 5, screenshots**: retake any screenshots and demos the
   changes affect, on every platform.
4. **Phase 6, PR**: update the existing PR as described there.
5. **Phase 7, review**: submit a new review covering the new commits,
   and respond to its comments. If the user left feedback as PR
   comments, reply to those threads too.
6. **Phase 8, tests**: run the full test suite again.
7. **Phase 9**: confirm the preview is up and shows the new changes,
   restarting it if needed, then ask for merge approval again with an
   updated **Try it** section.

Keep looping until the user approves the merge. If the user only asks a
question, answer it and ask for approval again; that doesn't need a new
loop.

## 10. Clean up

Only after the PR is confirmed merged:

**Linear**: set the status to *done*, unless the GitHub integration has
already done it. Reply in the work log with a final summary: the merged
PR, what shipped, how many rework rounds there were, and any follow-ups
left out of scope. Suggest the follow-ups to the user as new tickets,
but don't create them unless the user asks.

Stop the preview before you remove the worktree. End the background
process and anything it started, such as the web server, the API or a
database container. Then run the repo's documented cleanup for
per-worktree preview resources, such as dropping a preview database.
Check that the preview's ports are free.

```bash
cd "$ORIGINAL_REPO"
git worktree remove "$WORKTREE"   # if it refuses, inspect what's left; don't --force without asking
git branch -D "$BRANCH" 2>/dev/null || true
git worktree prune
rm -rf "/tmp/$TICKET-pr"          # local screenshots and PR drafts; the uploaded copies live on GitHub
```

Then return to the main checkout of the repo, not a worktree, and pull
the merge. `$ORIGINAL_REPO` may itself be a worktree if the user started
there, so resolve the main checkout from the shared git directory:

```bash
MAIN_REPO=$(dirname "$(git -C "$ORIGINAL_REPO" rev-parse --path-format=absolute --git-common-dir)")
cd "$MAIN_REPO"
git branch --show-current   # must be $DEFAULT_BRANCH
git status --porcelain      # must be empty
git pull --ff-only
```

Only pull if the main checkout is on `$DEFAULT_BRANCH` and has no
uncommitted changes, including untracked files. If either check fails,
skip the pull and leave the checkout alone: don't stash, switch branches
or commit. Tell the user why you skipped it. If `git pull --ff-only`
fails because the branches have diverged, stop and tell the user; don't
merge or rebase.

Tell the user the worktree is removed, that you're back in `$MAIN_REPO`,
and whether you pulled the merge.

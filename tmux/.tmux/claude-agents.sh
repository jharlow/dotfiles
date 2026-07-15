#!/usr/bin/env bash
# claude-agents.sh — pick a tmux pane running a Claude Code or Codex CLI agent.
#
# Bound to `prefix + a` (see ~/.tmux.conf). Lists every pane whose *foreground*
# process is a live `claude` or `codex` agent, shows each one's current status
# (Working / Awaiting input / Idle), and jumps to the selected pane. Styled to
# feel like the `prefix + s` session tree: fullscreen, list on the left, a live
# preview of the pane on the right.
#
# Detection is layered:
#   * "Is a live agent the active app here?"  -> authoritative. A claude/codex
#     process must exist in the pane's process tree AND the pane's foreground
#     command must not be a shell (so a backgrounded/exited agent that left a
#     shell prompt is correctly ignored — pane titles linger, so we don't trust
#     them for presence).
#   * "What's its status?"  -> heuristic, from the pane's live screen + title.
#     The knobs to tune if a CLI changes its UI are STATUS_* and the title-byte
#     check in pane_status().

set -u
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

SHELLS='^-?(zsh|bash|fish|sh|dash|tcsh|ksh)$'
# Status heuristics (ASCII-safe so they work regardless of the popup's locale).
STATUS_AWAITING='Do you want|Allow (command|this)|Approve|Waiting for your| 1\. Yes| 2\. No|❯ 1\.'
# Markers unlikely to appear in prose (spinner line only). Used for both agents.
STATUS_WORKING='esc to interrupt|to interrupt|tokens\)'
# Looser markers for codex, whose working signal isn't in the pane title.
STATUS_WORKING_CODEX='Working|Thinking|Generating|Running'

# Single row template used for both the data rows and the header, so their
# column separators line up exactly. First field is the status dot (width 1).
ROW_FMT='%s %-14s │ %-6s │ %-18s │ %s'
printf -v HEADER "$ROW_FMT" ' ' 'STATUS' 'AGENT' 'LOCATION' 'TITLE'

# --- gather panes (one tmux call; includes fg command + title) ---------------
declare -A pane_pid pane_loc pane_cmd pane_title
while IFS=$'\t' read -r id pid cmd loc win title; do
  pane_pid[$id]=$pid
  pane_cmd[$id]=$cmd
  pane_loc[$id]=$loc
  pane_title[$id]=$title
done < <(tmux list-panes -a -F \
  '#{pane_id}	#{pane_pid}	#{pane_current_command}	#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_title}')

# --- process table: ppid map (all procs) + agent pids (grep, no fork/pid) -----
psout=$(ps -axww -o pid=,ppid=,command=)
declare -A ppid_of
while read -r p pp _; do ppid_of[$p]=$pp; done <<<"$psout"

declare -A agent_kind_of  # agent pid -> claude|codex
while read -r p _ rest; do
  [[ $rest == *claude-agents* ]] && continue
  case " $rest " in
    *" claude "*|*/claude" "*) agent_kind_of[$p]=claude ;;
    *codex*)                   agent_kind_of[$p]=codex  ;;
  esac
done < <(grep -iE '(^| |/)(claude|codex)( |$)' <<<"$psout")

# pane shell pid -> pane id, for the ancestor walk.
declare -A by_pid
for id in "${!pane_pid[@]}"; do by_pid[${pane_pid[$id]}]=$id; done

# Walk up from a process to the pane id that owns it (or empty).
owning_pane() {
  local pid=$1 hops=0
  while [[ -n ${pid:-} && $pid != 0 && $hops -lt 40 ]]; do
    [[ -n ${by_pid[$pid]:-} ]] && { printf '%s' "${by_pid[$pid]}"; return; }
    pid=${ppid_of[$pid]:-0}; ((hops++))
  done
}

# Status for a confirmed-active agent pane.
pane_status() {
  local id=$1 kind=$2 content b3
  # Claude animates its pane title with a braille spinner *only while running*,
  # so a braille title is an authoritative "working" — it beats content markers
  # (a real input prompt stops the spinner, so the title won't be braille then).
  if [[ $kind == claude ]]; then
    b3=$(printf '%s' "${pane_title[$id]}" | head -c3 | od -An -tx1 | tr -d ' ')
    case "$b3" in e2a0*|e2a1*|e2a2*|e2a3*) echo working; return ;; esac
  fi
  content=$(tmux capture-pane -p -t "$id" 2>/dev/null)
  if grep -qE "$STATUS_AWAITING" <<<"$content"; then echo awaiting; return; fi
  grep -qE "$STATUS_WORKING" <<<"$content" && { echo working; return; }
  if [[ $kind == codex ]] && grep -qE "$STATUS_WORKING_CODEX" <<<"$content"; then
    echo working; return
  fi
  echo idle
}

# --- build rows: one per pane with a live agent as the foreground app --------
declare -A seen
rows=""
for pid in "${!agent_kind_of[@]}"; do
  id=$(owning_pane "$pid"); [[ -z $id ]] && continue
  [[ -n ${seen[$id]:-} ]] && continue
  # Foreground must actually be the agent, not a shell it was launched from.
  [[ ${pane_cmd[$id]} =~ $SHELLS ]] && continue
  seen[$id]=1

  kind=${agent_kind_of[$pid]}
  case "$(pane_status "$id" "$kind")" in
    awaiting) prio=0; dot=$'\e[38;5;214m●\e[0m'; word='Awaiting input' ;;
    working)  prio=1; dot=$'\e[38;5;142m●\e[0m'; word='Working'        ;;
    *)        prio=2; dot=$'\e[38;5;245m●\e[0m'; word='Idle'           ;;
  esac

  printf -v cols "$ROW_FMT" \
    "$dot" "$word" "$kind" "${pane_loc[$id]}" "${pane_title[$id]:-—}"
  rows+="${prio}	${id}	${cols}"$'\n'
done

if [[ -z $rows ]]; then
  tmux display-message "No Claude or Codex agents running"
  exit 0
fi

# Sort Awaiting -> Working -> Idle, then drop the sort key (leaving id<TAB>cols).
list=$(printf '%s' "$rows" | sort -t$'\t' -k1,1n -k3 | cut -f2-)

choice=$(printf '%s\n' "$list" | fzf \
  --ansi --no-sort --delimiter=$'\t' --with-nth=2.. \
  --layout=reverse --height=100% --border=none --no-separator \
  --header="$HEADER" \
  --prompt='  agents  ' --pointer='▶' --info=inline \
  --preview 'tmux capture-pane -e -p -t {1}' \
  --preview-window='right,58%,border-left,wrap' \
  --color='bg+:237,fg+:223,hl:214,hl+:214,pointer:167,prompt:214,header:245,gutter:-1,info:245,border:239') \
  || exit 0

id=${choice%%$'\t'*}
[[ -z $id ]] && exit 0
tmux switch-client -t "$id" 2>/dev/null
tmux select-window -t "$id"
tmux select-pane -t "$id"

#!/usr/bin/env zsh
# agents.sh — pick an opencode session open in some tmux pane and jump to it.
#
# Runs under zsh (the macOS default) because it uses associative arrays, which
# the system bash 3.2 does not support. Do not run it with `bash agents.sh`.
#
# Bound to `prefix + a` (see ~/.tmux.conf). Lists every session open as a tab in
# an opencode TUI running under tmux, with its live status, and on select
# switches to that pane and focuses the session's tab. Styled to feel like the
# `prefix + s` session tree: fullscreen, list on the left, a preview of the
# session's recent conversation on the right.
#
# The data comes from the TUI plugin at ~/.config/opencode/plugins/tmux/tui.ts,
# which writes one <pid>.tsv per TUI and focuses a tab when we drop a
# <pid>.focus file next to it. Keep the two in sync.
#
# `agents.sh preview <sessionID>` renders the preview pane. It reads the
# session's messages from the opencode service, so it works for background tabs
# that their pane is not currently showing.

set -u
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

# Messages fetched for the preview. Tool calls are one message each, so this
# needs to be generous to reach back past a long run of tool use.
PREVIEW_LIMIT=60

preview() {
  opencode api get "/api/session/$1/message?limit=$PREVIEW_LIMIT&order=desc" 2>/dev/null \
    | jq -r '
      def dim: "\u001b[38;5;245m\(.)\u001b[0m";
      def oneline($n): gsub("\\s+"; " ") | if length > $n then .[0:$n] + "…" else . end;
      # The most telling argument of a tool call, for a one-line summary.
      def summary: (.state.input // {}) as $in
        | ($in.command // $in.description // $in.filePath // $in.path
           // $in.pattern // $in.query // $in.url // $in.prompt // "")
        | tostring | oneline(70);
      .data | reverse | .[]
      | if .type == "user" then
          "\n\u001b[1;38;5;214m❯ You\u001b[0m\n\(.text // "")\n"
        elif .type == "assistant" then
          (.content // [])[]
          | if .type == "text" then "\(.text)\n"
            elif .type == "tool" then
              ("  ⚙ \(.name)  \(summary)" | dim)
                + (if .state.status == "error" then "  \u001b[38;5;167m✗\u001b[0m" else "" end)
            else empty end
        else empty end
    ' 2>/dev/null \
    || printf '\e[38;5;245m(could not load this session from the opencode service)\e[0m\n'
}

if [[ ${1:-} == preview ]]; then
  preview "${2:?session id}"
  exit 0
fi

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/opencode/tui"
DIR_MAX=20

# Shorten a path for the DIR column to its last component (~ for home), which
# is the project name and leaves the width for titles.
short_dir() {
  local d=${1:t}
  [[ $1 == $HOME || -z $1 ]] && d='~'
  (( ${#d} > DIR_MAX )) && d="${d:0:$((DIR_MAX - 1))}…"
  printf '%s' "$d"
}

# --- live panes: pane id -> session:window.pane ------------------------------
typeset -A pane_loc
while IFS=$'\t' read -r id loc; do
  pane_loc[$id]=$loc
done < <(tmux list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}.#{pane_index}')

# --- collect rows: one per open session tab ----------------------------------
# Columns are sized to their widest value once every row is known.
typeset -a r_prio r_pid r_pane r_sid r_dot r_word r_mark r_loc r_dir r_title
w_loc=8 w_dir=3
for f in "$STATE_DIR"/*.tsv(N); do
  pid=${${f:t}%.tsv}
  # A SIGKILLed TUI never deletes its file, so the pid must still be live.
  kill -0 "$pid" 2>/dev/null || continue
  while IFS=$'\t' read -r pane sid active st dir title; do
    [[ -n ${pane_loc[$pane]:-} ]] || continue
    case $st in
      awaiting) prio=0; dot=$'\e[38;5;214m●\e[0m'; word='Awaiting' ;;
      error)    prio=1; dot=$'\e[38;5;167m●\e[0m'; word='Error'    ;;
      done)     prio=2; dot=$'\e[38;5;109m●\e[0m'; word='Done'     ;;
      working)  prio=3; dot=$'\e[38;5;142m●\e[0m'; word='Working'  ;;
      *)        prio=4; dot=$'\e[38;5;245m●\e[0m'; word='Idle'     ;;
    esac
    loc=${pane_loc[$pane]} sdir=$(short_dir "$dir")
    (( ${#loc} > w_loc )) && w_loc=${#loc}
    (( ${#sdir} > w_dir )) && w_dir=${#sdir}
    r_prio+=$prio r_pid+=$pid r_pane+=$pane r_sid+=$sid r_dot+=$dot r_word+=$word
    r_mark+=$([[ $active == 1 ]] && print '▸' || print ' ')
    r_loc+=$loc r_dir+=$sdir r_title+=${title:-—}
  done <"$f"
done

if (( ! ${#r_sid} )); then
  tmux display-message "No opencode sessions open in tmux"
  exit 0
fi

# Single row template used for both the data rows and the header, so their
# column separators line up exactly. First field is the status dot (width 1),
# third marks the tab currently shown in its pane.
ROW_FMT="%s %-8s │ %s %-${w_loc}s │ %-${w_dir}s │ %s"
printf -v HEADER "$ROW_FMT" ' ' 'STATUS' ' ' 'LOCATION' 'DIR' 'TITLE'

rows=""
for i in {1..${#r_sid}}; do
  printf -v cols "$ROW_FMT" \
    "${r_dot[i]}" "${r_word[i]}" "${r_mark[i]}" "${r_loc[i]}" "${r_dir[i]}" "${r_title[i]}"
  # Fields: sort key, location (sort only), pid, pane, session id, columns.
  rows+="${r_prio[i]}	${r_loc[i]}	${r_pid[i]}	${r_pane[i]}	${r_sid[i]}	${cols}"$'\n'
done

# Sort by status, then location, and drop both sort keys.
list=$(printf '%s' "$rows" | sort -t$'\t' -k1,1n -k2,2 | cut -f3-)

choice=$(printf '%s\n' "$list" | fzf \
  --ansi --no-sort --delimiter=$'\t' --with-nth=4.. \
  --layout=reverse --height=100% --border=none --no-separator \
  --header="$HEADER" \
  --prompt='  opencode  ' --pointer='▶' --info=inline \
  --preview "${(q)0} preview {3}" \
  --preview-window='right,50%,border-left,wrap,follow' \
  --color='bg+:237,fg+:223,hl:214,hl+:214,pointer:167,prompt:214,header:245,gutter:-1,info:245,border:239') \
  || exit 0

IFS=$'\t' read -r pid pane sid _ <<<"$choice"
[[ -z ${pane:-} ]] && exit 0

# Ask the TUI to bring the tab forward first, so it is already showing when the
# pane appears. Write then rename so the plugin never reads a partial id.
tmp="$STATE_DIR/.$pid.focus.$$"
printf '%s\n' "$sid" >"$tmp" && mv -f "$tmp" "$STATE_DIR/$pid.focus"

tmux switch-client -t "$pane" 2>/dev/null
tmux select-window -t "$pane"
tmux select-pane -t "$pane"

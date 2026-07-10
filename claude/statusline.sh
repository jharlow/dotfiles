#!/usr/bin/env bash
# Claude Code status line (two lines):
#   [model] ⚡effort | 📁 cwd | 🌿 branch
#   <ctx bar> ctx% | $cost | ⏱️ total time
#
# The context bar is a solid block bar (█) drawn over a dotted background (·),
# colored green/yellow/red by usage. Fast mode (⚡) is read from the persistent
# `fastMode` user setting, since it is not present in the stdin payload.

input=$(cat)

esc=$(printf '\033')
reset="${esc}[0m"
dim="${esc}[90m"                 # gray — separators + dotted bar background

# --- extract everything in a single jq pass (one value per line, so empty
#     fields such as a missing effort level are preserved, not collapsed) ---
{
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r cwd
  IFS= read -r pct
  IFS= read -r cost
  IFS= read -r dur_ms
} < <(printf '%s' "$input" | jq -r '
  .model.display_name // "?",
  (.effort.level // ""),
  (.workspace.current_dir // .cwd // ""),
  (.context_window.used_percentage // 0),
  (.cost.total_cost_usd // 0),
  (.cost.total_duration_ms // 0)
')

# fast mode: read the persistent user setting (toggled by /fast)
fast=$(jq -r '.fastMode // false' "$HOME/.claude/settings.json" 2>/dev/null)

# --- current git branch (soft-truncate very long names, keep the tail) ---
branch=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
fi
if [ -n "$branch" ] && [ "${#branch}" -gt 30 ]; then
  branch="…${branch: -29}"
fi

# --- cwd: collapse $HOME to ~ ---
if [ -n "$HOME" ] && [ "${cwd#"$HOME"}" != "$cwd" ]; then
  cwd="~${cwd#"$HOME"}"
fi

# --- context bar: solid (█) on dotted (·), colored by usage ---
pct_int=$(printf '%.0f' "$pct" 2>/dev/null); [ -z "$pct_int" ] && pct_int=0
width=10
filled=$(( (pct_int * width + 50) / 100 ))
[ "$filled" -gt "$width" ] && filled=$width
[ "$filled" -lt 0 ] && filled=0
empty=$(( width - filled ))

if   [ "$pct_int" -ge 80 ]; then barcol="${esc}[31m"   # red
elif [ "$pct_int" -ge 50 ]; then barcol="${esc}[33m"   # yellow
else                             barcol="${esc}[32m"   # green
fi

bar="${barcol}"
i=0; while [ "$i" -lt "$filled" ]; do bar="${bar}█"; i=$((i + 1)); done
bar="${bar}${dim}"
i=0; while [ "$i" -lt "$empty" ]; do bar="${bar}·"; i=$((i + 1)); done
bar="${bar}${reset}"

# --- cost ---
cost_fmt=$(awk -v c="$cost" 'BEGIN { if (c + 0 < 0.01) printf "%.4f", c; else printf "%.2f", c }')

# --- total time (from ms) ---
secs=$(( dur_ms / 1000 ))
if   [ "$secs" -ge 3600 ]; then time_fmt="$((secs / 3600))h $(((secs % 3600) / 60))m"
elif [ "$secs" -ge 60 ];   then time_fmt="$((secs / 60))m $((secs % 60))s"
else                            time_fmt="${secs}s"
fi

# --- segment colors ---
c_model="${esc}[1;35m"   # bold magenta
c_fast="${esc}[93m"      # bright yellow
c_effort="${esc}[34m"    # blue
c_cwd="${esc}[32m"       # green
c_branch="${esc}[36m"    # cyan
c_cost="${esc}[33m"      # yellow
c_time="${esc}[90m"      # gray
sep="${dim} | ${reset}"

# --- line 1: [model] ⚡effort | 📁 cwd | 🌿 branch ---
flags=""
[ "$fast" = "true" ] && flags="${c_fast}⚡${reset}"
[ -n "$effort" ] && flags="${flags}${c_effort}${effort}${reset}"

line1="${c_model}[${model}]${reset}"
[ -n "$flags" ] && line1="${line1} ${flags}"
line1="${line1}${sep}${c_cwd}📁 ${cwd}${reset}"
[ -n "$branch" ] && line1="${line1}${sep}${c_branch}🌿 ${branch}${reset}"

# --- line 2: <bar> ctx% | $cost | ⏱️ total time ---
line2="${bar} ${barcol}${pct_int}%${reset}${sep}${c_cost}\$${cost_fmt}${reset}${sep}${c_time}⏱️ ${time_fmt}${reset}"

printf '%s\n%s\n' "$line1" "$line2"

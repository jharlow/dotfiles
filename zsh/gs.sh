#!/usr/bin/env zsh

setopt pipefail

script_dir=${0:A:h}
active_command_pid=''
active_spinner_pid=''

cleanup_children() {
  if [[ -n $active_command_pid ]]; then
    kill "$active_command_pid" 2>/dev/null
    wait "$active_command_pid" 2>/dev/null
    active_command_pid=''
  fi

  if [[ -n $active_spinner_pid ]]; then
    kill "$active_spinner_pid" 2>/dev/null
    wait "$active_spinner_pid" 2>/dev/null
    active_spinner_pid=''
  fi

}

cancel() {
  trap - INT TERM HUP
  cleanup_children
  [[ -t 2 ]] && printf '\r\033[K' >&2
  exit 130
}

trap cancel INT TERM HUP

run_with_timeout() {
  local seconds=$1
  shift
  perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
}

fzf_notify() {
  curl --silent --max-time 1 --request POST "http://localhost:${FZF_PORT}" --data-binary "$1" >/dev/null 2>&1
}

run_with_spinner() {
  local label=$1
  shift

  local output_file pid result frame_index=1
  local -a frames=('|' '/' '-' $'\\')
  output_file="$(mktemp)" || return 1

  "$@" >"$output_file" 2>&1 &
  pid=$!
  active_command_pid=$pid
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[K[%s] %s' "${frames[frame_index]}" "$label" >/dev/tty
    frame_index=$((frame_index % ${#frames} + 1))
    sleep 0.1
  done

  wait "$pid"
  result=$?
  active_command_pid=''
  if (( result == 0 )); then
    printf '\r\033[K✓ %s' "$label" >/dev/tty
    sleep 1
    printf '\r\033[K' >/dev/tty
  else
    printf '\r\033[K✗ %s\n' "$label" >/dev/tty
    command cat "$output_file" >&2
  fi

  command rm -f "$output_file"
  return "$result"
}

run_function_with_spinner() {
  local label=$1
  shift

  local spinner_pid result
  (
    local frame_index=1
    local -a frames=('|' '/' '-' $'\\')
    while true; do
      printf '\r\033[K[%s] %s' "${frames[frame_index]}" "$label" >/dev/tty
      frame_index=$((frame_index % ${#frames} + 1))
      sleep 0.1
    done
  ) &
  spinner_pid=$!
  active_spinner_pid=$spinner_pid

  "$@"
  result=$?
  kill "$spinner_pid" 2>/dev/null
  wait "$spinner_pid" 2>/dev/null
  active_spinner_pid=''

  if (( result == 0 )); then
    printf '\r\033[K✓ %s' "$label" >/dev/tty
    sleep 1
    printf '\r\033[K' >/dev/tty
  else
    printf '\r\033[K✗ %s\n' "$label" >/dev/tty
  fi

  return "$result"
}

run_tuicr() {
  local number=$1
  local spinner_pid result
  local repo_selector=$PWD

  (
    local frame_index=1
    local -a frames=('|' '/' '-' $'\\')
    while ! tuicr review list --repo "$repo_selector" 2>/dev/null | \
      jq -e --arg number "$number" \
        'any(.[]; .active == true and .kind == "pr" and .anchor == ("pr/" + $number))' >/dev/null; do
      printf '\r\033[K[%s] Opening pull request #%s in tuicr' "${frames[frame_index]}" "$number" >/dev/tty
      frame_index=$((frame_index % ${#frames} + 1))
      sleep 0.1
    done
  ) &
  spinner_pid=$!
  active_spinner_pid=$spinner_pid

  tuicr pr "$number"
  result=$?

  kill "$spinner_pid" 2>/dev/null
  wait "$spinner_pid" 2>/dev/null
  active_spinner_pid=''
  printf '\r\033[K' >/dev/tty
  return "$result"
}

run_fzf_action() {
  local action=$1
  local target=${2:-}
  local label success output_file rows_file spinner_pid result

  case $action in
    ready)
      label='Marking pull request ready'
      success='Pull request marked ready'
      ;;
    draft)
      label='Converting pull request to draft'
      success='Pull request converted to draft'
      ;;
    approve)
      label='Approving pull request'
      success='Pull request approved'
      ;;
    view)
      label='Opening pull request'
      success='Opened pull request'
      ;;
    yank)
      label='Copying stack links'
      success='Copied stack links'
      ;;
    refresh)
      label='Updating stack'
      success='Stack updated'
      ;;
    *) return 2 ;;
  esac

  if [[ $target == - ]]; then
    fzf_notify 'change-footer(✗ The selected branch has no pull request)'
    return 1
  fi

  output_file="$(mktemp)" || return 1
  (
    local frame_index=1
    local -a frames=('|' '/' '-' $'\\')
    while true; do
      fzf_notify "change-footer([${frames[frame_index]}] ${label})"
      frame_index=$((frame_index % ${#frames} + 1))
      sleep 0.1
    done
  ) &
  spinner_pid=$!
  active_spinner_pid=$spinner_pid

  case $action in
    ready) run_with_timeout 30 gh pr ready "$target" >"$output_file" 2>&1 ;;
    draft) run_with_timeout 30 gh pr ready --undo "$target" >"$output_file" 2>&1 ;;
    approve) run_with_timeout 30 gh pr review "$target" --approve >"$output_file" 2>&1 ;;
    view) run_with_timeout 30 gh pr view "$target" --web >"$output_file" 2>&1 ;;
    yank) run_with_timeout 60 "$script_dir/prl.sh" >"$output_file" 2>&1 ;;
    refresh) run_with_timeout 30 "$script_dir/gs.sh" __rows >"$output_file" 2>&1 ;;
  esac
  result=$?

  if (( result == 0 )) && [[ $action == refresh ]]; then
    rows_file=$output_file
  elif (( result == 0 )) && [[ $action == ready || $action == draft || $action == approve ]]; then
    rows_file="$(mktemp)" || result=1
    if (( result == 0 )); then
      "$script_dir/gs.sh" __rows >"$rows_file" 2>>"$output_file" || result=$?
    fi
  fi

  kill "$spinner_pid" 2>/dev/null
  wait "$spinner_pid" 2>/dev/null
  active_spinner_pid=''

  if (( result == 0 )); then
    if [[ $action == ready || $action == draft || $action == approve || $action == refresh ]]; then
      fzf_notify "reload(command cat ${(q)rows_file})+change-footer(✓ ${success})"
    else
      fzf_notify "change-footer(✓ ${success})"
    fi
    sleep 1
    fzf_notify 'change-footer()'
  else
    fzf_notify "change-footer(✗ ${label} failed)"
  fi

  command rm -f "$output_file"
  [[ -n $rows_file ]] && command rm -f "$rows_file"
  return "$result"
}

case ${1:-} in
  co) set -- checkout "${@:2}" ;;
  v) set -- view "${@:2}" ;;
  r)
    if [[ ${2:-} == -u ]]; then
      set -- rebase --upstack "${@:3}"
    else
      set -- rebase "${@:2}"
    fi
    ;;
  a) set -- add "${@:2}" ;;
  i) set -- init "${@:2}" ;;
  su)
    if [[ ${2:-} == -a ]]; then
      set -- submit --auto "${@:3}"
    else
      set -- submit "${@:2}"
    fi
    ;;
  sy) set -- sync "${@:2}" ;;
  p) set -- push "${@:2}" ;;
  b) set -- bottom "${@:2}" ;;
  t) set -- top "${@:2}" ;;
  u) set -- up "${@:2}" ;;
  d) set -- down "${@:2}" ;;
esac

if [[ ${1:-} != view && ${1:-} != checkout && ${1:-} != __fzf-action && ${1:-} != __rows && \
  ${1:-} != __checkout-rows && ${1:-} != __checkout-preview && ${1:-} != __checkout-filter && \
  ${1:-} != __checkout-toggle && ${1:-} != __view-header ]] || \
  [[ ${1:-} == checkout && $# -ne 1 ]] || \
  [[ ${1:-} == view && $# -ne 1 ]]; then
  exec gh stack "$@"
fi

for dependency in gh jq fzf curl perl; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print -u2 -r -- "gs: $dependency is required"
    exit 1
  fi
done

export GH_PROMPT_DISABLED=1

typeset -a tmux_fzf_bindings
if [[ -n ${TMUX:-} ]]; then
  tmux_fzf_bindings=(
    --bind='ctrl-h:execute-silent(tmux select-pane -L)'
    --bind='ctrl-j:execute-silent(tmux select-pane -D)'
    --bind='ctrl-k:execute-silent(tmux select-pane -U)'
    --bind='ctrl-l:execute-silent(tmux select-pane -R)'
  )
fi

checkout_status_bar() {
  local -i merged=$1 open=$2 closed=$3 unpushed=$4 total boxes assigned i best
  local -a counts scaled remainders colors
  counts=($merged $open $closed $unpushed)
  colors=('\033[35m' '\033[32m' '\033[31m' '\033[90m')
  total=$((merged + open + closed + unpushed))
  (( total == 0 )) && { printf '—'; return; }

  if (( total <= 5 )); then
    scaled=(${counts[@]})
  else
    scaled=(0 0 0 0)
    remainders=(0 0 0 0)
    assigned=0
    for i in {1..4}; do
      scaled[i]=$((counts[i] * 5 / total))
      remainders[i]=$((counts[i] * 5 % total))
      assigned=$((assigned + scaled[i]))
    done
    while (( assigned < 5 )); do
      best=1
      for i in {2..4}; do
        (( remainders[i] > remainders[best] )) && best=$i
      done
      scaled[best]=$((scaled[best] + 1))
      remainders[best]=-1
      assigned=$((assigned + 1))
    done
  fi

  for i in {1..4}; do
    (( scaled[i] > 0 )) && printf "${colors[i]}%0.s▆\033[0m" {1..${scaled[i]}}
    boxes=$((boxes + scaled[i]))
  done
  (( boxes < 5 )) && printf '%*s' $((5 - boxes)) ''
}

truncate_checkout_cell() {
  local value=$1
  local -i width=$2
  if (( ${#value} > width )); then
    printf '%s…' "${value[1,$((width - 1))]}"
  else
    printf '%s' "$value"
  fi
}

load_checkout_rows() {
  local git_dir stack_file local_json remote_json repo raw
  local number summary base merged open closed unpushed type created target branches status_bar display search_padding

  git_dir="$(git rev-parse --git-dir 2>/dev/null)" || {
    print -u2 -r -- 'gs checkout: not a git repository'
    return 1
  }
  stack_file="${git_dir}/gh-stack"
  [[ -f $stack_file ]] && local_json="$(command cat "$stack_file")" || local_json='{"stacks":[]}'
  repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)" || repo=''
  remote_json='[]'
  if [[ -n $repo ]]; then
    remote_json="$(run_with_timeout 20 gh api "repos/${repo}/stacks" 2>/dev/null)" || remote_json='[]'
  fi

  raw="$(jq -nr --argjson local "$local_json" --argjson remote "$remote_json" '
    def merged: (.merged_at // "") != "";
    def age:
      if . == null or . == "" then "—"
      else ((now - fromdateiso8601) | floor) as $s
      | if $s < 60 then "just now"
        elif $s < 3600 then "\($s / 60 | floor)m ago"
        elif $s < 86400 then "\($s / 3600 | floor)h ago"
        elif $s < 604800 then "\($s / 86400 | floor)d ago"
        elif $s < 2592000 then "\($s / 604800 | floor)w ago"
        elif $s < 31536000 then "\($s / 2592000 | floor)mo ago"
        else "\($s / 31536000 | floor)y ago" end
      end;
    def summary($branches):
      if ($branches | length) == 0 then ""
      elif ($branches | length) == 1 then $branches[0]
      else "\($branches[0])...\($branches[-1])" end;
    def remote_status($prs):
      [($prs | map(select(merged)) | length),
       ($prs | map(select((merged | not) and .state == "open")) | length),
       ($prs | map(select((merged | not) and .state == "closed")) | length), 0];
    def local_status($stack; $match):
      reduce ($stack.branches[]?) as $branch ([0,0,0,0];
        if $branch.pullRequest == null then .[3] += 1
        else ($match.pull_requests // [] | map(select(.number == $branch.pullRequest.number)) | first) as $pr
        | if $pr != null then
            if ($pr | merged) then .[0] += 1
            elif $pr.state == "closed" then .[2] += 1
            else .[1] += 1 end
          elif ($branch.pullRequest.merged // false) then .[0] += 1
          else .[1] += 1 end
        end);
    def remote_match($stack):
      $remote | map(select(
        (($stack.number // 0) != 0 and .number == $stack.number) or
        (($stack.id // "") != "" and (.id | tostring) == $stack.id)
      )) | first;
    def local_row($stack):
      remote_match($stack) as $match
      | [$stack.branches[]?.branch] as $branches
      | local_status($stack; $match) as $status
      | select(($status[1] + $status[2] + $status[3]) > 0)
      | (($stack.branches | reverse | map(select((.pullRequest.merged // false) | not)) | first).branch // $branches[-1]) as $target
      | [($match.number // $stack.number // 0), summary($branches),
         ($match.base.ref // $stack.trunk.branch // ""), $status[], "Local",
         (($match.created_at // null) | age), $target, ($branches | join("\u001f"))];
    def remote_row($stack):
      [$stack.pull_requests[]?.head.ref] as $branches
      | remote_status($stack.pull_requests // []) as $status
      | select(($branches | length) > 0 and ($status[1] + $status[2] + $status[3]) > 0)
      | [$stack.number, summary($branches), ($stack.base.ref // ""), $status[], "Remote",
         (($stack.created_at // null) | age), ($stack.number | tostring), ($branches | join("\u001f"))];
    [($local.stacks[]? | local_row(.)),
     ($remote[]? as $r
       | select(any($local.stacks[]?;
           (((.number // 0) != 0 and .number == $r.number) or
            ((.id // "") != "" and .id == ($r.id | tostring)))) | not)
       | remote_row($r))]
    | sort_by(if .[0] == 0 then -2147483648 else -.[0] end)
    | .[] | @tsv
  ')" || return 1

  printf -v search_padding '%*s' 512 ''
  while IFS=$'\t' read -r number summary base merged open closed unpushed type created target branches; do
    [[ -z $target ]] && continue
    [[ $number == 0 ]] && number='—'
    summary="$(truncate_checkout_cell "$summary" 42)"
    base="$(truncate_checkout_cell "$base" 18)"
    status_bar="$(checkout_status_bar "$merged" "$open" "$closed" "$unpushed")"
    printf -v display '%-5s %-42s %-18s %s  %-6s %-10s' "$number" "$summary" "$base" "$status_bar" "$type" "$created"
    display+="${search_padding}${branches//$'\x1f'/ }"
    printf '%s\t%s\t%s\t%s\t%s\n' "$display" "$target" "$base" "$branches" "$type"
  done <<<"$raw"
}

checkout_column_header='      #     Branches                                   Base               Status Type   Created'

if [[ ${1:-} == __checkout-rows ]]; then
  load_checkout_rows
  exit $?
fi

if [[ ${1:-} == __checkout-preview ]]; then
  query=${4:-}
  typeset -a preview_branches matched_branches
  preview_branches=("${(@f)$(print -rn -- "${3:-}" | tr '\037' '\n')}")
  if [[ -n $query ]]; then
    matched_branches=("${(@f)$(printf '%s\n' "${preview_branches[@]}" | fzf --exact --filter="$query")}")
  fi

  print -r -- "(${2:-})"
  for branch in "${preview_branches[@]}"; do
    print -r -- '  ↑'
    if (( ${matched_branches[(Ie)$branch]} )); then
      printf '\033[1;33m%s\033[0m\n' "$branch"
    else
      print -r -- "$branch"
    fi
  done
  exit 0
fi

if [[ ${1:-} == __checkout-filter ]]; then
  mode=${2:-All}
  printf '%s\n' "$checkout_column_header"
  while IFS=$'\t' read -r display target base branches type; do
    [[ $mode == All || $type == $mode ]] && printf '%s\t%s\t%s\t%s\t%s\n' "$display" "$target" "$base" "$branches" "$type"
  done <"${3:-/dev/null}"
  exit 0
fi

if [[ ${1:-} == __checkout-toggle ]]; then
  mode=${2:-All}
  [[ ${FZF_BORDER_LABEL:-All} == $mode ]] && mode=All
  printf 'reload(%s __checkout-filter %s %s)+change-border-label(%s)\n' \
    "${(q)script_dir}/gs.sh" "$mode" "${(q)3}" "$mode"
  exit 0
fi

if [[ ${1:-} == checkout ]]; then
  checkout_rows_file="$(mktemp)" || exit 1
  if ! run_function_with_spinner 'Loading stacks' load_checkout_rows >"$checkout_rows_file"; then
    command rm -f "$checkout_rows_file"
    exit 1
  fi
  if [[ ! -s $checkout_rows_file ]]; then
    command rm -f "$checkout_rows_file"
    print -r -- 'No stacks available to check out'
    exit 0
  fi
  trap 'command rm -f "$checkout_rows_file"; cancel' INT TERM HUP
  checkout_header='NORMAL | Enter/c checkout | i search | j/k navigate | l local | r remote | q quit'
  checkout_insert_header='INSERT | Esc normal | Enter checkout'

  selection="$("$script_dir/gs.sh" __checkout-filter All "$checkout_rows_file" | fzf \
    "${tmux_fzf_bindings[@]}" \
    --ansi \
    --border \
    --border-label='All' \
    --cycle \
    --delimiter=$'\t' \
    --disabled \
    --exact \
    --header="$checkout_header" \
    --header-lines=1 \
    --no-input \
    --bind='double-click:ignore' \
    --bind="alt-i:show-input+enable-search+change-prompt(INSERT> )+change-header($checkout_insert_header)" \
    --bind="esc:disable-search+hide-input+change-header($checkout_header)" \
    --bind='enter:accept' \
    --bind='i:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-i)" || echo put)' \
    --bind='j:transform([ "$FZF_INPUT_STATE" != enabled ] && echo down || echo put)' \
    --bind='k:transform([ "$FZF_INPUT_STATE" != enabled ] && echo up || echo put)' \
    --bind='l:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-l)" || echo put)' \
    --bind='r:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-r)" || echo put)' \
    --bind='c:transform([ "$FZF_INPUT_STATE" != enabled ] && echo accept || echo put)' \
    --bind='q:transform([ "$FZF_INPUT_STATE" != enabled ] && echo abort || echo put)' \
    --bind="alt-l:transform(${(q)script_dir}/gs.sh __checkout-toggle Local ${(q)checkout_rows_file})" \
    --bind="alt-r:transform(${(q)script_dir}/gs.sh __checkout-toggle Remote ${(q)checkout_rows_file})" \
    --no-hscroll \
    --no-multi \
    --no-sort \
    --preview="${(q)script_dir}/gs.sh __checkout-preview {3} {4} {q}" \
    --preview-window='up,70%,wrap' \
    --with-nth=1)"
  result=$?
  command rm -f "$checkout_rows_file"
  (( result != 0 )) && exit 0

  target=${${selection#*$'\t'}%%$'\t'*}
  [[ -z $target ]] && exit 0
  run_with_spinner "Checking out stack" gh stack checkout "$target"
  exit $?
fi

message=''
typeset -a rows
printf -v column_header '     %-7s %-10s %-4s %-4s %-4s %-48s %s' 'PR' 'status' '[ap]' '[ci]' '[co]' 'title' 'branch'

view_header() {
  local target=${1:--}
  local input_state=${2:-disabled}
  local review_status=${3:--}
  local notice=${4:-}

  if [[ $input_state == enabled ]]; then
    printf 'INSERT | Esc normal'
    return
  fi

  printf 'NORMAL | Enter/c checkout | i search | u update\n'
  printf 'r ready | d draft | '
  case $review_status in
    APPROVED) printf '\033[32m✓ a approved\033[0m' ;;
    CHANGES_REQUESTED) printf '\033[31m✗ a rejected\033[0m' ;;
    *) printf '\033[33m◌ a approve\033[0m' ;;
  esac
  printf ' | m merge stack\n'
  printf 'y yank | v view web | '
  if [[ $target == - ]]; then
    printf '\033[90mt tuicr\033[0m'
  else
    printf 't tuicr'
  fi
  printf ' | q quit'
  [[ -n $notice ]] && printf '\n%s' "$notice"
}

if [[ ${1:-} == __view-header ]]; then
  view_header "${2:--}" "${3:-disabled}" "${4:--}" "${5:-}"
  exit 0
fi

load_rows() {
  local stack_json first_url repo_path repo owner name graphql response prs_json
  local branch number url current title state draft decision merge_state approved ci_state comments
  local dot pr_status marker display approved_dot ci_dot comments_dot approved_cell ci_cell comments_cell
  local downstack_blocked=false

  if ! stack_json="$(run_with_timeout 20 gh stack view --json)"; then
    print -u2 -r -- 'gs view: loading the stack failed or timed out'
    return 1
  fi

  first_url="$(jq -r '[.branches[].pr.url // empty] | first // ""' <<<"$stack_json")" || return 1
  prs_json='[]'

  if [[ -n $first_url ]]; then
    repo_path=${first_url#*://*/}
    repo=${repo_path%/pull/*}
    owner=${repo%%/*}
    name=${repo#*/}
    graphql='query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) {'

    for number in "${(@f)$(jq -r '.branches[].pr.number // empty' <<<"$stack_json")}"; do
      graphql+=" pr${number}: pullRequest(number: ${number}) { number url title state isDraft reviewDecision mergeStateStatus latestReviews(first: 100) { nodes { state } } commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } reviewThreads(first: 100) { nodes { isResolved } pageInfo { hasNextPage } } }"
    done
    graphql+=' } }'

    if ! response="$(run_with_timeout 20 gh api graphql -f query="$graphql" -F owner="$owner" -F name="$name")" || \
      ! prs_json="$(jq '[.data.repository[] | select(. != null)]' <<<"$response")"; then
      print -u2 -r -- 'gs view: unable to load pull requests'
      return 1
    fi
  fi

  rows=()
  while IFS=$'\x1f' read -r branch number url current title state draft decision merge_state approved ci_state comments; do
    marker=' '
    [[ $current == true ]] && marker='*'
    [[ -z $title ]] && title=$branch

    if [[ -z $url ]]; then
      printf -v display '%s ·  %-7s %-10s %s %s %s %-48s %s' "$marker" '-' 'no PR' ' 🔴 ' ' 🔴 ' ' 🔴 ' "$title" "$branch"
      rows+=("${display}"$'\t-\tNONE\tfalse\t-\t'"${branch}"$'\tNONE')
      continue
    fi

    [[ $approved == true ]] && approved_dot='🟢' || approved_dot='🔴'
    case $ci_state in
      SUCCESS) ci_dot='🟢' ;;
      PENDING|EXPECTED) ci_dot='🟡' ;;
      *) ci_dot='🔴' ;;
    esac
    [[ $comments == true ]] && comments_dot='🟢' || comments_dot='🔴'
    approved_cell=" ${approved_dot} "
    ci_cell=" ${ci_dot} "
    comments_cell=" ${comments_dot} "

    if [[ $state == MERGED ]]; then
      dot='🟣'
      pr_status='merged'
    elif [[ $draft == true ]]; then
      dot='⚪'
      pr_status='draft'
    elif [[ $decision == CHANGES_REQUESTED ]]; then
      dot='🟠'
      pr_status='changes'
    elif [[ $merge_state == BLOCKED ]]; then
      dot='🟡'
      pr_status='blocked'
    elif [[ $downstack_blocked == true ]]; then
      dot='🔴'
      pr_status='downstream'
    elif [[ $merge_state == CLEAN ]]; then
      dot='🟢'
      pr_status='ready'
    else
      dot='🔵'
      pr_status='pending'
    fi
    [[ $merge_state == BLOCKED ]] && downstack_blocked=true

    printf -v display '%s %s #%-6s %-10s %s %s %s %-48s %s' "$marker" "$dot" "$number" "$pr_status" "$approved_cell" "$ci_cell" "$comments_cell" "$title" "$branch"
    rows+=("${display}"$'\t'"${url}"$'\t'"${state}"$'\t'"${draft}"$'\t'"${number}"$'\t'"${branch}"$'\t'"${decision}")
  done < <(jq -nr --argjson stack "$stack_json" --argjson prs "$prs_json" '
    $stack.branches[]
    | (.pr.url // "") as $url
    | ($prs | map(select(.url == $url)) | first) as $pr
    | [
        .name,
        (.pr.number // ""),
        $url,
        (.isCurrent // false),
        ($pr.title // ""),
        ($pr.state // .pr.state // ""),
        ($pr.isDraft // false),
        ($pr.reviewDecision // "-"),
        ($pr.mergeStateStatus // "-"),
        (($pr.reviewDecision // ([ $pr.latestReviews.nodes[]?.state | select(. == "APPROVED") ] | if length > 0 then "APPROVED" else "" end)) == "APPROVED"),
        ($pr.commits.nodes[-1].commit.statusCheckRollup.state // "-"),
        (([$pr.reviewThreads.nodes[]? | select(.isResolved == false)] | length) == 0
          and (($pr.reviewThreads.pageInfo.hasNextPage // false) == false))
      ]
    | join("\u001f")
  ')

  if (( ${#rows} == 0 )); then
    print -u2 -r -- 'gs view: the current stack has no branches'
    return 1
  fi
}

if [[ ${1:-} == __rows ]]; then
  load_rows || exit 1
  printf '%s\n' "$column_header" "${rows[@]}"
  exit 0
fi

if [[ ${1:-} == __fzf-action ]]; then
  run_fzf_action "${2:-}" "${3:-}"
  exit $?
fi

while true; do
  run_function_with_spinner 'Loading stack' load_rows || exit 1

  first_url=${${rows[1]#*$'\t'}%%$'\t'*}
  first_review_status=${rows[1]##*$'\t'}
  notice=$message
  normal_header="$(view_header "$first_url" disabled "$first_review_status" "$notice")"
  insert_header='INSERT | Esc normal'
  message=''

  selection="$(printf '%s\n' "$column_header" "${rows[@]}" | fzf \
    "${tmux_fzf_bindings[@]}" \
    --ansi \
    --border \
    --cycle \
    --delimiter=$'\t' \
    --disabled \
    --header="$normal_header" \
    --header-lines=1 \
    --listen=0 \
    --no-input \
    --bind='double-click:ignore' \
    --bind="alt-i:show-input+enable-search+change-prompt(INSERT> )+change-header($insert_header)" \
    --bind="esc:disable-search+hide-input+transform-header(${(q)script_dir}/gs.sh __view-header {2} disabled {7} ${(q)notice})" \
    --bind="focus:transform-header(${(q)script_dir}/gs.sh __view-header {2} \"\$FZF_INPUT_STATE\" {7} ${(q)notice})" \
    --bind='enter:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-c)" || echo ignore)' \
    --bind='i:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-i)" || echo put)' \
    --bind='j:transform([ "$FZF_INPUT_STATE" != enabled ] && echo down || echo put)' \
    --bind='k:transform([ "$FZF_INPUT_STATE" != enabled ] && echo up || echo put)' \
    --bind='c:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-c)" || echo put)' \
    --bind='r:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-r)" || echo put)' \
    --bind='d:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-d)" || echo put)' \
    --bind='a:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-a)" || echo put)' \
    --bind='u:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-u)" || echo put)' \
    --bind='m:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-m)" || echo put)' \
    --bind='y:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-y)" || echo put)' \
    --bind='v:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-v)" || echo put)' \
    --bind='t:transform(if [ "$FZF_INPUT_STATE" = enabled ]; then echo put; elif [ {2} = - ]; then echo ignore; else echo "trigger(alt-t)"; fi)' \
    --bind='q:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-q)" || echo put)' \
    --bind='alt-c:print(c)+accept,alt-m:print(m)+accept,alt-t:print(t)+accept,alt-q:abort' \
    --bind="alt-r:execute-silent(${(q)script_dir}/gs.sh __fzf-action ready {2} </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-d:execute-silent(${(q)script_dir}/gs.sh __fzf-action draft {2} </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-a:execute-silent(${(q)script_dir}/gs.sh __fzf-action approve {2} </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-u:execute-silent(${(q)script_dir}/gs.sh __fzf-action refresh </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-v:execute-silent(${(q)script_dir}/gs.sh __fzf-action view {2} </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-y:execute-silent(${(q)script_dir}/gs.sh __fzf-action yank </dev/null >/dev/null 2>&1 &)" \
    --id-nth=6 \
    --no-multi \
    --no-sort \
    --preview='url={2}; [ -n "$url" ] && gh pr view "$url"' \
    --preview-window='up,60%,wrap' \
    --track \
    --with-nth=1)" || exit 0

  key=${selection%%$'\n'*}
  row=${selection#*$'\n'}
  [[ $selection == "$key" ]] && row=''

  if [[ -z $row ]]; then
    message='Select a pull request first'
    continue
  fi

  IFS=$'\t' read -r display url state draft number branch review_status <<<"$row"

  if [[ $key == c ]]; then
    if run_with_spinner "Checking out ${branch}" gh stack checkout "$branch"; then
      exit 0
    fi
    message="Unable to check out ${branch}"
    continue
  fi

  if [[ $url == - ]]; then
    message='The selected branch does not have a pull request'
    continue
  fi

  case $key in
    t)
      if ! command -v tuicr >/dev/null 2>&1; then
        message='tuicr is required to open pull requests'
        continue
      fi
      run_tuicr "$number"
      ;;
    m)
      if [[ $state != OPEN ]]; then
        message='Only open pull requests can be merged'
        continue
      fi

      print -n -r -- "Atomically squash merge the stack through #${number}? [y/N] " >/dev/tty
      if read -q </dev/tty; then
        print >/dev/tty
        if run_with_spinner "Merging stack through #${number}" gh stack merge "$number" --yes --squash; then
          message="Stack merged through #${number}"
        else
          message='Unable to merge stack'
        fi
      else
        print >/dev/tty
        message='Merge cancelled'
      fi
      ;;
  esac
done

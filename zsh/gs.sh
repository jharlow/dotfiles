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
    view) run_with_timeout 30 gh pr view "$target" --web >"$output_file" 2>&1 ;;
    yank) run_with_timeout 60 "$script_dir/prl.sh" >"$output_file" 2>&1 ;;
    refresh) run_with_timeout 30 "$script_dir/gs.sh" __rows >"$output_file" 2>&1 ;;
  esac
  result=$?

  if (( result == 0 )) && [[ $action == refresh ]]; then
    rows_file=$output_file
  elif (( result == 0 )) && [[ $action == ready || $action == draft ]]; then
    rows_file="$(mktemp)" || result=1
    if (( result == 0 )); then
      "$script_dir/gs.sh" __rows >"$rows_file" 2>>"$output_file" || result=$?
    fi
  fi

  kill "$spinner_pid" 2>/dev/null
  wait "$spinner_pid" 2>/dev/null
  active_spinner_pid=''

  if (( result == 0 )); then
    if [[ $action == ready || $action == draft || $action == refresh ]]; then
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
  r) set -- rebase "${@:2}" ;;
  a) set -- add "${@:2}" ;;
  i) set -- init "${@:2}" ;;
  su) set -- submit "${@:2}" ;;
  sy) set -- sync "${@:2}" ;;
  p) set -- push "${@:2}" ;;
  b) set -- bottom "${@:2}" ;;
  t) set -- top "${@:2}" ;;
  u) set -- up "${@:2}" ;;
  d) set -- down "${@:2}" ;;
esac

if [[ ${1:-} != view && ${1:-} != __fzf-action && ${1:-} != __rows ]] || \
  [[ ${1:-} == view && $# -ne 1 ]]; then
  exec gh stack "$@"
fi

for dependency in gh jq fzf curl perl; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print -u2 -r -- "gs view: $dependency is required"
    exit 1
  fi
done

export GH_PROMPT_DISABLED=1

message=''
typeset -a rows
printf -v column_header '     %-7s %-10s %-4s %-4s %-4s %-48s %s' 'PR' 'status' '[ap]' '[ci]' '[co]' 'title' 'branch'

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
      graphql+=" pr${number}: pullRequest(number: ${number}) { number url title state isDraft reviewDecision mergeStateStatus commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } reviewThreads(first: 100) { nodes { isResolved } pageInfo { hasNextPage } } }"
    done
    graphql+=' } }'

    if ! response="$(run_with_timeout 20 gh api graphql -f query="$graphql" -F owner="$owner" -F name="$name")" || \
      ! prs_json="$(jq '[.data.repository[] | select(. != null)]' <<<"$response")"; then
      print -u2 -r -- 'gs view: unable to load pull requests'
      return 1
    fi
  fi

  rows=()
  while IFS=$'\t' read -r branch number url current title state draft decision merge_state approved ci_state comments; do
    marker=' '
    [[ $current == true ]] && marker='*'

    if [[ -z $url ]]; then
      printf -v display '%s ·  %-7s %-10s %s %s %s %-48s %s' "$marker" '-' 'no PR' ' 🔴 ' ' 🔴 ' ' 🔴 ' '' "$branch"
      rows+=("${display}"$'\t-\tNONE\tfalse\t-\t'"${branch}")
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
    rows+=("${display}"$'\t'"${url}"$'\t'"${state}"$'\t'"${draft}"$'\t'"${number}"$'\t'"${branch}")
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
        (($pr.reviewDecision // "") == "APPROVED"),
        ($pr.commits.nodes[-1].commit.statusCheckRollup.state // "-"),
        (([$pr.reviewThreads.nodes[]? | select(.isResolved == false)] | length) == 0
          and (($pr.reviewThreads.pageInfo.hasNextPage // false) == false))
      ]
    | @tsv
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

  normal_header='NORMAL | Enter/c checkout | i search | u update'
  normal_header+=$'\n''r ready | d draft | m merge stack'
  normal_header+=$'\n''y yank | v view web | q quit'
  [[ -n $message ]] && normal_header+=$'\n'"$message"
  insert_header='INSERT | Esc normal'
  message=''

  selection="$(printf '%s\n' "$column_header" "${rows[@]}" | fzf \
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
    --bind="esc:disable-search+hide-input+change-header($normal_header)" \
    --bind='enter:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-c)" || echo ignore)' \
    --bind='i:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-i)" || echo put)' \
    --bind='j:transform([ "$FZF_INPUT_STATE" != enabled ] && echo down || echo put)' \
    --bind='k:transform([ "$FZF_INPUT_STATE" != enabled ] && echo up || echo put)' \
    --bind='c:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-c)" || echo put)' \
    --bind='r:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-r)" || echo put)' \
    --bind='d:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-d)" || echo put)' \
    --bind='u:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-u)" || echo put)' \
    --bind='m:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-m)" || echo put)' \
    --bind='y:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-y)" || echo put)' \
    --bind='v:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-v)" || echo put)' \
    --bind='q:transform([ "$FZF_INPUT_STATE" != enabled ] && echo "trigger(alt-q)" || echo put)' \
    --bind='alt-c:print(c)+accept,alt-m:print(m)+accept,alt-q:abort' \
    --bind="alt-r:execute-silent(${(q)script_dir}/gs.sh __fzf-action ready {2} </dev/null >/dev/null 2>&1 &)" \
    --bind="alt-d:execute-silent(${(q)script_dir}/gs.sh __fzf-action draft {2} </dev/null >/dev/null 2>&1 &)" \
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

  IFS=$'\t' read -r display url state draft number branch <<<"$row"

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

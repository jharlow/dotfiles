#!/usr/bin/env zsh

setopt pipefail

usage() {
  print -r -- "Usage: prl [-m|--markdown]"
}

copy_to_clipboard() {
  local plain_text=$1
  local html=$2

  osascript -l JavaScript -e '
ObjC.import("AppKit");

function run(argv) {
  const plainText = argv[0];
  const html = argv[1];
  const htmlData = $(html).dataUsingEncoding($.NSUTF8StringEncoding);
  const attributed = $.NSAttributedString.alloc.initWithHTMLDocumentAttributes(htmlData, Ref());
  const rtf = attributed.RTFFromRangeDocumentAttributes($.NSMakeRange(0, attributed.length), Ref());
  const pasteboard = $.NSPasteboard.generalPasteboard;

  pasteboard.clearContents;
  pasteboard.setStringForType($(plainText), $.NSPasteboardTypeString);
  pasteboard.setStringForType($(html), $.NSPasteboardTypeHTML);
  pasteboard.setDataForType(rtf, $.NSPasteboardTypeRTF);
}
' "$plain_text" "$html"
}

format=slack
case "${1:-}" in
  '') ;;
  -m|--markdown) format=markdown ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

for dependency in gh jq osascript; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    print -u2 -r -- "prl: $dependency is required"
    exit 1
  fi
done

if ! stack_json="$(gh stack view --json)"; then
  print -u2 -r -- "prl: unable to read the current gh stack"
  exit 1
fi

if ! stack_prs="$(jq -r '
  .branches[]
  | select(.pr != null)
  | [.pr.number, .pr.url]
  | @tsv
' <<<"$stack_json")"; then
  print -u2 -r -- "prl: unable to parse gh stack output"
  exit 1
fi

if [[ -z $stack_prs ]]; then
  print -u2 -r -- "prl: no pull requests found in the current stack"
  exit 1
fi

typeset -a pr_numbers pr_urls pr_repos pr_titles pr_states pr_drafts pr_decisions pr_merge_states pr_additions pr_deletions

while IFS=$'\t' read -r number url; do
  [[ -z $number || -z $url ]] && continue

  if [[ $url != */pull/* ]]; then
    print -u2 -r -- "prl: unsupported pull request URL: $url"
    exit 1
  fi

  repo_path="${url#*://*/}"
  repo="${repo_path%/pull/*}"
  if [[ -z $repo || $repo == "$repo_path" ]]; then
    print -u2 -r -- "prl: unable to determine repository from: $url"
    exit 1
  fi

  if ! pr_json="$(gh pr view "$url" --json title,state,isDraft,reviewDecision,mergeStateStatus,additions,deletions)"; then
    print -u2 -r -- "prl: unable to read pull request: $url"
    exit 1
  fi

  if ! title="$(jq -r '.title' <<<"$pr_json")" || \
    ! state="$(jq -r '.state' <<<"$pr_json")" || \
    ! draft="$(jq -r '.isDraft' <<<"$pr_json")" || \
    ! decision="$(jq -r '.reviewDecision // ""' <<<"$pr_json")" || \
    ! merge_state="$(jq -r '.mergeStateStatus // ""' <<<"$pr_json")" || \
    ! additions="$(jq -r '.additions // 0' <<<"$pr_json")" || \
    ! deletions="$(jq -r '.deletions // 0' <<<"$pr_json")"; then
    print -u2 -r -- "prl: unable to parse pull request: $url"
    exit 1
  fi

  pr_numbers+=("$number")
  pr_urls+=("$url")
  pr_repos+=("$repo")
  pr_titles+=("$title")
  pr_states+=("$state")
  pr_drafts+=("$draft")
  pr_decisions+=("$decision")
  pr_merge_states+=("$merge_state")
  pr_additions+=("$additions")
  pr_deletions+=("$deletions")
done <<< "$stack_prs"

if (( ${#pr_numbers} == 0 )); then
  print -u2 -r -- "prl: no pull requests found in the current stack"
  exit 1
fi

all_same_repo=true
for repo in "${pr_repos[@]}"; do
  if [[ "$repo" != "${pr_repos[1]}" ]]; then
    all_same_repo=false
    break
  fi
done

output=''
html_output='<!doctype html><html><body>'
for ((index = 1; index <= ${#pr_numbers}; index++)); do
  number="${pr_numbers[index]}"
  url="${pr_urls[index]}"
  repo="${pr_repos[index]}"
  title="${pr_titles[index]}"
  state="${pr_states[index]}"
  draft="${pr_drafts[index]}"
  decision="${pr_decisions[index]}"
  merge_state="${pr_merge_states[index]}"
  additions="${pr_additions[index]}"
  deletions="${pr_deletions[index]}"

  if [[ $state == MERGED ]]; then
    emoji='🟣'
    shortcode=':large_purple_circle:'
  elif [[ $draft == true ]]; then
    emoji='⚪'
    shortcode=':white_circle:'
  elif [[ $decision == CHANGES_REQUESTED ]]; then
    emoji='🟠'
    shortcode=':large_orange_circle:'
  elif [[ $decision == APPROVED || $merge_state == CLEAN ]]; then
    emoji='🟢'
    shortcode=':large_green_circle:'
  else
    emoji='🔵'
    shortcode=':large_blue_circle:'
  fi

  if [[ $all_same_repo == true ]]; then
    label="#${number} ${title}"
  else
    label="${repo}#${number} ${title}"
  fi

  markdown_label=${label//\\/\\\\}
  markdown_label=${markdown_label//\[/\\[}
  markdown_label=${markdown_label//\]/\\]}
  diff_stat="\`+${additions}/-${deletions}\`"
  if [[ $format == slack ]]; then
    output+="${shortcode} [${markdown_label}](${url}) ${diff_stat}"$'\n'
  else
    output+="${emoji} [${markdown_label}](${url}) ${diff_stat}"$'\n'
  fi

  html_label=${label//&/\&amp;}
  html_label=${html_label//</\&lt;}
  html_label=${html_label//>/\&gt;}
  html_url=${url//&/\&amp;}
  html_url=${html_url//\"/\&quot;}
  html_output+="${emoji} <a href=\"${html_url}\">${html_label}</a> <code>+${additions}/-${deletions}</code><br>"
done

html_output+='</body></html>'

if ! copy_to_clipboard "$output" "$html_output"; then
  print -u2 -r -- "prl: unable to copy links to the clipboard"
  exit 1
fi

print -rn -- "$output"
print -u2 -r -- "prl: copied ${#pr_numbers} PR link(s) to the clipboard"

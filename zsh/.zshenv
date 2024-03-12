. "$HOME/.cargo/env"

# Provides a list of commits in the current branch that are not in the base branch
# Removes anything except markdown bullet points
function git-changes-short {
  base_branch=$(gh pr view --json baseRefName --jq '.baseRefName' | tr -d '"')
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  revision_range="$base_branch..$current_branch"
  git log \
    --first-parent \
    --no-merges \
    --format=%B \
    $revision_range \
    | sed '/^[^-]/d;/^$/d' \
    | tail -r
}

# Provides a list of commits in the current branch that are not in the base branch
# Replaces JIRA ticket numbers with a markdown H3 tag
function git-changes-long {
  base_branch=$(gh pr view --json baseRefName --jq '.baseRefName' | tr -d '"')
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  revision_range="$base_branch..$current_branch"
  git log \
	  --first-parent \
	  --no-merges \
	  --format=%B \
	  --reverse \
	  $revision_range | 
	sed -E 's/[A-Z0-9]{2,4}-[0-9]{1,6}:/####/g'
}


# SECURE ENVS
# - Stored sectrets in dotfiles reference 1Password items however the actual values are pulled locally
# - This means you are not prompted for 1Password credentials when running `source ~/.zshrc` or `source ~/.zshenv`
# - The big benefit is that you do not need to give biometric auth every time you open a new terminal window
# - Add new exports in `secrets.zsh`

export DOTFILES_DIR="${HOME}/dotfiles"

# If zhs/secrets-out.zsh does not exist, create it.
secrets_path="${DOTFILES_DIR}/zsh/.secrets.zsh"
secrets_UNPROTECTED_path="${DOTFILES_DIR}/zsh/.secrets-UNPROTECTED.zsh"

if [ ! -f "$secrets_UNPROTECTED_path" ]; then
    echo "Creating ${secrets_UNPROTECTED_path}..."
    touch $secrets_UNPROTECTED_path
    op --account "my.1password.com" inject --in-file $secrets_path --out-file $secrets_UNPROTECTED_path
fi

# Check to see that if after removing everything to the right of `=` in
# zsh/secrets-in.zsh and zsh/secrets-out.zsh, the files are the same. If they
# are the same do nothing. If the are different create an updated version of
# zsh/secrets-out.zsh.
secrets_no_values=$(cat $secrets_path | sed 's/=.*//' | base64)
secrets_UNPROTECTED_no_values=$(cat $secrets_UNPROTECTED_path | sed 's/=.*//' | base64)

if [ ! "$secrets_in_no_values" = "$secrets_out_no_values" ]; then
    echo "Secrets have changed... updating ${secrets_UNPROTECTED_path}"
    rm $secrets_UNPROTECTED_path
    op --account "my.1password.com" inject --in-file $secrets_path --out-file $secrets_UNPROTECTED_path
fi

source $secrets_UNPROTECTED_path

# Convenience commmand to update secrets
alias update-secrets='[ -f $secrets_UNPROTECTED_path ] && rm $secrets_UNPROTECTED_path; op --account "my.1password.com" inject --in-file $secrets_path --out-file $secrets_UNPROTECTED_path && source $secrets_UNPROTECTED_path'

# FUNCTIONS
# Functions loaded in `zshenv` are available to all shells including Neovim
# (eg. `:r !git-changes-short` will not work if function is defined in `zshrc`)

function git-changes {
  base_branch=$(gh pr view --json baseRefName --jq '.baseRefName' | tr -d '"')
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  revision_range="$base_branch..$current_branch"
  git log \
    --first-parent \
    --no-merges \
    --format=%B \
    $revision_range | \
    sed -E 's/[A-Z0-9]{2,4}-[0-9]{1,6}://g' | \
    tail -r | \
    sed '/^$/d' |
    sed 's/^/* /'
}

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

# Provides a list of general TS PR diff lines breakdown to highlight minimal application code
function pr-diff-sum() {
  gh pr view --json files | jq -r "
    .files | 
    map({ path: .path, lines: (.additions + .deletions) }) | 
    reduce .[] as \$file ({}; 
      if \$file.path | contains(\"test/\") then 
        .testCode += \$file.lines 
      elif \$file.path == \"yarn.lock\" then 
        .yarnLock = \$file.lines 
      else 
        .appCode += \$file.lines 
      end
    ) | 
    \"> * \(.appCode // 0) lines of application code\n> * \(.testCode // 0) lines of test code\n> * \(.yarnLock // 0) lines of yarn.lock\"
  "
}

# $EDITOR
export EDITOR=nvim

## ALIASES
# Enable aliases to be sudo’ed
alias sudo="sudo "

# Navigation
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias -- -="cd -"
alias gitroot='cd $(git rev-parse --show-toplevel)'

# Shortcuts
alias ls="ls --color"
alias -- +x="chmod +x"
alias o="open"
alias oo="open ."
alias n="$EDITOR"
alias lg="lazygit"
alias cc="code ."

# Download file and save it with filename of remote file
alias get="curl -O -L"

## COMPLETIONS
# Load default completions
autoload -Uz compinit

# Caching autocompletion
# https://blog.callstack.io/supercharge-your-terminal-with-zsh-8b369d689770
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit -i
else
  compinit -C -i
fi

# Menu-like autocompletion selection
zmodload -i zsh/complist
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'l' vi-forward-char

# Automatically list choices on ambiguous completion
setopt auto_list
# Automatically use menu completion
setopt auto_menu
# Move cursor to end if word had one match
setopt always_to_end

# Select completions with arrow keys
zstyle ':completion:*' menu select
# Group results by category
zstyle ':completion:*' group-name ''
# Enable approximate matches for completion
zstyle ':completion:::::' completer _expand _complete _ignored _approximate
# Case and hyphen insensitive
zstyle ':completion:*' matcher-list 'm:{a-zA-Z-_}={A-Za-z_-}' 'r:|=*' 'l:|=* r:|=*'
# Use caching so that commands like apt and dpkg complete are useable
zstyle ':completion::complete:*' use-cache 1
zstyle ':completion::complete:*' cache-path $ZSH_CACHE_DIR

## PLUGINS
# Save command history to disk
HISTFILE=$HOME/.zsh_history
HISTSIZE=100000
SAVEHIST=$HISTSIZE
setopt appendhistory

# Zoxide
eval "$(zoxide init zsh)"

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Plugins
source ~/.zplug/init.zsh
zplug "jeffreytse/zsh-vi-mode"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-completions"
zplug "plugins/git", from:oh-my-zsh
zplug "plugins/aws", from:oh-my-zsh
zplug "sineto/web-search"
zplug "Aloxaf/fzf-tab"
zplug load

# Starship prompt
export STARSHIP_CONFIG=~/.starship.toml
eval "$(starship init zsh)"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm
export PNPM_HOME="/Users/johnharlow/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export GLOW_PATH="/Users/johnharlow/.local/bin/"
case ":$PATH:" in
  *":$GLOW_PATH:"*) ;;
  *) export PATH="$PATH:$GLOW_PATH" ;;
esac


### BENCH STUFF
alias watch-log="aws logs describe-log-groups | jq -r \".logGroups[] | .logGroupName | select(startswith(\\\"/aws/lambda/$FULL_NAME\\\"))\" | fzf | xargs -I _ aws logs tail _ --follow"
alias pr-diff-sum='gh pr view --json files | jq -r " .files | map({ path: .path, lines: (.additions + .deletions) }) | reduce .[] as \$file ({}; if \$file.path | contains(\"test/\") then .testCode += \$file.lines elif \$file.path == \"yarn.lock\" then .yarnLock = \$file.lines else .appCode += \$file.lines end) | \"* \(.appCode // 0) lines of application code\n* \(.testCode // 0) lines of test code\n* \(.yarnLock // 0) lines of yarn.lock\" "'

function legacy-stack-update() {
echo "Updating legacy-runtime..."
cd ${BENCH_SOURCE_DIR:-~/benchLabs}/bench-backend/src/apps/legacy-runtime
git pull
if [ $? -ne 0 ]; then
  echo "${RED}ERROR!${NC} Could not update legacy-runtime successfully, please check location and repository state"
  return 1
fi
echo "Running update script... "
ansible-playbook -i inventory.yaml update.yaml
if [ $? -ne 0 ]; then
  echo "${RED}ERROR!${NC} Please remediate errors in the output above and re-run the command"
  return 1
else
  echo "${GREEN}SUCCESS!${NC} Please give a few minutes for Bench software stack to start back up!"
fi
}

function go-cloud() {
AWS_SSO_OK=$(aws sts get-caller-identity | grep 'Account')

if [[ -z ${AWS_SSO_OK} ]] ; then
  aws sso login
fi

cd ${BENCH_SOURCE_DIR:-~/benchLabs}/bench-backend/src/apps/legacy-runtime
yawsso -d
}


# Export all the configuration variables from the ~/.bench.conf file
while read line;
do
  if [ ! -z "$line" ]; then
    eval "export $line" > /dev/null
  fi
done < $HOME/.bench.conf


function go-front() {
  if [ ! -e .nvmrc ]; then
    echo "Could not find .nvmrc file required for this to run. Verify you are in a front-end project folder"
    return 1
  fi

  nvm use
  if [ $? -eq 3 ]; then
    nvm install "$(cat .nvmrc)"
  fi

  npm list -g yarn
  if [ $? -eq 1 ]; then
    npm install -g yarn
  fi

  npm list -g husky
  if [ $? -eq 1 ]; then
    npm install -g husky
  fi

  if grep prepare package.json; then
    npm run prepare
  else
    husky install
  fi

  yarn install
}

# ASDF config
. "$HOME/.asdf/asdf.sh"
. "$HOME/.asdf/completions/asdf.bash"

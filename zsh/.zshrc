# Update 
export DOTFILES_DIR="${HOME}/dotfiles"
alias cellar="brew update &&
  brew bundle install --file=${DOTFILES_DIR}/brew/Brewfile &&\
  brew bundle cleanup --force --file=${DOTFILES_DIR}/brew/Brewfile &&\
  brew upgrade"

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
alias y="yes"
alias e="$EDITOR"
alias n="nvim"
alias lg="lazygit"
alias l="lazygit"
alias c="claude"
alias oc="opencode"
alias cl="clear"
alias cc="code ."
alias mux=tmuxinator

# Download file and save it with filename of remote file
alias get="curl -O -L"

# Github Cli shortcuts
alias gh="${DOTFILES_DIR}/zsh/gh.sh"
alias gs="${DOTFILES_DIR}/zsh/gs.sh"
alias cr="tuicr"

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

# fzf
source <(fzf --zsh)

# FZF
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Plugins
export ZPLUG_HOME=$HOMEBREW_PREFIX/opt/zplug
source $ZPLUG_HOME/init.zsh
zplug "jeffreytse/zsh-vi-mode"
zplug "zsh-users/zsh-autosuggestions"
zplug "zsh-users/zsh-syntax-highlighting"
zplug "zsh-users/zsh-completions"
zplug "plugins/git", from:oh-my-zsh
zplug "plugins/aws", from:oh-my-zsh
zplug "sineto/web-search"
zplug "Aloxaf/fzf-tab"
zplug load

# Override oh-my-zsh git plugin's `gr` (git remote) -> jump to repo root
alias gr='gitroot'

# Starship prompt
export STARSHIP_CONFIG=~/.starship.toml
# Suppress transient "command timed out" WARNs printed when tmux-continuum
# restores a session and many panes run git concurrently. Errors still show.
export STARSHIP_LOG=error
# Initialize starship *after* zsh-vi-mode finishes rebuilding ZLE. Calling
# `starship init` directly here causes zsh-vi-mode to re-wrap starship's
# zle-keymap-select widget, leading to infinite recursion
# ("maximum nested function level reached"). Deferring via zsh-vi-mode's
# post-init hook ensures starship wraps the widget exactly once.
zvm_after_init_commands+=('eval "$(starship init zsh)"')

# nvm (lazy-loaded). `node`/`npm` come from nodenv; nvm is only sourced on
# first explicit use to avoid its ~250ms startup cost (nvm_auto).
export NVM_DIR="$HOME/.nvm"
nvm() {
  unset -f nvm
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  nvm "$@"
}

# pnpm
export PNPM_HOME="/Users/johnharlow/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# rust
. "$HOME/.cargo/env"

# glow
export GLOW_PATH="/Users/johnharlow/.local/bin/"
case ":$PATH:" in
  *":$GLOW_PATH:"*) ;;
  *) export PATH="$PATH:$GLOW_PATH" ;;
esac

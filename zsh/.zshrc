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
zplug load

# Starship prompt
export STARSHIP_CONFIG=~/.starship.toml
eval "$(starship init zsh)"


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export GITHUB_TOKEN=$(eval "op read 'op://Personal/GitHub - Personal Access Token - Bench/token'")

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

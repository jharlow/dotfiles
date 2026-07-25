.PHONY: all
all: stow

.PHONY: stow
stow: create_directories
	@stow -t ~ tmux zsh git vim
	@stow -t ~/.config/tmuxinator tmuxinator
	@stow -t ~/.config/nvim nvim
	@stow -t ~/.config/git gitconfig
	@stow -t ~/.config/gh gh
	@stow -t ~/.config/ghostty ghostty
	@stow --no-folding -t ~/.config/opencode opencode
	@stow -t "$(HOME)/Library/Application Support/lazygit" lazygit
	@stow -t ~/.config/zed zed
	@stow -t ~/.agents agents
	@stow -t ~/.claude claude
	@$(MAKE) --no-print-directory link_agent_skills

# Point each coding agent's skill directory at the shared, dotfiles-managed
# ~/.agents/skills. Per-skill links preserve agent-owned directories.
.PHONY: link_agent_skills
link_agent_skills:
	@mkdir -p ~/.claude/skills
	@for skill in $(CURDIR)/agents/skills/*/; do \
		name=$$(basename $$skill); \
		ln -sfn ../../.agents/skills/$$name $(HOME)/.claude/skills/$$name; \
	done

# Apply the shared MCP declarations to both coding agents. This remains
# separate from `stow` because both CLIs maintain additional local state.
.PHONY: agent-mcp claude-mcp opencode-mcp
agent-mcp:
	@$(HOME)/dotfiles/agents/mcp/apply.sh all

claude-mcp:
	@$(HOME)/dotfiles/agents/mcp/apply.sh claude

opencode-mcp:
	@$(HOME)/dotfiles/agents/mcp/apply.sh opencode

.PHONY: unstow
unstow:
	@stow -D -t ~ tmux zsh git vim
	@stow -D -t ~/.config/tmuxinator tmuxinator
	@stow -D -t ~/.config/nvim nvim
	@stow -D -t ~/.config/git gitconfig
	@stow -D -t ~/.config/opencode opencode
	@stow -D -t ~/.config/zed zed
	@stow -D -t "$(HOME)/Library/Application Support/lazygit" lazygit
	@stow -D -t ~/.claude claude
	@for skill in $(CURDIR)/agents/skills/*/; do \
		name=$$(basename $$skill); \
		rm -f $(HOME)/.claude/skills/$$name; \
	done
	@stow -D -t ~/.agents agents

.PHONY: create_directories
create_directories:
	@mkdir -p ~/.config/tmuxinator
	@mkdir -p ~/.config/nvim
	@mkdir -p ~/.config/git
	@mkdir -p ~/.config/gh
	@mkdir -p ~/.config/ghostty
	@mkdir -p ~/.config/opencode
	@mkdir -p "$(HOME)/Library/Application Support/lazygit"
	@mkdir -p ~/.config/zed
	@mkdir -p ~/.claude
	@mkdir -p ~/.claude/skills
	@mkdir -p ~/.agents
	@mkdir -p ~/.vim

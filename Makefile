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
	@stow -t "$(HOME)/Library/Application Support/lazygit" lazygit
	@stow -t ~/.config/zed zed
	@stow -t ~/.agents agents
	@stow --no-folding --ignore='^plugins$$' -t ~/.config/opencode opencode
	@$(MAKE) --no-print-directory link_opencode_plugins
	@stow --no-folding -t ~/.pi/agent pi
	@stow -t ~/.claude claude
	@stow --no-folding -t ~/.agent-browser agent-browser
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

# OpenCode only discovers a global plugin whose directory is a real directory
# or a link to one, not a directory of per-file links, so link each plugin
# directory whole instead of letting stow unfold it.
.PHONY: link_opencode_plugins
link_opencode_plugins:
	@mkdir -p ~/.config/opencode/plugins
	@for plugin in $(CURDIR)/opencode/plugins/*/; do \
		target=$(HOME)/.config/opencode/plugins/$$(basename $$plugin); \
		if [ -d $$target ] && [ ! -L $$target ]; then \
			echo "skipping $$target: a real directory is in the way"; \
		else \
			ln -sfn $${plugin%/} $$target; \
		fi; \
	done

# Apply the shared MCP declarations to all coding agents. This remains
# separate from `stow` because the CLIs maintain additional local state.
# An empty servers.json clears the servers from every client.
.PHONY: agent-mcp claude-mcp opencode-mcp pi-mcp
agent-mcp:
	@$(HOME)/dotfiles/agents/mcp/apply.sh all

pi-mcp:
	@$(HOME)/dotfiles/agents/mcp/apply.sh pi

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
	@stow -D -t ~/.config/zed zed
	@stow -D -t "$(HOME)/Library/Application Support/lazygit" lazygit
	@stow --no-folding -D -t ~/.pi/agent pi
	@stow --no-folding --ignore='^plugins$$' -D -t ~/.config/opencode opencode
	@for plugin in $(CURDIR)/opencode/plugins/*/; do \
		rm -f $(HOME)/.config/opencode/plugins/$$(basename $$plugin); \
	done
	@stow -D -t ~/.claude claude
	@stow --no-folding -D -t ~/.agent-browser agent-browser
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
	@mkdir -p ~/.pi/agent
	@mkdir -p ~/.claude
	@mkdir -p ~/.claude/skills
	@mkdir -p ~/.agents
	@mkdir -p ~/.agent-browser
	@mkdir -p ~/.vim

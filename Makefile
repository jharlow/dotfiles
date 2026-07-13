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
	@stow -t ~/.claude claude
	@stow -t ~/.agents agents
	@$(MAKE) --no-print-directory link_claude_skills

# Point Claude Code's skill dir at the shared, dotfiles-managed ~/.agents/skills.
# Claude reads ~/.claude/skills/<name>; ~/.agents/skills is itself stowed to
# ~/dotfiles/agents/skills, so these links resolve into the repo.
.PHONY: link_claude_skills
link_claude_skills:
	@mkdir -p ~/.claude/skills
	@for skill in $(CURDIR)/agents/skills/*/; do \
		name=$$(basename $$skill); \
		ln -sfn ../../.agents/skills/$$name $(HOME)/.claude/skills/$$name; \
	done

# Apply user-scope MCP servers declared in claude/mcp/servers.json.
# Separate from `stow` because it needs the `claude` CLI and writes to
# ~/.claude.json (which can't be symlinked). Safe to re-run.
.PHONY: claude-mcp
claude-mcp:
	@$(HOME)/dotfiles/claude/mcp/apply.sh

.PHONY: unstow
unstow:
	@stow -D -t ~ tmux zsh git vim
	@stow -D -t ~/.config/tmuxinator tmuxinator
	@stow -D -t ~/.config/nvim nvim
	@stow -D -t ~/.config/git gitconfig
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
	@mkdir -p "$(HOME)/Library/Application Support/lazygit"
	@mkdir -p ~/.config/zed
	@mkdir -p ~/.claude
	@mkdir -p ~/.claude/skills
	@mkdir -p ~/.agents
	@mkdir -p ~/.vim

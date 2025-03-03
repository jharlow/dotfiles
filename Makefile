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

.PHONY: unstow
unstow:
	@stow -D -t ~ tmux zsh git vim
	@stow -D -t ~/.config/tmuxinator tmuxinator
	@stow -D -t ~/.config/nvim nvim
	@stow -D -t ~/.config/git gitconfig

.PHONY: create_directories
create_directories:
	@mkdir -p ~/.config/tmuxinator
	@mkdir -p ~/.config/nvim
	@mkdir -p ~/.config/git
	@mkdir -p ~/.config/gh
	@mkdir -p ~/.config/ghostty
	@mkdir -p ~/.vim

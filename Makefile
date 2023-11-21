.PHONY: all
all: stow

.PHONY: stow
stow:
	@stow -t ~ tmux zsh git
	@stow -t ~/.config/nvim nvim

.PHONY: unstow
unstow:
	@stow -D -t ~ tmux zsh git
	@stow -D -t ~/.config/nvim nvim

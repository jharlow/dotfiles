.PHONY: all
all: stow

.PHONY: stow
stow:
	@stow -t ~ tmux zsh git
	@stow -t ~/.config/nvim nvim
	@stow -t ~/.config/git gitconfig
	@source ~/.zshenv
	@source ~/.zshrc

.PHONY: unstow
unstow:
	@stow -D -t ~ tmux zsh git
	@stow -D -t ~/.config/nvim nvim
	@stow -D -t ~/.config/git gitconfig

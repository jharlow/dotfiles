# My dotfiles

## Setup apps & cli

This setup assumes you are using a Macbook.

### Install apps

```sh
bash ~/dotfiles/setup/apps
```

### Install cli tools

```sh
bash ~/dotfiles/setup/cli
```

### Install `zsh`

```sh
bash ~/dotfiles/setup/zsh
```

## Link dotfiles

This repo uses submodules to divide out TPM packages and my `nvim` config files. You'll need to ensure these submodules are recursively installed.

```sh
git submodule update --recursive --remote
```

Then run `make` to symlink your dotfiles to the root directory.

```sh
make
```

Don't forget to install your `zplug` and install `tmux` plugins (`prefix + I` aka `<CA> + <S-I>`) before `source ~/.zshrc`!

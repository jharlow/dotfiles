# `jharlow`'s dotfiles

## Overview

- Simple `zsh` configuration with plugins supplied via `zplug`
- Autoloading secrets secured by biometrics using 1Password
- Declarative package management using `Brewfile`
- `neovim` + `tmux` + `tmuxinator` setup for development
- Lightweight, highly customizable pattern for any other configuration

## Rationale

My aim is to make a lightweight, relatively unopinionated set of `dotfiles` that are targeted specifically to MacOS and should enable me to:

- Declaratively set as much of my system configuration as possible
- Go from a new machine to a development environment in ~15 mins

Most of this configuration is set via symlinks managed by Stow.

<details>
<summary><b>🤨 Why not <code>nix</code>?</b></summary>

I have played around with a `nix` config on my Mac. My conclusion from many, many hours of playing with it was that:

<ol>
    <li><code>Brewfile</code> offers a pretty good compromise between a system built specifically for Mac and declarative style</li>
    <li>It is a lot slower to push small changes to configuration through the machine using <code>nix</code>, whereas changes to symlinked files are available instantly</li>
</ol>

</details>

## Setup

> [!CAUTION]
> Following these steps will alter your machine's configuration. This repository was designed to be lightweight and easy to review. It is highly recommended that you understand what each command will do before executing them.

Some software in necessary to get started with these `dotfiles`, although the requirements are minimal.

- [Homebrew](https://brew.sh/)
- [Git (installable via `homebrew`)](https://git-scm.com/)

Once you have those installed, clone this repo:

```sh
# clone from home so you have a ~/dotfiles directory
cd ~
# I use ssh as the standard git protocol
git clone git@github.com:jharlow/dotfiles.git
```

### Install apps

You can install all the apps specified declaratively in `brew/Brewfile` by running the following command:

```sh
# note this assumes you are using the ~/dotfiles directory
brew update &&
  brew bundle install --cleanup --file=~/dotfiles/brew/Brewfile --no-lock &&
  brew upgrade
```

After the installation of these `dotfiles` is complete, this command will be aliased for you:

```sh
cellar
```

Finally, install Rust using [`rustup`](https://rustup.rs/).

### Get started with 1Password

I use [1Password](https://1password.com) to sign my Git commits and to securely access secrets in the terminal. You can see specifically how this is managed in `zsh/.zshenv` and `zsh/.secrets.zsh`.

To enable this to work, sign in to the 1Password app, and then go to `Settings` -> `Developer`. Check "Use the SSH agent" and "Integrate with the 1Password CLI". You should then be able to run `op whoami` to verify that the integration is working.

If you haven't set up SSH signing and secret access through 1Password before, check that `zsh/.secrets.zsh` points to valid secrets and that you have [set up SSH signing](https://developer.1password.com/docs/ssh/git-commit-signing/#step-1-configure-git-commit-signing-with-ssh).

### Push configuration changes

Once apps are installed, the `make` command should be available in the terminal. Before running it, make sure you pull in the linked git submodules:

```sh
git submodule update --init --recursive --remote
```

Once the submodules are up-to-date, you can now symlink the configuration files into their correct locations:

```sh
make
```

Finally, you need to source the `zsh` configuration files and install the shell's plugins:

```sh
source ~/.zshrc && source ~/.zshenv
```

```sh
zplug install
```

When you open `tmux` for the first time, you may need to install the `tpm` plugins as well using `prefix + I`.

### Manual configuration

There are some additional GUI applications that require manual configuration. All of them were installed in the "Install apps" step.

#### [Rectangle](https://rectangleapp.com/)

Rectangle is my window management app of choice. To configure it, open the app, provide it with the permissions it needs, and import the `rectangle/config.json` file at "Settings" -> "Import".

#### [Karabiner-Elements](https://karabiner-elements.pqrs.org/)

I use Karabiner-Elements to swap my caps lock and escape keys so that escape is closer to the home row when using `vim` bindings. To configure it, open the app, provide wit with the permissions it needs, and set the two swaps under "Simple Modifications" -> "For all devices".

#### [Ice](https://icemenubar.app/)

Ice provides a nicer menu bar and hides most of the icons in the menu until requested. After opening the app and providing it the permissions it needs, go to the settings.

Under "General", set:

- "Launch at login" to `enabled`
- "Menu bar item spacing" to `-4`

Under "Menu bar appearance", set:

- "Shape kind" to `split`

#### [Rocket Typist](https://witt-software.com/rockettypist/)

This is a paid app that I use for snippet macros, which saves me a lot of time when writing pull requests. To configure, open the app, enable the permissions it needs, and select:

- "Abbreviations" to `enabled`
- "Auto-paste" to `enabled`
- "Launch at login" to `enabled`

#### [Raycast](https://www.raycast.com/)

You've probably already heard of Raycast. Configuration is very well-streamlined, open the app and follow it's instructions.

## Usage

Mostly, usage should be intuitive and invisible. Because everything is symlinked, you should be able to make changes to the files in `~/dotfiles` and have those changes become instantly available (sometimes you may need to `source` them when using the same terminal instance).

If you update the `zsh/.secrets.zsh` file, or the secret values as stored in 1Password, you'll need to run `update-secrets`. Similarly, if you update the `brew/Brewfile` you'll need to run `cellar` for those changes to take effect.

Symlinks are declared in `Makefile`, which makes it easy to change the structure of the repository and/or add new configurations following this pattern.

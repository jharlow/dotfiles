# Installs GUI apps
# https://formulae.brew.sh/cask/

# Common stuff
RED="$(tput setaf 1)"
UNDERLINE="$(tput sgr 0 1)"
NOCOLOR="$(tput sgr0)"
function error() { echo -e "$UNDERLINE$RED$1$NOCOLOR\n"; }

# Check that Homebrew is installed
command -v brew >/dev/null 2>&1 || { error "Homebrew not installed: https://brew.sh/"; exit 1; }

brew install --cask 1password
brew install --cask devtoys
brew install --cask firefox
brew install --cask google-chrome
brew install --cask hiddenbar
brew install --cask iterm2
brew install --cask karabiner-elements
brew install --cask maccy
brew install --cask rectangle
brew install --cask rocket-typist
brew install --cask screen-studio
brew install --cask visual-studio-code
brew install --cask raycast

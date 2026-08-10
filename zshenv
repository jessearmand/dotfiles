. "$HOME/.cargo/env"

export PATH=$PATH:/usr/local/MacGPG2/bin
export ANDROID_HOME=~/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools

# ripgrep has no default config location: it reads ~/.ripgreprc only when this
# points at it. Lives in zshenv (not zshrc) so non-interactive shells get it too.
export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"


# ~/.zshrc: interactive zsh configuration.
#
# Load order. Each phase depends only on the phases above it:
#   1. Instant prompt    Powerlevel10k draws a cached prompt at once. Keep first.
#   2. Helpers           path/fpath dedup and the output cache used below.
#   3. Environment       Plain exports and the (cached) Homebrew environment.
#   4. PATH              One ordered list, highest precedence first.
#   5. Zinit             Plugin manager, theme, and fzf: what the first prompt needs.
#   6. Completion        fpath entries, generated completion scripts, compinit.
#   7. Turbo             Loads just after the first prompt: git helpers and
#                        syntax highlighting.
#   8. mise              Must stay last. See the note there.
#
# Shells without job control (`zsh -ic` from agent harnesses) skip everything
# that needs ZLE: the instant prompt, the theme and the fzf key bindings. Turbo
# plugins never load in `zsh -c` shells, because no prompt is ever drawn.

### 1. Powerlevel10k instant prompt ###########################################
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
# Skipped without job control: instant prompt needs `setopt monitor`, which
# fails there and takes gitstatus down with it.
if [[ -o monitor && -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

### 2. Helpers ################################################################
# Keep only the first occurrence of each entry. Prepending an entry that is
# already present therefore moves it to the front instead of duplicating it,
# and nested shells no longer grow PATH/fpath.
typeset -gU path fpath

typeset -g ZSHRC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

# .zshrc-cache <file> <source> <command...>
# Writes the output of <command> to <file> unless <file> is newer than
# <source>, the binary or script that produces it. It also regenerates when
# <source> resolves to a different path: this catches upgrades of symlinked
# binaries whose targets keep a fixed mtime (Nix store paths have mtime 1).
# Returns non-zero when <source> is missing or <command> fails.
.zshrc-cache() {
  local file=$1 src=$2 stamp="${1:h}/.${1:t}.source"
  shift 2
  [[ -n $src && -e $src ]] || return 1
  src=${src:A}
  [[ -s $file && $file -nt $src && -r $stamp && "$(<$stamp)" == "$src" ]] && return 0
  command mkdir -p -- "${file:h}" || return 1
  if "$@" >| "$file.$$" 2>/dev/null && [[ -s "$file.$$" ]]; then
    command mv -f -- "$file.$$" "$file" && print -r -- "$src" >| "$stamp"
  else
    command rm -f -- "$file.$$"
    return 1
  fi
}

# .zshrc-source-cached <name> <source> <command...>
# Replaces `eval "$(command)"` for init scripts whose output only changes
# when <source> changes.
.zshrc-source-cached() {
  local file="$ZSHRC_CACHE/init/$1.zsh"
  shift
  .zshrc-cache "$file" "$@" && source "$file"
}

### 3. Environment ############################################################
export LANG=en_US.UTF-8

export MATLAB_RUNTIME="/Applications/MATLAB/MATLAB_Runtime/v97"
export DYLD_LIBRARY_PATH="${MATLAB_RUNTIME}/runtime/maci64:${MATLAB_RUNTIME}/sys/os/maci64:${MATLAB_RUNTIME}/bin/maci64"

export PNPM_HOME="${HOME}/Library/pnpm"

### Alibaba cloud mirror for homebrew
# export HOMEBREW_API_DOMAIN=https://mirrors.aliyun.com/homebrew-bottles/api
# export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.aliyun.com/homebrew-bottles
# export HOMEBREW_BREW_GIT_REMOTE=https://mirrors.aliyun.com/homebrew/brew.git

# Homebrew sets HOMEBREW_*, MANPATH and INFOPATH, and puts its site-functions
# on fpath before compinit. `brew shellenv` costs ~25 ms, so its output is
# cached and regenerated only when brew's shellenv.sh changes. It runs with a
# minimal PATH because brew prints nothing when its dirs already lead PATH
# (nested shells), which would poison the cache.
.zshrc-source-cached brew-shellenv /opt/homebrew/Library/Homebrew/cmd/shellenv.sh \
  env PATH=/usr/bin:/bin:/usr/sbin:/sbin /opt/homebrew/bin/brew shellenv zsh

### 4. PATH ###################################################################
# The single place that decides command precedence, highest first. Because
# path is unique (phase 2), each directory lands exactly where it is listed,
# whatever /etc/zprofile's path_helper, ~/.zprofile, brew's path_helper call
# or a parent shell already put in PATH. When an installer appends a PATH line
# to this file, move the directory into this list instead.
#
# Two layers still go on top at runtime: zinit-managed programs (phase 5)
# and mise tools (phase 8).
path=(
  "${HOME}/.bend/bin"
  "${HOME}/.kimi-code/bin"
  "${HOME}/.opencode/bin"
  "${HOME}/.local/bin"                     # uv, mise, Antigravity CLI
  "${PNPM_HOME}/bin"
  "${HOME}/.deno/bin"
  "${HOME}/.nix-profile/bin"               # Nix beats Homebrew on overlap (git, ffmpeg)
  /nix/var/nix/profiles/default/bin
  "${HOMEBREW_PREFIX:-/opt/homebrew}/bin"
  "${HOMEBREW_PREFIX:-/opt/homebrew}/sbin"
  # Below Homebrew: tools with unique names that never need to override it.
  "${HOME}/Develop/google-cloud-sdk/bin"
  "${HOME}/go/bin"
  "${HOME}/.grok/bin"
  "${HOME}/.bun/bin"
  "${HOME}/.mint/bin"
  $path                                    # login PATH: /etc/paths, zshenv, ~/.zprofile
  "${HOME}/.cache/lm-studio/bin"           # LM Studio CLI (lms), lowest
)

### 5. Zinit and synchronous plugins ##########################################
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
  print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
  command mkdir -p "${ZINIT_HOME:h}" && command chmod g-rwX "${ZINIT_HOME:h}"
  command git clone https://github.com/zdharma-continuum/zinit "$ZINIT_HOME" && \
    print -P "%F{33} %F{34}Installation successful.%f%b" || \
    print -P "%F{160} The clone has failed.%f%b"
fi
source "$ZINIT_HOME/zinit.zsh"

# Terminal and prompt. Both are skipped where they do nothing: iTerm2's
# integration outside iTerm2, and the theme without job control (no prompt
# to render, and gitstatus/ZLE initialization would fail noisily).
if [[ $TERM_PROGRAM == iTerm.app || $LC_TERMINAL == iTerm2 ]] && [[ -r "${HOME}/.iterm2_shell_integration.zsh" ]]; then
  source "${HOME}/.iterm2_shell_integration.zsh"
fi
if [[ -o monitor ]]; then
  zinit depth"1" light-mode for romkatv/powerlevel10k
  # To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
  [[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh
fi

# fzf binary from GitHub releases. Its shell integration (Ctrl-T/Ctrl-R/Alt-C
# and `**<Tab>`) is cached and regenerated when `zinit update` replaces the
# binary. Not sourced without job control: the bindings need ZLE, and fzf's
# option save/restore fails noisily on the unsettable `zle` option.
zinit from"gh-r" as"program" light-mode for junegunn/fzf
[[ -o monitor ]] && .zshrc-source-cached fzf "${commands[fzf]}" fzf --zsh

### 6. Completion ############################################################
# compinit indexes every _file on fpath; each completion function loads on
# first use, which is cheaper than an eval of the script at startup.
fpath=(
  "$ZSHRC_CACHE/completions"               # generated below
  "${HOME}/.zsh/completions"               # deno
  "${HOME}/.grok/completions/zsh"          # after an upgrade: grok completions zsh > ~/.grok/completions/zsh/_grok
  $fpath                                   # incl. Homebrew site-functions and zinit's completions
)

# CLIs that print their completion script. Cached as fpath files and
# regenerated when the binary changes.
.zshrc-cache "$ZSHRC_CACHE/completions/_uv" "${commands[uv]}" uv generate-shell-completion zsh
.zshrc-cache "$ZSHRC_CACHE/completions/_uvx" "${commands[uvx]}" uvx --generate-shell-completion zsh

# compinit trusts the dump for a day. For 24 hours after a full check it runs
# with -C: no compaudit and no rescan of fpath. After that, one shell runs
# the full check, which rebuilds the dump if completion files were added or
# removed, and touches it to start the next day. A completion installed
# today can take up to a day to appear. `rm ~/.zcompdump` picks it up now.
#
# compinit stays synchronous, not in Turbo: mise's hook (phase 8) runs its own
# `compinit -i` when compdef is missing and registers tool completions such as
# fnox. A later compinit from Turbo would run a second time and reset them.
() {
  setopt localoptions extendedglob
  local dump="${ZINIT[ZCOMPDUMP_PATH]:-${ZDOTDIR:-$HOME}/.zcompdump}"
  if [[ -n $dump(#qN.mh-24) ]]; then
    ZINIT[COMPINIT_OPTS]=-C
    zicompinit
  else
    ZINIT[COMPINIT_OPTS]=
    zicompinit
    # compinit rewrites the dump only when the file count changes.
    command touch -- "$dump"
  fi
  # compinit sources the dump; zsh reads dump.zwc instead when it is newer.
  [[ -s $dump && ! "$dump.zwc" -nt $dump ]] && zcompile -- "$dump"
}
zinit cdreplay -q                          # compdef calls captured from plugins above

# Completions registered by code instead of fpath files. They need compdef.
# gcloud, gsutil and bq ship bash completions (loads bashcompinit).
[[ -r "${HOME}/Develop/google-cloud-sdk/completion.zsh.inc" ]] && \
  source "${HOME}/Develop/google-cloud-sdk/completion.zsh.inc"
compdef _gnu_generic zed

### 7. Turbo: loaded right after the first prompt ##############################
# Listed order is load order. fast-syntax-highlighting loads last because it
# wraps every ZLE widget that exists when it loads (fzf's included).
zinit wait lucid light-mode for \
    alexiszamanidis/zsh-git-fzf \
  blockf \
    zdharma-continuum/fast-syntax-highlighting

### 8. mise: must stay last ###################################################
# Its precmd hook rebuilds PATH from the snapshot taken at activation, which
# demotes every prepend after this line (e.g. nix bash below /bin/bash).
# Invoked by absolute path so it doesn't rely on PATH.
eval "$(~/.local/bin/mise activate zsh)"

# Added by the cua installer
export PATH="/Users/jessearmand/.local/bin:$PATH"

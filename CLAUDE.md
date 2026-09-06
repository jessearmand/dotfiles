# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A minimal dotfiles repository tracking only actively-used configuration files. No automated setup - just tracked configs that can be optionally symlinked to `$HOME`.

## File Naming Convention

Files are stored **without** a leading dot and map to `$HOME` by prefixing with `.`:
- `zshrc` → `~/.zshrc`
- `gitconfig` → `~/.gitconfig`

Files under `config/` map to `~/.config/` with the same relative path:
- `config/nix/nix.conf` → `~/.config/nix/nix.conf`

## Setup

**Symlink dotfiles (optional):**
```bash
./script/link-dotfiles --dry-run   # Preview what would be linked
./script/link-dotfiles --force     # Create symlinks (backs up existing files)
```

**Create private git config:**
```bash
touch ~/.gitconfig.private && chmod 600 ~/.gitconfig.private
```

## Managed Files

| File | Purpose |
|------|---------|
| `zshrc` | Zsh config: Zinit plugins, FZF, Powerlevel10k, PATH setup |
| `zshenv` | Environment variables for shell startup |
| `p10k.zsh` | Powerlevel10k theme config |
| `tmux.conf` | Tmux with vim-style keybindings |
| `gitconfig` | Git: nvim editor/diff/merge, GPG signing, aliases |
| `gitignore` | Global git ignore patterns |
| `gitmessage` | Git commit message template |
| `ripgreprc` | Ripgrep config: hidden files, smart case, line limits |
| `config/nix/nix.conf` | Nix experimental features (nix-command, flakes) |
| `npmrc` | npm: skip versions published in the last 7 days |
| `bunfig.toml` | bun: skip versions published in the last 7 days |
| `config/pnpm/config.yaml` | pnpm: skip versions published in the last 7 days |
| `config/uv/uv.toml` | uv: skip versions published in the last 7 days |

## Key Tools & Dependencies

- **Shell:** Zsh with [Zinit](https://github.com/zdharma-continuum/zinit) plugin manager
- **Theme:** [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- **Search:** FZF (fuzzy finder), ripgrep
- **Editor:** Neovim (all git operations use nvim)
- **Version manager:** [mise](https://mise.jdx.dev/) (`~/.local/bin/mise`)
- **Package source:** CLI tools come from a [Nix profile](nix-migration.md)
  (`nix profile list`); Homebrew is reserved for macOS-specific / daemon tools
  (colima, docker, lsusb, mactop) and casks. Requires `~/.config/nix/nix.conf`
  with `experimental-features = nix-command flakes` — tracked here as
  `config/nix/nix.conf` and linked by `link-dotfiles`.

## Git Aliases

```bash
git dc     # diff --cached
git hist   # Pretty graph log with dates
git lol    # Oneline graph log
git lola   # Oneline graph log (all branches)
```

## Not Managed Here

- `~/.config/**` (app-specific configs including mise, LazyVim)
- `~/.claude*`, `~/.codex*` (coding agents)
- Archived configs in `deprecated/`

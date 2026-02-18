# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

A minimal dotfiles repository tracking only actively-used configuration files. No automated setup - just tracked configs that can be optionally symlinked to `$HOME`.

## File Naming Convention

Files are stored **without** a leading dot and map to `$HOME` by prefixing with `.`:
- `zshrc` → `~/.zshrc`
- `gitconfig` → `~/.gitconfig`

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

## Key Tools & Dependencies

- **Shell:** Zsh with [Zinit](https://github.com/zdharma-continuum/zinit) plugin manager
- **Theme:** [Powerlevel10k](https://github.com/romkatv/powerlevel10k)
- **Search:** FZF (fuzzy finder), ripgrep
- **Editor:** Neovim (all git operations use nvim)
- **Version manager:** [mise](https://mise.jdx.dev/) (`~/.local/bin/mise`)

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

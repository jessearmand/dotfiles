dotfiles
========

This repo tracks the small set of dotfiles I actually use.

Layout
------

Files in this repo are stored at the repo root *without* a leading dot.
They map to `$HOME` by prefixing with `.`.

Examples:

- `zshrc` -> `~/.zshrc`
- `gitconfig` -> `~/.gitconfig`
- `p10k.zsh` -> `~/.p10k.zsh`

Files under `config/` map to `~/.config/` with the same relative path:

- `config/nix/nix.conf` -> `~/.config/nix/nix.conf`
- `config/uv/uv.toml` -> `~/.config/uv/uv.toml`
- `config/pnpm/config.yaml` -> `~/Library/Preferences/pnpm/config.yaml` on macOS, `~/.config/pnpm/config.yaml` elsewhere

Managed files
-------------

- `zshrc`
- `zshenv`
- `p10k.zsh`
- `tmux.conf`
- `gitconfig`
- `gitignore`
- `gitmessage`
- `ripgreprc`
- `config/nix/nix.conf`
- `npmrc`
- `bunfig.toml`
- `config/pnpm/config.yaml`
- `config/uv/uv.toml`

Ignored / managed elsewhere
--------------------------

- Most of `~/.config/**` (app-specific), including `~/.config/mise/config.toml`
- LazyVim (`~/.config/nvim`)
- Coding agents (`~/.claude*`, `~/.codex*`, `~/.config/opencode`)

Private config
--------------

This repo does not store personal identity or secrets.

`gitconfig` includes `~/.gitconfig.private` for machine/user-specific settings.
Create it locally (and keep it private):

    touch ~/.gitconfig.private
    chmod 600 ~/.gitconfig.private

Example contents:

    [user]
      name = Your Name
      email = you@example.com
      signingkey = YOUR_KEY_ID

PATH ordering in zshrc
----------------------

`zshrc` has two PATH zones, split by `eval "$(brew shellenv)"`:

- `brew shellenv` runs macOS `path_helper`, which **rebuilds** PATH: it
  front-loads `/etc/paths` + `/etc/paths.d/*` (including
  `/opt/homebrew/bin`), then re-appends previously-set entries behind them.
  Every prepend *before* that line (mint, bun, grok, go, gcloud, cargo)
  therefore ends up **below** homebrew — harmless for uniquely-named
  binaries, but useless for overriding anything.
- Entries that must outrank homebrew live in the marked block *after*
  `brew shellenv`, where later prepends win. Final precedence:

      ~/.local/bin > pnpm > deno > nix profile > homebrew > system

`~/.local/bin` appears twice on purpose: the early prepend is load-bearing
(`mise activate` and the `uv`/`uvx` completion evals need those binaries
during startup); the late one restores its precedence after `path_helper`
demotes it.

When an installer appends a PATH line to `~/.zshrc`, move it into the
marked block — its position decides whether it can override brew/nix at all.

Linking (optional)
-----------------

No symlinks are created automatically. If you want symlinks, use:

    ./script/link-dotfiles --dry-run
    ./script/link-dotfiles --force

`--dry-run` (the default) walks every entry and reports what it would do,
printing a diff for each destination whose contents differ from the repo copy.

`--force` applies the plan, but only replaces a destination outright when it is
byte-identical to the repo. Anything carrying local edits — git identity,
credential helpers, host paths — is shown as a diff and confirmed one file at a
time, so a blanket run cannot silently overwrite machine-specific config. Add
`--yes` to answer those confirmations up front; with no terminal on stdin the
differing files are skipped rather than replaced.

Replaced files are moved aside as `<dest>.bak.<timestamp>` — nothing is deleted.

Deprecated
----------

Old thoughtbot-era dotfiles and unused configs are archived under `deprecated/`.

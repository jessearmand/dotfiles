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

      mise tools > ~/.local/bin > pnpm > deno > nix profile > homebrew > system

`~/.local/bin` appears twice on purpose: the early prepend is load-bearing
(the `uv`/`uvx` completion evals need those binaries during startup); the
late one restores its precedence after `path_helper` demotes it.

`mise activate` is the **last** line. Its precmd hook rebuilds PATH from the
snapshot taken at activation, so anything prepended after it gets demoted
behind `/bin` before the first prompt — with it near the top, `bash`
resolved to macOS's 3.2 instead of nix's `bashInteractive` despite the nix
prepend. Keep every PATH export above it.

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

Scripts
-------

`script/spotlight-exclude-caches` adds visible cache directories
(`~/Library/Caches`, `~/Library/pnpm/store`, `~/go/pkg/mod`, Xcode
DerivedData, ...) to Spotlight's per-volume exclusion list, then turns
indexing off and back on so `mds` reloads it. Dot-directories such as
`~/.cache` or `~/.npm` are never indexed, so they are not listed.

Apple ships no CLI for that list; it is the `Exclusions` array in the
volume's `VolumeConfiguration.plist`, the same list System Settings >
Spotlight > Search Privacy edits. `.Spotlight-V100` is TCC-protected, so the
script needs root **and** the terminal app must have Full Disk Access
(System Settings > Privacy & Security > Full Disk Access). Without it even
root gets "Operation not permitted", and the supported route is to drag the
directories the dry run prints into Search Privacy by hand.

    sudo script/spotlight-exclude-caches            # dry run: what would be added
    sudo script/spotlight-exclude-caches --apply    # add them and restart indexing
    sudo script/spotlight-exclude-caches --list     # show the current list

Only directories that exist are added, nothing is removed, and the plist is
backed up next to itself first. Extra paths can be passed as arguments.

`script/package-audit` audits every globally installed package across cargo,
pnpm, npm, bun, yarn and uv, using each manager's own auditor (`cargo audit
bin`, `pnpm audit`, `npm audit`, `bun audit`, `yarn audit`, `pip-audit`). A
manager that is not installed, or has no global packages, is reported as such
rather than treated as a failure. Exit status is 0 when clean, 1 when
vulnerabilities were found, 2 when an auditor could not run.

    script/package-audit                 # everything
    script/package-audit --only cargo,uv # a subset
    script/package-audit --notify        # plus a macOS notification

`mise.toml` wraps all of this as tasks, so from the checkout (or with
`mise -C ~/Develop/dotfiles`) `mise tasks` lists them and:

    mise run audit                    # audit now (extra args pass through: -- --only uv)
    mise run audit:agent:install      # also :run, :status, :uninstall
    mise run audit:log                # summary of the last scheduled run
    mise run spotlight                # dry run; also spotlight:list, spotlight:apply

`script/install-package-audit-agent` schedules it weekly (Monday 10:00) as a
launchd user agent, logging to `~/Library/Logs/package-audit/`. The plist is
rendered from `launchagents/*.plist.template` with this checkout's absolute
path, since launchd does not expand `~`:

    script/install-package-audit-agent            # install / reload
    script/install-package-audit-agent --run      # audit now
    script/install-package-audit-agent --status
    script/install-package-audit-agent --uninstall

Deprecated
----------

Old thoughtbot-era dotfiles and unused configs are archived under `deprecated/`.

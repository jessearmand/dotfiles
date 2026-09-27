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

zshrc load order
----------------

`zshrc` runs in numbered phases, and each phase depends only on the phases
above it. The header of the file lists them: instant prompt, helpers,
environment, PATH, zinit, completion, Turbo, mise.

**PATH** is one ordered list in phase 4, highest precedence first. `path` is
declared unique (`typeset -U`), so assigning the list moves each directory to
the position where it is listed and drops the later duplicates. The result
is the same in a fresh login shell and in a nested shell that inherits PATH.
The path_helper runs from `/etc/zprofile` and from `brew shellenv` cannot
reorder it, because both run before the list. Final precedence:

    mise tools > zinit programs (fzf) > opencode/kimi/bend > ~/.local/bin
      > pnpm > deno > nix profile > homebrew > gcloud/go/grok/bun/mint
      > login PATH (system, zshenv, ~/.zprofile) > lm-studio

When an installer appends a PATH line to `~/.zshrc`, move the directory into
the list. Its position in the list sets its precedence.

`mise activate` is the **last** line. Its precmd hook rebuilds PATH from the
snapshot taken at activation, so anything prepended after it gets demoted
behind `/bin` before the first prompt. With mise near the top, `bash`
resolved to macOS's 3.2 instead of nix's `bashInteractive` despite the nix
prepend.

**compinit** runs synchronously in phase 6, before mise. It trusts the dump
(`compinit -C`) for 24 hours after each full check. To pick up a newly
installed completion at once, run `rm ~/.zcompdump`. mise's hook runs its
own `compinit -i` when `compdef` is missing, and it registers tool
completions (for example fnox). A compinit deferred to Turbo would run a
second time and reset those registrations.

**Generated scripts are cached** in `~/.cache/zsh`: `brew shellenv`,
`fzf --zsh`, and the `uv`/`uvx` completions. Each cache file is regenerated
when the binary or script that produces it changes. The resolved path is
compared too, for Nix store paths, whose mtime never changes. To force a
rebuild, delete `~/.cache/zsh`.

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

# Brew → Nix migration on Apple Silicon

A practical guide derived from migrating ~12 packages from Homebrew to Nix on
macOS aarch64 (Apple Silicon, Determinate-installer Nix). Not a tutorial on Nix
itself — a record of decisions, gotchas, and recipes that don't show up in
linear documentation.

## Why migrate at all

The pull is reproducibility: a Nix profile is a single declarative manifest you
can serialize, share, and rebuild on a fresh machine. Brew's per-formula
imperative state is harder to reason about and drifts with every `brew update`.

The push is brew's overlap with Nix isn't worth keeping for tools that are
"just a binary" (Rust/Go/Haskell CLIs, plain C tools without macOS hooks).
Migrating those reduces drift surface without losing anything.

The brake is that aarch64-darwin in nixpkgs is a second-class citizen for
anything touching macOS-specific surfaces (Metal, virtualization, codesigning
entitlements, font registration). Some packages must stay on brew indefinitely.

## Prerequisites

Nix's modern CLI (`nix <verb>`) is gated behind two **experimental features**.
Without enabling them, every command fails with:

```
error: experimental Nix feature 'nix-command' is disabled;
add '--extra-experimental-features nix-command' to enable it
```

Enable per-user, persistent — create `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

`flakes` is also required because `nix search`, `nix profile install`, etc. all
consume **flake installables** (e.g. `nixpkgs#ripgrep`). The shorthand
`nixpkgs` resolves via the global flake registry (`nix registry list`) to
`github:NixOS/nixpkgs`.

System-wide alternative is `/etc/nix/nix.conf` (needs sudo); on nix-darwin it
goes in `configuration.nix` as `nix.settings.experimental-features = [ ... ]`.

## The PATH ordering trap (critical on macOS)

`brew shellenv` invokes `/usr/libexec/path_helper -s`, which **rebuilds** PATH
from `/etc/paths` plus `/etc/paths.d/*` first, then appends your existing PATH.
Brew's installer drops `/etc/paths.d/homebrew`, so this front-loads
`/opt/homebrew/bin` on every shell startup, defeating any earlier `export
PATH="$HOME/.nix-profile/bin:$PATH"`.

Fix: re-prepend nix paths *after* `brew shellenv`. In `~/.zshrc`:

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"

# `brew shellenv` runs path_helper which front-loads /opt/homebrew/bin.
# Re-prepend nix paths so nix profile beats homebrew on overlap (e.g. git, ffmpeg).
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"
```

Without this, you'll install nix versions of tools and silently keep using
brew's because of PATH precedence. The Determinate Nix installer adds nix to
PATH via `/etc/zshrc` (which runs *before* `~/.zshrc`), and `brew shellenv`
later overrides that.

Two extra failure modes surface when the fix *looks* present but isn't effective:

- **Stale / unsymlinked dotfiles.** If `~/.zshrc` is a hand-managed copy that has
  drifted from your tracked repo (this repo is not symlinked — see `CLAUDE.md`),
  the fix can be committed to the repo yet absent from the *running* file. Symptom
  is identical (brew wins). Verify the LIVE file, not the repo:
  `rg nix-profile ~/.zshrc`, then confirm with `zsh -lic 'command -v git'`.
- **Hardcoded `/opt/homebrew` paths in configs.** `gh auth setup-git` writes
  `helper = !/opt/homebrew/bin/gh auth git-credential` into `~/.gitconfig` with an
  *absolute* brew path. Uninstalling brew `gh` then breaks GitHub HTTPS auth
  silently. Rewrite to PATH-relative `!gh auth git-credential`. Before any brew
  uninstall, audit: `rg -l /opt/homebrew ~/.gitconfig ~/.zshrc ~/.config 2>/dev/null`.

## Migration tier framework

Decide per-package using these tiers. The key dimension is **how much the tool
reaches into macOS-specific surfaces** — pure CLI binaries are safe; anything
touching launchd, virtualization, codesigning, GUI integration, or font
registration belongs on brew.

### Tier 1 — Migrate now, low risk

Pure binary CLI tools, well-maintained in nixpkgs, no macOS-specific patches.
Single-command batch is safe:

```sh
nix profile install nixpkgs#{ast-grep,coreutils,difftastic,gh,mkcert,p7zip,pkgconf,ripgrep,shellcheck,tree,wget}
brew uninstall ast-grep coreutils difftastic gh mkcert p7zip pkgconf ripgrep shellcheck tree wget
brew autoremove
```

Validated in this session: ast-grep, coreutils, difftastic, gh, mkcert, p7zip,
pkgconf, ripgrep, shellcheck, tree, wget, plus stylua, tmux, lua-language-server.

Notes:
- `coreutils`: nix puts `ls`, `cp`, `md5sum`, `sha1sum`, etc. **unprefixed** on
  PATH (no `g` prefix like brew does on macOS). With nix-first PATH, `ls`
  becomes GNU ls — long-form flags work, but BSD-only flags (`ls -G` for color)
  break. Watch for aliases.
- `md5sha1sum` (brew formula) has no nix counterpart and isn't needed —
  coreutils provides those binaries natively.
- `difftastic` binary is `difft`, not `difftastic` (same in brew). Existing
  `~/.gitconfig` `[difftool "difftastic"]` blocks already use `difft`.

### Tier 2 — Should work, verify after migrating

Migrate, but smoke-test the specific feature you depend on:

| Package | Verify |
|---------|--------|
| `neovim` | `:checkhealth`, `:Lazy sync`, treesitter parsers rebuild on first open |
| `lua-language-server` | nvim's LSP attaches to Lua files |
| `luarocks` | only matters if you write Lua plugins; nix luarocks brings own lua interpreter |
| `stylua` | conform.nvim formatter still runs |
| `cmake` | finds macOS SDK frameworks (sysroot) |
| `llama.cpp` | **Metal acceleration** — see Apple Silicon section below |
| `ghostscript`, `qpdf` | basic CLI usage; PostScript/PDF interpreters work standalone |
| `ocrmypdf` | text-layer add works (we confirmed on `Simulacra-Simulation.pdf`) |
| `ffmpeg` | encoders include `libmp3lame` etc. (`ffmpeg -encoders`) |

For neovim specifically: nixpkgs's `neovim` ships with **provider support
disabled by default** (no Python/Node embedded). Enable with:

```sh
nix profile install --impure --expr 'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.neovim.override { withPython3 = true; withNodeJs = true; }'
```

Most LazyVim setups *don't need* providers (pure-Lua plugins, treesitter, LSP
servers spawned as subprocesses). Audit with `grep -r "python_host_prog\|node_host_prog\|pynvim" ~/.config/nvim/`.

### Tier 3 — Keep on brew (macOS-specific or daemon-managed)

| Package | Why brew wins |
|---------|---------------|
| `colima` | Lima VM, deeply tied to macOS Virtualization.framework. Brew's formula has Apple-Silicon-specific patches. |
| `docker`, `docker-buildx`, `docker-compose` | CLI clients usually configured to talk to brew's colima. Mixing client/daemon sources risks socket-path confusion. |
| `cloudflared` | Daemon. Brew handles `brew services` integration with launchd. |
| `lsusb` | Brew's `lsusb` is a custom shell wrapper around `system_profiler SPUSBDataType` — nixpkgs ships the Linux original which doesn't work on macOS the same way. |
| `mactop` | Apple Silicon system monitor — uses `powermetrics` and macOS-specific perf counters. |
| **All casks** (fonts, GUI apps) | Casks install to `/Applications`, `~/Library/Fonts`, etc. Nix has no cask story; nix-installed fonts on macOS need manual registration to be discoverable by GUI apps. |

### Tier 4 — Investigate before deciding

| Package | Question to answer |
|---------|---------------------|
| `git-xet` | Hugging Face xet protocol extension. Available in nixpkgs but verify integration with `~/.gitconfig`'s git-lfs/xet hooks before swapping. |
| `icu4c@77` | Versioned ICU. **Probably a transitive dep something needs** — check `brew uses --installed icu4c@77`. If unused, drop. If used, leave alone. |
| `mint` | Swift package manager. Swift toolchain on nix-darwin is hit-or-miss; brew is pragmatic until you specifically want Swift in nix. |
| `mole`, `tmuxai` | Niche / very recent tools. Verify nixpkgs has them (`nix search nixpkgs <name>`). If not, file PR upstream or stay on brew. |
| `perl` | If anything calls `/opt/homebrew/bin/perl` (build scripts, custom tools), removing breaks them silently. Audit before touching. |
| `pipx` | Largely redundant if you have `uv` + `uvx` (which mise can manage). Often just `brew uninstall` rather than migrate. |

**Verifying availability: "in nixpkgs" ≠ "buildable."** `nix search nixpkgs <name>`
and `nix eval nixpkgs#<name>.version` only *evaluate metadata* — they succeed even
when a package is flagged unbuildable. The real gate is:

```sh
nix eval nixpkgs#<name>.meta.broken    # true = refuses to build
```

`nix profile install` evaluates the derivation's `drvPath`, which trips the
`broken` assertion and aborts. And because **`nix profile install` is atomic per
invocation**, one broken package in a batch fails the *entire* batch — nothing
installs, and the error names only the broken package. So check `meta.broken` for
every Tier 4 candidate *before* batching, or install risky ones one at a time.

### Tier 4 verdicts (2026-06 session)

| Package | Verdict |
|---------|---------|
| `mole` | **`meta.broken = true`** in nixpkgs — `nix eval .version` returns `2.0.0`, but `nix profile install` refuses with "Refusing to evaluate package 'mole-2.0.0' … because it has problems: broken". **Kept on brew.** The canonical "exists but unbuildable" case. |
| `mint` | `meta.broken = false` — installs cleanly (Mint 0.28.1). The Swift-toolchain pessimism above didn't bite for mint *itself*; whether it can *build* Swift packages on nix-darwin is a separate, untested question. **Migrated to nix.** |
| `perl` | `brew uses --installed perl` empty → nothing depended on it. **Migrated to nix** (5.42.0); nix perl wins on PATH so any bare `perl` call still resolves. |
| `pipx` | **Dropped** (uv/uvx covers it). |
| `icu4c@77`, `icu4c@78` | Orphans (`brew uses --installed` empty) → **dropped**. Gotcha: a *new* versioned icu4c can get promoted to a leaf mid-teardown and survive `brew autoremove` (locally flagged install-on-request); remove it explicitly. |
| `tmuxai` | No nix counterpart → **dropped**. Cascade-removed `tmux` as collateral (tmux was a tmuxai dep, not a leaf) — restore tmux via nix afterward. |
| `rust-analyzer` | Moved to **rustup**, not nix or brew (`rustup component add rust-analyzer`, proxy at `~/.cargo/bin/rust-analyzer`). For toolchain-coupled tools, the language's own distribution is often the right third option. |

## Apple Silicon-specific gotchas

### W^X kills (SIGKILL during image/SIMD work)

Some nixpkgs aarch64-darwin builds SIGKILL at runtime during heavy work, even
though `--version` or `--help` runs fine. Confirmed example this session:
**unpaper-7.0.0** SIGKILLs when processing any image. Hypothesis: the binary
calls into a JIT-using image lib (libpng/libjpeg-turbo SIMD paths) without the
right `MAP_JIT` mmap flag or codesigning entitlement that macOS arm64 enforces.

Pattern recognition:
- `signal -9` from kernel during processing, no crash report;
- binary correctly built (arm64, ad-hoc/linker-signed — `codesign -dv` looks normal);
- works at startup (`--version`), fails at runtime;
- brew bottle for the same package works fine (their build scripts handle entitlements).

Workaround if the broken package is a transitive dep of one you need: rebuild
the consumer with a stub. See "Stub a broken dep" below.

### Metal acceleration (ML/AI tools)

Nixpkgs default builds prefer LGPL/portability over platform features.
Anything ML-adjacent (`llama.cpp`, `whisper.cpp`, etc.) defaults to **no GPU
acceleration** on aarch64-darwin, where brew bottles typically include Metal
compiled in. Override syntax:

```sh
nix profile install --impure --expr 'let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}; in pkgs.llama-cpp.override { metalSupport = true; }'
```

(Exact attribute name varies — `llama-cpp` uses `metalSupport`, others use
`withMetal` or `enableMetal`. Check the package's `default.nix` in nixpkgs.)

Watch for **silent 10× perf loss** if you skip the override.

### Build-from-source frequency

Nixpkgs's binary cache (`cache.nixos.org`) has lower hit rates on
aarch64-darwin than on Linux. You'll occasionally watch a package compile from
source where brew would have grabbed a bottle in 5 seconds. First-time
installs of large closures (ocrmypdf, neovim) can take longer than expected.

### Codesigning is ad-hoc

All nix-built binaries on darwin get `linker-signed` ad-hoc signatures (visible
via `codesign -dv`). This is normal. macOS only complains if Gatekeeper sees
the binary in a quarantined location (downloads, etc.) — `~/.nix-profile/bin/`
is fine.

## Migration patterns and recipes

### Standard install + brew teardown

```sh
nix profile install nixpkgs#<package>
brew uninstall <package>
brew autoremove --dry-run    # preview cascading orphans
brew autoremove              # accept the cascade
brew cleanup                 # sweep stale cellars from past upgrades
```

**Leaves shift as you go — iterate.** Removing a package promotes its now-orphaned
deps to leaves, and removing *those* can cascade further. Re-run `brew leaves`
after each round. This session: `ffmpeg` was a *dependency* at the start (not a
leaf), got promoted to a leaf only after its dependents left, and uninstalling it
then cascaded **103** codec formulae (x264, x265, aom, dav1d, rav1e, tesseract,
openssl@3, glib …); a second `brew autoremove` pass caught still more. Don't
assume one pass is terminal. Modern Homebrew (≥4.x) also auto-runs an autoremove
at the end of each `brew uninstall`, so the cascade often happens inline.

### Override an attribute (skip flaky tests)

```sh
nix profile install --impure --expr '
  let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
  in pkgs.<package>.overrideAttrs (_: { doCheck = false; doInstallCheck = false; })
'
```

`overrideAttrs` patches the derivation's *attributes*. Required when a package
runs a flaky pytest/meson test suite during build that doesn't reflect runtime
behavior.

### Override an input (swap a dep)

```sh
nix profile install --impure --expr '
  let pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
      patched = pkgs.<dep>.overrideAttrs (_: { doCheck = false; });
  in pkgs.<consumer>.override { <dep> = patched; }
'
```

`.override` passes different inputs to the package's build function. Different
mechanism from `overrideAttrs`. Use both together to bypass a flaky dep
without forking nixpkgs.

### Stub a broken dep

When a transitive dep is broken on aarch64-darwin (e.g. unpaper SIGKILL) but
the consumer is otherwise useful, replace the dep with a fail-fast shell
script:

```sh
nix profile install --impure --file /path/to/expr.nix
```

Where `expr.nix` contains:

```nix
let
  pkgs = (builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem};
  stub = pkgs.writeShellScriptBin "<dep-name>" ''
    echo "<dep-name> is unavailable in this build" >&2
    exit 1
  '';
in
  (pkgs.<consumer>.override { <dep-name> = stub; }).overridePythonAttrs
    (_: { doCheck = false; doInstallCheck = false; })
```

`writeShellScriptBin` produces a derivation with a `bin/<name>` script. From
the consumer's perspective it looks identical to a real package — same file
layout, same store-path-with-`bin/<name>` shape. Used in this session to make
`ocrmypdf --clean` fail with a clear message instead of SIGKILL.

### Closure pinning (why "remove" doesn't free disk)

Nixpkgs patches consumers to invoke deps via **absolute store paths**, not
PATH lookup. Consequence: `nix profile remove <dep>` only takes the dep off
your `~/.nix-profile/bin/` PATH; the consumer still references it via the
embedded store path, and the file stays on disk pinned by the consumer.

To actually free the on-disk closure of a now-orphan dep, also run:

```sh
nix-collect-garbage -d
```

The `-d` flag deletes old profile generations (which would otherwise pin every
package you've ever installed). Loses rollback ability. Run periodically for
hygiene.

## Maintenance

### Profile inspection

```sh
nix profile list                    # current packages
nix profile history                 # generations history
nix profile diff-closures           # what changed between generations
nix profile rollback                # revert to previous generation
```

### Garbage collection

```sh
nix-collect-garbage --dry-run       # preview orphan paths
nix-collect-garbage                 # remove orphans (preserves all generations)
nix-collect-garbage -d              # also delete old generations (more aggressive)
sudo nix-collect-garbage -d         # also clean root profiles (system installs, daemon)
```

### Store optimisation

```sh
nix store optimise                  # hardlink-deduplicate identical files
```

Not enabled by default on darwin. Can reclaim 1–5 GB on a typical setup if
you've been installing heavily.

### Brew side hygiene after a migration

```sh
brew autoremove                     # clean orphans whose only dependent was just removed
brew cleanup                        # sweep stale versioned cellars
brew uninstall --force <name>       # remove all versions, including unlinked stale cellars
```

The "old version stays linked" pattern: when brew upgrades a formula it
sometimes leaves the previous cellar around. After several upgrades and an
autoremove, you can have a stale 2.x cellar linked but no formula needing it.
`brew cleanup` catches most; `--force` is the manual sweep.

## Reference: what was migrated in this session

| Package | Reason | Notes |
|---------|--------|-------|
| `git` | Tier 1 | Brings macOS Keychain credential helper natively. `gitk` not bundled — use `gitFull` if needed. |
| `ffmpeg` | Tier 2 | nix 8.0.1 with `libmp3lame`. Validated on WAV → MP3 (mono 24kHz). |
| `ghostscript`, `qpdf` | Tier 2 | Standalone PDF tooling. |
| `ocrmypdf` | Tier 2 | Custom build with stub unpaper (see "Stub a broken dep"). Base mode works, `--clean` fails fast. **2026-06 follow-up: dropped entirely instead** — if you don't actually need OCR, dropping it avoids the stub build and cascade-frees ghostscript/qpdf/tesseract/unpaper (~900 MB). |
| `ast-grep`, `coreutils`, `difftastic`, `gh`, `mkcert`, `p7zip`, `pkgconf`, `ripgrep`, `shellcheck`, `tree`, `wget` | Tier 1 | Single batch install. |
| `neovim` | Tier 2 | 0.12.2 plain build. LazyVim's 43 plugins discovered cleanly, `:checkhealth` no errors. |
| `lua-language-server`, `luarocks`, `stylua` | Tier 2 | Lua tooling for nvim. |
| `tmux` | (collateral; restored) | Brew cascade-removed it during `tmuxai` cleanup. Restored via nix to align with migration direction. |

Brew uninstalled, no nix replacement needed: `tmuxai` (rare), `pipx` (uv
covers it), `tesseract-lang` (ocrmypdf bundles its own tesseract closure),
`md5sha1sum` (subsumed by nix coreutils).

Brew leaves: 33 → 14 (-58%). Brew formulae: 115 → 25 (-78%). Nix profile: 21
packages.

**Second session (2026-06, this machine), fuller pass:** brew leaves 35 → 7
(-80%), brew formulae 178 → 9 (-95%), nix profile 25 packages. ocrmypdf dropped
(not stubbed); mole kept on brew (`meta.broken`); rust-analyzer moved to rustup;
perl/mint/mole-attempt resolved per the Tier 4 verdicts above. Kept on brew:
colima, docker(+buildx,+compose), lsusb, mactop, mole, and all casks.

## Open questions / future work

- `~/.config/nix/nix.conf` is not yet tracked in this dotfiles repo. The
  `script/link-dotfiles` helper currently maps repo files to `~/.<name>` only
  — it doesn't handle nested `~/.config/<app>/<file>` paths. Either extend the
  script to support nested mappings, or track this file via a different
  mechanism.
- Tier 4 packages mostly decided in the 2026-06 session — see "Tier 4 verdicts"
  above. Still open: `git-xet` (xet protocol; verify gitconfig hooks before
  swapping). `mole` blocked upstream on `meta.broken` — recheck after a nixpkgs
  bump or file/track the fix.
- `llama.cpp` is the strongest Tier 2 candidate gated on validating Metal
  acceleration in the nix build.
- `nix store optimise` — **done** (2026-06): 307.6 MiB freed by hard-linking
  56,882 files. Re-run periodically after heavy installs.

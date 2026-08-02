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

The brake is that aarch64-darwin in nixpkgs *can* be a second-class citizen for
macOS-specific surfaces — but verify rather than assume. Some genuinely belong on
brew (GUI casks, font registration, Metal builds that default off). Others *look*
brew-only but aren't: nixpkgs handles Virtualization.framework **codesigning
entitlements** for lima/colima just like brew does (see the colima correction
below) — there the reason to stay on brew is operational (stateful VMs), not
technical. Don't let "it touches macOS" become a reflexive "keep on brew."

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

### Which "channel" are you on? (flakes have no channels)

`nix-channel --list` is empty here — this is a flakes-only setup. The registry
(`nix registry list`) resolves `flake:nixpkgs` → `github:NixOS/nixpkgs/nixpkgs-unstable`,
so installs track the **rolling unstable** branch, *not* a numbered release
(e.g. `26.05`). Key nuance: there's **no single pin for the whole profile** —
each `nix profile install` re-locks `nixpkgs` to unstable's tip *at that moment*,
so `nix profile list` shows different revisions per package. Realign everything
onto one current revision with `nix profile upgrade --all`. To pin to a stable
release instead, repoint the registry: `nix registry add nixpkgs github:NixOS/nixpkgs/nixos-26.05`.

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

### Tier 3 — Keep on brew (macOS-specific only)

After the colima/lima migration (below), Tier 3 is effectively **just casks** —
no pure CLI tool on this machine genuinely requires brew anymore.

| Package | Why brew wins |
|---------|---------------|
| **All casks** (fonts, GUI apps — e.g. `wezterm@nightly`) | Casks install to `/Applications`, `~/Library/Fonts`, etc. Nix has no cask story; a nix GUI app lands in the store, unregistered with Spotlight/Launchpad/macOS app handling. Fonts need manual registration. |

> **Correction (2026-06-19): "macOS virtualization is brew-specific" was false —
> and now proven so with a live VM.** An earlier version of this guide claimed
> colima/lima must stay on brew because they're "deeply tied to
> Virtualization.framework with Apple-Silicon brew patches nix lacks." Wrong.
> `nixpkgs#colima` (0.10.1) and `nixpkgs#lima`/`lima-full` (2.1.2) build for
> `aarch64-darwin`, and nixpkgs attaches the **identical** `vz.entitlements`
> (`com.apple.security.virtualization` + network client/server) via ad-hoc
> codesign — the very thing the native `vz` driver needs — and sets `dontStrip`
> on darwin so the entitlement survives. `com.apple.security.virtualization`
> works with ad-hoc signing on Apple Silicon (no paid Developer cert). **We
> migrated and verified it**: a fresh nix colima boots with `vmType: vz` (the
> native driver), `docker run hello-world` passes, and `docker run --platform
> linux/amd64 alpine uname -m` returns `x86_64` (cross-arch emulation intact). So
> the VM side was never brew-bound; the only real cost is the stateful teardown.
>
> **lima vs lima-full:** same version, differing only by `withAdditionalGuestAgents`.
> `lima` ships the **native-arch** guest agent only (same-arch VMs); `lima-full`
> bundles guest agents for **all arches**, enabling cross-arch guests (amd64 Linux
> on Apple Silicon via emulation). nix `colima` wraps **`lima-full` + `qemu`** onto
> its *internal* PATH; install `nixpkgs#lima-full` separately too if you want
> `limactl` on your shell PATH (colima alone doesn't expose it).
>
> **Safe migration recipe (stateful — plan a teardown):**
> ```sh
> colima stop && colima delete -f          # no containers? nothing to lose
> brew uninstall colima && brew autoremove  # sweeps lima
> nix profile install nixpkgs#colima nixpkgs#lima-full
> colima start                              # provisions a fresh vz VM
> docker run --rm hello-world               # verify client(nix)↔server(nix VM)
> ```

> **Reclassified out of Tier 3 (2026-06-04):** `docker` (+`docker-buildx`,
> +`docker-compose`), `cloudflared`, `mactop`, and `lsusb` were all originally
> parked here but **migrated to nix** — see "The client/daemon boundary" and the
> Tier 4 verdicts. Three lessons came out of this:
> - **"daemon-adjacent" ≠ "is a daemon."** docker/cloudflared are clients, not
>   the daemon (colima) they sit next to.
> - **"shells out" ≠ "links in."** `mactop` *calls* the system
>   `/usr/bin/powermetrics` at runtime rather than linking a macOS framework, so
>   the Go binary itself is portable — only the external tool it invokes is
>   macOS-specific (and that's on the system PATH regardless of packaging).
> - **attribute ≠ binary, and same name ≠ same tool.** `lsusb` *looked* absent
>   because `nixpkgs#lsusb` isn't an attribute — but `nixpkgs#usbutils` provides
>   the `lsusb` binary and supports `aarch64-darwin`. Beware the inverse too:
>   nix's usbutils `lsusb` (libusb) is a *different program* than brew's `lsusb`
>   (a shell wrapper over `system_profiler`) that happens to share the name.

### The client/daemon boundary (the cleanest cut line)

The deciding question for daemon-adjacent tools isn't "does this touch a daemon?"
but **"is this tool the daemon, or a client of it?"** The boundary is the
socket/IPC channel:

```
docker CLI (nix)  →  unix socket  →  colima  →  lima  →  Virtualization.framework  →  Linux VM (dockerd)
   client                            wrapper   VM mgr      macOS kernel
   ── host side, portable ──         ──── VM side: also nix now (vz verified) ────
```

Everything **host-side** of the socket (the `docker` CLI and its `buildx`/`compose`
plugins) is just binaries reading config and writing to a socket — portable across
package managers; migrate freely. The **VM side** (colima → lima → VZ.framework) is
**also nix now**: nixpkgs ships colima/lima and signs the Virtualization.framework
entitlement, so the native `vz` driver runs unchanged — we confirmed a live nix VM
reporting "macOS Virtualization.Framework". It's not brew-bound; it's just
**stateful**, so it migrates on a planned stop/delete/restart rather than a
transparent binary swap. The clean rule: the client moves for free; the daemon
moves too, but schedule the teardown — verify with `colima status` (look for
"macOS Virtualization.Framework") and `ps aux | rg Virtualization.framework`.

- **Lima vs colima:** Lima ("Linux machines") is the general VM manager — boots a
  Linux guest via Virtualization.framework, handles mounts/port-forwarding/DNS;
  not container-specific. **Colima** ("Containers on Lima") is a thin wrapper that
  provisions a Lima VM preloaded with Docker/containerd, forwards the container
  socket (`~/.colima/default/docker.sock`), and wires the docker `context`. Colima
  literally creates a Lima instance named `colima` (`limactl list` shows it).
- **The one real gotcha — plugin discovery.** `buildx` and `compose` are docker CLI
  *plugins*, found by directory scan. A nix docker won't scan brew's
  `/opt/homebrew/lib/docker/cli-plugins`, so migrating `docker` alone silently
  breaks `docker buildx`/`docker compose`. Fix source-independently by seeding the
  one dir docker *always* scans:
  ```sh
  mkdir -p ~/.docker/cli-plugins
  ln -sfn ~/.nix-profile/libexec/docker/cli-plugins/docker-buildx  ~/.docker/cli-plugins/docker-buildx
  ln -sfn ~/.nix-profile/libexec/docker/cli-plugins/docker-compose ~/.docker/cli-plugins/docker-compose
  ```
  Pointing at the **profile** path (not the raw store path) keeps the symlink valid
  across nix upgrades.
- **Verify the daemon is reachable before celebrating.** `colima start`, then
  `docker version` should show both Client and Server; `docker buildx ls` should
  list the colima builder; `docker run --rm hello-world` is the end-to-end proof.
  Client newer than server (e.g. client 29.5 / server 27.4) is fine — docker
  clients are backward-compatible; `colima delete && colima start` re-provisions a
  newer engine if you want them aligned.
- **`cloudflared` was never actually a daemon here.** The Tier-3 "keep for
  `brew services`/launchd" rationale only applies if you *run* it as a managed
  service. Check first: `brew services list | rg cloudflared`, `launchctl list |
  rg cloudflared`, `ls ~/.cloudflared`. All empty → it's a dormant CLI binary →
  migrate freely. (If you later want a persistent tunnel, nix won't write the
  launchd plist for you; run it manually or author a LaunchAgent.)

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
| `docker` (+`docker-buildx`, +`docker-compose`) | All `meta.broken = false`, no brew reverse-deps. **Migrated to nix** as a set (29.5.2 / buildx 0.31.1 / compose 5.1.4), verified end-to-end against a live colima daemon (`hello-world` ran). Plugins seeded into `~/.docker/cli-plugins`. (At the time, colima was still on brew; it was later migrated too — see the 2026-06-19 correction.) See "The client/daemon boundary." |
| `cloudflared` | `meta.broken = false`, not registered with `brew services`/launchd, no `~/.cloudflared`. Was a dormant CLI, not a running daemon → **migrated to nix** (2026.5.0). |
| `cmake` | `meta.broken = false`, no brew reverse-deps (a user-requested leaf). Its real dependents are *source builds* invisible to `brew uses`, so the safety check is functional, not graph-based. **Migrated to nix** (4.1.2, up from brew's 3.30.2) after a configure+build+run smoke test confirmed it detects AppleClang + the macOS SDK. Caveat: empty `CMAKE_OSX_SYSROOT` is fine — cmake defers to AppleClang's default SDK; a compiling `#include <stdio.h>` is the real proof. |
| `git-xet` (+`git-lfs`) | Both `meta.broken = false`. `git-xet` was the brew leaf; `git-lfs` came in as its dep. **Migrated together** (git-xet 0.2.1, git-lfs 3.7.1). git-lfs's `filter.lfs.*` integration keeps working because git invokes `git-lfs` via PATH (nix-first), and the gitconfig had no `[xet]`/`/opt/homebrew` hardcoding. Removing brew git-xet did *not* orphan `openssl@3`/`ca-certificates` — `llama.cpp` still needs them. |
| `mactop` | `meta.broken = false`. Reclassified out of Tier 3: it *shells out* to `/usr/bin/powermetrics`, doesn't link a framework, so the Go binary is portable. **Migrated to nix** (2.1.3, up from brew's 2.1.1) and **runs fine without `sudo`** (recent mactop reads SMC/`IOReport` directly; admin-group membership covers the rest). General caveat, *not* specific to mactop: if you ever run a nix CLI as root, `sudo` resets PATH to `secure_path` (`/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin`), which **excludes `~/.nix-profile/bin`** — so `sudo <tool>` won't find it. Use `sudo "$(command -v <tool>)"`, alias it, or add the nix path to `secure_path` in sudoers. |
| `lsusb` (via `usbutils`) | **The attribute is `usbutils`, not `lsusb`** — that mistake made it look absent. `nixpkgs#usbutils` (`meta.broken = false`, v019) lists `aarch64-darwin` and ships the `lsusb` binary. **Migrated** — but it's a *different tool*: nix's is the real libusb/IOKit `lsusb`, brew's was a shell wrapper over `system_profiler`. Smoke test was decisive: brew's wrapper exited 1 with **empty** output on this machine, while nix's enumerated real devices (`0bda:5411` hub, `0bda:8153` USB-ethernet). Caveat: vendor/product **names don't resolve** (bare hex IDs) because `usb.ids` isn't in the closure — point `usbutils` at `hwdata`'s `usb.ids` if you want labels. |
| `perl` | `brew uses --installed perl` empty → nothing depended on it. **Migrated to nix** (5.42.0); nix perl wins on PATH so any bare `perl` call still resolves. Uninstalling brew perl autoremoved its orphaned deps `berkeley-db@5` + `gdbm` for free. |
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

**Phantom kegs `autoremove` can't see.** `brew list` enumerates *Cellar
directories*, while `brew info --json=v2 --installed` lists *tracked* installs —
when they disagree, you have untracked orphan kegs. Seen this session:
`cryptography` (an *empty* Cellar dir) plus `python-cryptography` (a dangling
symlink → `cryptography`, left by the 2024 homebrew rename `python-cryptography`
→ `cryptography`). Both showed in `brew list`, depended on nothing
(`brew uses --installed` empty), and `brew info` reported "Not installed" — but
`brew autoremove` ignored them because they aren't in the tracked dependency
graph. Diagnose with `ls -la /opt/homebrew/Cellar/<name>` (empty dir or symlink
= phantom) and clear by hand: `rmdir` the empty dir, `rm` the dangling symlink.

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
perl/mint/mole-attempt resolved per the Tier 4 verdicts above.

**Third pass (2026-06-04, this machine):** migrated `mint`, the docker stack
(`docker`+`docker-buildx`+`docker-compose`), `cloudflared`, `perl`, and `cmake`
to nix — each verified (docker end-to-end against a live colima daemon; cmake via
a configure+build+run smoke test). This is where the "client/daemon boundary"
principle was nailed down: docker/cloudflared were Tier-3-by-association, not
genuine daemons. **Brew leaves 14 → 8.**

**Fourth pass (2026-06-04, same day):** migrated `git-xet` + its `git-lfs` dep,
`mactop` (the "shells out ≠ links in" reclassification), and `lsusb` (via
`usbutils` — the "attribute ≠ binary" fix) — plus swept the
`cryptography`/`python-cryptography` phantom kegs. **Brew leaves 8 → 4.** Now kept
on brew: `colima` + `lima` (the VM daemon stack), `icu4c@77` (transitive),
`llama.cpp` (Tier 2 — Metal validation still pending), `mole` (`meta.broken`),
and all casks (incl. `wezterm@nightly`).

**Migration pass (2026-06-19):** **migrated `colima` + `lima-full` to nix** —
disproving the earlier "macOS virtualization is brew-only" claim. Clean stateful
teardown (no containers): `colima stop && colima delete -f`, uninstall brew
colima (autoremove swept lima 2.0.3), `nix profile install nixpkgs#colima
nixpkgs#lima-full`, `colima start`. Verified end-to-end: fresh VM boots with
`vmType: vz` and `colima status` reports "macOS Virtualization.Framework"; docker
client 29.5.2 (nix) ↔ server 29.2.1 (nix VM); `hello-world` ran; `--platform
linux/amd64` returned `x86_64` (cross-arch emulation via lima-full+qemu). Also
documented `lima` vs `lima-full` (native vs all-arch guest agents). **Brew leaves
4 → 3** — `icu4c@77` (transitive), `llama.cpp` (Tier 2, Metal pending), `mole`
(`meta.broken`, the only hard blocker). Tier 3 is now effectively just casks.

## Open questions / future work

- `~/.config/nix/nix.conf` — **done** (2026-08-02): tracked as
  `config/nix/nix.conf`; `script/link-dotfiles` now maps `config/<path>` →
  `~/.config/<path>` (creating parent directories as needed).
- Tier 4 packages mostly decided in the 2026-06 session — see "Tier 4 verdicts"
  above. Still open: `git-xet` (xet protocol; verify gitconfig hooks before
  swapping). `mole` blocked upstream on `meta.broken` — recheck after a nixpkgs
  bump or file/track the fix.
- `llama.cpp` is the strongest Tier 2 candidate gated on validating Metal
  acceleration in the nix build.
- `nix store optimise` — **done** (2026-06): 307.6 MiB freed by hard-linking
  56,882 files. Re-run periodically after heavy installs.

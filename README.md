# .dotfiles

My CLI env — theme system + modern-unix tools + fish setup.
Works on Arch (with root), macOS, and no-root clusters (RHEL etc.).

## Install

```sh
git clone <this-repo> ~/.dotfiles
~/.dotfiles/install.sh                          # tools + fish config + kitty patch
~/.dotfiles/install.sh --with-helix             # also build helix from source
~/.dotfiles/install.sh --with-fish --with-helix # full cluster setup (no root)
```

Flags: `--force` reinstalls, `--dry-run` shows what would happen, `--with-helix`
builds helix from source, `--with-fish` builds fish 4.x from source
(needs `cmake` + `ncurses-devel` present on the system; rustup is auto-bootstrapped).
Set `DOTFILES_ENV=arch-root|mac|rhel-noroot|generic` to override auto-detection.

Idempotent — safe to re-run.

### macOS

Detected automatically (`uname -s == Darwin`). On a blank machine the script:
- bootstraps Homebrew if missing
- installs python3, fish, and kitty (cask) via `brew`, then everything in the
  tools list below via `brew install <formula>` (same package names as Arch)
- creates `~/.config/kitty/kitty.conf` if it doesn't exist yet, so the theme
  include still gets patched in
- runs `chsh -s $(which fish)` to make fish your login shell (adds it to
  `/etc/shells` first if needed) — this will prompt for your password
- `--with-helix` installs helix via `brew` instead of building from source

Not automated: a Nerd Font. Starship/eza/fastfetch icons need one for kitty to
render correctly — `brew install --cask font-jetbrains-mono-nerd-font` and set
it in kitty's `font_family`.

## What it installs

**Tools** (via `paru` on Arch, `brew` on macOS, prebuilt musl binaries elsewhere, `cargo install` fallback):
`fzf`, `bat`, `eza`, `fd`, `ripgrep`, `zoxide`, `delta`, `fastfetch`, `btop`, `glow`, `csvlens`, `yazi`, `zellij`.
(`zellij` ships prebuilt musl binaries and a cargo crate, so every install path
handles it.)

**Helix config** (`~/.config/helix/config.toml` symlink — any pre-existing
real file is backed up to `config.toml.bak` first):
- cursor changes shape per mode: block (normal), bar (insert), underline (select)
- `space e` — open yazi in the current file's directory; picking a file opens
  it as a new buffer (needs helix 25.01+ for the `%{buffer_name}`/`%sh{}`
  expansions it relies on)
- `A-,` / `A-.` — previous/next buffer (also available as the built-in `gp`/`gn`)
- `A-w` — close the current buffer
- `space b` — buffer picker (built into helix, no config needed)

**Fish conf.d** (`~/.config/fish/conf.d/env-setup.fish` symlink):
- `~/.local/bin` and `~/.cargo/bin` on PATH
- `zoxide init` (adds `z` and `zi`)
- `ls`/`ll`/`la`/`tree` → `eza`
- `cat` → `bat`
- `y` — yazi wrapper that `cd`s into the exit directory
- `theme` — the theme picker
- `fish_greeting` — runs `fastfetch` if installed

**Kitty patch** (local only, skipped if kitty absent):
- prepends `include ~/.config/kitty/theme-current.conf`
- adds `allow_remote_control socket-only` + `listen_on`
- removes any quickshell-generated theme include

**zellij patch** (skipped if zellij absent):
- seeds a managed theme block into `~/.config/zellij/config.kdl` (creating the
  file if needed) by running `theme-apply.py` once

## Theme system

Run `theme` in fish. Fuzzy-pick from ~170 helix themes (system + your custom
themes in `~/helix-ide/config/helix/themes/`). Live preview repaints kitty +
all helix instances as you scroll. Enter keeps, Esc restores.

Behind the scenes: `theme-apply.py` derives an ANSI palette from the helix
theme, writes `~/.config/kitty/theme-current.conf`, updates `theme = "..."` in
`~/.config/helix/config.toml`, calls `kitty @ set-colors --all --configured`,
and sends `SIGUSR1` to all `hx` processes (buffer-safe reload).

It also rewrites a managed `themes { theme-current { ... } }` block in
`~/.config/zellij/config.kdl` — tab bar, status line, and pane frames, derived
from the same palette. zellij has no ANSI-16 palette of its own (kitty supplies
that underneath it), so this only covers zellij's own UI chrome, not syntax
colors. The theme is inline in the main config, which zellij watches and
live-reloads on write — no reload signal needed, unlike `kitty @ set-colors`.

Yazi and Claude Code inherit from kitty's palette — no code needed there.

## Cluster caveat

The theme picker's kitty/zellij repaint steps only run where those tools are
installed. On the cluster, install grabs the tools and the fish env, skips
whichever patch doesn't apply. Terminal colors on the cluster come from your
*local* kitty via SSH — theme changes on your laptop propagate to your
remote helix for free. zellij, if present on the cluster, gets its own
locally-relevant theme (its UI-chrome colors don't need to match your laptop).

## Reverting

- Kitty: edit `~/.config/kitty/kitty.conf`, remove the `include
  theme-current.conf` line and the `allow_remote_control` line. Optionally
  re-add quickshell's include.
- zellij: edit `~/.config/zellij/config.kdl`, delete the `theme-system` block
  (everything between the `>>> theme-system` and `<<< theme-system` markers).
- Fish: `rm ~/.config/fish/conf.d/env-setup.fish`.
- Helix: pick any theme normally via `:theme` — `theme-apply.py` no longer
  rewrites `config.toml` once you stop calling it. To drop the tracked config
  entirely: `rm ~/.config/helix/config.toml` and restore
  `config.toml.bak` if install.sh made one.

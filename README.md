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
`fzf`, `bat`, `eza`, `fd`, `ripgrep`, `zoxide`, `delta`, `fastfetch`, `btop`, `glow`, `tmux`.
(`tmux` has no prebuilt binaries or cargo crate — the no-root/generic path just
skips it if it's not already there; it usually is on clusters.)

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

**tmux patch** (skipped if tmux absent):
- creates `~/.tmux.conf` if it doesn't exist yet
- appends `source-file -q ~/.config/tmux/theme-current.conf`

## Theme system

Run `theme` in fish. Fuzzy-pick from ~170 helix themes (system + your custom
themes in `~/helix-ide/config/helix/themes/`). Live preview repaints kitty +
all helix instances as you scroll. Enter keeps, Esc restores.

Behind the scenes: `theme-apply.py` derives an ANSI palette from the helix
theme, writes `~/.config/kitty/theme-current.conf`, updates `theme = "..."` in
`~/.config/helix/config.toml`, calls `kitty @ set-colors --all --configured`,
and sends `SIGUSR1` to all `hx` processes (buffer-safe reload).

It also writes `~/.config/tmux/theme-current.conf` — status bar, pane
borders, message line, and copy-mode selection highlight, derived from the
same palette. tmux has no ANSI-16 palette of its own (kitty supplies that
underneath it), so this only covers tmux's own UI chrome, not syntax colors.
If a tmux server is already running, `tmux source-file` reloads it live the
same way `kitty @ set-colors` does.

Yazi and Claude Code inherit from kitty's palette — no code needed there.

## Cluster caveat

The theme picker's kitty/tmux repaint steps only run where those tools are
installed. On the cluster, install grabs the tools and the fish env, skips
whichever patch doesn't apply. Terminal colors on the cluster come from your
*local* kitty via SSH — theme changes on your laptop propagate to your
remote helix for free. tmux, if present on the cluster, gets its own
locally-relevant theme (status bar colors don't need to match your laptop).

## Reverting

- Kitty: edit `~/.config/kitty/kitty.conf`, remove the `include
  theme-current.conf` line and the `allow_remote_control` line. Optionally
  re-add quickshell's include.
- tmux: edit `~/.tmux.conf`, remove the `source-file ... theme-current.conf`
  line.
- Fish: `rm ~/.config/fish/conf.d/env-setup.fish`.
- Helix: pick any theme normally via `:theme` — `theme-apply.py` no longer
  rewrites `config.toml` once you stop calling it.

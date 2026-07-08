# .dotfiles

My CLI env — theme system + modern-unix tools + fish setup.
Works on Arch (with root) and no-root clusters (RHEL etc.).

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
Set `DOTFILES_ENV=arch-root|rhel-noroot|generic` to override auto-detection.

Idempotent — safe to re-run.

## What it installs

**Tools** (via `paru` on Arch, prebuilt musl binaries elsewhere, `cargo install` fallback):
`fzf`, `bat`, `eza`, `fd`, `ripgrep`, `zoxide`, `delta`, `fastfetch`, `btop`, `glow`.

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

## Theme system

Run `theme` in fish. Fuzzy-pick from ~170 helix themes (system + your custom
themes in `~/helix-ide/config/helix/themes/`). Live preview repaints kitty +
all helix instances as you scroll. Enter keeps, Esc restores.

Behind the scenes: `theme-apply.py` derives an ANSI palette from the helix
theme, writes `~/.config/kitty/theme-current.conf`, updates `theme = "..."` in
`~/.config/helix/config.toml`, calls `kitty @ set-colors --all --configured`,
and sends `SIGUSR1` to all `hx` processes (buffer-safe reload).

Yazi and Claude Code inherit from kitty's palette — no code needed there.

## Cluster caveat

The theme picker only runs where kitty is installed. On the cluster, install
grabs the tools and the fish env, skips the kitty patch. Terminal colors on
the cluster come from your *local* kitty via SSH — theme changes on your
laptop propagate to your remote helix for free.

## Reverting

- Kitty: edit `~/.config/kitty/kitty.conf`, remove the `include
  theme-current.conf` line and the `allow_remote_control` line. Optionally
  re-add quickshell's include.
- Fish: `rm ~/.config/fish/conf.d/env-setup.fish`.
- Helix: pick any theme normally via `:theme` — `theme-apply.py` no longer
  rewrites `config.toml` once you stop calling it.

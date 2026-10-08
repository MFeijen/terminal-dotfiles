# .dotfiles

My CLI env — theme system + modern-unix tools + fish setup.
Works on Arch (with root), Fedora (incl. Asahi), macOS, and no-root clusters
(RHEL etc.), on x86_64 and aarch64.

## Install

```sh
git clone <this-repo> ~/.dotfiles
~/.dotfiles/install.sh                          # tools + fish config + ghostty patch
~/.dotfiles/install.sh --with-helix             # also build helix from source
~/.dotfiles/install.sh --with-fish --with-helix # full cluster setup (no root)
```

Flags: `--force` reinstalls, `--dry-run` shows what would happen, `--with-helix`
builds helix from source, `--with-fish` builds fish 4.x from source
(needs `cmake` + `ncurses-devel` present on the system; rustup is auto-bootstrapped).
Set `DOTFILES_ENV=arch-root|fedora-root|mac|rhel-noroot|generic` to override auto-detection.

Idempotent — safe to re-run.

### macOS

Detected automatically (`uname -s == Darwin`). On a blank machine the script:
- bootstraps Homebrew if missing
- installs python3, fish, and ghostty (cask) via `brew`, then everything in the
  tools list below via `brew install <formula>` (same package names as Arch)
- creates `~/.config/ghostty/config` if it doesn't exist yet, so the theme
  include still gets patched in
- runs `chsh -s $(which fish)` to make fish your login shell (adds it to
  `/etc/shells` first if needed) — this will prompt for your password
- `--with-helix` installs helix via `brew` instead of building from source

Not automated: a Nerd Font. Starship/eza/fastfetch icons need one for ghostty
to render correctly — `brew install --cask font-jetbrains-mono-nerd-font` and
set it in ghostty's `font-family`.

### Fedora

Detected when `/etc/fedora-release` exists and you can sudo (in `wheel` —
sudo prompts once). Without sudo it falls back to the no-root path. The script:
- installs fish and the tools below via `dnf` (`fd` is `fd-find` there);
  anything not in the enabled repos (`csvlens`, `yazi`, `zellij`, `eza` and
  `starship` unless their COPRs are on) comes from the prebuilt-binary path
- installs ghostty from the `scottames/ghostty` COPR (enables it first)
- runs `chsh -s $(which fish)` like on macOS
- `--with-helix` installs helix via `dnf` instead of building from source

## What it installs

**Tools** (via `paru` on Arch, `dnf` on Fedora, `brew` on macOS, prebuilt binaries elsewhere — musl where the project ships it, else gnu — `cargo install` fallback):
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

**Window manager** — AeroSpace on macOS, Hyprland on Linux, same binds on
both, pressed with the Alt key on both. AeroSpace's `alt-*` binds are
`super-*` on Hyprland (`mod` at the top of `hyprland/keybinds.lua`), and
Hyprland swaps Alt and Super, so Alt is the key that sends Super there:
- macOS: `~/.aerospace.toml` symlink to `aerospace/aerospace.toml`
- Linux (when Hyprland is installed): `hyprland/{general,rules,keybinds}.lua`
  symlinked into `~/.config/hypr/custom/` — the slot end-4's dots load after
  their own defaults and leave alone on update. Pre-existing real files are
  backed up to `*.lua.bak`; a running session is reloaded. Hyprland also
  auto-reloads when you save one of them.
- `mod-hjkl` focus, `mod-shift-hjkl` move, `mod-1..8` workspace,
  `mod-shift-1..8` send window there (focus stays), `mod-ctrl-h/l` prev/next
  workspace on this monitor, `mod-tab` back-and-forth, `mod-shift-tab`
  workspace to the next monitor, `mod-enter` ghostty, `mod-q` close, `mod-f`
  fullscreen (Hyprland's "maximized" — bar and gaps stay, like aerospace),
  `mod-minus`/`mod-equal` resize, `mod-r` resize mode, `mod-shift-;` service mode
- workspaces 1–8 always exist; 1–4 live on the laptop screen (eDP-1), 5–8 on
  the external (HDMI-A-1)
- Hyprland has no accordion layout, so `mod-,` stacks the workspace's windows
  into one group (tabs) and `mod-/` splits them back out (or flips the split
  when there's no group). Service-mode join-with (`mod-shift-hjkl`) groups a
  window with its neighbour; service-mode `r` dissolves all groups
- these replace end-4's binds on the same keys. Moved: lock to `ctrl-super-q`,
  cheatsheet to `super-shift-/`, real fullscreen to
  `super-shift-f`. Still elsewhere: suspend (session menu, `ctrl-alt-delete`),
  overview (4-finger swipe up), zoom (`super` + keypad `-`/`+`). Dropped: bar
  toggle (`super-j`), on-screen keyboard (`super-k`)
- Hyprland only: Caps Lock and Escape are swapped, and so are Alt and Super
  (`caps:swapescape,altwin:swap_alt_win` — all keyboards, including external ones)
- on macOS, `alt-,` shadows helix's `A-,` (previous buffer) — use `gp`

**Fish conf.d** (`~/.config/fish/conf.d/env-setup.fish` symlink):
- `~/.local/bin` and `~/.cargo/bin` on PATH
- `zoxide init` (adds `z` and `zi`)
- `ls`/`ll`/`la`/`tree` → `eza`
- `cat` → `bat`
- `y` — yazi wrapper that `cd`s into the exit directory
- `theme` — the theme picker (`--local` binds it to the current folder,
  `--ssh <host>` to a host)
- `ssh` — wrapper that paints the terminal with the host's bound theme
- `fish_greeting` — runs `fastfetch` if installed
- **zellij session prompt** — on opening an interactive terminal, offers to
  start a new zellij session, attach to an existing/exited one, or drop into a
  plain shell. Skipped when already inside zellij or when `ZELLIJ_NO_AUTOSTART`
  is set. Enter = new, a listed number = attach that session, `s` = plain shell.

**Ghostty patch** (local only, skipped if ghostty absent):
- appends `config-file = ?theme-current.conf` (ghostty loads a `config-file`
  *after* the file declaring it, so the theme wins wherever the line sits)
- on a fresh config only, seeds `macos-option-as-alt` and
  `shell-integration-features = ssh-env,ssh-terminfo` (remote terminfo install)
- Linux only: appends `command = <path to fish>` unless a `command` line is
  already there. Ghostty prefers `$SHELL` over your passwd entry, and a desktop
  session that was already running when `chsh` ran keeps the old `$SHELL` until
  you log in again. Log out and back in once anyway, so other tools that start
  `$SHELL` get fish too.
- no remote-control setup: the live repaint uses OSC escapes, not a socket

**zellij patch** (skipped if zellij absent):
- seeds a managed theme block into `~/.config/zellij/config.kdl` (creating the
  file if needed) by running `theme-apply.py` once

## Theme system

Run `theme` in fish. Fuzzy-pick from ~170 helix themes (system + your custom
themes in `~/helix-ide/config/helix/themes/`). Live preview repaints ghostty +
all helix instances as you scroll. Enter keeps, Esc restores.

Behind the scenes: `theme-apply.py` derives an ANSI palette from the helix
theme, writes `~/.config/ghostty/theme-current.conf`, updates `theme = "..."` in
`~/.config/helix/config.toml`, writes the palette to `/dev/tty` as OSC 4/10/11/
12/17/19 escapes, and sends `SIGUSR1` to all `hx` processes (buffer-safe reload).

The OSC escapes are why there's no reload step: ghostty has no remote-control
CLI (kitty's `kitty @ set-colors`), so the palette is pushed to the terminal
directly. That repaints the running window instantly. `theme-current.conf` is
what makes it *stick* for new windows — but those come from ghostty's
long-running process, which read the file at startup. On Linux, a final apply
also sends that process `SIGUSR2` (ghostty 1.2+ reloads its config on it, and
only processes that handle the signal get it), so new windows open in the new
theme. On macOS a **newly opened window keeps the old palette until you
reload** (`super+shift+,`) or restart ghostty.

It also rewrites a managed `themes { theme-current { ... } }` block in
`~/.config/zellij/config.kdl` — tab bar, status line, and pane frames, derived
from the same palette. zellij has no ANSI-16 palette of its own (ghostty
supplies that underneath it), so this only covers zellij's own UI chrome, not
syntax colors. The theme is inline in the main config, which zellij watches and
live-reloads on write — no reload signal needed.

Yazi and Claude Code inherit from ghostty's palette — no code needed there.

### Folder-local themes

`theme` sets the theme everywhere. `theme --local` binds the **current
directory** to a theme instead — only the terminal you ran it in repaints, and
only while you're inside that directory tree.

```fish
theme                # pick a global theme (all terminals, as before)
theme --local        # pick a theme for $PWD (this terminal only)
theme --unbind       # drop $PWD's binding
```

Bindings live in `~/.config/theme-system/local.toml` as `"<path>" = "<theme>"`
— nothing is written into your repos, so there's nothing to gitignore.
Subdirectories inherit; the nearest bound ancestor wins, so binding `~/work`
themes every project under it and binding `~/work/api` overrides it there.

A fish hook on `$PWD` reconciles the terminal on every `cd`: OSC escapes are
per-surface, so a local theme repaints just that window and leaves your other
terminals — and every global config file — untouched. The global theme in
`~/.config/helix/config.toml` stays the source of truth for unbound
directories.

Helix has no per-project theme and only reloads the config path it was started
with, so a local theme reaches it as a whole generated config in
`~/.cache/theme-system/helix-<theme>.toml`; a `hx` wrapper passes it with `-c`.
It's regenerated on every sync, so your keymaps and editor settings are never
stranded in a stale copy. An explicit `-c`/`--config` of your own wins.

Two things this deliberately doesn't do: zellij stays on the global theme (its
theme is one watched file, so it can't differ per window), and changing the
*global* theme repaints locally-bound terminals too — they snap back on their
next `cd`. The `cd` hook costs nothing until you bind your first folder; after
that it's ~50ms per directory change.

### Per-host themes

`theme --ssh <host>` binds a **host** to a theme, so `ssh prod` paints that
window red and `ssh laptop` doesn't — a glance tells you where you're typing.

```fish
theme --ssh myserver     # pick a theme for that host
ssh myserver             # terminal repaints, restores on logout
theme --unbind myserver  # drop the binding
```

Bindings share `~/.config/theme-system/local.toml` under `ssh:` keys. The host
is canonicalized through `ssh -G`, so `~/.ssh/config` aliases and flags like
`-p` resolve to the same key however you type the connection.

Ghostty's shell integration defines its own `ssh` wrapper (`ssh-env`,
`ssh-terminfo`) from a *vendor* conf.d — sourced after your own, from a
`fish_prompt` handler, so it wins any wrapper defined at source time. Ours
re-wraps on each prompt and before each command, keeping ghostty's as the inner
call, so its terminfo/env work still happens.

Nothing is installed on the remote: the `ssh` wrapper repaints the *local*
surface before connecting, and OSC colors already cross the connection (see
below). On exit the terminal is restored to whatever it should show locally,
which also repairs a palette the remote session changed itself.

## Cluster caveat

The theme picker's ghostty/zellij config steps only run where those tools are
installed. On the cluster, install grabs the tools and the fish env, skips
whichever patch doesn't apply. Terminal colors on the cluster come from your
*local* ghostty via SSH — theme changes on your laptop propagate to your
remote helix for free. zellij, if present on the cluster, gets its own
locally-relevant theme (its UI-chrome colors don't need to match your laptop).

## Reverting

- Ghostty: edit `~/.config/ghostty/config`, remove the `config-file =
  ?theme-current.conf` line, then reload with `super+shift+,`.
- zellij: edit `~/.config/zellij/config.kdl`, delete the `theme-system` block
  (everything between the `>>> theme-system` and `<<< theme-system` markers).
- Fish: `rm ~/.config/fish/conf.d/env-setup.fish`.
- Hyprland: `rm ~/.config/hypr/custom/{general,rules,keybinds}.lua`, rename
  the `.lua.bak` files back, then `hyprctl reload`.
- Helix: pick any theme normally via `:theme` — `theme-apply.py` no longer
  rewrites `config.toml` once you stop calling it. To drop the tracked config
  entirely: `rm ~/.config/helix/config.toml` and restore
  `config.toml.bak` if install.sh made one.

# .dotfiles

My CLI env — modern-unix tools + fish setup.
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
- installs fish and ghostty (cask) via `brew`, then everything in the
  tools list below via `brew install <formula>` (same package names as Arch)
- creates `~/.config/ghostty/config` if it doesn't exist yet
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
  (Enter on a folder opens Finder, `l` still enters it — `yazi/yazi.toml`, mac only)
- `fish_greeting` — runs `fastfetch` if installed
- **zellij session prompt** — on opening an interactive terminal, offers to
  start a new zellij session, attach to an existing/exited one, or drop into a
  plain shell. Skipped when already inside zellij or when `ZELLIJ_NO_AUTOSTART`
  is set. Enter = new, a listed number = attach that session, `s` = plain shell.

**Ghostty patch** (local only, skipped if ghostty absent):
- on a fresh config only, seeds `macos-option-as-alt` and
  `shell-integration-features = ssh-env,ssh-terminfo` (remote terminfo install)
- Linux only: appends `command = <path to fish>` unless a `command` line is
  already there. Ghostty prefers `$SHELL` over your passwd entry, and a desktop
  session that was already running when `chsh` ran keeps the old `$SHELL` until
  you log in again. Log out and back in once anyway, so other tools that start
  `$SHELL` get fish too.

## Reverting

- Leftovers from the removed theme system, on machines installed before it
  went: remove the `config-file = ?theme-current.conf` line from
  `~/.config/ghostty/config`, delete the `theme-system` block from
  `~/.config/zellij/config.kdl` (between the `>>> theme-system` and
  `<<< theme-system` markers), and `rm -r ~/.config/theme-system
  ~/.cache/theme-system`.
- Fish: `rm ~/.config/fish/conf.d/env-setup.fish`.
- Hyprland: `rm ~/.config/hypr/custom/{general,rules,keybinds}.lua`, rename
  the `.lua.bak` files back, then `hyprctl reload`.
- Helix: to drop the tracked config: `rm ~/.config/helix/config.toml` and restore
  `config.toml.bak` if install.sh made one.

# Handoff — CLI env & theme system

Everything a next session (or a fresh Claude) needs to pick this up cold.
Written 2026-07-08.

---

## Goal

One consistent theme across the terminal (kitty originally, ghostty since
2026-08-31 — see the migration section at the end), helix, yazi, and Claude Code — driven by
picking a helix theme via fuzzy picker. Plus a portable "install my CLI env"
script that works on Arch (with root) and no-root clusters (RHEL etc.).

## Design decisions (from grill session)

Every one of these was a fork we chose deliberately. Don't re-litigate without
reading these first.

| # | Decision | Why |
|---|----------|-----|
| Q1 | Replace quickshell's terminal theming with helix-driven | User wants deliberate control, not wallpaper-synced auto |
| Q2 | External fzf picker (not helix's native `:theme`) | Native picker can't broadcast to kitty; fzf can preview live across tools |
| Q3 | Palette fidelity: exact bg/fg from `ui.background`/`ui.text`, best-effort heuristic ANSI 16 | Ships all 174 themes; some ANSI mappings will be imperfect (accepted) |
| Q4 | Live reload on every fzf preview keystroke — both kitty and helix | The point is *seeing* the theme apply in real code, including syntax colors |
| Q5 | `pkill -SIGUSR1 hx` to all helix instances | SIGUSR1 is buffer-safe; user runs multiple helix rarely with different themes |
| Q6 | Own a separate file `~/.config/kitty/theme-current.conf`; kitty.conf `include`s it | Avoids fighting quickshell (which keeps writing its own file, ignored) |
| Q7 | Entry: fish alias `theme`, no keybind | ctrl+alt+t was taken by WM; user pivoted to just an alias |
| Q10 | Scope: theme picker + curated modern-unix tools; skips theme portion on cluster | Cluster has no kitty (SSH from local) |

Other locked choices:
- Repo location: `~/.dotfiles/`
- Tools installed: `fzf`, `bat`, `eza`, `fd`, `ripgrep`, `zoxide`, `delta`
- Install strategy: arch+root → `paru`, else → prebuilt musl binary from GitHub releases → `cargo install` fallback
- Yazi & Claude Code: **no code needed** — inherit from kitty
- Helix build: gated behind `--with-helix` flag (rustup + `cargo install --path helix-term`)
- Fish `y` function for yazi cd-integration included

## File map

```
~/.dotfiles/
├── install.sh                         # main installer (bash, portable)
├── README.md                          # user-facing docs
├── HANDOFF.md                         # this file
├── theme-system/
│   ├── theme-apply.py                 # theme parse → ghostty/zellij/helix sync
│   └── theme-picker.fish              # fish function `theme` (fzf UI)
└── fish/
    └── env-setup.fish                 # dropped into ~/.config/fish/conf.d/
```

## `install.sh` — what it actually does

1. Parses flags: `--with-helix`, `--force`, `--dry-run`
2. `detect_env()`: `arch-root` | `arch-noroot` | `rhel-noroot` | `debian-root` | `generic`
   - Override with `DOTFILES_ENV=...` env var
   - Detection uses `sudo -v -n` to check for cached sudo (won't prompt)
3. For each tool: skip if installed (unless `--force`), else:
   - Arch+root: `paru -S --needed`
   - Else: download prebuilt binary from GitHub → fall back to `cargo install`
4. If `--with-helix`: install rustup if missing → clone helix → `cargo install --path helix-term` → symlink runtime to `~/.config/helix/runtime`
5. Symlink `~/.dotfiles/fish/env-setup.fish` → `~/.config/fish/conf.d/env-setup.fish`
6. If kitty present: patch `~/.config/kitty/kitty.conf`
   - Prepend `include ~/.config/kitty/theme-current.conf`
   - Remove any `include`-of-quickshell-generated theme file
   - Append `allow_remote_control socket-only` + `listen_on unix:/tmp/kitty-%i`
   - Seed `theme-current.conf` with catppuccin_mocha if missing

## `theme-apply.py` — core logic

- Resolves `inherits =` chain in helix theme TOMLs (recursive, cycle-detected)
- Deep-merges palettes (child overrides parent)
- Derives:
  - `background` from `ui.background.bg` (fallback: palette `base`/`bg`/`background`/`base00`/`black`)
  - `foreground` from `ui.text` (string or `.fg`)
  - `cursor` from `ui.cursor.primary.bg` or `ui.cursor.fg` or `fg`
  - selection_bg/fg similarly
  - ANSI 16: prefer literal palette names (`red`, `green`, `blue`, `base08`..., `mauve`, `sapphire`, etc.); fall back to semantic roles (`error`, `string`, `function`); fall back to hardcoded catppuccin defaults
  - Bright variants: prefer `bright_red` etc.; fall back to `brighten()` (adds 24 to each channel)
- Writes `~/.config/kitty/theme-current.conf` (kitty conf format)
- Rewrites `theme = "..."` line in `~/.config/helix/config.toml`
- Runs `kitty @ set-colors --all --configured <file>`
- Runs `pkill -SIGUSR1 -x hx`

Modes:
- `theme-apply.py <name>` — apply
- `theme-apply.py --current` — print current theme name (from helix config.toml)
- `theme-apply.py --preview <name>` — apply + print swatch preview to stdout (used by fzf `--preview`)

**Requires python 3.11+** (for `tomllib`). Falls back to `tomli` package if importable.

## `theme-picker.fish` — fish function

- Snapshots current theme name via `theme-apply.py --current`
- Enumerates themes from `~/.config/helix/themes`, `~/helix-ide/config/helix/themes`, `/usr/lib/helix/runtime/themes` (in precedence order)
- Deduplicates by basename, sorts
- Feeds into `fzf` with `--preview 'python3 theme-apply.py --preview {}'`
- On Enter: applies selection (already applied by preview, but explicit)
- On Esc / empty: restores original

## Current state (as of handoff)

**Verified working:**
- `theme-apply.py` runs correctly on `catppuccin_mocha` and `ayu_dark`
- Kitty conf is regenerated with correct palette
- Fish `theme` function loads in fresh shells
- `install.sh` completed successfully on local Arch
  - `~/.config/kitty/kitty.conf` patched (include + allow_remote_control + listen_on)
  - `~/.config/fish/conf.d/env-setup.fish` symlinked
- Repo layout matches file map above

**NOT yet verified:**
- Live kitty reload during fzf preview (`kitty @ set-colors`)
- Live helix reload via SIGUSR1
- End-to-end user flow: run `theme`, browse, pick, everything updates
- Install on cluster (RHEL, no root) — untested; prebuilt-binary path is untested
- `--with-helix` flag — untested

## Open issue (as of last message) — RESOLVED, and moot since the ghostty migration

User reported "theme selector isn't doing anything" after running `install.sh`.

**Prime suspect:** kitty was already running before install.sh patched its
config. `allow_remote_control` and `listen_on` are read at kitty *startup*.
Running instance won't respond to `kitty @` commands. **Fix:** fully quit
kitty and relaunch. Test with `kitty @ ls` from a prompt — should print JSON.

**Diagnostic queued for user to run:**

1. `kitty @ ls` — does remote control respond?
2. `theme` (in fish) — does fzf open? Does scrolling change kitty colors?
3. `pkill -SIGUSR1 -x hx` — does an open helix repaint?

Waiting for user to report which of a/b/c fail.

## Debugging cheat-sheet

- **Ghostty not repainting:** the live swap is OSC escapes on `/dev/tty`, so check you're in a real tty (`test -t 1`) — under a pipe or a CI runner it silently no-ops by design. Check the config is wired: `ghostty +show-config | grep background` should show the theme's color, and `ghostty +validate-config` should exit 0. Remember a **newly opened window** keeps the old palette until `super+shift+,` — that's expected, not a bug (ghostty reads config at app start)
- **Helix not repainting:** check `hx` is actually running; check config.toml was updated (`cat ~/.config/helix/config.toml`); manually send `pkill -SIGUSR1 -x hx`
- **Theme function not found:** check symlink `ls -l ~/.config/fish/conf.d/env-setup.fish`; re-source with `source ~/.config/fish/conf.d/env-setup.fish`; restart fish
- **Custom themes missing from picker:** check `~/helix-ide/config/helix/themes/` exists; check `.toml` extension; run `ls` on each theme_dir in the fish function
- **Palette looks weird for a theme:** the ANSI heuristic mis-mapped for that theme. Options: hand-tune `pick()` calls in `derive_palette()` for specific palette-name conventions, or add a per-theme override table
- **Backing the theme system out of ghostty:** delete the `config-file = ?theme-current.conf` line from `~/.config/ghostty/config` and reload (`super+shift+,`)

## Things intentionally NOT built

- Yazi theme file — yazi inherits the terminal palette (kitty then, ghostty now)
- Claude Code theme — same, inherits from the terminal
- Helix keybind for `theme` — user picked fish alias only
- Terminal keybind — user picked fish alias only
- Per-theme hand-tuning of ANSI mapping — accepted "best effort" fidelity (Q3)
- Dotfiles for anything beyond fish conf.d — configs stay per-machine
- fzf.fish plugin, ctrl+r history search, etc. — user asked but then said "just build the selecter" and moved on
- Backwards-compat with quickshell running in parallel — quickshell keeps writing its file, we ignore it

## Environment context

- User: `mees.feijen@gmail.com`
- Local: Arch Linux, Hyprland + quickshell (looks like an ML4W-derived rice), fish shell, kitty terminal, helix editor
- Kitty font: JetBrains Mono Nerd Font, size 11
- Existing helix config: theme was `base16_transparent` (inherit from terminal); now managed by `theme-apply.py`
- Custom helix themes: `~/helix-ide/config/helix/themes/{beans_clear,term-bg}.toml`
- Cluster: RHEL, no root, rust already built there, helix already built there
- Existing `~/dotfiles/` (no leading dot) is mylinuxforwork/dotfiles Hyprland pack — **don't touch it**

## macOS support (added 2026-07-12)

`detect_env()` returns `mac` on Darwin. `install_tool`'s brew branch reuses the
existing `arch_pkg` column as the brew formula name (they match for every tool
in the list — verified against homebrew-core). Mac-only additions, gated on
`ENVKIND == mac`:
- `ensure_brew`/`install_via_brew`: bootstraps Homebrew if missing, `eval`s
  `brew shellenv` so PATH is correct for the rest of the script's run
- `setup_mac_essentials`: installs python3 (needed by `theme-apply.py`'s
  `tomllib`), fish, and kitty (cask) — none of these were in the generic
  tool list since they need cask/shell-change handling
- `build_helix` tries `brew install helix` before falling back to the
  cargo source build
- `patch_kitty` creates `kitty.conf` if absent (fresh installs won't have
  one), and the quickshell-include removal was rewritten from `sed -i` to
  `grep -v` + tmpfile — GNU `sed -i` and BSD/macOS `sed -i` have incompatible
  flag syntax, this dodges it rather than branching on it
- `setup_fish_shell_mac`: adds fish to `/etc/shells` and runs `chsh -s`
  (user explicitly asked for this — it's a system-wide account change,
  prompts for password)

`theme-picker.fish` was already portable for this: `theme-system/themes/`
vendors the full helix theme catalog (see commit `368f43a`) so the picker
works with zero themes installed, same mechanism that covers the RHEL
cluster case.

**Verified end-to-end on the user's real Mac (2026-07-13)** — this surfaced
bugs the design review didn't catch:
- `install.sh` and `theme-apply.py` both hardcoded `~/.dotfiles` as the repo
  path; the user's actual clone is `~/terminal-dotfiles`. Every symlink and
  the theme-seed step pointed at nothing. Fixed by self-locating from the
  script's own path (`SCRIPT_DIR`/`Path(__file__)`) instead of a hardcoded
  name. `theme-picker.fish` and `fish/env-setup.fish` had the same hardcoded
  fallback, fixed to match — `env-setup.fish` in particular resolves it via
  `dirname (dirname (realpath (status -f)))` since it's loaded through a
  symlink from `conf.d/`.
- `setup_mac_essentials` checked `have python3`, true for macOS's bundled
  `/usr/bin/python3` (3.9, no `tomllib`) — it shadowed brew's newer one and
  never got replaced. Now checks the actual version on PATH.
- Bigger one: once `chsh` makes fish the login shell, brew's `/opt/homebrew/bin`
  vanishes from PATH entirely on a fresh terminal window — bash/zsh get it
  from macOS's `/etc/paths.d/homebrew` via `path_helper`, which fish never
  calls. Fixed by sourcing `brew shellenv fish` at the top of
  `env-setup.fish`. This one's easy to miss in testing because a `fish`
  launched *inside* an already-brew-configured zsh session inherits the
  right PATH regardless — it only breaks on a real fresh login.
- `chsh` also doesn't take effect for the *current* GUI session — loginwindow/
  Terminal.app cache the shell from session start. Directory Services updates
  immediately (`dscl`, `dscacheutil` all show it), but a log out/in or reboot
  is needed before new windows actually launch fish. Not a bug, just a thing
  to warn the user about every time.

## tmux support (added 2026-07-13)

Added at user request, with full live theming (not just tool-install) since
`derive_palette()` in `theme-apply.py` already produces everything needed —
tmux just needed to be a second consumer of it.

- `install.sh`: `tmux` added to the `install_tool` list. It has no prebuilt
  binaries (source tarballs only, no GitHub release assets) and no cargo
  crate, so the no-root/generic fallback just skips it — acceptable since
  tmux is usually already present on clusters anyway.
- `patch_tmux()` mirrors `patch_kitty()`: creates `~/.tmux.conf` if absent,
  appends `source-file -q ~/.config/tmux/theme-current.conf`. Deliberately
  `~/.tmux.conf` and not the XDG `~/.config/tmux/tmux.conf` tmux 3.1+ also
  checks — `~/.tmux.conf` works on every tmux version.
- `theme-apply.py`: new `write_tmux_conf()`/`derive_tmux_style()` /
  `reload_tmux()`. Key design point: tmux is a multiplexer, not a terminal
  emulator — it has no ANSI-16 palette of its own (kitty supplies that
  underneath it). So tmux only gets UI-chrome styling: status bar,
  active/inactive window tabs, pane borders, message line, copy-mode
  selection highlight (`mode-style`, mapped to the same selection colors
  helix/kitty use). Accent color is `palette["color4"]` (blue) — used for
  active pane border, current window highlight, and message-line background.
- `reload_tmux()` only runs `tmux source-file` if a server is already
  running (`tmux list-sessions` exit code) — otherwise it'd spawn a
  throwaway server just to set options nothing would see, mirroring how
  `reload_kitty`/`reload_helix` are also no-ops when those aren't running.
- No changes needed to `theme-picker.fish` — it just calls
  `theme-apply.py <name>`, which now handles kitty+tmux+helix internally.
  The picker's fzf UI is a generic front-end already.
- Verified live: wrote the file, sourced it into a real tmux session with
  `tmux source-file`, confirmed `tmux show-options -g status-style` reflects
  the new colors. Ran through `install.sh` for real — `patch_tmux` created
  `~/.tmux.conf` and seeded `theme-current.conf` correctly on first run.

## gtop support (added 2026-07-14)

Reported as "theme does not work for gtop" — colors didn't change at all while
kitty/helix/tmux did.

Root cause (traced through source, not guessed): gtop is *not* a color-model
problem. Its colors are the six blessed named colors (`utils.colors =
['magenta','cyan','blue','yellow','green','red']`), all ANSI indices 1–6.
blessed emits those as plain SGR `\e[31m`–`\e[36m` (program.js: the `color <
16` branch), and the line graphs go through drawille-canvas which does the same
(`'\033[3' + colors[name] + 'm'`). So every cell is *palette-indexed* — kitty
renders it from the themeable `color1`–`color6` that `theme-apply.py` already
writes. gtop inherits from kitty for free, exactly like yazi/Claude Code.

The bug was **delivery, not color**: kitty's `set-colors` updates the palette
for future output but does not retroactively recolor already-drawn cells, and
blessed's normal per-frame `render()` only re-emits cells whose glyph changed
(diffed against `olines`). A mostly-static graph therefore never re-emits its
color codes, so it keeps whatever kitty resolved at first draw. kitty/helix/tmux
looked fine only because each gets an explicit full-redraw trigger
(`set-colors` default fg/bg, `source-file`, `SIGUSR1`); gtop got none.

Fix: `reload_gtop()` sends `pkill -SIGWINCH -f gtop`. SIGWINCH → blessed
`screen.alloc()` (resets `olines`, clears screen) + `render()` = full repaint,
re-emitting every cell against kitty's now-updated palette. Direct analog of
`reload_helix()`'s `pkill -SIGUSR1 -x hx`. Uses `-f` (argv match) not `-x`
because the process name is `node`, with gtop in its arguments. Called after
`reload_kitty()` so the palette is already updated when gtop repaints; harmless
no-op (`check=False`, rc 1) when gtop isn't running. SIGWINCH's default
disposition is "ignore", so a loose `-f gtop` match can't damage bystanders.

Not added: gtop to the `install.sh` tool list — it's an npm package, out of
scope for the current installer, and wasn't requested.

## Switched tmux → zellij (2026-07-15)

Dropped tmux entirely, replaced with zellij as the multiplexer. Same "second
consumer of `derive_palette()`" model as tmux was — only the delivery mechanism
differs, because zellij's theming works nothing like tmux's.

- `install.sh`: `tmux` line in the `install_tool` list → `zellij`
  (`zellij-org/zellij`, `x86_64-unknown-linux-musl.tar.gz`, cargo crate
  `zellij`). Unlike tmux, zellij ships prebuilt binaries *and* has a crate, so
  the no-root/generic path installs it too — no special-casing.
- **Key difference from tmux — delivery.** tmux sourced a separate generated
  file (`theme-current.conf`) and reloaded via `tmux source-file`. zellij has
  no KDL `include`/`source` mechanism, and — critically — only live-reloads
  themes defined *inline in the main config*; themes dropped in the `themes/`
  folder are read once at startup and not watched. So `theme-apply.py` owns a
  delimited block (`>>> theme-system … <<< theme-system` KDL line comments)
  written straight into `~/.config/zellij/config.kdl`. `write_zellij_conf()`
  regex-replaces that block in place (or appends it) and leaves the rest of the
  user's config untouched.
- **No reload signal.** Because the theme is inline, zellij's own config watcher
  live-reloads it the instant the file is written — so there's no
  `reload_zellij()` at all (the tmux analog `reload_tmux()` was deleted). The
  write *is* the signal. This is the one spot where zellij is simpler than tmux.
- `derive_zellij_theme()` replaces `derive_tmux_style()`. zellij's classic theme
  format is just `fg`/`bg` + the eight base ANSI hues + `orange`; zellij derives
  all its own chrome (tab bar, status line, pane frames) from those, so we don't
  hand-map individual UI elements the way tmux's `status-style` etc. required.
  ANSI-16 has no dedicated orange → mapped to `color3` (yellow), nearest hue.
  Colors emitted as hex strings (`fg "#rrggbb"`), which the classic format
  accepts.
- `patch_zellij()` replaces `patch_tmux()`: if config.kdl doesn't already
  contain the `theme-system` marker, run `theme-apply.py` once to seed it
  (creating config.kdl if absent). `grep -qs` tolerates the missing file.
- README updated (tool list, patch section, theme-system + cluster + reverting
  paragraphs). Reverting is now "delete the marked block from config.kdl".
- No changes to `theme-picker.fish` — it just calls `theme-apply.py <name>`.

### Session prompt at terminal startup

`zellij/zellij-startup.fish` (sourced from `env-setup.fish`, same standalone-file
pattern as the theme/starship pickers — no new install.sh symlink needed since
`env-setup.fish` resolves the repo root and sources it). Runs during conf.d
sourcing (before the first prompt) so a choice drops you straight into a session.

- Guards, all early-`return`: non-interactive shell, zellij not installed,
  already inside a session (`$ZELLIJ`), opt-out (`$ZELLIJ_NO_AUTOSTART`), or no
  tty on stdin/stdout. The `$ZELLIJ` guard is what keeps new panes/subshells
  inside a session from re-prompting.
- Menu from `zellij list-sessions --short --no-formatting` (names only, no ANSI;
  includes exited-but-resurrectable sessions — `zellij attach <name>` resurrects
  a dead one). Enter/`n` → new session, a listed number → attach that one,
  `s`/anything else → plain shell (out-of-range numbers fall through to plain).
- Runs zellij, does **not** `exec` it — quitting/detaching (Ctrl-o d) returns to
  a normal shell instead of closing the terminal, which keeps the "plain shell"
  option meaningful. Swap to `exec zellij` if you want the terminal to close
  with the session.
- Menu is colored via `set_color` with ANSI color *names* (green keys, cyan
  session names, magenta title) — names not hex, so they resolve through the
  palette kitty+zellij already themed and the menu matches the active theme for
  free.
- **Horizontally centered** as a block: one shared left margin (spaces) on every
  line, so entries stay left-aligned within the block while the block sits in the
  middle. Margin = `(tput cols - widest_line) / 2`, widths measured on the plain
  text with `string length` (never the colored strings). Only spaces are used for
  padding — they survive fish command substitution, unlike newlines. No vertical
  centering / screen-clear: an earlier full box attempt hit two fish gotchas
  (command-sub eats newlines; `_` is a read-only var so `for _ in …` fails), so
  the robust horizontal-only version is what's kept.
- Verified: fish `-n` syntax, guard no-ops (`$ZELLIJ` set, non-interactive,
  opt-out), and the dispatch table for every input class
  (attach/new/skip/out-of-range/junk).

## Migrated kitty → ghostty (2026-08-31)

Full replacement, not dual-support: kitty is gone from `install.sh` and
`theme-apply.py`. (`~/.config/kitty/` is left on disk untouched — nothing was
deleted from the machine, so falling back is just relaunching kitty.) zellij was
deliberately left in scope-untouched; ghostty's native tabs/splits arguably
replace it, but that's a separate decision.

**The one real architectural change — how the live repaint is delivered.**
Everything else was renaming. kitty had a remote-control socket, so
`reload_kitty()` shelled out to `kitty @ set-colors --all --configured`. Ghostty
has no remote-control CLI at all; its only config-reload trigger is the
`super+shift+,` keybind, which nothing external can fire. Verified against the
installed binary, not assumed: `ghostty +list-actions` has `reload_config` only
as a *keybind* action, and `ghostty --help` lists no equivalent of `kitty @`.

So `set_colors_osc()` replaces `reload_kitty()` and pushes the palette to the
terminal as standard OSC escapes instead — OSC 4 (ANSI 16), 10/11/12 (fg/bg/
cursor), 17/19 (selection bg/fg). Confirmed supported: the binary's config docs
state "Ghostty currently supports OSC 10 (foreground), OSC 11 (background), and
OSC 4 (256 color palette)". This is strictly better than the socket in three
ways — instant (no reload round-trip), no emulator-side setup to enable
(`allow_remote_control`/`listen_on` are gone from the install patch), and it
works verbatim over SSH.

Two consequences worth knowing:
- **Written to `/dev/tty`, never stdout.** During `theme`'s fzf preview, stdout
  is a pipe fzf renders into — escapes sent there would print as literal garbage
  in the preview pane instead of reaching the terminal. Wrapped in
  `except OSError: pass` so a missing controlling terminal is a silent no-op and
  the config write still lands.
- **Known ceiling: new windows lag.** OSC repaints the *running* surface.
  `theme-current.conf` is what persists the choice, but ghostty reads config at
  app start — so a window opened after a theme change shows the old palette
  until `super+shift+,` or an app restart. kitty's `--configured` flag updated
  both at once; there is no ghostty equivalent. Accepted rather than worked
  around (the alternative is synthesizing the keybind via AppleScript, which
  needs Accessibility permission for a cosmetic edge case).

Mechanical parts:
- `write_kitty_conf()` → `write_ghostty_conf()`. Ghostty spells the ANSI 16 as
  repeated `palette = <n>=<hex>` lines rather than kitty's one `colorN` key
  each, and uses `cursor-color`/`selection-background`/`selection-foreground`.
  The internal `derive_palette()` dict is unchanged and still the neutral
  intermediate — `derive_zellij_theme()` and `print_swatch()` consume it as
  before, so only the writer was swapped.
- `patch_kitty()` → `patch_ghostty()`, and it got *simpler*: `config-file` is
  applied **after** the file that declares it, so appending is enough — no
  prepend-via-tmpfile dance like kitty's `include` needed. The quickshell-include
  strip went away with it (that was Arch/kitty-specific and long dead here).
- Fresh-config seed only (mirrors the existing `starship.toml` "never stomp an
  existing file" pattern): `macos-option-as-alt = true`, carried over from the
  old `kitty.conf`, plus `shell-integration-features = ssh-env,ssh-terminfo`.
- **`shell-integration-features` is the native replacement for the old
  `kitten ssh` wrapper** that `env-setup.fish` had commented out. Those two flags
  are OFF by default (`no-ssh-env,no-ssh-terminfo`) — checked, not assumed. They
  install the `xterm-ghostty` terminfo entry on the remote and fall back to
  `xterm-256color` when the host has no `tic`, which is exactly what the kitten
  wrapper did, minus its fatal flaw (kitten refused outright on non-tty stdin,
  breaking scripts and VS Code Remote-SSH probes). Also verified the flag set
  *merges* rather than replaces — resolved value keeps `cursor,title,path`.
  The dead commented-out fish block was deleted.

**Verified:**
- Generated config for 4 themes (catppuccin_mocha, gruvbox_dark_soft,
  github_light, rose_pine_moon); asserted 21 settings each, 16 of them `palette`.
- `ghostty +validate-config` exits 0 against the real `~/.config/ghostty/config`
  + its `config-file`d theme.
- `ghostty +show-config` confirms the theme's colors override ghostty's defaults
  (i.e. the `config-file` precedence works as documented), and that
  `shell-integration-features`/`macos-option-as-alt` resolve as intended.
- Real cutover run: `~/.config/ghostty/config` seeded, `theme-apply.py
  catppuccin_frappe` (the already-active theme, so a deliberate colour no-op).

**Not verified:** the live OSC repaint during an interactive `theme` fzf session
— that needs a real tty, which the agent shell isn't. Run `theme` and confirm
colors move as you scroll.

## Style notes for future edits

- User prefers terse responses, no fluff
- User is technical, doesn't want hand-holding but does want the "why"
- One question at a time during design discussions (grill-me pattern)
- Confirm before destructive/system-wide changes

## Folder-local theme now reaches helix from any launcher (2026-09-24)

Reported as "hx doesn't switch color when I enter a new folder". The local
theme only ever reached helix through the fish `hx` function, and fish
functions don't exist in child processes — so `yazi` (which runs `$EDITOR`),
git, and anything else launched the real binary with no `-c` and got the
global theme. Confirmed on the live session: the running `hx` had yazi as its
parent and no `-c` in its argv.

Fix: `theme-system/hx-local`, a 3-line sh wrapper that is now what `$EDITOR`
names *and* what the fish function delegates to — one injection point for
every launch route. It resolves the binding from its **own cwd** (via the new
`theme-apply.py --config-path`) rather than an inherited variable, which also
fixes navigating into another project *inside* yazi: yazi spawns the editor
with the hovered folder as cwd.

Dropped with it: `HELIX_LOCAL_CONFIG` (nothing reads it now) and the variant
write on every `cd` — `--sync` is purely the terminal repaint, and the variant
is generated at helix launch instead. `--config-path` prints it, nothing else.

Covered by `test_theme_local.py::test_hx_wrapper_injects_config` (fake `hx` on
PATH, asserts the argv for bound/inherited/unbound dirs and an explicit `-c`).

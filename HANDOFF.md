# Handoff — CLI env & theme system

Everything a next session (or a fresh Claude) needs to pick this up cold.
Written 2026-07-08.

---

## Goal

One consistent theme across kitty, helix, yazi, and Claude Code — driven by
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
│   ├── theme-apply.py                 # theme parse → kitty/helix sync
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

## Open issue (as of last message)

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

- **Kitty not repainting:** check `kitty @ ls` works; check `allow_remote_control` in effect via `kitty --debug-config | grep remote`; check `theme-current.conf` exists and is valid
- **Helix not repainting:** check `hx` is actually running; check config.toml was updated (`cat ~/.config/helix/config.toml`); manually send `pkill -SIGUSR1 -x hx`
- **Theme function not found:** check symlink `ls -l ~/.config/fish/conf.d/env-setup.fish`; re-source with `source ~/.config/fish/conf.d/env-setup.fish`; restart fish
- **Custom themes missing from picker:** check `~/helix-ide/config/helix/themes/` exists; check `.toml` extension; run `ls` on each theme_dir in the fish function
- **Palette looks weird for a theme:** the ANSI heuristic mis-mapped for that theme. Options: hand-tune `pick()` calls in `derive_palette()` for specific palette-name conventions, or add a per-theme override table
- **Reverting quickshell control:** revert the two changes at top of `~/.config/kitty/kitty.conf` (the `include` and the `allow_remote_control`/`listen_on` lines). Re-add `include ~/.local/state/quickshell/user/generated/terminal/kitty-theme.conf` if desired

## Things intentionally NOT built

- Yazi theme file — yazi inherits terminal palette from kitty
- Claude Code theme — same, inherits from kitty
- Helix keybind for `theme` — user picked fish alias only
- Kitty keybind — user picked fish alias only
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

## Style notes for future edits

- User prefers terse responses, no fluff
- User is technical, doesn't want hand-holding but does want the "why"
- One question at a time during design discussions (grill-me pattern)
- Confirm before destructive/system-wide changes

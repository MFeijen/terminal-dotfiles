#!/usr/bin/env bash
# install.sh — set up my CLI env on a fresh machine.
# Idempotent. Safe to re-run. Detects arch+root vs rhel+noroot vs other.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="${DOTFILES:-$SCRIPT_DIR}"
LOCAL_BIN="$HOME/.local/bin"
CARGO_BIN="$HOME/.cargo/bin"
CONFIG="$HOME/.config"

WITH_HELIX=0
WITH_FISH=0
CLUSTER=0
FORCE=0
DRY=0
for arg in "$@"; do
    case "$arg" in
        --with-helix) WITH_HELIX=1 ;;
        --with-fish)  WITH_FISH=1 ;;
        --cluster)    CLUSTER=1 ;;
        --force)      FORCE=1 ;;
        --dry-run)    DRY=1 ;;
        -h|--help)
            cat <<EOF
Usage: install.sh [--with-helix] [--with-fish] [--cluster] [--force] [--dry-run]

  --with-helix   Also build helix from source (via rustup + cargo)
  --with-fish    Also build fish shell from source (via rustup + cmake)
  --cluster      Apply cluster-side fixes (guard bare 'fish' in ~/.bashrc so
                 kitten ssh's non-interactive bootstrap can complete cleanly)
  --force        Reinstall tools even if already present
  --dry-run      Show what would happen, don't do it
EOF
            exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

# --- utility -----------------------------------------------------------------

log()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; }
run()  { if ((DRY)); then echo "+ $*"; else eval "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

mkdir -p "$LOCAL_BIN" "$CONFIG/fish/conf.d"

# --- environment detection ---------------------------------------------------

detect_env() {
    # "root" here means "can invoke a system package manager with sudo".
    # We assume sudo is available if the user is in a machine's sudoers file;
    # can be overridden with DOTFILES_ENV=... env var.
    if [[ -n "${DOTFILES_ENV:-}" ]]; then echo "$DOTFILES_ENV"; return; fi
    if [[ "$(uname -s)" == "Darwin" ]]; then echo "mac"; return; fi
    if have pacman && sudo -v -n 2>/dev/null; then echo "arch-root"; return; fi
    if have pacman; then echo "arch-noroot"; return; fi
    if [[ -f /etc/redhat-release ]]; then echo "rhel-noroot"; return; fi
    if have apt-get && sudo -v -n 2>/dev/null; then echo "debian-root"; return; fi
    echo "generic"
}

ENVKIND=$(detect_env)
log "detected environment: $ENVKIND"

# --- prebuilt-binary installer ----------------------------------------------
# usage: install_binary <name> <github-repo> <asset-regex> <binary-in-archive>
install_binary() {
    local name=$1 repo=$2 pattern=$3 binpath=$4
    have curl || { err "curl missing"; return 1; }
    log "  fetching $name from github.com/$repo"
    local url
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | python3 -c "
import sys, json, re
d = json.load(sys.stdin)
p = re.compile(r'$pattern')
for a in d['assets']:
    if p.search(a['name']):
        print(a['browser_download_url']); break
")
    if [[ -z "$url" ]]; then err "no asset matched /$pattern/ for $name"; return 1; fi
    local tmp; tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" RETURN
    local file="$tmp/$(basename "$url")"
    if ((DRY)); then
        echo "+ would download $url and install $binpath to $LOCAL_BIN"
        return 0
    fi
    run "curl -fsSL -o '$file' '$url'"
    case "$file" in
        *.tar.gz|*.tgz) run "tar -xzf '$file' -C '$tmp'" ;;
        *.tar.xz)       run "tar -xJf '$file' -C '$tmp'" ;;
        *.tar.bz2|*.tbz) run "tar -xjf '$file' -C '$tmp'" ;;
        *.zip)          run "unzip -q '$file' -d '$tmp'" ;;
        *)              run "cp '$file' '$tmp/bin'" ;;
    esac
    local found
    found=$(find "$tmp" -type f -name "$binpath" -executable 2>/dev/null | head -1)
    [[ -z "$found" ]] && found=$(find "$tmp" -type f -name "$binpath" 2>/dev/null | head -1)
    if [[ -z "$found" ]]; then err "$binpath not in archive"; return 1; fi
    run "install -m 0755 '$found' '$LOCAL_BIN/$binpath'"
    log "  installed $binpath -> $LOCAL_BIN"
}

# --- cargo installer ---------------------------------------------------------
install_via_cargo() {
    local crate=$1 bin=${2:-$1}
    have cargo || { err "cargo missing (try --with-helix to bootstrap rust)"; return 1; }
    log "  cargo install $crate (this takes a while)"
    run "cargo install --locked '$crate'"
}

# --- system-package installer -----------------------------------------------
install_via_paru() {
    local pkg=$1
    if have paru; then
        run "paru -S --needed --noconfirm '$pkg'"
    elif have pacman; then
        run "sudo pacman -S --needed --noconfirm '$pkg'"
    else
        return 1
    fi
}

# --- homebrew installer (mac) -------------------------------------------------
ensure_brew() {
    if ! have brew; then
        log "  installing Homebrew"
        run '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    fi
    local brew_bin=""
    if [[ -x /opt/homebrew/bin/brew ]]; then brew_bin=/opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then brew_bin=/usr/local/bin/brew
    else brew_bin=$(command -v brew || true); fi
    [[ -n "$brew_bin" ]] && eval "$("$brew_bin" shellenv)"
}

install_via_brew() {
    local pkg=$1 cask=${2:-0}
    ensure_brew || return 1
    if ((cask)); then
        run "brew install --cask '$pkg'"
    else
        run "brew install '$pkg'"
    fi
}

# --- unified tool install ----------------------------------------------------
# usage: install_tool <bin> <pkg-name> <github-repo> <asset-regex> <cargo-crate>
# <pkg-name> doubles as the paru package name (arch-root) and the brew formula
# name (mac) — they happen to match for every tool in the list below.
install_tool() {
    local bin=$1 arch_pkg=$2 repo=$3 pattern=$4 crate=$5
    if have "$bin" && ((!FORCE)); then
        log "$bin: already installed ($(command -v "$bin"))"
        return 0
    fi
    log "$bin: installing"
    case "$ENVKIND" in
        arch-root)
            install_via_paru "$arch_pkg" && return 0
            ;;
        mac)
            install_via_brew "$arch_pkg" && return 0
            ;;
    esac
    # no-root path: prebuilt binary → cargo fallback → skip
    if install_binary "$bin" "$repo" "$pattern" "$bin"; then return 0; fi
    if [[ -n "$crate" ]] && have cargo; then
        warn "$bin: prebuilt binary failed, trying cargo"
        install_via_cargo "$crate" "$bin" && return 0
    fi
    warn "$bin: install failed — skipping"
    return 0
}

# --- mac-only bootstrap -------------------------------------------------------
# fish, kitty, and python3 (needed by theme-apply.py) aren't in the generic
# install_tool list above since they need cask/shell-change/no-cargo-fallback
# handling that doesn't apply to the other envs.
setup_mac_essentials() {
    # macOS ships an old /usr/bin/python3 (no tomllib, needs 3.11+) that
    # shadows brew's — check the version actually on PATH, not just presence.
    if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
        log "python3: installing (brew, needed by theme-apply.py's tomllib)"
        install_via_brew python
    fi
    if ! have fish; then
        log "fish: installing (brew)"
        install_via_brew fish
    else
        log "fish: already installed ($(command -v fish))"
    fi
    if ! have kitty; then
        log "kitty: installing (brew cask)"
        install_via_brew kitty 1
    else
        log "kitty: already installed ($(command -v kitty))"
    fi
}

if [[ "$ENVKIND" == "mac" ]]; then
    ensure_brew
    setup_mac_essentials
fi

# --- tools -------------------------------------------------------------------
# For no-root path: match the *asset name* from the release, not the binary name.
# Pattern is a Python regex; we search (not match).

install_tool fzf     fzf     junegunn/fzf         'linux_amd64\.tar\.gz$'                    ''
install_tool bat     bat     sharkdp/bat          'x86_64-unknown-linux-musl\.tar\.gz$'     'bat'
install_tool eza     eza     eza-community/eza    'x86_64-unknown-linux-musl\.tar\.gz$'     'eza'
install_tool fd      fd      sharkdp/fd           'x86_64-unknown-linux-musl\.tar\.gz$'     'fd-find'
install_tool rg      ripgrep BurntSushi/ripgrep   'x86_64-unknown-linux-musl\.tar\.gz$'     'ripgrep'
install_tool zoxide  zoxide  ajeetdsouza/zoxide   'x86_64-unknown-linux-musl\.tar\.gz$'     'zoxide'
install_tool delta   git-delta dandavison/delta   'x86_64-unknown-linux-musl\.tar\.gz$'     'git-delta'
install_tool fastfetch fastfetch fastfetch-cli/fastfetch 'linux-amd64\.tar\.gz$'             ''
install_tool btop    btop    aristocratos/btop    'x86_64-unknown-linux-musl\.tar\.gz$'      ''
install_tool glow    glow    charmbracelet/glow   'Linux_x86_64\.tar\.gz$'                   ''
install_tool starship starship starship/starship  'x86_64-unknown-linux-musl\.tar\.gz$'      'starship'
install_tool csvlens csvlens YS-L/csvlens         'x86_64-unknown-linux-(musl|gnu)\.tar\.(gz|xz)$' 'csvlens'
install_tool yazi    yazi    sxyazi/yazi          'x86_64-unknown-linux-musl\.zip$'                'yazi-fm'
# zellij ships prebuilt musl binaries and has a cargo crate, so every path
# (paru/brew/prebuilt/cargo) can install it — no special-casing needed.
install_tool zellij   zellij  zellij-org/zellij     'x86_64-unknown-linux-musl\.tar\.gz$'      'zellij'

# --- optional: build from source (helix, fish) ------------------------------
ensure_rust() {
    if have cargo; then return 0; fi
    log "  installing rustup (user-scope)"
    run "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --no-modify-path"
    export PATH="$CARGO_BIN:$PATH"
}

build_helix() {
    if have hx && ((!FORCE)); then
        log "helix: already installed ($(command -v hx))"
        return 0
    fi
    log "helix: bootstrapping"
    if [[ "$ENVKIND" == "mac" ]]; then
        install_via_brew helix && return 0
        warn "helix: brew install failed, falling back to source build"
    fi
    ensure_rust

    local src="$HOME/.local/src/helix"
    if [[ -d "$src/.git" ]]; then
        run "git -C '$src' pull --ff-only"
    else
        run "mkdir -p '$(dirname "$src")' && git clone https://github.com/helix-editor/helix '$src'"
    fi
    run "cd '$src' && cargo install --path helix-term --locked"

    # runtime files
    run "mkdir -p '$CONFIG/helix'"
    if [[ ! -e "$CONFIG/helix/runtime" ]]; then
        run "ln -sfn '$src/runtime' '$CONFIG/helix/runtime'"
    fi
}

build_fish() {
    if have fish && ((!FORCE)); then
        log "fish: already installed ($(command -v fish))"
        return 0
    fi
    log "fish: bootstrapping (build from source)"

    if ! have cmake; then err "fish build needs cmake — not found on PATH"; return 1; fi
    ensure_rust

    local src="$HOME/.local/src/fish-shell"
    if [[ -d "$src/.git" ]]; then
        run "git -C '$src' pull --ff-only"
    else
        run "mkdir -p '$(dirname "$src")' && git clone https://github.com/fish-shell/fish-shell '$src'"
    fi
    run "cd '$src' && cmake -B build -DCMAKE_INSTALL_PREFIX='$HOME/.local' -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && cmake --install build"

    log "fish installed to \$HOME/.local/bin/fish"
    log "  to make it your default: echo 'exec \$HOME/.local/bin/fish' >> ~/.bashrc"
}

if ((WITH_HELIX)); then build_helix; fi
if ((WITH_FISH));  then build_fish;  fi

# --- fish conf.d -------------------------------------------------------------
log "deploying fish conf.d"
run "ln -sfn '$DOTFILES/fish/env-setup.fish' '$CONFIG/fish/conf.d/env-setup.fish'"

# --- helix config -------------------------------------------------------------
# config.toml is helix's only config file (no include mechanism), and
# theme-apply.py rewrites the `theme = "..."` line in place — so symlinking
# the repo's copy in means theme switches edit the tracked file, same as
# they already did before this was tracked. Back up any pre-existing real
# file once so a hand-edited config isn't silently lost.
log "deploying helix config"
run "mkdir -p '$CONFIG/helix'"
if [[ -e "$CONFIG/helix/config.toml" && ! -L "$CONFIG/helix/config.toml" ]]; then
    log "helix: existing config.toml found — backing up to config.toml.bak"
    run "mv '$CONFIG/helix/config.toml' '$CONFIG/helix/config.toml.bak'"
fi
run "ln -sfn '$DOTFILES/helix/config.toml' '$CONFIG/helix/config.toml'"

# --- starship config ---------------------------------------------------------
# Only set the default on fresh installs — never stomp a user's chosen variant.
if [[ ! -e "$CONFIG/starship.toml" ]]; then
    log "deploying starship.toml (default: pure-preset)"
    run "ln -sfn '$DOTFILES/starship/variants/pure-preset.toml' '$CONFIG/starship.toml'"
else
    log "starship.toml: already present — leaving as-is (use \`starship-style\` to switch)"
fi

# --- kitty patch (local only) ------------------------------------------------
patch_kitty() {
    local conf="$CONFIG/kitty/kitty.conf"
    if [[ ! -f "$conf" ]]; then
        log "kitty: no config found — creating one"
        run "mkdir -p '$CONFIG/kitty' && touch '$conf'"
    fi
    if grep -q 'theme-current.conf' "$conf"; then
        log "kitty: theme-current.conf already included"
    else
        log "kitty: including theme-current.conf"
        # Portable in-place edit (avoids `sed -i` flag differences between
        # GNU sed and macOS's BSD sed): rebuild the file via a temp copy.
        run "grep -v 'quickshell.*kitty-theme.conf' '$conf' > '$conf.tmp' || true; { echo 'include ~/.config/kitty/theme-current.conf'; cat '$conf.tmp'; } > '$conf'; rm -f '$conf.tmp'"
    fi
    if ! grep -q '^allow_remote_control' "$conf"; then
        log "kitty: enabling remote control"
        run "printf '\nallow_remote_control socket-only\nlisten_on unix:/tmp/kitty-%%i\n' >> '$conf'"
    fi
    # seed a theme if the file doesn't exist yet
    if [[ ! -f "$CONFIG/kitty/theme-current.conf" ]]; then
        run "python3 '$DOTFILES/theme-system/theme-apply.py' catppuccin_mocha"
    fi
}

if have kitty; then patch_kitty; else log "kitty not installed — theme-system files still deployed"; fi

# --- zellij patch ------------------------------------------------------------
# zellij has no KDL include mechanism and only live-reloads themes defined
# inline in the main config, so theme-apply.py writes a managed block straight
# into ~/.config/zellij/config.kdl. Seeding just means running it once if that
# block isn't there yet (it creates config.kdl too if absent).
patch_zellij() {
    local conf="$CONFIG/zellij/config.kdl"
    if grep -qs 'theme-system' "$conf"; then
        log "zellij: theme block already present"
    else
        log "zellij: seeding theme block into config.kdl"
        run "python3 '$DOTFILES/theme-system/theme-apply.py' catppuccin_mocha"
    fi
}

if have zellij; then patch_zellij; else log "zellij not installed — theme-system files still deployed"; fi

# --- espanso config (text expander) ------------------------------------------
# espanso auto-loads every yml under <config>/match/, so we just symlink the
# repo's latex.yml in. The config dir is platform-specific (macOS keeps it in
# Application Support, everything else follows XDG). Only installed on mac —
# espanso needs a desktop session (X11/Wayland), not a headless cluster.
deploy_espanso() {
    local espanso_dir
    if [[ "$ENVKIND" == "mac" ]]; then
        espanso_dir="$HOME/Library/Application Support/espanso"
    else
        espanso_dir="${XDG_CONFIG_HOME:-$HOME/.config}/espanso"
    fi

    if [[ "$ENVKIND" == "mac" ]] && ! have espanso; then
        log "espanso: installing (brew tap espanso/espanso)"
        ensure_brew
        run "brew tap espanso/espanso"
        run "brew install espanso"
    fi

    log "deploying espanso latex matches"
    run "mkdir -p '$espanso_dir/match'"
    run "ln -sfn '$DOTFILES/espanso/match/latex.yml' '$espanso_dir/match/latex.yml'"

    if [[ "$ENVKIND" == "mac" ]] && have espanso; then
        # register the launchd service once (harmless if already registered)
        run "espanso service register || true"
        log "espanso: grant Accessibility permission (System Settings > Privacy &"
        log "  Security > Accessibility), then run 'espanso start' to activate."
    fi
}

deploy_espanso

# --- cluster-side bashrc patch ----------------------------------------------
# Cluster login shells are typically bash. If ~/.bashrc launches fish
# unconditionally, kitten ssh's non-interactive bootstrap gets replaced by
# fish mid-transfer and kitty's shell-integration payload leaks as raw
# commands. Guard the launch with an interactive-shell check and use exec
# so bash doesn't sit around waiting on a nested fish.
patch_bashrc_for_fish() {
    local rc="$HOME/.bashrc"
    if [[ ! -f "$rc" ]]; then
        log "bashrc: not found — skipping"
        return 0
    fi
    if grep -qE '^\[\[ \$- == \*i\* \]\] && exec fish' "$rc"; then
        log "bashrc: already patched"
        return 0
    fi
    if ! grep -qE '^\s*(exec\s+)?fish\s*$' "$rc"; then
        log "bashrc: no bare 'fish' launch found — nothing to patch"
        return 0
    fi
    log "bashrc: guarding fish launch (interactive-only, exec)"
    run "sed -i.dotfiles.bak -E 's|^\s*(exec\s+)?fish\s*$|[[ \$- == *i* ]] \&\& exec fish|' '$rc'"
}

if ((CLUSTER)); then patch_bashrc_for_fish; fi

# --- mac: set fish as the login shell ----------------------------------------
setup_fish_shell_mac() {
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || true)
    if [[ -z "$fish_path" ]]; then
        warn "fish: not found — skipping default-shell change"
        return 0
    fi
    if [[ "${SHELL:-}" == "$fish_path" ]]; then
        log "fish: already the default shell"
        return 0
    fi
    if ! grep -qxF "$fish_path" /etc/shells 2>/dev/null; then
        log "fish: adding $fish_path to /etc/shells (sudo)"
        run "echo '$fish_path' | sudo tee -a /etc/shells >/dev/null"
    fi
    log "fish: setting as default login shell (chsh — may prompt for your password)"
    run "chsh -s '$fish_path'"
}

if [[ "$ENVKIND" == "mac" ]]; then setup_fish_shell_mac; fi

log "done. restart kitty (or new tab) to pick up remote-control changes."
log "run \`theme\` from fish to pick a theme."

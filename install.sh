#!/usr/bin/env bash
# install.sh — set up my CLI env on a fresh machine.
# Idempotent. Safe to re-run. Detects arch+root vs rhel+noroot vs other.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/.dotfiles}"
LOCAL_BIN="$HOME/.local/bin"
CARGO_BIN="$HOME/.cargo/bin"
CONFIG="$HOME/.config"

WITH_HELIX=0
WITH_FISH=0
FORCE=0
DRY=0
for arg in "$@"; do
    case "$arg" in
        --with-helix) WITH_HELIX=1 ;;
        --with-fish)  WITH_FISH=1 ;;
        --force)      FORCE=1 ;;
        --dry-run)    DRY=1 ;;
        -h|--help)
            cat <<EOF
Usage: install.sh [--with-helix] [--with-fish] [--force] [--dry-run]

  --with-helix   Also build helix from source (via rustup + cargo)
  --with-fish    Also build fish shell from source (via rustup + cmake)
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

# --- unified tool install ----------------------------------------------------
# usage: install_tool <bin> <arch-pkg> <github-repo> <asset-regex> <cargo-crate>
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

# --- starship config ---------------------------------------------------------
log "deploying starship.toml"
run "ln -sfn '$DOTFILES/starship/starship.toml' '$CONFIG/starship.toml'"

# --- kitty patch (local only) ------------------------------------------------
patch_kitty() {
    local conf="$CONFIG/kitty/kitty.conf"
    if [[ ! -f "$conf" ]]; then
        log "kitty: no config found — skipping"
        return 0
    fi
    if grep -q 'theme-current.conf' "$conf"; then
        log "kitty: theme-current.conf already included"
    else
        log "kitty: including theme-current.conf"
        # remove any existing include of the quickshell path
        run "sed -i '/quickshell.*kitty-theme.conf/d' '$conf'"
        # prepend our include
        run "sed -i '1i include ~/.config/kitty/theme-current.conf' '$conf'"
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

log "done. restart kitty (or new tab) to pick up remote-control changes."
log "run \`theme\` from fish to pick a theme."

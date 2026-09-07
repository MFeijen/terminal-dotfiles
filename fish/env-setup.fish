# ~/.dotfiles env — dropped into ~/.config/fish/conf.d by install.sh
# Kept minimal; project-specific overrides go in your usual fish config.

# Homebrew (mac): bash/zsh get /opt/homebrew/bin via macOS's /etc/paths.d +
# path_helper, but fish never reads that — without this, brew-installed tools
# (including ghostty, starship, fzf...) vanish once fish is the login shell.
if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv fish | source
else if test -x /usr/local/bin/brew
    /usr/local/bin/brew shellenv fish | source
end

# ~/.local/bin — where the no-root installer places prebuilt binaries.
if not contains -- $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end

# ~/.cargo/bin — cargo-installed tools (helix, fallback tool installs).
if test -d $HOME/.cargo/bin; and not contains -- $HOME/.cargo/bin $PATH
    set -gx PATH $HOME/.cargo/bin $PATH
end

# Editor — helix. Set after the PATH blocks above so `hx` is resolvable.
# yazi's built-in `edit` opener shells out to `$EDITOR` (defaulting to vi/vim
# when unset), so this is what makes helix — not vim — the norm for yazi.
if type -q hx
    set -gx EDITOR hx
    set -gx VISUAL hx
end

# zoxide (smart cd) — provides `z` and `zi`.
if type -q zoxide
    zoxide init fish | source
end

# starship prompt.
if type -q starship
    starship init fish | source
end

# Modern-unix aliases — only if the tool is installed.
if type -q eza
    alias ls='eza --group-directories-first'
    alias ll='eza -l --group-directories-first --git'
    alias la='eza -la --group-directories-first --git'
    alias tree='eza --tree'
end

if type -q bat
    alias cat='bat --paging=never --style=plain'
    set -gx BAT_THEME base16
end

# No ssh wrapper needed here — ghostty handles remote terminfo in *config*
# rather than by wrapping the ssh binary. install.sh seeds
# `shell-integration-features = ssh-env,ssh-terminfo`, which installs the
# xterm-ghostty entry on the remote (falling back to xterm-256color when the
# host has no `tic`) and propagates COLORTERM. That's what the old
# `kitten ssh` function did, minus its fatal flaw: kitten refused outright on
# a non-tty stdin, breaking scripts and VS Code Remote-SSH probes.

# Greeting — fastfetch if installed, silent under SSH (remote binary may be
# ABI-incompatible, e.g. old glibc on HPC login nodes).
function fish_greeting
    if type -q fastfetch; and not set -q SSH_CONNECTION
        fastfetch
    end
end

# Locate the dotfiles repo root by resolving this file's own path — it's
# symlinked in from ~/.config/fish/conf.d/, and the repo isn't guaranteed to
# be at ~/.dotfiles (e.g. cluster/mac clones may use a different name).
set -l dotfiles_root (dirname (dirname (realpath (status -f))))

# Theme picker — loaded from the dotfiles repo.
set -l theme_picker $dotfiles_root/theme-system/theme-picker.fish
if test -f $theme_picker
    source $theme_picker
end

# Starship variant picker.
set -l starship_picker $dotfiles_root/starship/starship-picker.fish
if test -f $starship_picker
    source $starship_picker
end

# yazi wrapper: cd into the directory yazi exits in.
function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    command rm -f -- "$tmp"
end

# zellij autostart is disabled. To start zellij automatically on terminal
# launch again, restore the source block below (the script is still at
# zellij/zellij-startup.fish):
#
#     set -l zellij_startup $dotfiles_root/zellij/zellij-startup.fish
#     if test -f $zellij_startup
#         source $zellij_startup
#     end

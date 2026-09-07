# Resolved at source time — `status -f` inside a function is the definition
# file, but capturing it here keeps that out of every call site.
set -g __theme_apply (dirname (status -f))/theme-apply.py

function __theme_sync --on-variable PWD --description "Re-theme this terminal for \$PWD"
    # Fast path: with no registry at all nothing is bound anywhere, so no
    # terminal can be locally painted and there is nothing to restore. Keeps cd
    # free (~50ms of python) for anyone not using folder-local themes.
    if not test -e $HOME/.config/theme-system/local.toml
        set -e HELIX_LOCAL_CONFIG
        return
    end
    # Prints a helix config path when $PWD is bound to a local theme, nothing
    # otherwise. Repaints this terminal either way (leaving a bound folder has
    # to restore the global palette).
    set -l cfg (python3 $__theme_apply --sync)
    if test -n "$cfg"
        set -gx HELIX_LOCAL_CONFIG $cfg
    else
        set -e HELIX_LOCAL_CONFIG
    end
end

function hx --wraps hx --description "helix, using the folder-local theme when one is bound"
    # helix has no per-project theme, so a local theme reaches it as a whole
    # generated config. An explicit -c/--config from the caller wins.
    if set -q HELIX_LOCAL_CONFIG; and not contains -- -c $argv; and not contains -- --config $argv
        command hx -c $HELIX_LOCAL_CONFIG $argv
    else
        command hx $argv
    end
end

function __theme_ssh_host --description "Canonical hostname ssh would connect to"
    # ssh's own parser handles aliases, ~/.ssh/config Host blocks and flags like
    # -p/-l, so `theme --ssh prod` and `ssh -4 prod` land on the same registry
    # key. Empty when the args name no host ssh can resolve.
    command ssh -G $argv 2>/dev/null | string replace -rf '^hostname ' ''
end

# Ghostty's shell integration defines its own `ssh` wrapper (ssh-env,
# ssh-terminfo) — from a *vendor* conf.d, which fish sources after this file,
# inside its own fish_prompt handler. Same event, later registration, so it wins
# whatever we do at source time. Re-wrap on every prompt instead, skipping the
# work once ours is on top: one builtin per prompt, and it heals itself if
# anything redefines `ssh` later.
function __theme_ssh_install --on-event fish_prompt --on-event fish_preexec
    functions -q ssh; and functions ssh | string match -q '*__theme_ssh_inner*'; and return

    # Whatever `ssh` currently is becomes the inner call, so ghostty's wrapper
    # keeps doing its terminfo/env work. Never reached when `ssh` is already
    # ours (the early return above), so this can't wrap itself.
    functions -e __theme_ssh_inner  # -c refuses an existing target
    if functions -q ssh
        functions -c ssh __theme_ssh_inner
    else
        function __theme_ssh_inner --wraps ssh
            command ssh $argv
        end
    end

    function ssh --wraps ssh --description "ssh, painting this terminal with the host's theme"
        # OSC crosses the connection (the remote pty is the same surface), so
        # painting before connecting themes the remote session with no remote setup.
        set -l theme
        if test -e $HOME/.config/theme-system/local.toml
            # Fast path: no registry means nothing is bound anywhere, so ssh
            # never pays for `ssh -G` plus a python spawn when nobody uses it.
            set -l host (__theme_ssh_host $argv)
            test -n "$host"; and set theme (python3 $__theme_apply --ssh-current $host)
        end
        test -n "$theme"; and python3 $__theme_apply --terminal $theme

        __theme_ssh_inner $argv
        set -l code $status

        # Restore what this terminal should show locally ($PWD's theme, else the
        # global one) — also repairs a palette the remote session changed itself.
        test -n "$theme"; and __theme_sync
        return $code
    end
end

function theme --description "Fuzzy-pick a theme: global by default, --local binds \$PWD"
    if not test -x "$__theme_apply"
        echo "theme: $__theme_apply not found or not executable" >&2
        return 1
    end

    if test "$argv[1]" = --unbind
        if set -q argv[2]
            python3 $__theme_apply --ssh-clear (__theme_ssh_host $argv[2])
            echo "theme: unbound $argv[2]"
        else
            python3 $__theme_apply --local-clear
            __theme_sync
            echo "theme: unbound $PWD"
        end
        return
    end

    set -l scope global
    set -l ssh_host
    if test "$argv[1]" = --local -o "$argv[1]" = -l
        set scope local
        set -e argv[1]
    else if test "$argv[1]" = --ssh
        set scope ssh
        set ssh_host (__theme_ssh_host $argv[2])
        if test -z "$ssh_host"
            echo "theme: --ssh needs a host, e.g. theme --ssh myserver" >&2
            return 1
        end
        set -e argv[1]
        set -e argv[1]
    else if string match -qr '^-' -- "$argv[1]"
        # Loud, because the previous version of this function ignored argv
        # entirely — an unknown flag silently fell through to a global apply.
        echo "theme: unknown option '$argv[1]'" >&2
        echo "usage: theme [--local|-l] | theme --ssh <host> | theme --unbind [host]" >&2
        return 1
    end

    # snapshot current theme so we can restore on cancel
    set -l original (python3 $__theme_apply --current)
    if test -z "$original"
        set original default
    end

    # theme sources, in the order theme-apply.py resolves them
    set -l theme_dirs \
        ~/.config/helix/themes \
        ~/helix-ide/config/helix/themes \
        /usr/lib/helix/runtime/themes \
        (dirname $__theme_apply)/themes

    set -l themes
    for d in $theme_dirs
        if test -d "$d"
            for f in $d/*.toml
                test -f "$f"; or continue
                set -a themes (basename "$f" .toml)
            end
        end
    end

    # dedupe, sort
    set themes (printf '%s\n' $themes | sort -u)

    if test (count $themes) -eq 0
        echo "theme: no themes found" >&2
        return 1
    end

    # Local picking must preview per-terminal, or browsing would rewrite the
    # global ghostty/zellij/helix configs on every keystroke.
    set -l preview_flag --preview
    set -l header "enter: keep globally · esc: restore [$original]"
    if test $scope = local
        set preview_flag --preview-local
        set header "enter: bind $PWD · esc: restore"
    else if test $scope = ssh
        set preview_flag --preview-local
        set header "enter: bind ssh $ssh_host · esc: restore"
    end

    set -l selection (printf '%s\n' $themes | fzf \
        --prompt="theme ($scope)> " \
        --height=60% \
        --reverse \
        --ansi \
        --preview "python3 $__theme_apply $preview_flag {}" \
        --preview-window="right:60%" \
        --bind "esc:abort" \
        --header="$header" \
        --query "$original")

    if test -z "$selection"
        # cancelled — undo whatever the preview painted
        if test $scope != global
            __theme_sync
        else
            python3 $__theme_apply "$original"
        end
        echo "theme: restored $original"
        return
    end

    if test $scope = ssh
        python3 $__theme_apply --ssh $ssh_host "$selection"
        # the preview painted this terminal; it belongs to the host, not here
        __theme_sync
        echo "theme: $selection (ssh $ssh_host)"
    else if test $scope = local
        python3 $__theme_apply --local "$selection" >/dev/null
        __theme_sync
        echo "theme: $selection (local to $PWD)"
    else
        python3 $__theme_apply "$selection"
        # a binding on $PWD still outranks the global theme in this terminal
        __theme_sync
        echo "theme: $selection (global)"
    end
end

# --on-variable PWD does not fire at startup, so seed this terminal now.
__theme_sync

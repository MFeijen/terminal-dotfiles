# zellij-startup.fish — sourced by fish/env-setup.fish.
#
# When you open an interactive terminal, offer to: start a new zellij session,
# attach to an existing one (running OR a resurrectable exited one), or carry on
# in a plain shell. Skipped when already inside zellij, when zellij isn't
# installed, when there's no tty to prompt on, or when $ZELLIJ_NO_AUTOSTART is
# set (the manual opt-out — `set -x ZELLIJ_NO_AUTOSTART 1` to disable).
#
# Runs during conf.d sourcing (before the first prompt) so a choice drops you
# straight into a session. zellij is run (not exec'd), so quitting or detaching
# it (Ctrl-o d) leaves you at a normal shell rather than closing the terminal.

status is-interactive; or return
command -q zellij; or return
set -q ZELLIJ; and return               # already inside a zellij session
set -q ZELLIJ_NO_AUTOSTART; and return   # opt-out escape hatch
isatty stdin; and isatty stdout; or return

# --short: names only; --no-formatting: strip ANSI so names parse cleanly.
# Lists both running sessions and exited-but-resurrectable ones.
set -l zj_sessions (zellij list-sessions --short --no-formatting 2>/dev/null)
set -l zj_n (count $zj_sessions)

# Colors use ANSI *names* (not hex), so they resolve through the palette
# kitty+zellij already themed — the menu matches your current theme for free.
set -l zj_ck green     # option keys
set -l zj_cn cyan      # session names
set -l zj_ct magenta   # title
set -l zj_cd brblack   # dim hints

set_color -o $zj_ct; echo -n 'zellij'; set_color normal; echo ' — pick a session:'
if test $zj_n -gt 0
    for zj_i in (seq $zj_n)
        echo -s '  ' (set_color -o $zj_ck) $zj_i (set_color normal) ') attach  ' \
            (set_color $zj_cn) $zj_sessions[$zj_i] (set_color normal)
    end
end
echo -s '  ' (set_color -o $zj_ck) n (set_color normal) ') new session   ' (set_color $zj_cd) '(Enter)' (set_color normal)
echo -s '  ' (set_color -o $zj_ck) s (set_color normal) ') skip — plain shell'

read -l -P (set_color -o $zj_ck)'❯ '(set_color normal) zj_reply

if string match -qr '^[0-9]+$' -- $zj_reply; and test "$zj_reply" -ge 1 -a "$zj_reply" -le "$zj_n"
    # attach resurrects the session if it had exited.
    zellij attach $zj_sessions[$zj_reply]
else
    switch $zj_reply
        case n N new ''
            zellij
        case '*'
            # s / skip / anything unrecognized → stay in the plain shell.
    end
end

# zellij-startup.fish — sourced by fish/env-setup.fish.
#
# When you open an interactive terminal, drop straight into zellij. Skipped when
# already inside zellij, when zellij isn't installed, when there's no tty, or
# when $ZELLIJ_NO_AUTOSTART is set (the manual opt-out —
# `set -x ZELLIJ_NO_AUTOSTART 1` to disable).
#
# Runs during conf.d sourcing (before the first prompt). zellij is run (not
# exec'd), so quitting or detaching it (Ctrl-o d) leaves you at a normal shell
# rather than closing the terminal.

status is-interactive; or return
command -q zellij; or return
set -q ZELLIJ; and return               # already inside a zellij session
set -q ZELLIJ_NO_AUTOSTART; and return   # opt-out escape hatch
isatty stdin; and isatty stdout; or return

zellij

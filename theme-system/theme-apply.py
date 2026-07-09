#!/usr/bin/env python3
"""
Apply a helix theme across helix, kitty, and yazi (via inherited terminal palette).

Usage:
    theme-apply.py <theme-name>          # apply theme
    theme-apply.py --current              # print current helix theme name
    theme-apply.py --preview <theme-name> # apply theme AND print swatch preview

Reads:
    Helix theme files from ~/.config/helix/themes/, ~/helix-ide/config/helix/themes/,
    and /usr/lib/helix/runtime/themes/ (in that precedence order).

Writes:
    ~/.config/kitty/theme-current.conf   — kitty palette
    ~/.config/helix/config.toml          — updates `theme = "..."`

Signals:
    kitty @ set-colors --all --configured  (live palette swap)
    pkill -SIGUSR1 hx                       (helix config reload, buffer-safe)
"""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

try:
    import tomllib  # py3.11+
except ImportError:
    try:
        import tomli as tomllib  # type: ignore
    except ImportError:
        sys.exit("error: needs python 3.11+ or `pip install --user tomli`")

HOME = Path.home()
THEME_DIRS = [
    HOME / ".config/helix/themes",
    HOME / "helix-ide/config/helix/themes",
    Path("/usr/lib/helix/runtime/themes"),
    HOME / ".dotfiles/theme-system/themes",
]
KITTY_THEME_OUT = HOME / ".config/kitty/theme-current.conf"
HELIX_CONFIG = HOME / ".config/helix/config.toml"

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")


def find_theme_file(name: str) -> Path:
    for d in THEME_DIRS:
        p = d / f"{name}.toml"
        if p.is_file():
            return p
    sys.exit(f"error: theme '{name}' not found in {[str(d) for d in THEME_DIRS]}")


def load_theme_chain(name: str, seen: set[str] | None = None) -> dict:
    """Load theme, following `inherits` recursively. Child overrides parent."""
    if seen is None:
        seen = set()
    if name in seen:
        sys.exit(f"error: cycle in theme inheritance at '{name}'")
    seen.add(name)

    path = find_theme_file(name)
    with open(path, "rb") as f:
        data = tomllib.load(f)

    parent_name = data.pop("inherits", None)
    if parent_name:
        parent = load_theme_chain(parent_name, seen)
        # deep-merge: child scalars/tables win; palette merged
        merged = {**parent, **data}
        merged_palette = {**parent.get("palette", {}), **data.get("palette", {})}
        if merged_palette:
            merged["palette"] = merged_palette
        return merged
    return data


def resolve_color(val, palette: dict) -> str | None:
    """Resolve a theme value (str or table) into a hex color or None."""
    if val is None:
        return None
    if isinstance(val, dict):
        # try fg first (foreground colors carry more info for most keys),
        # caller chooses fg vs bg by picking the field
        return None  # caller handles dict access explicitly
    if isinstance(val, str):
        if HEX_RE.match(val):
            return val.lower()
        # named palette reference
        looked = palette.get(val)
        if looked and isinstance(looked, str) and HEX_RE.match(looked):
            return looked.lower()
    return None


def get_fg(theme: dict, key: str) -> str | None:
    """Extract fg color from theme[key], resolving palette refs."""
    palette = theme.get("palette", {})
    val = theme.get(key)
    if isinstance(val, str):
        return resolve_color(val, palette)
    if isinstance(val, dict):
        fg = val.get("fg")
        if fg is not None:
            return resolve_color(fg, palette)
    return None


def get_bg(theme: dict, key: str) -> str | None:
    palette = theme.get("palette", {})
    val = theme.get(key)
    if isinstance(val, dict):
        bg = val.get("bg")
        if bg is not None:
            return resolve_color(bg, palette)
    return None


def palette_lookup(palette: dict, *names: str) -> str | None:
    for n in names:
        v = palette.get(n)
        if isinstance(v, str) and HEX_RE.match(v):
            return v.lower()
    return None


def brighten(hex_color: str, amount: int = 24) -> str:
    """Lighten a hex color by adding `amount` to each channel."""
    r = min(255, int(hex_color[1:3], 16) + amount)
    g = min(255, int(hex_color[3:5], 16) + amount)
    b = min(255, int(hex_color[5:7], 16) + amount)
    return f"#{r:02x}{g:02x}{b:02x}"


def derive_palette(theme: dict) -> dict[str, str]:
    """Derive kitty palette from helix theme."""
    p = theme.get("palette", {})

    bg = (
        get_bg(theme, "ui.background")
        or palette_lookup(p, "background", "bg", "base", "base00", "black")
        or "#1e1e2e"
    )
    fg = (
        get_fg(theme, "ui.text")
        or palette_lookup(p, "foreground", "fg", "text", "base05", "white")
        or "#cdd6f4"
    )
    cursor = (
        get_bg(theme, "ui.cursor.primary")
        or get_fg(theme, "ui.cursor")
        or fg
    )
    sel_bg = (
        get_bg(theme, "ui.selection")
        or palette_lookup(p, "selection", "surface1", "base02")
        or "#3f4258"
    )
    sel_fg = get_fg(theme, "ui.selection") or fg

    # ANSI 16 — prefer literal color names in palette, fall back to semantic roles.
    def pick(names, semantic_keys, default):
        v = palette_lookup(p, *names)
        if v:
            return v
        for k in semantic_keys:
            v = get_fg(theme, k) or get_bg(theme, k)
            if v:
                return v
        return default

    black = bg
    red = pick(
        ["red", "base08"],
        ["error", "diagnostic.error", "keyword.control.exception"],
        "#f38ba8",
    )
    green = pick(
        ["green", "base0B"],
        ["string", "diff.plus", "markup.list.checked"],
        "#a6e3a1",
    )
    yellow = pick(
        ["yellow", "base0A"],
        ["warning", "diagnostic.warning", "constant.numeric"],
        "#f9e2af",
    )
    blue = pick(
        ["blue", "base0D"],
        ["function", "info", "diagnostic.info"],
        "#89b4fa",
    )
    magenta = pick(
        ["magenta", "purple", "mauve", "pink", "base0E"],
        ["keyword", "keyword.control", "operator"],
        "#cba6f7",
    )
    cyan = pick(
        ["cyan", "teal", "sapphire", "sky", "base0C"],
        ["type", "constructor", "namespace"],
        "#94e2d5",
    )
    white = fg

    # bright variants: try named brights, else lighten
    def bright(names, base):
        v = palette_lookup(p, *names)
        return v if v else brighten(base)

    br_black = bright(["bright_black", "gray", "grey", "surface2", "base03"], black)
    br_red = bright(["bright_red"], red)
    br_green = bright(["bright_green"], green)
    br_yellow = bright(["bright_yellow"], yellow)
    br_blue = bright(["bright_blue"], blue)
    br_magenta = bright(["bright_magenta", "bright_purple"], magenta)
    br_cyan = bright(["bright_cyan"], cyan)
    br_white = bright(["bright_white"], white)

    return {
        "background": bg,
        "foreground": fg,
        "cursor": cursor,
        "selection_background": sel_bg,
        "selection_foreground": sel_fg,
        "color0": black,
        "color1": red,
        "color2": green,
        "color3": yellow,
        "color4": blue,
        "color5": magenta,
        "color6": cyan,
        "color7": white,
        "color8": br_black,
        "color9": br_red,
        "color10": br_green,
        "color11": br_yellow,
        "color12": br_blue,
        "color13": br_magenta,
        "color14": br_cyan,
        "color15": br_white,
    }


def write_kitty_conf(palette: dict[str, str]) -> None:
    KITTY_THEME_OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"# generated by theme-apply.py — do not edit\n"]
    for k, v in palette.items():
        lines.append(f"{k:24}{v}\n")
    KITTY_THEME_OUT.write_text("".join(lines))


def update_helix_config(theme_name: str) -> None:
    if not HELIX_CONFIG.is_file():
        HELIX_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        HELIX_CONFIG.write_text(f'theme = "{theme_name}"\n')
        return
    text = HELIX_CONFIG.read_text()
    new_line = f'theme = "{theme_name}"'
    if re.search(r"(?m)^\s*theme\s*=", text):
        text = re.sub(r"(?m)^\s*theme\s*=.*$", new_line, text, count=1)
    else:
        text = new_line + "\n" + text
    HELIX_CONFIG.write_text(text)


def current_helix_theme() -> str | None:
    if not HELIX_CONFIG.is_file():
        return None
    m = re.search(r'(?m)^\s*theme\s*=\s*"([^"]+)"', HELIX_CONFIG.read_text())
    return m.group(1) if m else None


def reload_kitty() -> None:
    if not shutil.which("kitty"):
        return
    # Try socket first (from listen_on setting), then fallback to env
    for args in (
        ["kitty", "@", "set-colors", "--all", "--configured", str(KITTY_THEME_OUT)],
    ):
        try:
            subprocess.run(args, check=False, capture_output=True, timeout=2)
        except Exception:
            pass


def reload_helix() -> None:
    if not shutil.which("pkill"):
        return
    subprocess.run(["pkill", "-SIGUSR1", "-x", "hx"], check=False, capture_output=True)


def print_swatch(name: str, palette: dict[str, str]) -> None:
    def sw(hex_color: str) -> str:
        r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
        return f"\x1b[48;2;{r};{g};{b}m   \x1b[0m"

    print(f"\n  \x1b[1m{name}\x1b[0m")
    print(f"\n  bg {palette['background']}  fg {palette['foreground']}")
    print(f"  {sw(palette['background'])}{sw(palette['foreground'])}\n")
    row1 = "  " + "".join(sw(palette[f"color{i}"]) for i in range(8))
    row2 = "  " + "".join(sw(palette[f"color{i}"]) for i in range(8, 16))
    print(row1)
    print(row2)
    print()

    # sample text in the derived colors
    def fg(hex_color: str, s: str) -> str:
        r, g, b = int(hex_color[1:3], 16), int(hex_color[3:5], 16), int(hex_color[5:7], 16)
        return f"\x1b[38;2;{r};{g};{b}m{s}\x1b[0m"

    samples = [
        ("keyword", palette["color5"]),
        ("string", palette["color2"]),
        ("function", palette["color4"]),
        ("type", palette["color6"]),
        ("number", palette["color3"]),
        ("error", palette["color1"]),
    ]
    print("  " + "  ".join(fg(c, s) for s, c in samples))


def apply(name: str, preview: bool = False) -> None:
    theme = load_theme_chain(name)
    palette = derive_palette(theme)
    write_kitty_conf(palette)
    update_helix_config(name)
    reload_kitty()
    reload_helix()
    if preview:
        print_swatch(name, palette)


def main() -> None:
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    if args[0] == "--current":
        cur = current_helix_theme()
        print(cur if cur else "")
        return
    if args[0] == "--preview":
        if len(args) < 2:
            sys.exit("--preview needs a theme name")
        apply(args[1], preview=True)
        return
    apply(args[0])


if __name__ == "__main__":
    main()

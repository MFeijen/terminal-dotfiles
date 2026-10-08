#!/usr/bin/env python3
"""Self-check for the folder-local theme logic. Run: python3 test_theme_local.py"""

import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "theme_apply", Path(__file__).parent / "theme-apply.py"
)
ta = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ta)


def test_registry_roundtrip(tmp):
    ta.LOCAL_REGISTRY = tmp / "local.toml"
    assert ta.read_registry() == {}, "missing registry must read as empty"
    reg = {str(tmp / "work"): "nord", str(tmp / "a b'c\"d"): "acme"}
    ta.write_registry(reg)
    assert ta.read_registry() == reg, "quotes and spaces in paths must survive"


def test_resolve_walks_up(tmp):
    ta.LOCAL_REGISTRY = tmp / "local.toml"
    deep = tmp / "work" / "api" / "src"
    deep.mkdir(parents=True)
    ta.write_registry({str(tmp / "work"): "nord"})
    assert ta.resolve_local(deep) == "nord", "subdirs inherit an ancestor binding"

    ta.write_registry({str(tmp / "work"): "nord", str(tmp / "work" / "api"): "acme"})
    assert ta.resolve_local(deep) == "acme", "nearest ancestor wins"

    ta.write_registry({})
    assert ta.resolve_local(deep) is None, "unbound tree resolves to global"


def test_ssh_bindings(tmp):
    ta.LOCAL_REGISTRY = tmp / "local.toml"
    ta.write_registry({str(tmp / "work"): "nord", ta.SSH_PREFIX + "box": "acme"})
    assert ta.ssh_theme("box") == "acme"
    assert ta.ssh_theme("other") is None, "unbound host has no theme"
    # the two scopes share one file and must not see each other's keys
    assert ta.resolve_local(tmp / "work") == "nord", "ssh keys don't break paths"
    assert ta.ssh_theme(str(tmp / "work")) is None, "path keys aren't host keys"


def test_config_theme_swap():
    swap = ta._config_with_theme
    assert swap('theme = "old"\nfoo = 1\n', "new") == 'theme = "new"\nfoo = 1\n'
    assert swap("foo = 1\n", "new") == 'theme = "new"\nfoo = 1\n', "insert when absent"
    # only the top-level key, not a `theme = ` inside a later table
    out = swap('theme = "old"\n[editor]\ntheme = "x"\n', "new")
    assert out.count('"new"') == 1 and 'theme = "x"' in out


def test_hx_wrapper_injects_config(tmp):
    """hx-local is what every launch route goes through, fish or not."""
    home = tmp / "home"
    (home / ".config/theme-system").mkdir(parents=True)
    (home / ".config/helix").mkdir(parents=True)
    (home / ".config/helix/config.toml").write_text('theme = "global"\n')
    proj = home / "proj"
    (proj / "sub").mkdir(parents=True)
    (home / ".config/theme-system/local.toml").write_text(f'"{proj}" = "nord"\n')

    # A fake hx on PATH so the wrapper's argv is observable without helix.
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    (bin_dir / "hx").write_text('#!/bin/sh\necho "$@"\n')
    (bin_dir / "hx").chmod(0o755)

    def run(cwd, *args):
        env = dict(os.environ, HOME=str(home), PATH=f"{bin_dir}:{os.environ['PATH']}")
        out = subprocess.run(
            [str(Path(__file__).parent / "hx-local"), *args],
            cwd=cwd, env=env, capture_output=True, text=True, check=True,
        )
        return out.stdout.strip()

    variant = home / ".cache/theme-system/helix-nord.toml"
    assert run(proj, "a.py") == f"-c {variant} a.py", "bound dir gets the variant"
    assert 'theme = "nord"' in variant.read_text(), "variant carries the bound theme"
    assert run(proj / "sub", "a.py") == f"-c {variant} a.py", "subdirs inherit it"
    assert run(home, "a.py") == "a.py", "unbound dir launches helix untouched"
    assert run(proj, "-c", "mine.toml") == "-c mine.toml", "explicit -c wins"


with tempfile.TemporaryDirectory() as d:
    tmp = Path(d).resolve()  # bind_local stores resolved paths; match it
    test_registry_roundtrip(tmp)
    test_resolve_walks_up(tmp)
    test_ssh_bindings(tmp)
    test_config_theme_swap()
    test_hx_wrapper_injects_config(tmp)
print("ok")

#!/usr/bin/env python3
"""Self-check for the folder-local theme logic. Run: python3 test_theme_local.py"""

import importlib.util
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


with tempfile.TemporaryDirectory() as d:
    tmp = Path(d).resolve()  # bind_local stores resolved paths; match it
    test_registry_roundtrip(tmp)
    test_resolve_walks_up(tmp)
    test_ssh_bindings(tmp)
    test_config_theme_swap()
print("ok")

#!/usr/bin/env python3
"""Install the local LazyVim configuration, backing up every replaced file."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

CLAUDE_EXTRA = "lazyvim.plugins.extras.ai.claudecode"


def plan(config_dir, repo):
    settings = config_dir / "lazyvim.json"
    original = json.loads(settings.read_text())
    if not isinstance(original, dict) or not isinstance(original.get("extras"), list):
        raise ValueError("lazyvim.json must contain an extras array")
    original["extras"] = [item for item in original["extras"] if item != CLAUDE_EXTRA]
    # A copied config needs an explicit checkout path, rather than the path of
    # its installed Lua file under ~/.config/nvim/lua/plugins.
    source = (repo / "install/herde.lua").read_text()
    source = source.replace('local repo = vim.fn.fnamemodify(source, ":p:h:h")',
                            'local repo = ' + json.dumps(str(repo), ensure_ascii=False))
    return {
        settings: json.dumps(original, indent=2, ensure_ascii=False) + "\n",
        config_dir / "lua/plugins/herde.lua": source,
    }


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, tmp = tempfile.mkstemp(prefix=".herde-", dir=path.parent)
    try:
        with os.fdopen(handle, "w") as stream:
            stream.write(content)
        os.chmod(tmp, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def install(config_dir, repo, apply=False):
    changes = {path: text for path, text in plan(config_dir, repo).items()
               if not path.exists() or path.read_text() != text}
    if not changes:
        print("Configuration is already current.")
        return
    for path in changes:
        print(("Update " if path.exists() else "Create ") + str(path))
    print("Disable Claude Code; Herde: <leader>a; Herdr comments: <leader>aR.")
    if not apply:
        print("Preview only. Add --apply to install.")
        return
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = config_dir / ".herde-backups" / stamp
    originals = {path: path.read_bytes() if path.exists() else None for path in changes}
    # Back up all originals before touching any configuration file.
    backup.mkdir(parents=True)
    for path, content in originals.items():
        if content is not None:
            target = backup / path.relative_to(config_dir)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    written = []
    try:
        for path, text in changes.items():
            atomic_write(path, text)
            written.append(path)
    except Exception:
        for path in reversed(written):
            if originals[path] is None:
                path.unlink()
            else:
                atomic_write(path, originals[path].decode())
        raise
    print("Installed. Backups: " + str(backup))
    print("Restart Neovim. Herde uses the existing Snacks picker; open it with <leader>aa.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=Path.home() / ".config/nvim")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    try:
        install(args.config_dir.expanduser().resolve(), Path(__file__).resolve().parents[1], args.apply)
    except (OSError, ValueError) as err:
        print("Installation failed: " + str(err), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

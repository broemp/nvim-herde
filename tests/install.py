"""Exercise the installer in an isolated LazyVim configuration."""
import importlib.util
import json
from pathlib import Path
import tempfile

repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("configure", repo / "install/configure.py")
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)
with tempfile.TemporaryDirectory() as tmp:
    config = Path(tmp)
    original = {"extras": [configure.CLAUDE_EXTRA, "keep.this.extra"], "version": 8}
    settings = config / "lazyvim.json"
    settings.write_text(json.dumps(original))
    configure.install(config, repo)
    assert json.loads(settings.read_text()) == original
    configure.install(config, repo, apply=True)
    assert json.loads(settings.read_text()) == {"extras": ["keep.this.extra"], "version": 8}
    installed = config / "lua/plugins/herde.lua"
    assert installed.exists() and 'prefix = "<leader>aR"' in installed.read_text()
    assert str(repo) in installed.read_text(), "installed spec must point to this checkout"
    backups = list((config / ".herde-backups").glob("*/lazyvim.json"))
    assert len(backups) == 1 and json.loads(backups[0].read_text()) == original
    before = installed.read_bytes()
    configure.install(config, repo, apply=True)
    assert installed.read_bytes() == before and len(list((config / ".herde-backups").iterdir())) == 1
print("Installer checks passed")

# Local development and personal configuration

The public installation uses `broemp/nvim-herde`; see the main README and `examples/github.lua`. The files under `install/` are an opt-in migration for the original local development setup.

## Work from a local checkout

Copy `examples/lazyvim.lua` to your Neovim plugin configuration and replace its `dir` with the absolute path of your checkout. Its default `~/misc/herde` path is only a development example.

The Lua module is `herde`, the command is `:Herde`, and the optional lazy.nvim display name is `herde.nvim`. The GitHub repository is `broemp/nvim-herde`.

## Personal configuration migration

From this checkout:

```sh
python3 install/configure.py
python3 install/configure.py --apply
```

The first command previews changes. The second backs up replaced configuration files, removes the `lazyvim.plugins.extras.ai.claudecode` extra, disables `coder/claudecode.nvim`, installs Herde from the current checkout, and moves an existing `herdr-nvim` plugin's comment shortcuts to `<leader>aR`.

This migration is intended for that specific configuration. Standard GitHub installation does not disable other plugins or change their shortcuts.

The default target is `~/.config/nvim`. `--config-dir /path/to/config` selects another configuration. Backups live below the target's `.herde-backups/` directory. Restart Neovim after applying the migration.

## Publish to the existing GitHub repository

```sh
bash scripts/publish.sh
```

The script runs checks, initializes `main` if necessary, configures the `broemp/nvim-herde` origin, commits the checkout, and makes a normal push. It uses your existing Git identity and GitHub credentials. If the remote contains divergent commits, Git rejects the push; reconcile that history before retrying.


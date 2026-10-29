# Backend contracts

## Herdr

The implementation uses CLI 0.9.5 and its offline JSON API schema, protocol 22, as the verified contract. `herdr --help`, `herdr agent`, `herdr api`, and `herdr api schema --json` were inspected locally. The checked commands are:

- `herdr api snapshot`: one coherent inventory of workspaces and agents.
- `herdr agent get <pane-id>`: revalidate an occupant before an action.
- `herdr agent read <pane-id> --source recent-unwrapped --lines N --format text`: read plain-text output without focusing; this CLI response is not JSON.
- `herdr agent focus <pane-id>`: explicitly focus a selected agent.
- `herdr agent prompt <pane-id> <text>`: submit once, without waiting for a model turn.

All commands use argv arrays, without a shell. A configured `machine` or `session` selector is prepended consistently; they cannot be combined. The default namespace uses the inherited Herdr socket path when available. Machine targets are marked remote and cannot be opened as local checkouts.

Neovim may run independently of Herdr. Without an explicit selector, the CLI resolves its default session or inherited socket context. The plugin does not reject a missing `HERDR_ENV` variable. A named session can be selected with `herdr.session`. Prompts beginning with `-` are rejected with an instruction to add an introductory sentence: the installed CLI does not document positional flag escaping, so the adapter does not insert an unverified delimiter or alter the user's text.

`api snapshot` returns `result.snapshot` with `workspaces` and `agents`. Workspaces provide `workspace_id`, `label`, and optional `worktree.checkout_path`. Agents provide `agent`, `agent_status`, `name`, `workspace_id`, `pane_id`, `terminal_id`, `cwd`, `foreground_cwd`, and optional `agent_session`. The socket schema represents reads as `result.read.text`, but the CLI's `--format text` renders that content directly to stdout. The adapter therefore treats preview stdout as literal text, including content that happens to look like JSON. Structured commands continue to use JSON decoding. The fixture in `tests/fixtures/herdr/snapshot.json` is synthetic data matching this schema, not a captured live conversation.

Lifecycle states are `idle`, `working`, `blocked`, `done`, and `unknown`. Unknown data remains unknown. The core tracks attention separately from Herdr's viewed status. The CLI does not advertise a streaming subscription command, so this adapter uses polling even though the socket protocol has subscriptions.

Stable identities combine backend namespace, agent kind, conversation reference, and terminal identity. Terminal identity allows a pane move without transferring a label to another concurrent terminal with the same conversation. Without a conversation reference, identity is temporary for the current adapter instance; labels must not be restored onto these agents after a restart. A replacement that happens entirely between polls and has the same terminal, kind, and no conversation reference cannot be distinguished reliably. The adapter cannot atomically bind a prompt to an occupant: it revalidates immediately before submission, and Herdr performs its own current-agent checks, but a replacement in that short interval remains a protocol limitation.

Live `status`, `agent list`, and `workspace list` calls were attempted from a Herdr-managed environment but denied by the execution sandbox's socket permissions (`Operation not permitted`). Focus and prompt mutations were not run against the user's live agents. Runtime interoperability therefore remains to be checked in a normally permitted terminal. The plugin never starts or replaces a Herdr server to resolve a connection failure.

## Pi

The installed Herdr CLI advertises `pi` among supported agent kinds. Herde displays and operates a Herdr-managed Pi agent through the same adapter as Codex, Claude, and other recognized agents.

The installed Pi help advertises `--mode rpc`, but that starts a Pi process with a dedicated transport; it does not establish an attachment API for arbitrary existing interactive Pi terminals. No standalone Pi adapter is implemented or claimed. This avoids launching duplicate model processes or treating session files as live control channels.

## Demo

Use `backend = "demo"` to try the UI without Herdr. It exposes two workspaces and three agents, including Pi and an agent needing input. Its paths refer to the current directory by default. `demo = { animate = true }` toggles the builder between working and done every fourth snapshot. Preview and checkout are supported; terminal focus and prompt submission are explicitly unsupported. Demo mode never launches or prompts a real agent.

## Adapter API

An adapter provides `snapshot(cb)`, `read(agent, cb)`, `focus(agent, cb)`, `prompt(agent, text, cb)`, and `stop()`, invoked as methods. Callbacks receive `(error, result)` on Neovim's main loop. Errors are readable strings. Snapshots contain namespaced workspace and agent IDs; capabilities advertise available actions. Jobs are asynchronous, time limited, output bounded, and cancelled on teardown. Failed or timed-out prompts are never resubmitted automatically because delivery may already have occurred.

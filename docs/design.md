# Plugin layout and architecture

The editor remains the main surface. A narrow sidebar answers “what is running?”; a larger inbox answers “what needs me?”. Output previews provide context before a terminal or worktree switch.

The following wireframes are proposed interfaces using illustrative data.

## Default editor layout

```text
+--------------------------------------------+---------------------------+
| booking/service.go                         | herde                     |
|                                            | 3 working · 2 attention   |
| func Book(...) {                           | ───────────────────────── |
|     ...                                    | i inbox   / search        |
| }                                          |                           |
|                                            | ▾ cruised               3 |
|                                            |   ~/cruise/cruised        |
|                                            |   ! reviewer              |
+--------------------------------------------+|     review retries        |
| reviewer · Needs input                     |     codex · Needs input   |
| r refresh   f follow off   Enter focus      |   ● builder               |
|                                            |     fix booking retries   |
| Should retries include timeouts?            |     pi · Working · 2m     |
|                                            | ▸ shared-bundle         1 |
+--------------------------------------------+---------------------------+
```

The sidebar defaults to 38 columns on the right and can be resized. `sidebar.position` can select the left instead. Polling preserves the exact row and scroll position; an explicit agent selection navigates to its entry. Numbered project headings sort alphabetically, with numbered workspace rows sorted by name below them. Repository identities group linked worktrees, with checkout paths as the fallback. Workspace headings and muted paths separate groups; agent names, task labels, and status metadata form distinct lines. Status markers alone use diagnostic colors. Window surfaces, separators, hints, and headings link to the active Neovim colorscheme. The preview is optional and appears below the editing area. On small screens it becomes a floating window instead of squeezing the editor. State has text labels as well as configurable markers.

Selection remains attached to the selected entity during refresh. Workspace order stays stable by default; agents needing attention appear first within a workspace. Collapse state survives refreshes and restarts.

## Attention inbox

```text
+------------------------------------------------------------------------+
| ATTENTION     workspace: all      unresolved + unseen                    |
|                                                                        |
| ? cruised / reviewer       Needs input                         2m ago   |
|   review retries                                                       |
|                                                                        |
| + cruised / tests          Completed                            5m ago   |
|   verify cancellation                                                  |
|------------------------------------------------------------------------|
| reviewer: Should retries include timeouts?                              |
|                                                                        |
| Enter focus   o checkout   p prompt   a acknowledge   f filter   q close |
+------------------------------------------------------------------------+
```

Input requests remain unresolved until the observed agent state changes. Acknowledgement records that the user has seen the event; it does not answer the agent or resolve its request. Acknowledged completions leave the default inbox and remain available in bounded history.

Opening the inbox or reading a preview does not acknowledge events. Explicit terminal focus acknowledges events for that agent only after focus succeeds. An agent can leave the blocked state while its event is unseen; the event then appears resolved in history rather than remaining an active request.

Notifications link conceptually to the same event records as the inbox. A newly opened plugin establishes the current state as a baseline: existing blocked agents are shown, but old completions are not invented. A completion requires observed working activity followed by a backend-reported settled ready state. Unknown, missing, or disconnected states do not imply completion. Very short turns that occur entirely between polls may be missed unless a backend provides event history.

## Workspace and worktree navigation

Workspace selection filters the overview. A separate “open checkout” action changes editor context, so browsing agents does not unexpectedly change files or directories.

Checkout navigation saves the current editor session, selects or creates the destination workspace tab, and restores its editor context when available. An open sidebar follows the active tab as one reusable panel, with focus left in the editor; intentionally closing the panel disables following until it is opened again. The panel names the current checkout and shows a return hint. `b`, `<leader>ab`, or `:Herde back` returns to the previous tab, including the source editor with its unsaved buffers. UI layout records contain sidebar state; editor session files contain windows, buffers, and tab-local directories. Missing checkouts and remote-only paths stay visible but cannot be opened as local files. A first visit opens the existing checkout root without creating a worktree.

## Commands and mappings

Commands form the public API. Keymaps are configurable suggestions for a LazyVim spec and must be checked for conflicts during integration.

- `:Herde toggle` / `<leader>aa`: toggle sidebar.
- `:Herde agents` / `<leader>af`: search agents with snapshots; Enter focuses the selected Herdr pane, while Ctrl-O in Snacks opens a read-only snapshot.
- `:Herde workspaces` / `<leader>aw`: select a workspace.
- `:Herde inbox` / `<leader>ai`: open attention inbox.
- `:Herde attention` / `<leader>a/`: fuzzy-search active attention.
- `:Herde next-attention` / `<leader>an`: select the next agent needing attention.
- `:Herde previous` / `<leader>ap`: return to the previous live agent.
- `:Herde checkout` / `<leader>ao`: open the selected agent's checkout.
- `:Herde back` / `<leader>ab`: return to the previous workspace or editor tab.
- `:Herde label` / `<leader>al`: edit the selected agent's task label.
- `:Herde compose` / `<leader>as`: open the prompt composer; visual mode includes the selection.
- `:Herde quiet` / `<leader>aq`: toggle notifications without hiding inbox entries.
- `:Herde refresh` / `<leader>ar`: request an asynchronous refresh and report its result.
- `:checkhealth herde`: diagnose setup and backend connectivity.

Inside the sidebar, `j/k` move selection, `h/l` collapse or expand, Enter focuses the selected agent's terminal, and `o`, `p`, and `a` open its checkout, compose a prompt, and acknowledge attention. A workspace row expands on Enter. Picker acceptance follows the picker's advertised action.

## Repository structure

The implementation follows this structure. Direct Pi RPC is deferred; Pi agents currently use the Herdr backend.

```text
herde.nvim/
  README.md
  PLAN.md
  plugin/herde.lua                  command registration, lazy initialization
  lua/herde/
    init.lua                       setup, public API, teardown
    config.lua                     defaults and validation
    types.lua                      Lua annotations and normalized entities
    health.lua                     checkhealth entry point
    core/
      store.lua                    canonical snapshots and subscriptions
      refresh.lua                  polling/events, backoff, stale results
      attention.lua                transitions, inbox, acknowledgement
      navigation.lua               target history and focus actions
      persistence.lua              atomic, versioned local metadata
      workspaces.lua               layouts, labels, workspace preferences
      worktrees.lua                validated checkout navigation
      sessions.lua                 editor context save and restoration
      context.lua                  file, selection, diagnostics collection
    backends/
      init.lua                     registry and capability checks
      herdr.lua                    verified CLI/API adapter
      demo.lua                     deterministic development inventory
    transport/
      process.lua                  argv jobs, cancellation, output bounds
    ui/
      sidebar.lua                  grouped inventory
      inbox.lua                    attention list and filters
      preview.lua                  bounded output view
      composer.lua                 exact target and context preview
      picker.lua                   native fallback and picker dispatch
      notify.lua                   transition notifications, quiet/mute
      statusline.lua               cheap cached counts
      highlights.lua               theme defaults and state styling
    integrations/
      fzf.lua                      optional fzf picker and async output previews
      snacks.lua                   default LazyVim picker and async previews
  examples/lazyvim.lua              installation and suggested mappings
  doc/herde.txt                     Neovim help
  docs/
    design.md                      UI and architecture
    backends.md                    verified contracts and versions
  tests/
    fixtures/herdr/                captured, sanitized backend responses
    core/                          transitions, identity, persistence
    backends/                      parsing and failure cases
    smoke.lua                      headless loading and lifecycle
```

Use Neovim's built-in APIs for the base UI and process execution. The LazyVim spec uses its existing Snacks picker for agent, workspace, and attention search with no new dependency. The optional fzf adapter derives colors from Neovim highlight groups. `picker='auto'` prefers Snacks, then fzf-lua, then vim.ui.select; explicit fzf mode reports missing dependencies. Importing a module must not start polling or change windows; setup and explicit actions control those effects.

## Backend boundary

The adapter supplies snapshots, recent output, terminal focus, and prompt submission where supported. Capability flags control whether actions appear. The adapter normalizes transport errors, unsupported operations, unknown states, and disconnects without making the UI interpret raw terminal text.

Herdr is a workspace and terminal backend. Pi is an agent kind when managed through a compatible backend; a direct Pi adapter is a separate possibility, not a prerequisite for the first release. Local and remote server identities must be separate namespaces.

The core store owns normalized entities and derived counts. The UI subscribes to it and sends actions through the public API. Rendering never issues backend commands. Persistence stores local preferences and attention metadata, not authoritative backend lifecycle state.

## Identity and lifecycle

- Workspace identity includes backend and server/session namespace, plus the backend's workspace ID.
- Agent identity includes an occupant or run identity where available. A pane location is mutable and is not itself proof of agent identity.
- Agent names are display and lookup aids within their backend scope; they are not globally unique persistent IDs.
- Task labels follow a verified occupant across pane moves. If a backend cannot establish continuity, preserve the old label as unbound metadata and offer manual rebinding.
- Event identity includes the agent identity and a locally observed transition sequence. Backend timestamps are used only when supplied and understood.
- UI selection and history tolerate vanished agents. Stale snapshots remain marked stale until a successful refresh replaces them.

## Persistence and responsiveness

Store versioned metadata and editor sessions under Neovim's state directory. Separate namespaces prevent collisions between servers and sessions. Keep prompt drafts in memory and avoid transcript persistence by default. Concurrent Neovim instances must not corrupt files: use an explicit writer/merge policy before enabling shared metadata writes.

All backend operations run asynchronously. Refreshes are bounded and coalesced; stale callbacks cannot overwrite a newer snapshot. Preview output has line and byte limits. Notification delivery is separate from polling and rendering. Timers, subprocesses, subscriptions, and plugin-owned windows are cleaned up on teardown.

## Scope boundaries

The initial plugin does not automatically answer agent approvals, distribute tasks, create or delete worktrees, upgrade backends, or attach existing terminals through an unverified protocol. Launch presets can follow once navigation and attention handling are reliable.

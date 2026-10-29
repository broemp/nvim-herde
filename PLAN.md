# Implementation plan

Build a complete Lua plugin in small usable increments. Each milestone has a concrete completion check. The initial interface uses Herdr panes for interaction and Neovim windows for discovery, previews, and composing prompts.

## Implementation status

The Lua implementation, LazyVim spec, help, demo adapter, and headless checks are now present. Core state, persistence, navigation, UI, context sending, and backend contracts are implemented. The LazyVim spec uses its existing Snacks Picker for agent, workspace, and attention searches with no new dependency. The installed Snacks picker passed a real headless integration check, including live output previews and cleanup. Fzf-lua remains an optional adapter. Fzf selection and preview contracts are checked with a stub and filtering with the installed fzf binary. Downloading fzf-lua itself was blocked, so full interactive fzf-lua behavior remains unverified. The example spec passed the installed lazy.nvim loader with dependency loading isolated from that offline check.

Backend discovery verified Herdr 0.9.5's offline protocol-22 schema and its Pi agent kind. Live Herdr socket access was denied by the execution sandbox, so real terminal focus and prompt submission remain unverified. Fixtures are explicitly synthetic. Direct Pi RPC attachment is deferred because its RPC mode starts a separate process rather than attaching to existing terminals. Interactive visual QA inside a full LazyVim session remains a manual check; automated window and isolated loader checks do not replace it.

The milestones below retain the original acceptance criteria for ongoing verification.

## 1. Verify backend contracts

- Inspect installed Herdr help and representative JSON responses in an authorized Herdr environment. Do not inspect or control a live session from outside Herdr.
- Check agent listing, workspace listing, pane focus, recent output, prompt submission, checkout paths, lifecycle states, and connection failures.
- Check whether a supported change stream exists; otherwise use asynchronous polling with bounded concurrency and backoff.
- Verify Pi identity and supported integration interfaces. Prefer Herdr-managed Pi if the installed version supports it. Define direct Pi support only from verified interfaces.
- Record captured response fixtures, capability flags, supported versions, and identity limitations.
- Verify the Neovim minimum version and LazyVim integration APIs against their official documentation before implementation.

Completion: documented adapter contracts and realistic fixtures; no assumed CLI flags or fabricated status detection.

## 2. Build the Lua foundation

- Add idempotent `require("herde").setup(opts)`, validated defaults, commands, and teardown.
- Implement asynchronous process execution with argument arrays, timeout handling, bounded output, cancellation, and structured errors.
- Normalize workspaces, agent occupants, pane locations, capabilities, and connection state into one store.
- Ignore results from obsolete refreshes; prevent overlapping polls and release timers on exit.
- Add a fixture-backed demo adapter for development and deterministic checks.
- Add `:checkhealth herde` for dependencies, backend availability, and configuration issues.

Completion: headless Neovim can load, refresh, and tear down without leaking jobs or timers. Missing Herdr produces an actionable health result.

## 3. Ship overview and switching

- Build a workspace sidebar with counts, collapse state, stable selection, task labels, and stale-data indicators.
- Add a workspace-and-agent picker, previous-agent toggle, current-workspace cycling, and next-attention navigation.
- Add a bounded, read-only recent-output preview with explicit refresh and follow controls.
- Implement explicit terminal focus through adapter capabilities. Preview reads never acknowledge completion or change terminal focus.
- Add LazyVim mappings, fzf-lua search and previews, a native fallback picker, and a statusline function.

Completion: discover, preview, and focus an agent by keyboard; updates preserve selection and editor focus. Unsupported actions explain the missing capability.

## 4. Add attention and notifications

- Maintain local attention events independently of Herdr's seen state.
- Create inbox entries when an agent becomes blocked or finishes observed work. Initial discovery establishes a baseline instead of notifying about existing idle agents.
- Deduplicate repeated observations and distinguish acknowledgement from resolving the underlying blocked state.
- Support workspace filtering, unresolved input requests, unseen completions, and acknowledged history.
- Notify once per observed transition, with global quiet mode and workspace mute. Do not notify for every poll or on reconnection alone.
- Preserve existing pending attention when a backend disconnects; mark its status stale.

Completion: repeated polls do not duplicate entries; blocked agents remain discoverable after acknowledgement; restarts and reconnects do not flood notifications.

## 5. Add labels, workspace layouts, and worktrees

- Persist versioned local metadata using atomic writes and bounded history. Avoid persisting transcripts or composed context by default.
- Bind labels to verified agent identities, not sidebar positions. Treat a replacement pane occupant as a new agent; require rebinding when identity is ambiguous.
- Save per-workspace sidebar width, collapsed groups, preview visibility, last selected agent, and active inbox filter.
- Store editor sessions separately from the small UI layout records.
- Resolve checkout paths through backend metadata, validating that the path exists locally. Never infer a checkout from a workspace display name.
- Before switching checkout, save the current editor session. Load the destination session or open its root with a tab-local directory. Leave modified buffers intact; do not force-close them or run Git checkout/reset.
- Offer switching between existing worktrees only. Worktree creation and deletion are outside the initial scope.

Completion: return to each workspace's UI and editor context; unsaved buffers survive; missing and remote-only paths receive clear feedback; stale labels do not silently attach to new agents.

## 6. Add editor context and prompt composition

- Compose a prompt with an explicit workspace and agent target.
- Attach file locations, selected text with line numbers, and selected diagnostics, all visible before submission.
- Keep drafts per target in memory and retain them after submission failures.
- Revalidate the target occupant immediately before sending; refuse unavailable or blocked targets where the backend cannot accept a prompt safely.
- Submit once on user action. A timeout with uncertain delivery never triggers an automatic resend.

Completion: exact previewed context reaches the intended agent; target changes, failures, and uncertain delivery preserve the draft and never cause duplicate submissions.

## 7. Package and validate

- Add a copyable LazyVim spec, command reference, configuration reference, help tags, and troubleshooting documentation.
- Test state transitions, identity replacement, acknowledgement, notification deduplication, metadata migration, path handling, and adapter error parsing with meaningful fixture-based checks.
- Run headless Neovim smoke checks and manually exercise the UI in Neovim and LazyVim, including small windows and rapid switching.
- Verify responsiveness using a large fixture inventory and slow backend responses.
- Perform live adapter checks only in an authorized environment. Report any integration that remains unverified.

Completion: installation from a local checkout works, documented commands match behavior, checks pass, and remaining compatibility limits are explicit.

## Defaults to implement

- Open a sidebar without taking editor focus; focusing it is a separate action.
- Poll adaptively when events are unavailable; proposed starting intervals are two seconds while visible and ten seconds while hidden, with error backoff.
- Refresh previews only for the selected agent; cap retained output.
- Notify for newly observed completions and requests for input; allow either category to be disabled.
- Save local UI metadata automatically. Restore full editor sessions only through explicit workspace navigation.
- Keep the backend neutral model small; add capabilities when an implemented workflow needs them.

These defaults can be changed during implementation without changing the accepted feature scope.

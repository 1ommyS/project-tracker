# CLAUDE.md

Read and follow [AGENTS.md](AGENTS.md) before changing Trace. It is the shared source of repository instructions, commands, compatibility constraints, and current architecture.

Current interaction rules:
- A project is identified by its title in the UI; retain all legacy metadata on disk.
- Sidebar selection opens a project; rename is explicit. One navigation action creates one history step.
- Daily status editing uses a fixed project/date, explicit Save/Cancel, and keeps the draft on failure.
- Markdown formatting uses native AppKit input/Undo and UTF-16 ranges. Validate ambiguous reserved headings/unclosed code fences before saving; keep the draft and prior file on failure.
- Serialize writes per project, apply mutations to the latest model, and rebase status URLs after folder moves.
- «Статусы» (⌘6) offers a remembered Table/List switch. Table uses native virtualized rows and bounded excerpts; list renders full day cards lazily. Shared date/search/filter controls must describe their scope.
- Align status controls, table/list and footer in one centered `PulseMetrics.contentWidth` container with screen insets. Extra day columns scroll inside it. Replace every AppIcon PNG resolution together when changing the logo.
- Repository warm scans cache decoded files with precise invalidation; never drop external events during self-writes. Reuse revision-based overview/agenda projections, avoid per-character re-parsing, and run archive subprocesses on the repository actor.
- Performance benchmark fixture and limits are documented in docs/PERFORMANCE.md; do not equate file-load speedups with measured frame rate.
- Keep row identities stable across Markdown reloads using optional trace task/artifact ID comments. Do not animate per keystroke or resize editors between edit/preview.
- Quick status is a floating window (⌘⇧S / macOS menu bar); ⌘Return appends, never replaces the day. Unsaved draft lives until app exit. The Confluence guide supplies a copyable prompt and an accepted two-section Markdown format.
- Artifact edits keep the same ID; invalid URLs keep the form open.
- Real macOS delivery checks require a properly signed app bundle (local ad hoc command is in README); keep CODE_SIGNING_ALLOWED=NO for automated CI tests.
- Notification tests use an injected fake client; real scheduling is serialized, skips completed projects, and completion is idempotent. Report actual OS test delivery separately from scheduling.
- Use native controls and keyboard/accessibility support. Startup must not open notification settings.

When changing these behaviors, update AGENTS.md, this file, docs/UX-AUDIT.md, and the next-release notes; run `python3 scripts/sync-release-notes.py`.

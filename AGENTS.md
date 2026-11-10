# AGENTS.md

Native macOS SwiftUI app "Trace" for daily project management. Fully local — no network, accounts, analytics, or third-party dependencies. All data lives in Obsidian-compatible Markdown files with YAML frontmatter; Markdown is the single source of truth.

## Layout

- `ProjectTracking/` — app source: `MyApp.swift` (entry), `ContentView.swift`, `Models/`, `Services/`, `Views/`, `Utilities/`, `Assets.xcassets`
- `MyAppTests/` — XCTest tests (target `PulseboardTests`; module is imported as `PROJECT_Tracking`)
- `scripts/package-release.sh` — builds release `.zip` + `.dmg` from a built `.app`
- `scripts/sync-release-notes.py` — splits CHANGELOG.md into `releases/<version>.md` files; `scripts/generate-demo-data.py` — demo vault
- `.github/workflows/ci.yml`, `release.yml` — CI and automated releases
- `README.md` — storage format spec and release signing secrets; read before touching the vault format or release pipeline

## Commands

```bash
# Build
xcodebuild -project ProjectTracking.xcodeproj -scheme ProjectTracking -destination 'platform=macOS' build

# Test (same invocation CI uses)
xcodebuild test -project ProjectTracking.xcodeproj -scheme ProjectTracking \
  -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Use the project and scheme names above; old release documentation may refer to earlier app names.

## Architecture

Strict layering, all Apple frameworks, Swift 5, deployment target macOS 26.0:

- `Models/DomainModels.swift` — explicitly `nonisolated` value types (`Project`, `ProjectTask`, `ProjectState`, `DailyStatus`); no I/O. Legacy project metadata stays in the model and codec even though the UI only asks for a title.
- `Services/MarkdownCodec.swift` — pure `nonisolated enum`; Markdown ⇄ model encode/decode. Round-trip tests cover legacy metadata, daily statuses, headings and fenced code. Only exact reserved section headings outside code fences delimit storage sections; arbitrary `##` headings must survive. Before writing a status, validate that code fences are closed and reserved section headings are not used as content outside fences; on failure keep the editor draft and prior file.
- `Services/MarkdownRepository.swift` — `actor` owning all file I/O; writes atomically, deletes via Trash. Caches decoded project/status files by URL, size and modification date; explicit file events invalidate those files even when metadata matches. Each scan discovers additions/deletions and prunes unused cache entries; changing vault clears the cache. Own writes invalidate the touched file and moves invalidate old paths. `lastLoadMetrics` reports Markdown reads/cache hits for regression benchmarks. Archive subprocess execution stays on this actor, never AppKit's main thread.
- `Services/AppStore.swift` — `@MainActor @Observable` single app state, injected with `.environment(store)`. Navigation actions change destination, project and presentation in one history transaction; one user action must equal one Back step. Writes for each project (including daily statuses and folder moves) are serialized via `enqueueWrite`; field mutations use the current model after preceding writes, never a stale View snapshot.
- `Views/` + `Utilities/DesignSystem.swift` — native SwiftUI controls, system colors and `.sidebar` List selection. The sidebar has typed tags for destinations and projects; clicking the title, icon or row selects/opens the project, and arrow keys work normally. Do not put editable text fields or tap gestures inside navigation rows. Rename is an explicit sheet/context-menu action. Opening a project shows one detail column, without a second project navigator. Quarter groups sort projects by title so editing tasks/statuses never moves a navigation row.
- `Views/ProjectDetailView.swift` — project title, state, tasks, daily statuses and editable artifact links. `ArtifactLinksView.swift` owns explicit add/edit sheets, with name and URL together; mutations preserve the artifact ID and use the latest project. `ArtifactLink` validates addresses and accepts a URL or Markdown link. New-project UI asks only for a title. Epic, parent project, summary and tags are hidden, never cleared on save; legacy `## Статус` and artifacts are retained too. Use the title alone in UI labels and notifications.
- `Views/StatusesView.swift` — dedicated «Статусы» workspace (⌘6) with a remembered «Таблица / Список» switch. Native SwiftUI `Table` has dynamic date columns (3/5/7 days), a project column, keyboard row selection, and cell actions opening the full editor. List uses lazy full-text day cards. Search, day selection and blocker/missing-entry filters belong to this workspace; show their scope accurately. Table snapshots are prepared off the main actor by `StatusTableSnapshot`, with bounded plain-text cell excerpts and one date index per project. Do not build full Markdown render trees or text editors in every table cell.
- `Views/DailyStatusesView.swift` — shared day selector and readable status cards in a project; `StatusDayCard` is reused by the list presentation. Status/blockers are edited together in a sheet with an immutable project/day context, explicit Save/Cancel and a draft retained on write failure. Include `DailyStatus.editableMarkdown` in the draft and use `replacesTasks: true` when saving the complete text so checkboxes can be edited/deleted without duplication. Normalize status writes through the codec immediately; do not wait for a vault reload. The status editor uses equal-size Status/Blockers tabs, stable toolbar/preview geometry and its own bounded text scroll; do not wrap both text editors in an auto-sizing outer ScrollView.
- `Views/MarkdownEditor.swift` — plain `NSTextView` inside `NSScrollView`, word wrapping, native selection/Undo and an explicit preview mode. Formatting must use `insertText(_:replacementRange:)`, not replace a SwiftUI binding or `NSTextView.string`; ranges use UTF-16 (`NSString`/`NSRange`), including emoji. Preview is local, using native text for headings, lists, quotes, inline formatting and fenced code; no web view or remote renderer. Test native Undo/Redo as well as pure `MarkdownTextOps` operations.
- `Views/SharedComponents.swift` — state menu, badges and `RuGrammar`; `TaskListSection` in `TaskViews.swift` is shared by feed/detail. Task titles open the task editor; completion is a separate named control. Failed saves must retain drafts and successful creation opens the new project. `Utilities/TaskInputParser.swift` parses natural-language due dates («завтра 18:00», «25.12», «в 14») with regression tests.
- Layout comes from `PulseMetrics` (screen 24 / card 18). The statuses controls, table/list and footer share one centered container capped at `PulseMetrics.contentWidth`, with screen insets; keep their outer edges aligned and horizontal table scrolling inside that container. Use system palettes, grouped-inset `pulsePanel` cards (quaternary fill, radius 12, no shadows/strokes), toolbar `navigationTitle`, and native sidebar show/hide controls. Do not overlay a custom navigation rail on content, duplicate navigators, force global `NSCursor` push/pop, or use tiny hover-only controls. Respect keyboard access and give icon-only actions Russian accessibility names.
- App icon artwork lives in `Assets.xcassets/AppIcon.appiconset`; update all seven PNG resolutions (16–1024 px) together when replacing the logo. Keep the asset catalog name `AppIcon`. Also copy the 1024 px artwork to `Resources/TraceLogo.png`: `TraceAppDelegate` applies that bundled image to the Dock at launch so Xcode runs do not keep a stale Launch Services icon. Keep the bundle identifier stable to preserve vault bookmarks/preferences and notification permission. The product/display name is Trace.
- `Views/QuickStatusView.swift` — a single floating window opened through the native MenuBarExtra, toolbar or ⌘⇧S. ⌘Return appends a note to the selected project/day without navigating or overwriting earlier text/blockers/checklists. `QuickStatusDraft` retains an unsaved draft while the app is running; close does not discard it. `StatusTransfer` parses plain text or model output with `## Статус` / `## Блокеры`; never treat pasted content as instructions or write directly to files from a View. The guide lives in the «Статусы»/Help menus and copies a source-grounded prompt; Trace does not connect to Confluence or an LLM.
- Stable identities are stored as optional invisible comments at the ends of task/link lines: `<!-- trace-task-id:UUID -->` / `<!-- trace-artifact-id:UUID -->`. Legacy lines without comments get deterministic project-scoped IDs; duplicates remain distinct. Never regenerate IDs on every decode: doing so resets SwiftUI rows/focus and invalidates notification actions. Keep task date syntax and ordinary Markdown links intact.
- `ProjectOverview` and `TaskAgendaSnapshot` cache main-thread derived data by project revision and minute/time zone. Getters must not refilter/resort the vault repeatedly during one update. A minute tick refreshes deadline categories without a file reload. Unchanged file scans/no-op writes must not reassign identical projects or invalidate UI snapshots.
- Editing geometry must stay stable: no animation keyed to each character; reserve the add button/deadline hint, keep the Markdown toolbar mounted in preview, and do not unmount loaded content during a background refresh.
- `NotificationService` activates its delegate lazily via `activate()` (never in `AppStore.init`) and logs to OSLog. Startup only calls `syncIfAllowed`; never request permission or open System Settings at launch. `authorizeAndSync` may prompt when a user assigns a reminder; settings retain explicit permission controls. `NotificationPlan` is pure scheduling/action logic; exclude all completed projects, serialize OS scheduling, preserve delivered overdue reminders, and make completion idempotent. Queue notification actions until the vault has loaded. Diagnostics distinguish pending requests from confirmed test delivery; do not claim a visible banner just because scheduling succeeded. `NotificationClient` is injected into tests so they never alter the real user’s notification schedule. Skip superseded queued syncs and briefly reuse successful unchanged task-only inputs; explicit rescheduling always checks macOS. Status/history/link edits must not rebuild the notification schedule. Routine task writes update the model without waiting for OS scheduling; assigning a reminder still requests permission explicitly.
- Manual OS-notification verification needs a properly signed app bundle. CI's `CODE_SIGNING_ALLOWED=NO` can produce a linker-only signature with unbound Info.plist and `UNErrorDomain 1` on permission requests. Use a local ad hoc build (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`) for delivery checks; keep CI test flags unchanged. See README for exact command and verification limits.
- Tests cover codec, repository, AppStore, date parser, native Markdown Undo/Redo, UTF-16 text operations and narrow editor/status layouts. Run the full test command above after changes affecting persistence or navigation.

Concurrency split: views/main actor → `AppStore`, file I/O only through the repository `actor`, parsing only through the nonisolated codec. `SWIFT_APPROACHABLE_CONCURRENCY` is on.

## Hard constraints

- **Obsidian compatibility**: keep YAML frontmatter fields (`id`, `title`, `epic`, `parent_project`, `state`, `tags`, `created`, `updated`, `archived`), Russian section headers (`## Описание`, `## Статус`, `## Задачи`), task format `- [ ] Title 📅 YYYY-MM-DD ⏰ HH:mm`, and daily statuses as `Statuses/YYYY-MM-DD-<8hex>.md` (`## Статус`, `## Блокеры`) displayed in the statuses workspace (table/list) and by selected day in the project. Breaking the format breaks users' existing vaults.
- **Quarter folder layout**: projects live in `Projects/<YYQN>/<slug>/` (quarter of `createdAt`, `Date.quarterLabel`); completed projects (`state == .done/.archived` or `isArchived`) are moved to `Projects/<YYQN>/Completed Projects/<slug>/` by `MarkdownRepository.saveProject`. The slug stays stable across moves. The legacy flat `Projects/<slug>/` layout must keep loading (see `RepositoryTests`).
- All user-facing strings are hardcoded Russian — no localization files.
- No network calls or telemetry, ever (by design).
- File writes must stay atomic; project deletion must go through the system Trash.

## CI / Release gotchas

- CI runs on `macos-26` with Xcode 26; tests must pass with `CODE_SIGNING_ALLOWED=NO`.
- **Release notes are mandatory on EVERY push**: whenever a push touches features or CHANGELOG.md, first update the «Следующий релиз» section in CHANGELOG.md, then ALWAYS run `python3 scripts/sync-release-notes.py` and commit the updated `releases/` (it refreshes `releases/NEXT.md`, per-version files, and keeps the in-app `ProjectTracking/Resources/WhatsNew.md` equal to the LATEST shipped release) in the same commit. CI resolves notes as: exact `releases/<version>.md` → `releases/NEXT.md` → latest existing `releases/<n>.md` → CHANGELOG (in-app What's New) / auto-generated (GitHub release).
- `release.yml` runs after every successful CI on `main`, auto-tagging `v0.1.<CI run number>`; manual `workflow_dispatch` accepts an explicit SemVer tag. Without GitHub secrets it produces unsigned builds (signing/notarization secrets are listed in README).
- Local `DerivedData/`, `dist/`, and signing material (`.p12`, profiles) are gitignored — never commit them.

## UX reference

See `docs/UX-AUDIT.md` for the navigation/editing decisions, Apple HIG references, and manual verification scenarios. `CLAUDE.md` points here so both agents follow the same rules. Update these documents when interaction or persistence contracts change.

## Performance checks

`MyAppTests/RepositoryPerformanceTests.swift` creates 40 projects, 800 tasks and 1,200 daily statuses (1,240 Markdown files), records cold/median warm load times and verifies zero Markdown reads on unchanged warm scans. Time comparisons must use the same machine/configuration and must not be presented as an FPS or whole-app speedup. Cache invalidation and data correctness tests take precedence over a benchmark number. See `docs/PERFORMANCE.md` for measured results and limits.

## Git remotes

`origin` is `https://github.com/1ommyS/project-tracker.git`; `tracking-app` is the additional destination `https://github.com/Fi7in/tracking-app.git`. Keep both names distinct; do not replace a remote or force-push to bypass missing access/divergent history.

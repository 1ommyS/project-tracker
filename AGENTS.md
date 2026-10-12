# AGENTS.md

Native macOS SwiftUI app "Trace" for daily project management. Fully local — no network, accounts, analytics, or third-party dependencies. All data lives in Obsidian-compatible Markdown files with YAML frontmatter; Markdown is the single source of truth.

## Layout

- `ProjectTracking/` — app source: `MyApp.swift` (entry), `ContentView.swift`, `Models/`, `Services/`, `Views/`, `Utilities/`, `Assets.xcassets`
- `MyAppTests/` — XCTest tests (target `PulseboardTests`; module is imported as `PROJECT_Tracking`)
- `scripts/package-release.sh` — builds release `.zip` + `.dmg` from a built `.app`
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

The README's `Untitled Project.xcodeproj` / scheme `MyApp` commands are stale — use the names above.

## Architecture

Strict layering, all Apple frameworks, Swift 5, deployment target macOS 26.0:

- `Models/DomainModels.swift` — value types (`Project`, `ProjectTask`, `ProjectState`); no I/O. Task-only domain: statuses/notes were removed, `Project.md` keeps `## Описание` and `## Задачи` sections only
- `Services/MarkdownCodec.swift` — pure `nonisolated enum`; Markdown ⇄ model encode/decode. The only unit-tested layer — when changing the storage format, update `MarkdownCodecTests` round-trip tests
- `Services/MarkdownRepository.swift` — `actor` owning all file I/O; writes atomically, deletes via Trash
- `Services/AppStore.swift` — `@MainActor @Observable` single app state (Swift Observation, not ObservableObject/Combine), injected via `.environment(store)`; owns vault monitoring, security-scoped bookmarks, and the navigation history stack (⌘[/⌘] via `goBack`/`goForward`, pushed from `didSet` on destination/selection/presentation)
- `Views/` + `Utilities/DesignSystem.swift` — SwiftUI views read `AppStore` directly. `ProjectsView` has two presentations (`feed`/`editor`) tracked by `store.projectsPresentation`; `ProjectDetailView` is the inline editor with debounced autosave. Shared UI lives in `Views/SharedComponents.swift` (state menu, badges, `RuGrammar` plurals, `ProjectState.color`), sheets in `Views/SheetViews.swift`, the task block reused by feed/editor is `TaskListSection` in `TaskViews.swift`. `Utilities/TaskInputParser.swift` parses natural-language due dates («завтра 18:00», «25.12», «в 14») — covered by `TaskInputParserTests`. Layout metrics come from `PulseMetrics` in DesignSystem (screen 24 / card 18) — do not hardcode paddings. Visual style is native macOS: system color palette (`PulseStyle` aliases system colors), grouped-inset cards via `pulsePanel` (quaternary fill, radius 12, no shadows/strokes), a `.sidebar`-styled sidebar `List`, and screen titles via `navigationTitle` in the toolbar — do not add gradient backdrops, icon chips, or custom title bars. `NotificationService` activates its delegate lazily via `activate()` (never in `AppStore.init`) and logs to OSLog; `authorizeAndSync` is the entry point that may prompt for permission.

Concurrency split: views/main actor → `AppStore`, file I/O only through the repository `actor`, parsing only through the nonisolated codec. `SWIFT_APPROACHABLE_CONCURRENCY` is on.

## Hard constraints

- **Obsidian compatibility**: keep YAML frontmatter fields (`id`, `title`, `epic`, `parent_project`, `state`, `tags`, `created`, `updated`, `archived`), Russian section headers (`## Описание`, `## Статус`, `## Задачи`), and task format `- [ ] Title 📅 YYYY-MM-DD ⏰ HH:mm`. Breaking the format breaks users' existing vaults.
- **Quarter folder layout**: projects live in `Projects/<YYQN>/<slug>/` (quarter of `createdAt`, `Date.quarterLabel`); completed projects (`state == .done/.archived` or `isArchived`) are moved to `Projects/<YYQN>/Completed Projects/<slug>/` by `MarkdownRepository.saveProject`. The slug stays stable across moves. The legacy flat `Projects/<slug>/` layout must keep loading (see `RepositoryTests`).
- All user-facing strings are hardcoded Russian — no localization files.
- No network calls or telemetry, ever (by design).
- File writes must stay atomic; project deletion must go through the system Trash.

## CI / Release gotchas

- CI runs on `macos-26` with Xcode 26; tests must pass with `CODE_SIGNING_ALLOWED=NO`.
- `release.yml` runs after every successful CI on `main`, auto-tagging `v0.1.<CI run number>`; manual `workflow_dispatch` accepts an explicit SemVer tag. Without GitHub secrets it produces unsigned builds (signing/notarization secrets are listed in README).
- Local `DerivedData/`, `dist/`, and signing material (`.p12`, profiles) are gitignored — never commit them.

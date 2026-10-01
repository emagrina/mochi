# Mochi 🍡

Mochi is a lightweight, native macOS menu bar companion for monitoring autonomous AI coding
agents — Claude Code, OpenClaw-managed agents, or anything else — running in the background.
It answers one question at a glance: *are my agents working, waiting, stuck, or done?*

<p align="center"><img src="Resources/AppIcon-preview.png" width="128" height="128" alt="Mochi app icon"></p>

No screenshot gallery of the full UI is included in this repo — building and running the app
(instructions below) is the fastest way to see it. The icon above is the real, shipped
`AppIcon.icns`; the menu bar glyph it sits next to (`MochiMenuBarTemplate.png`, a proper
template image — white in dark menu bars, black in light ones) and `MochiAvatar.swift`'s
per-status character animations were both verified live, including against this machine's
actual menu bar, not just rendered in isolation — see `docs/architecture.md`'s "Visual assets"
section.

## What it is, concretely

- A **menu bar app** (`Mochi.app`) that shows a 🍡 plus an active-agent count, and a popover
  with one row per agent: a small animated character whose face encodes its status, the
  **agent's own identity** as the primary title (not just which runtime is executing it —
  see "Agent identity," below), current task/activity, and elapsed time.
- A **CLI** (`mochi`) that any script or agent calls to report in: `mochi start`, `mochi
  status`, `mochi attention`, `mochi done`, `mochi error`.
- A tiny **file-based protocol** (`~/.mochi/inbox/*.json`) connecting the two — no server, no
  socket, no account, no network. See `docs/protocol.md`.
- **Local-first, zero telemetry.** Nothing leaves your machine. See "Privacy," below.

## Install

Download the latest `Mochi-<version>.dmg` from
[GitHub Releases](../../releases/latest) — no Terminal, no Swift, no cloning this repo.

1. Open the downloaded `Mochi-<version>.dmg`.
2. Drag `Mochi` onto `Applications`.
3. Open Mochi from Applications (or Spotlight) like any other app.

**These are currently unsigned community builds** — Apple Developer ID signing and
notarization aren't set up yet (see `docs/releasing.md`), so macOS Gatekeeper will warn that
Mochi is "from an unidentified developer" the first time you open it. That's expected, not a
sign anything is wrong: right-click (Control-click) `Mochi.app` and choose **Open**, then
confirm once in the dialog that appears. These builds are **not** Apple-notarized — that
claim will only appear here once it's actually true.

Prefer to build from source instead? Continue to "Build & run" below.

## Build & run

Requires macOS 15+ and a full Xcode installation (not just Command Line Tools — see
`docs/architecture.md`'s toolchain note if `swift build` fails with a `dyld` error).

```sh
git clone <this repo>
cd mochi
swift build                 # builds MochiCore, the CLI, and the app library
swift test                  # 83 tests — protocol parsing, state transitions, lifecycle, ...
./Scripts/build-app.sh       # assembles .build/Mochi.app (icon, Info.plist, ad-hoc codesign)
open .build/Mochi.app
```

The Mochi glyph appears in your menu bar as a proper template icon — white in dark menu bars,
black in light ones, automatically. For a release build: `./Scripts/build-app.sh release`.
To build your own installable `.dmg` — the same kind "Install" above points to — see
`docs/releasing.md`.

### See it working immediately

```sh
# Put the CLI on your PATH for this shell, or copy .build/out/Products/Debug/mochi
# somewhere on PATH permanently.
export PATH="$PWD/.build/out/Products/Debug:$PATH"

mochi demo
```

This runs six scripted agents through realistic state transitions (thinking → working →
testing → done, one hitting an error, one requesting permission) over about 25 seconds,
including two sessions sharing one agent identity ("Chief of Staff," running and done at the
same time) to show how that's distinguished in the UI. Watch the menu bar and popover update
live. `mochi demo --agents 8 --step-delay 1` for a faster/bigger run.

Demo sessions are tagged with their own source (never confusable with a real session — see
"Session lifecycle," below) and disappear on their own a couple of minutes after the demo
finishes. To remove them immediately instead of waiting: `mochi demo --cleanup` — it only ever
touches demo data, identified by that tag, never by project or agent name.

## Using the CLI for real

```sh
ID=$(mochi start --agent claude --project Huginn --path ~/Projects/huginn --task "Redesign Library")
mochi status --id "$ID" --state working --activity "Editing LibraryView.swift"
mochi status --id "$ID" --state testing --message "Running tests"
mochi done   --id "$ID" --message "Library redesign complete." \
             --pr-number 42 --pr-url "https://github.com/example/huginn/pull/42"
```

If something goes wrong: `mochi error --id "$ID" --message "Tests failed: ..."`. If an agent
needs you: `mochi attention --id "$ID" --reason permission --message "..."`.

Other commands: `mochi list` (what's known right now), `mochi inspect <id>` (full detail),
`mochi doctor` (diagnose the local setup), `mochi --help` (everything, with full flag docs).
All commands support `--json` for scripting. Full protocol spec: `docs/protocol.md`.

## Agent identity

Mochi shows **who is doing the work** as the primary title — not just which runtime is
executing it. For OpenClaw, that's the agent's real configured name ("Developer", "Chief of
Staff"); for a script, it's whatever you pass via `--agent-name`:

```sh
mochi start --agent claude --agent-name "Frontend Agent" --agent-key "team:frontend" \
  --project Huginn --task "Fix layout bug"
```

`--agent-key` links multiple sessions as the same agent (so two rows read as "this agent has
two sessions," not as an ambiguous duplicate) without merging them — each keeps its own status,
task, and history. Omit both and a session is its own standalone agent, same as before. Full
design rationale, including a real bug this caught (OpenClaw's provider name was being shown
instead of the agent's identity), is in `docs/protocol.md#agent-identity-vs-session-identity`
and `docs/integrations.md`.

## Session lifecycle

**"Working" always means currently working** — a persisted status is historical evidence, not
proof of current liveness. A quiet session moves from its last active status to `Stale` (20
minutes of silence — "no longer confirmed," not "known to have stopped") and on to `Offline`
(90 minutes — presumed gone), both reversible the instant a fresh event arrives. This
reconciliation runs before Mochi ever shows you a session, including right after a cold launch
and standalone via `mochi list`/`doctor`, not only while the app is already running. OpenClaw
sessions get one extra, faster signal: Mochi notices immediately if a session it was tracking
simply disappears from OpenClaw's own active list, rather than waiting out the 20-minute
timeout.

Every session also carries an explicit, typed **source** (OpenClaw, Claude Code, Codex, the
generic CLI, process detection, or demo) — this is what makes demo data structurally
impossible to confuse with a real session, and it's visible in the agent detail view and
`mochi inspect`/`doctor`. This exists because of a real incident caught while building Mochi:
see `docs/protocol.md`'s "Session source" and "Session lifecycle" sections for the full story
and the exact rules.

## Integrations

| Integration | Status | Notes |
|---|---|---|
| Generic (any script/CLI) | **Supported** | The primary path — see above. |
| Claude Code | **Supported** (hooks) | `Integrations/ClaudeCode/` — hook script + a reliable wrapper for one-shot runs. |
| OpenClaw | **Heuristic** (polling) | Verified against a real install; see `docs/integrations.md` for exactly what's real vs. inferred. |
| Codex | **Detection-only** | No `codex` CLI was present to verify a real integration against — see `docs/integrations.md`. |
| Process detection | **Detection-only** | Notices a running process; shows as "Detected," never fakes activity detail. |

Full detail, including a real bug this caught by testing against a live OpenClaw install
(an unbounded query that flooded the UI with months of session history), is in
`docs/integrations.md`.

## Settings

General, Notifications, Appearance, Integrations, Advanced — open via the gear icon in the
popover, or ⌘, from the menu bar item. Notable defaults: notifications fire once per
completion/attention/error condition, never for routine status chatter; finished agents stay
visible for 10 minutes before aging out; launch-at-login uses `SMAppService` (the modern,
supported mechanism — no custom launch daemon).

## Privacy

Mochi is local-first by construction, not by policy:
- No network requests exist in this codebase except explicit, user-initiated ones (opening a
  pull request URL you clicked, which goes straight to your browser).
- No analytics, no telemetry, no crash reporting, no account, no login.
- Every integration reads local state (a CLI's JSON output, a local process list) — nothing is
  sent anywhere.
- All persisted data is plain JSON files under `~/.mochi` (Settings → Advanced → "Open Mochi
  Data Directory" to inspect it directly).

## Troubleshooting

Run `mochi doctor` first — it checks directory permissions, whether `Mochi.app` looks alive,
malformed/quarantined events, stale sessions, and whether `openclaw` is on `PATH`.

- **Nothing shows up in the popover:** confirm the CLI is actually writing events —
  `mochi list` should show whatever's been reported, independent of whether the app is running.
- **Malformed events:** quarantined automatically, never crash the app; the popover footer
  shows a count when any exist, and `mochi doctor` has the detail.
- **No notifications:** notifications require a real, launched `.app` bundle with a stable
  bundle identifier — running the raw `MochiApp` executable via `swift run` won't trigger
  authorization correctly; use `./Scripts/build-app.sh` and `open .build/Mochi.app`.

## Architecture & protocol

- `docs/architecture.md` — module layout, the event pipeline end to end, design decisions and
  why (including the toolchain issue hit while building this and how it was resolved).
- `docs/protocol.md` — the full event schema, the concurrency/atomicity guarantees, and what
  the test suite actually verifies about them.
- `docs/integrations.md` — per-integration reliability, verified against the actual tools
  installed on the machine this was built on.

## Tests

```sh
swift test
```

83 tests across 14 suites: protocol encode/decode (including malformed JSON, unknown future
status values, legacy timestamp formats), the state reducer (out-of-order delivery, duplicate
events, multiple simultaneous sessions, history capping), agent identity (the fallback chain,
and two sessions sharing an `agentKey` resolving to the same recognizable agent), session
lifecycle reconciliation (stale/offline transitions, demo expiry that never touches a real
session, terminal states that are never rewritten, a real spawned-and-exited process checked
for liveness, not a mock), demo cleanup (removes only demo-sourced data, verified against a
mix of demo and real sessions), backward-compatible decoding (a session persisted before
`source`/`agentIdentity` existed loads safely, and doesn't poison the rest of the snapshot
array), settings/session persistence round-trips, and concurrency (60 simultaneous event
writers, 30 simultaneous writers to one shared file) — all passing.

## What's not done

See `docs/architecture.md`'s closing section and `docs/integrations.md` for the honest list —
a push-based OpenClaw plugin, remote/multi-machine agents, a WidgetKit widget, and a few other
explicitly-deferred features, none of which the current architecture blocks.

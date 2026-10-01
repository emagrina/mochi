# Mochi 🍡

Mochi is a lightweight, native macOS menu bar companion for monitoring autonomous AI coding
agents — Claude Code, OpenClaw-managed agents, or anything else — running in the background.
It answers one question at a glance: *are my agents working, waiting, stuck, or done?*

<p align="center"><img src="Resources/AppIcon.iconset/icon_256x256.png" width="128" height="128" alt="Mochi app icon"></p>

No screenshots of the running app are included in this repo — the environment this was built
in has no attached display, so none could be honestly captured (see "Verification" below for
what *was* actually run and checked). The icon above and `MochiAvatar.swift` are the real,
rendered assets; building and running the app (instructions below) is the fastest way to see it.

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

## Build & run

Requires macOS 15+ and a full Xcode installation (not just Command Line Tools — see
`docs/architecture.md`'s toolchain note if `swift build` fails with a `dyld` error).

```sh
git clone <this repo>
cd mochi
swift build                 # builds MochiCore, the CLI, and the app library
swift test                  # 57 tests — protocol parsing, state transitions, concurrency, ...
./Scripts/build-app.sh       # assembles .build/Mochi.app (icon, Info.plist, ad-hoc codesign)
open .build/Mochi.app
```

The 🍡 appears in your menu bar. For a release build: `./Scripts/build-app.sh release`.

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
live. `mochi demo --agents 8 --step-delay 1` for a faster/bigger
run.

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

57 tests across 10 suites: protocol encode/decode (including malformed JSON, unknown future
status values, legacy timestamp formats), the state reducer (out-of-order delivery, duplicate
events, multiple simultaneous sessions, history capping), agent identity (the fallback chain,
and two sessions sharing an `agentKey` resolving to the same recognizable agent), stale-session
detection (including a real spawned-and-exited process, not a mock), settings/session
persistence round-trips (including forward/backward-compatible decoding), and concurrency (60
simultaneous event writers, 30 simultaneous writers to one shared file) — all passing.

## What's not done

See `docs/architecture.md`'s closing section and `docs/integrations.md` for the honest list —
a push-based OpenClaw plugin, remote/multi-machine agents, a WidgetKit widget, and a few other
explicitly-deferred features, none of which the current architecture blocks.

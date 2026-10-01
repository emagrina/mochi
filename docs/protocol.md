# The Mochi Event Protocol (v1)

This is the wire format any agent, script, or adapter uses to tell Mochi what's happening.
It is intentionally boring: small JSON files on disk, no server, no socket, no daemon.

## Why files, not a socket or HTTP server

The spec this app was built from explicitly asks for "the simplest robust architecture" and to
avoid a local HTTP server without a compelling reason. A filesystem mailbox wins on every axis
that matters here:

- **No server to keep alive.** Mochi.app doesn't need to be running for an agent to report in —
  the event just waits in `~/.mochi/inbox` until the app starts and drains it. A socket or HTTP
  server would mean "the agent's `mochi` call fails if Mochi.app isn't open," which defeats the
  point of a companion that can come and go.
- **Concurrency for free.** Multiple agents, possibly on different machines sharing this folder
  over a sync service (not a v1 goal, but the design doesn't preclude it), can write
  simultaneously without coordinating with each other, because every writer creates its own
  uniquely-named file.
- **Trivially inspectable.** `cat ~/.mochi/inbox/*.json` is a complete debugging tool. No
  protocol client needed to see what's going on.
- **Zero idle cost.** The app watches the directory with a `DispatchSource` (kqueue under the
  hood), not a poll loop — see "Watching," below.

## On-disk layout

```
~/.mochi/
  inbox/                 new event files land here
    quarantine/           events that failed to parse/validate
  processed/              recently-ingested events, kept briefly for `mochi doctor`
  state/
    sessions.json          app-owned snapshot of live session state (app is the only writer)
    settings.json           user preferences
  logs/                   reserved for future debug logging
```

Override the root with the `MOCHI_HOME` environment variable (used by the test suite and the
CLI's own smoke tests to avoid touching your real data).

## Writing an event

Every event is one JSON file, written **atomically**: the writer creates a uniquely-named
temp file in the destination directory, writes the full payload to it, then renames it into
place. Rename within one filesystem is atomic, so a reader never observes a half-written file,
and two concurrent writers never collide — each gets its own temp file and its own final
filename (`<timestamp>-<uuid>.json`). See `AtomicFile.swift` and `EventWriter.swift`.

The filename's timestamp prefix uses **millisecond-precision ISO 8601**, not whole seconds.
This matters more than it looks: two CLI calls run back-to-back (`mochi start` immediately
followed by `mochi status`) routinely land in the same wall-clock second, and a cold start
replays the inbox in filename order to reconstruct state. Whole-second timestamps made
same-second events sort by their random UUID suffix instead of call order — a real bug caught
by the test suite while building this (see `MochiDateCoding.swift`'s doc comment).

## Reading events (the app)

`EventInbox` (an actor) watches `~/.mochi/inbox` with a `DispatchSourceFileSystemObject`. On
any change, it **drains**: lists the directory, sorts by filename (chronological, by
construction), and processes every file it finds — not an incremental diff. This makes the
watcher resilient to missed or coalesced filesystem notifications, and means "Mochi wasn't
running when the event arrived" just means a bigger drain on next launch, not a lost event.

Each file is read, decoded, and validated. On success it's moved to `processed/` *before* being
handed to the consumer (so a fast consumer reacting to the event never sees a file still sitting
in the inbox — this ordering was itself a bug caught by the concurrency test suite). On
failure, it's moved to `inbox/quarantine/` instead of being deleted or crashing the app, and
`mochi doctor` reports the count.

`processed/` is pruned to the most recent `processedEventRetention` files (default 500, see
Settings → Advanced) so disk usage never grows without bound.

## Reading events (the CLI, without the app running)

`mochi list` / `mochi inspect` / `mochi doctor` don't depend on the app's `state/sessions.json`
snapshot at all — they replay every file in `processed/` and `inbox/` through the same
`SessionReducer` the app uses (see `SessionProjection.swift`). This is deliberate: Mochi must
stay useful even if `Mochi.app` has never been launched.

## Event schema

```jsonc
{
  "version": 1,                 // required. Any value 1...currentVersion is accepted.
  "event": "status",            // required. One of: start, status, activity, attention,
                                 // completed, error, heartbeat.
  "agentId": "claude-huginn-01", // required, non-empty. Identifier for this SESSION (despite
                                  // the name — kept for backward compatibility; see "Agent
                                  // identity vs. session identity" below). See "Choosing an
                                  // agentId" below.
  "provider": "claude",          // optional. claude | codex | openclaw | anything else.
  "agentKey": "openclaw:lead",    // optional. Stable identity for the AGENT itself, shared
                                   // across every session that agent runs. Omit it and this
                                   // session is treated as its own standalone agent (the
                                   // original, still-default behavior).
  "agentDisplayName": "Chief of Staff", // optional. The agent's configured/custom name —
                                          // becomes the PRIMARY title in the UI, ahead of
                                          // `provider`. See "Agent identity," below.
  "agentRole": "...",             // optional. A role/persona descriptor, if distinct from
                                    // agentDisplayName.
  "source": "genericCLI",         // optional. Where this event came from — see "Session
                                    // source," below. openclaw | claudeCode | codex |
                                    // genericCLI | passiveDiscovery (never "demo" from outside
                                    // `mochi demo` itself). Omit it and the session folds to
                                    // `unknown` — never silently treated as anything more
                                    // trustworthy than that.
  "sessionId": "...",            // optional. The *tool's own* session id, if different from agentId.
  "project": "Huginn",           // optional display name.
  "projectPath": "/Users/.../Huginn", // optional absolute path.
  "task": "Redesign Library",    // optional. Set at start; persists until changed.
  "status": "working",           // optional. idle | starting | working | thinking | testing |
                                  // waiting | needsPermission | paused | done | error, or any
                                  // other string (preserved, shown as-is, future-proof).
                                  // `stale` and `offline` are NOT valid values to send — they
                                  // are Mochi's own conclusions about silence (see "Session
                                  // lifecycle," below), never something a caller asserts.
  "activity": "editing LibraryView.swift", // optional short label.
  "message": "human-readable message",     // optional, shown in the activity log.
  "attentionReason": "permission",         // optional. permission | input | decision | other.
  "error": "error message",                // optional.
  "pullRequest": { "number": 42, "url": "...", "title": "..." }, // optional.
  "branch": "feature/x",         // optional.
  "repository": "org/repo",      // optional.
  "pid": 12345,                  // optional.
  "metadata": { "key": "value" }, // optional, freeform string map for anything else.
  "timestamp": "2026-10-01T14:03:40.123Z" // required, ISO 8601, fractional seconds recommended.
}
```

Every field beyond the four required ones is optional, and **all optional information must
degrade gracefully** — no integration provides everything, and the UI is built to show
"unknown" rather than fabricate a value.

### Event kinds

| `event`     | What it means | Required extra fields |
|---|---|---|
| `start`     | A new session began (or restarted). Resets `finishedAt`, error, and attention state. | — |
| `status`    | The session's primary status changed (and/or its activity/task). | `status` and/or `activity` |
| `activity`  | A finer-grained activity update that doesn't necessarily change `status`. | `activity` |
| `attention` | The session needs the user. Sets status to `needsPermission` unless overridden. | `message`, usually `attentionReason` |
| `completed` | The session finished. Sets `finishedAt`; may carry `pullRequest`. | — |
| `error`     | The session hit an error. | `message` and/or `error` |
| `heartbeat` | "Still here" — bumps `lastActivityAt` without changing status. Useful during a long silent operation to avoid looking stale. | — |

### Choosing an `agentId`

This is the session's identity for Mochi's purposes — **never just the provider name**, since
you can have many Claude or Codex sessions running at once. `mochi start` generates one for you
(`<provider>-<project-slug>-<6 hex chars>`) and prints it; scripts capture it and pass it to
every subsequent call. If you already have a stable identifier (a tool's own session UUID, a
PID, a tmux pane id), use that instead.

### Agent identity vs. session identity

These are two different things, and conflating them was a real bug: Mochi used to show the
*provider* ("OpenClaw") as the big title in the UI, with the actual agent ("Developer", "Chief
of Staff") relegated to a secondary line — backwards for anyone trying to recognize *who* is
working at a glance.

- **Session identity** (`agentId`, the required field) — one run. One dictionary entry, one
  activity log, one row in the popover. A session always belongs to exactly one agent.
- **Agent identity** (`agentKey` + `agentDisplayName`/`agentRole`, both optional) — *who* is
  doing the work, independent of any one run. One agent can have many sessions — a main
  conversation, a dashboard sub-thread, a spawned subagent — all sharing the same `agentKey`
  and `agentDisplayName`, each with its own `agentId`.

Mochi never merges two `AgentSession` rows into one just because they share an `agentKey` —
that would hide real information (a currently-running session vs. one that already finished,
for instance). What sharing a key gets you is that both rows display the *same recognizable
agent name*, so "two 'Chief of Staff' rows" reads as "this agent has two sessions," not as
"are these the same thing or not?" See `AgentIdentity` in `MochiCore/Domain/` and
`docs/architecture.md`.

The resolved title shown in the UI follows this fallback order: `agentDisplayName` →
`agentRole`-as-name (if `agentDisplayName` is absent, a short `name` would slot in here, but no
current integration populates one distinct from `agentDisplayName`) → `agentRole` → the
provider name, as an absolute last resort. The raw `agentKey`/`agentId` are never shown as a
title — a technical identifier like `openclaw:agent:lead:dashboard:cb34...` is worse as a
"name" than just honestly saying "OpenClaw."

If you report multiple sessions for what is conceptually one persistent agent (e.g. a named
Claude Code role you reuse across tasks), pass the same `--agent-key`/`agentKey` each time:

```sh
mochi start --agent claude --agent-name "Frontend Agent" --agent-key "team:frontend" \
  --project Huginn --task "Fix layout bug"
```

## Session source

A third axis, separate from both of the above: **where did this event actually come from.**
This exists because of a real incident — `mochi demo` sessions persisted from earlier
development testing were still showing up, as "Working," in a normal `open Mochi.app` launch
days later. They were indistinguishable from real sessions except by reading project names
like "Huginn" or "Serafín," which was explicitly the wrong signal to filter on: a real project
can legitimately be named anything a demo scenario also happens to use.

Every session carries a `source` (`SessionSource` in code): `openclaw`, `claudeCode`, `codex`,
`genericCLI`, `demo`, `passiveDiscovery`, or `unknown`. It's set once, from whichever event
creates the session, and never overwritten afterward (only ever *upgraded* away from
`unknown` if a later event finally supplies a real one). Two sources are special:

- **`demo`** is set unconditionally by `mochi demo` on every event it writes — there is no
  flag or option that lets a demo session claim to be anything else, and the plain CLI (and
  every integration adapter) never sets it. `mochi demo --cleanup` and automatic expiry
  (see "Session lifecycle," below) both key off this field, never off a project or agent name.
- **`unknown`** is the honest default for an event with no `source` field at all — either
  because it predates this field, or because it was hand-written outside the `mochi` CLI. It
  is never auto-upgraded to something more trustworthy, and nothing that operates on a
  specific known source (cleanup, OpenClaw-specific reconciliation) ever touches it; it just
  participates in the generic, time-based lifecycle rules like any other non-demo session.

## Session lifecycle

A persisted status is historical evidence, not proof of current liveness — treating
"the last event said working" as "therefore still working, forever" was the mechanism behind
the incident described above. `StaleDetector.reconcileLifecycle` runs on every session restore
and periodically thereafter (both in the live app and in the CLI's replay path, so `mochi list`
is truthful even standalone) and does three things, based purely on how long it's been since a
session's last event:

1. **Demo sessions** past a short retention window (a couple of minutes) are removed outright,
   regardless of status — see "Session source," above.
2. **Active-looking sessions** (`working`, `thinking`, `testing`, `waiting`, `needsPermission`)
   quiet for longer than `staleThreshold` (20 minutes) move to **`stale`** — "we can no longer
   confirm this," not "we know it stopped."
3. **Any non-terminal session** quiet for longer than `offlineThreshold` (90 minutes) moves to
   **`offline`** — presumed gone. Both transitions are fully reversible: a single fresh event
   for the same session id overrides either one exactly like any other status change, through
   the ordinary event pipeline.

`done` and `error` sessions are never touched — those already have real evidence behind them.
OpenClaw sessions get one additional, faster signal: `OpenClawAdapter` remembers what it saw on
the previous poll, and if a session it previously reported as active simply disappears from a
fresh `sessions list --active` result, it reports `stale` immediately rather than waiting for
the 20-minute timeout — real evidence of disappearance, not a guess.

## Resilience and concurrency, concretely

These properties are enforced by the test suite (`Tests/MochiCoreTests`), not just asserted
here:

- **Malformed JSON** doesn't crash anything — it's quarantined and counted (`MochiEventTests`,
  `EventInboxTests`, `SessionProjectionTests`).
- **Unknown status strings** (a future protocol version, a typo) decode into
  `AgentStatus.custom(...)` rather than failing (`MochiEventTests.unknownStatus`).
- **Unknown extra JSON fields** are ignored by `JSONDecoder` automatically — a newer writer can
  add fields a reader doesn't understand yet without breaking it (`forwardCompatibleExtraFields`).
- **Out-of-order delivery** (a slow write, a backlog replayed in the wrong order) can't regress
  the session's current state backward in time, but the event still lands in the activity log
  (`SessionReducerTests.outOfOrderDoesNotRegressState`).
- **Exact duplicate events** (a retried CLI call) don't produce duplicate log lines
  (`duplicateEventIsIdempotentInLog`).
- **Many concurrent writers** never corrupt each other's files — verified by firing 60
  simultaneous writes at the same inbox directory and decoding every resulting file
  (`ConcurrencyTests.concurrentEventWriters`).
- **`AtomicFile.write`** to a shared destination (used for `state/sessions.json` and
  `settings.json`, which only the app writes, but concurrently from multiple internal tasks) is
  all-or-nothing — verified by racing 30 writers and asserting the result is exactly one of
  their payloads, never a mix (`ConcurrencyTests.atomicOverwriteIsAllOrNothing`).

## A worked example

```sh
ID=$(mochi start --agent claude --project Huginn --path ~/Projects/huginn --task "Redesign Library")
mochi status  --id "$ID" --state thinking --message "Reading LibraryView.swift"
mochi status  --id "$ID" --state working  --activity "Editing LibraryView.swift"
mochi status  --id "$ID" --state testing  --message "Running frontend tests"
mochi done    --id "$ID" --message "Library redesign complete." --pr-number 42 \
              --pr-url "https://github.com/example/huginn/pull/42"
```

See `docs/integrations.md` for how real tools (OpenClaw, Claude Code) are wired to this
protocol today.

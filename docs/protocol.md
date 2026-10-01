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
  "agentId": "claude-huginn-01", // required, non-empty. Stable identifier for this session —
                                  // see "Choosing an agentId" below.
  "provider": "claude",          // optional. claude | codex | openclaw | anything else.
  "sessionId": "...",            // optional. The *tool's own* session id, if different from agentId.
  "project": "Huginn",           // optional display name.
  "projectPath": "/Users/.../Huginn", // optional absolute path.
  "task": "Redesign Library",    // optional. Set at start; persists until changed.
  "status": "working",           // optional. idle | starting | working | thinking | testing |
                                  // waiting | needsPermission | paused | done | error | offline,
                                  // or any other string (preserved, shown as-is, future-proof).
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

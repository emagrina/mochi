# Integrations

Every integration here is labeled with how much to trust it. These labels are shown verbatim
in Settings → Integrations, and this document is the source of truth for what they mean:

- **Supported** — a documented, first-party mechanism, verified against the actual tool
  installed on this machine while building Mochi.
- **Heuristic** — built on a real signal, but mapping that signal onto Mochi's states requires
  inference (e.g. "last updated 40 seconds ago" → "probably working").
- **Experimental** — works today but depends on behavior we could only partially verify
  locally; expect it to need adjustment against a differently-configured install.
- **Detection-only** — we can see a process exists and nothing more.

Mochi's core (`MochiCore`) has no dependency on any of these — each one is an adapter that
turns third-party state into ordinary Mochi protocol events (`docs/protocol.md`), the same
format the CLI uses. None of them patch or modify the third-party tool.

## OpenClaw — Heuristic, polling-based

Verified against OpenClaw 2026.9.7, installed locally.

**What's real:**
- `openclaw sessions list --json --all-agents --active <minutes>` is a documented, read-only
  CLI surface. Each session carries a genuine `status` field (`"running"`, `"done"`, ...),
  which `OpenClawAdapter` translates directly — this is a supported signal, not a guess.
- `openclaw approvals pending --json` is a documented surface for pending exec/plugin/
  system-agent approvals via the Gateway — the real signal for "needs you" the product spec
  asks for. We could not exercise it against a *live* pending approval while building this
  (nothing was actually waiting on approval during development), so the JSON field names used
  to correlate an approval back to a specific session are **experimental**: `OpenClawAdapter`
  tries a handful of plausible key names (`agentId`, `sessionId`, `session`, `agent`, `id`) and
  skips any approval it can't identify, rather than guessing wrong.
- `openclaw agents list --json` maps agent ids to `identityName` (e.g. `"Chief of Staff"`,
  `"Developer"` — the real, user-configured name OpenClaw exposes for that agent) and
  `workspace` (used for `projectPath`). `identityName` becomes `agentDisplayName` and is what
  Mochi shows as the row's PRIMARY title — see "Agent identity, not provider identity," below.
- A session `key` like `"agent:lead:dashboard:cb34..."` decomposes into the OpenClaw agent id
  (`"lead"`, stable across every session that agent runs — becomes `agentKey`) and a session
  kind (`"dashboard"`, `"acp"`, `"cron"`, `"main"`, ... — becomes the row's `project`/context
  label, e.g. "Dashboard session"). A session's own `label` field (a real OpenClaw-assigned
  description — a short nickname for a sub-thread, or a fuller task string for a spawned
  subagent) becomes `task`.
- **Disappearance detection**: `OpenClawAdapter` remembers which session keys it saw actively
  working/waiting on the *previous* poll. If one of them is simply absent from a fresh
  `sessions list --active` result, that's real evidence — not a guess — that OpenClaw no
  longer considers it active, and the adapter reports it `stale` immediately rather than
  waiting for Mochi's generic 20-minute silence timeout. This only ever moves a session to
  `stale`, never `offline` — a session dropping out of the active window doesn't tell us
  whether it finished cleanly or crashed, and `stale` ("no longer confirmed") is the honest
  signal for that, not `offline` ("presumed gone"). See `docs/protocol.md`'s "Session
  lifecycle" section.

**What's not available:** OpenClaw exposes no fine-grained activity signal — no
"thinking"/"testing" distinction. Mochi can only show working, done, or an OpenClaw-reported
status passed through verbatim. OpenClaw also doesn't expose a role distinct from
`identityName`, so `agentRole` is left unset for OpenClaw sessions rather than fabricated.

### Agent identity, not provider identity

Earlier versions of this adapter put `agentInfo?.identityName` into the `project` field and
left the UI showing "OpenClaw" as the primary title — which meant every row for every OpenClaw
agent looked the same at a glance ("OpenClaw" / "OpenClaw" / "OpenClaw"), with the actually
useful information (which agent, "Developer" vs. "Chief of Staff") demoted to secondary text.
Verified live against this machine's real OpenClaw install, that's genuinely confusing: you
can't tell two sessions of the same agent apart from two different agents, or a finished
session from a currently-running one, by title alone.

Fixed by introducing `agentKey`/`agentDisplayName` in the protocol (see
`docs/protocol.md#agent-identity-vs-session-identity`) and populating them from the real
`identityName`/agent-id data above. Verified output against this machine's live sessions:

```
Developer        Working      (OpenClaw) ACP session        · 16s   [openclaw:agent:developer:acp:4c43612a-...]
Chief of Staff   Working      (OpenClaw) Dashboard session   · 16s   [openclaw:agent:lead:dashboard:cb347e08-...]
Chief of Staff   Done         (OpenClaw)                     · 16s   [openclaw:agent:lead:main]
```

Both "Chief of Staff" rows share `agentKey = "openclaw:lead"` (confirmed via
`mochi inspect <id>`), so they're recognizable as the same agent while remaining two distinct,
independently-trackable sessions — one still running, one already done.

**A real bug this caught:** the first version of this adapter called `sessions list` with
`--limit all` and no recency bound. Run against this machine's actual, months-old OpenClaw
install, that returned the *entire* session history — every cron run, every subagent spawn,
ever — flooding Mochi's UI with 50+ irrelevant rows. It also treated OpenClaw's
`abortedLastRun` flag as an error signal, which turned out to be `true` on perfectly ordinary,
non-failed sessions, which would have produced false "problem" notifications. Both are fixed:
polling is bounded to `--active 30` (last 30 minutes), and `abortedLastRun` is ignored
entirely. This is exactly the kind of thing that's invisible without testing against a real
install, which is why it's called out here rather than just fixed silently.

**Not implemented (a real next step, not a stub):** OpenClaw has its own plugin/hook system
(`openclaw plugins init`, `openclaw hooks list`) that bundled hooks use to react to events like
`gateway:startup`, `command`, `session:compact:*`. A genuine push-based integration — a small
OpenClaw plugin that calls the Mochi CLI directly on session lifecycle events — is possible in
principle, confirmed by scaffolding a plugin locally. It is **not** implemented here because
verifying it end-to-end needs the user's own OpenClaw plugin install/enable/gateway-restart
flow, which is out of scope to ship half-verified. The polling adapter above needs no
installation step and works today.

Toggle: Settings → Integrations → OpenClaw. Polls every 15 seconds while enabled.

## Claude Code — Supported (hooks) + a reliable wrapper for one-shot runs

Claude Code's hook system (`settings.json` → `"hooks"`) is a documented, first-party mechanism.
`Integrations/ClaudeCode/mochi-claude-hook.sh` bridges four hook events to the Mochi CLI:

| Hook | Mochi event | Notes |
|---|---|---|
| `SessionStart` | `mochi start` | Once per session; a marker file prevents double-starts. |
| `PreToolUse` | `mochi status --state working` | Activity label is the tool name. |
| `Notification` | `mochi attention --reason input` | Fires for both permission prompts and "waiting on you" idle notices — Claude Code doesn't distinguish them in the payload, so neither do we. |
| `Stop` | `mochi status --state waiting` | **Not** `done` — `Stop` fires at the end of every turn, not just the end of the session. Reporting "waiting" is honest; reporting "done" here would be a guess. |

Wire it up in `~/.claude/settings.json` (or a project's `.claude/settings.json`):

```jsonc
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "/path/to/mochi-claude-hook.sh SessionStart" }] }],
    "PreToolUse":   [{ "hooks": [{ "type": "command", "command": "/path/to/mochi-claude-hook.sh PreToolUse" }] }],
    "Notification": [{ "hooks": [{ "type": "command", "command": "/path/to/mochi-claude-hook.sh Notification" }] }],
    "Stop":         [{ "hooks": [{ "type": "command", "command": "/path/to/mochi-claude-hook.sh Stop" }] }]
  }
}
```

Requires `jq` (bundled with modern macOS) and `mochi` on `PATH`.

**For reliable completion/error signaling**, especially for the one-shot, non-interactive
invocation that's the common shape for an autonomous background agent (`claude -p "task"` from
a script), use `mochi-claude-wrapper.sh` instead of relying on hooks for the finish state — it
knows the actual process exit code, so `done` vs. `error` is a fact, not an inference:

```sh
mochi-claude-wrapper.sh Huginn "Redesign Library page" -- -p "Redesign the Library page"
```

**Naming a persistent role** (e.g. if you run Claude Code repeatedly as a "Frontend Agent" and
separately as a "Backend Agent"): Claude Code itself has no concept of a named persona the way
OpenClaw does, so Mochi can't discover a name automatically — but the CLI/protocol support one
if you supply it. Pass `--agent-name` (and `--agent-key` to link multiple sessions as the same
agent) to `mochi start`:

```sh
mochi start --agent claude --agent-name "Frontend Agent" --agent-key "team:frontend" \
  --project Huginn --task "Fix layout bug"
```

This is the same mechanism OpenClaw's adapter uses internally — see
`docs/protocol.md#agent-identity-vs-session-identity`.

## Codex — Detection-only

No `codex` CLI was found on this machine (`which codex` → not found), so no hook/API surface
could be inspected or verified. Rather than guess at an integration we can't test, Codex gets
the same treatment as any unrecognized tool: process detection only (below). If you have Codex
installed and it exposes a hook/callback mechanism, `mochi`'s CLI commands work from any
wrapper script the same way the Claude Code wrapper does — see `mochi --help`.

## Process detection — Detection-only

`ProcessDiscoveryAdapter` runs `ps -axo pid=,comm=` every 20 seconds and matches exact (not
substring) basenames `claude`, `codex`, `openclaw`. A match produces a session with
`discovery: detected` — rendered in the UI as **"Detected — no activity information
available,"** never with a fabricated task or status beyond "idle." This exists purely to nudge
you toward real instrumentation, not to replace it (product spec section 10 is explicit that
detected and instrumented sessions must never be visually conflated — see `AgentRow`'s
`· detected` suffix and `AgentDetailView`'s distinct notice).

Detected sessions disappear automatically ~90 seconds after their process stops showing up in
a poll — they're a live nudge, not a historical record.

Toggle: Settings → Integrations → Process detection. Polls every 20 seconds while enabled.

## Generic / anything else

Any script can report into Mochi with zero configuration — see `docs/protocol.md` and
`mochi --help`. This is the actual primary integration path; everything above is a convenience
layered on top of it.

## `mochi doctor`

Diagnoses the local setup: event directory permissions, whether `Mochi.app` appears to be
running (based on when it last wrote its state snapshot), malformed/quarantined events, stale
sessions, and whether the `openclaw` CLI is on `PATH`. Run it first when something looks wrong.

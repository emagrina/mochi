# Architecture

## Why Swift Package Manager instead of an Xcode project

This machine has no complete Xcode installation — only Command Line Tools (and those turned
out to be a mismatched/broken install; see "Toolchain note" below). SwiftPM is also just a
better fit for a project that needs to build and test headlessly from a CLI agent: `swift
build`, `swift test`, and a hand-assembled `.app` bundle (`Scripts/build-app.sh`) give the same
result an Xcode project would, with a plain-text `Package.swift` instead of a generated
`.xcodeproj`. If you have a full Xcode installation, `swift package generate-xcodeproj` (or just
opening the folder in modern Xcode, which understands SwiftPM packages directly) works fine too.

**Toolchain note:** this machine's Command Line Tools install had a broken/mismatched
`swift-package` binary (a `dyld` symbol error on every invocation). The fix was pointing
`DEVELOPER_DIR` at a full Xcode.app install instead:
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
```
If `swift build` fails with a `dyld` error, check for the same mismatch (`xcode-select -p`,
compare against an actual Xcode install).

## Module layout

```
Sources/
  MochiCore/        Platform-agnostic library. No SwiftUI, no AppKit (except where a
                     feature genuinely needs an AppKit type, like NSColor for dynamic
                     colors — isolated to MochiApp's UI layer, not here).
    Domain/           AgentStatus, AgentIdentity, AgentSession, AggregateState — the data model.
    EventProtocol/    MochiEvent (the wire format), EventWriter, EventInbox (the watcher).
    StateEngine/      SessionReducer (pure fold function), SessionProjection (disk replay),
                      StaleDetector.
    Persistence/      MochiSettings, PersistenceStore (settings + session snapshot).
    Integrations/     IntegrationAdapter protocol, OpenClawAdapter, ProcessDiscoveryAdapter,
                      IntegrationsCoordinator (runs each adapter on its own interval).
    Notifications/    NotificationManager (thin UNUserNotificationCenter wrapper).
    Git/              GitInfo (cached `git rev-parse --abbrev-ref HEAD`).
    Terminal/         TerminalLauncher protocol, GhosttyLauncher, TerminalAppLauncher.
    Utilities/        AtomicFile, MochiPaths, MochiDateCoding, ProcessRunner.

  MochiApp/          The SwiftUI menu bar app. Owns AppModel (the one piece of mutable
                     state), consumes MochiCore, adds UI.
    AppModel.swift     @MainActor @Observable — sessions, settings, background task lifecycle.
    UI/MenuBar/        MenuBarLabel, PopoverView.
    UI/Agents/         AgentRow, AgentDetailView, AgentActions (validated open/copy actions).
    UI/Components/     MochiAvatar (the character), MochiColors.
    UI/Settings/       SettingsView (five tabs).
    UI/Onboarding/     OnboardingView (first-launch explainer).

  mochi/             The CLI. Depends on MochiCore + swift-argument-parser. Each subcommand
                     is its own file under Commands/.

Tests/MochiCoreTests/  Tests covering the protocol, reducer, stale detection, persistence,
                        agent identity, and — deliberately — concurrency (many simultaneous
                        writers).

Resources/
  DesignSources/       The two source illustrations everything visual is generated from —
                        see "Visual assets," below.
  AppIcon.iconset/      Generated, gitignored intermediate.
  AppIcon.icns           Generated, committed (so a clean checkout builds immediately).
  AppIcon-preview.png     A static copy for this README — not used by the app itself.
```

`MochiCore` has zero knowledge of OpenClaw, Claude Code, or any specific integration beyond the
generic `IntegrationAdapter` protocol — each concrete adapter lives in its own subfolder and
could be deleted without touching anything else (product spec section 8's requirement, made
structural rather than just a convention).

## The event pipeline, end to end

```
 CLI / wrapper script / adapter
          │ EventWriter.write()  (atomic file create)
          ▼
   ~/.mochi/inbox/*.json
          │ DispatchSource watch (kqueue) — zero polling while idle
          ▼
   EventInbox.drain()  (actor; move-to-processed happens before yielding, not after —
          │             see docs/protocol.md's concurrency section for why that ordering
          │             mattered)
          ▼
   AppModel.consumeEvents()  (MainActor; for-await loop)
          │ SessionReducer.apply(event, to: &sessions)
          ▼
   sessions: [String: AgentSession]   ← the single source of truth for the UI
          │
          ├─► notifyIfNeeded()  — at most one notification per attention/error/completion
          │                       condition, gated by settings
          └─► PopoverView / MenuBarLabel / AgentDetailView  (read-only consumers)
```

Separately, `IntegrationsCoordinator` runs each enabled adapter's `pollOnce` on its own timer,
writing ordinary `MochiEvent`s through the same `EventWriter` — adapters are indistinguishable
from any other event source once they hit the inbox.

The CLI's `list`/`inspect`/`doctor` commands don't participate in this live pipeline at all;
they call `SessionProjection.replayAll`, which runs the same `SessionReducer` over whatever's
in `processed/` + `inbox/` on disk. One reducer, two call sites, so there's no second copy of
"what does a status event mean" to drift out of sync.

## State model

`AgentStatus` is a value type, not a closed Swift enum switched on everywhere — it has a
`.custom(String)` case so an unrecognized status (a future protocol version, an integration's
own vocabulary like OpenClaw's `"running"`) degrades to "preserved and displayed" instead of
"crashes" or "silently coerced to the wrong thing." Sort priority, "is this active," "does this
need attention," and the friendly display label are all computed properties on this one type —
not duplicated switch statements scattered across the menu bar icon, the popover, and the CLI.

`AggregateState` is the single place that computes "what does the menu bar icon show" from a
list of sessions (product spec section 47's requirement against duplicated rollup logic). Its
`Headline` enum encodes the actual priority order (attention > error > active > waiting >
done/idle/empty) as data, not as scattered if-chains.

### Agent identity vs. session identity

`AgentSession` is keyed by *session* (one run); `AgentIdentity` (a field on every session, not
a separate dictionary) is keyed by *agent* (who's doing the work). This split exists because
the original model conflated them: a session's only identity was its own id, so the UI fell
back to showing the *provider* ("OpenClaw") as the primary title — true but useless, since it
answers "which runtime" instead of "which agent." Verified live against a real OpenClaw
install, two sessions of the same agent ("Chief of Staff," running a main conversation and a
dashboard sub-thread) were indistinguishable from two different agents at a glance; see
`docs/integrations.md`'s "Agent identity, not provider identity" for the before/after.

`AgentIdentity.title` is a fallback chain (configured display name → short name → role →
provider), computed in one place and consumed everywhere `AgentSession.displayName` is used —
the CLI's `list`/`inspect`, the popover row, the detail view, and notifications all got the fix
by construction rather than needing five separate edits. `AgentIdentity.key` is what lets two
sessions be *recognized* as the same agent (`OpenClawAdapter` derives it from the session key's
agent-id segment, stable across that agent's sessions) — Mochi never merges two `AgentSession`
rows just because they share a key, since that would hide real information (one might be done,
the other still running); sharing a key only makes both rows display the same resolved name.
Generic/CLI/Claude Code callers can opt in with `--agent-key`/`--agent-name`; omitting them
preserves the original one-session-per-task behavior (key defaults to the session's own id).

## Concurrency and persistence choices

- **Inbox:** per-event files + atomic rename. See `docs/protocol.md` for the full rationale —
  short version, it's the simplest mechanism that's provably safe for many concurrent writers
  without a server.
- **App-owned state** (`state/sessions.json`, `state/settings.json`): plain JSON, also written
  via `AtomicFile`, but single-writer (only `Mochi.app` touches these) so there's no
  multi-writer concern — SQLite or SwiftData would be solving a problem that doesn't exist
  here. The session snapshot is saved every 5 seconds while the app runs, so a restart doesn't
  lose `attentionNotified`/`completionNotified` bookkeeping (which is what prevents duplicate
  notifications) or recent history.
- **No database.** Total persisted state is a few sessions' worth of small JSON — "the
  simplest mechanism that's actually robust" beat "the default choice" here, same as the inbox.

## Notifications

`NotificationManager` is a three-method wrapper (`notifyCompleted`/`notifyAttention`/
`notifyError`) — there is no generic "send a notification for any status change" path, on
purpose, so routine status chatter (thinking, testing, working) structurally cannot spam the
user. Each session tracks `attentionNotified`/`completionNotified` booleans that flip to `true`
right before the notification is sent and reset on the next genuinely new occurrence (a fresh
`start` event, or a fresh `attention`/`error` event) — this is what gives "exactly one
notification per condition" (product spec section 37) rather than "one notification per status
event," which would still spam on every poll cycle for a long-attention-needed session.

## Stale detection

`StaleDetector` never rewrites a session's status based on silence — that would be claiming
certainty Mochi doesn't have. Instead `isStale(session)` is a computed signal the UI overlays
("Last seen 27m ago") on top of whatever the last real status was, and `isProcessAlive(pid:)`
is an additional, separate piece of evidence when a PID is known. Detected-only sessions (pure
process observation, no protocol events) use a much shorter window — they disappear from the
list ~90 seconds after the process stops showing up, since for those, "we stopped seeing it" is
strong evidence, not just an inference.

## Terminal integration (Ghostty)

Ghostty's own `--help` states plainly that launching it directly from argv0 isn't supported on
macOS and to use `open -na Ghostty.app` instead; `--working-directory` is a real, documented
config key (confirmed locally via `ghostty +show-config --default`). `TerminalLauncher` is a
protocol specifically so this isn't hard-wired — `TerminalAppLauncher` (plain Terminal.app) is
the fallback when Ghostty isn't installed, and either one only ever receives a path the caller
has already verified exists and is a directory (`AgentActions.canOpenTerminal`), launched via
`/usr/bin/open` with an argument array, never a constructed shell string.

## Visual assets

Both the app icon and the menu bar glyph are generated from two checked-in, high-resolution
source illustrations — `Resources/DesignSources/MochiAppIcon.png` and
`MochiMenuBarGlyph.png` — by `Scripts/generate-assets.swift`, never hand-exported or edited
pixel-by-pixel. The two have different jobs and are processed differently:

- **App icon**: `generate-assets.swift` finds the actual artwork's pixel bounding box inside
  the source (by brightness difference from the sampled background, since this source has no
  alpha channel), then crops the largest square frame — centered on that bbox, clamped to the
  source's own bounds — that still gives the artwork sensible padding. Clamping to the source
  bounds is what guarantees every exported iconset size (16pt up to 512pt@2x) is a downscale,
  never an upscale of a smaller derivative. `Scripts/build-app.sh` runs `iconutil` on the
  result to produce `Resources/AppIcon.icns`, copied into the `.app` bundle's `Resources/`
  directly (the standard `CFBundleIconFile` mechanism — nothing SwiftUI/SwiftPM-specific).
- **Menu bar glyph**: same bounding-box approach, but the crop keeps the artwork's own (non-
  square) aspect ratio, with tighter padding than the app icon — status-bar icons sit among
  tightly-drawn system glyphs (Wi-Fi, Control Center) and look wrong floating in extra
  whitespace next to them. The source is already a near-opaque near-white silhouette on a
  transparent background (confirmed by sampling actual pixel alpha values while building
  this), so the only processing needed is normalizing its RGB to pure black — a `isTemplate`
  image is rendered by AppKit using only the alpha channel, but doing this anyway keeps the
  exported asset self-describing rather than depending on that rule to paper over a
  non-black source. Exported once at a fixed, generous pixel height (216px) — far more than
  any menu bar needs — so a single file stays crisp at every Retina scale factor; see
  `MenuBarLabel.swift`, which loads it via `Bundle.module`, sets `NSImage.isTemplate = true`,
  and sets `.size` explicitly to an 18pt point size (not its native pixel size) to match the
  optical scale of neighboring system status items.

`Scripts/build-app.sh` regenerates both from source whenever `Resources/AppIcon.icns` or
`Sources/MochiApp/Resources/MochiMenuBarTemplate.png` is missing, and does so *before* calling
`swift build` — the menu bar template is a SwiftPM-processed resource that gets compiled into
the executable's resource bundle at build time, so it has to already exist on disk by then,
unlike the `.icns`, which is only ever copied into the `.app` bundle afterward. Both generated
outputs are committed (small, deterministic, and letting a clean checkout build immediately
without re-running the generator) alongside the two source images; only the intermediate
`Resources/AppIcon.iconset/*.png` files are gitignored.

## What's deliberately not built yet

- A genuine push-based OpenClaw plugin (vs. the polling adapter) — see `docs/integrations.md`.
- SSH/remote-machine agents, multiple Macs, pause/resume, sending input, cost/token display,
  GitHub PR *state* (open/merged/closed — the PR URL itself is shown today), project grouping,
  an iOS companion, Live Activities. None of these are structurally blocked by anything above —
  `AgentSession` already carries a stable `id` independent of machine/provider, and
  `IntegrationAdapter` doesn't assume local-only — they're just not v1.
- A WidgetKit widget — investigated, deliberately deprioritized to avoid destabilizing the
  core app for a secondary surface (product spec section 49's own guidance).

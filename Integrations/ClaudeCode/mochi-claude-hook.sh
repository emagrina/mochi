#!/bin/sh
# Bridges Claude Code's hook system to the Mochi CLI. See docs/integrations.md for the
# settings.json wiring and exactly which hook events this handles.
#
# Claude Code invokes hook commands with the event payload as JSON on stdin and the event
# name as $1 (we pass it explicitly from settings.json rather than relying on
# $CLAUDE_HOOK_EVENT, since the latter isn't part of the documented contract). Requires `jq`
# (bundled with modern macOS).
set -eu

EVENT_NAME="${1:-}"
PAYLOAD="$(cat)"

SESSION_ID="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty')"
CWD="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty')"
[ -z "$SESSION_ID" ] && exit 0

AGENT_ID="claude-code-${SESSION_ID}"
PROJECT_NAME="$(basename "${CWD:-unknown}")"
STATE_FILE="${MOCHI_HOME:-$HOME/.mochi}/state/claude-code-${SESSION_ID}.started"

case "$EVENT_NAME" in
  SessionStart)
    mkdir -p "$(dirname "$STATE_FILE")"
    if [ ! -f "$STATE_FILE" ]; then
      touch "$STATE_FILE"
      mochi start --agent claude --id "$AGENT_ID" --project "$PROJECT_NAME" --path "$CWD" \
        --task "Working in $PROJECT_NAME" >/dev/null 2>&1 || true
    fi
    ;;
  PreToolUse)
    TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // "a tool"')"
    mochi status --id "$AGENT_ID" --state working --activity "Using $TOOL_NAME" >/dev/null 2>&1 || true
    ;;
  Notification)
    # Claude Code fires this both for permission prompts and for "waiting on you" idle
    # notices; the payload's `message` is the only reliable signal to distinguish them, so
    # we pass it straight through rather than guessing a more specific reason.
    MESSAGE="$(printf '%s' "$PAYLOAD" | jq -r '.message // "Claude needs your attention."')"
    mochi attention --id "$AGENT_ID" --reason input --message "$MESSAGE" >/dev/null 2>&1 || true
    ;;
  Stop)
    # Stop fires at the end of EVERY turn, not just at the end of the whole session — in an
    # interactive multi-turn session you'll see this repeatedly. Reporting "waiting" (Claude
    # stopped generating, likely idle until the next message) is honest; reporting "done"
    # here would be a guess we can't back up. For reliable completion signaling on a
    # single-shot/non-interactive invocation, wrap the `claude` process itself instead — see
    # mochi-claude-wrapper.sh and docs/integrations.md.
    mochi status --id "$AGENT_ID" --state waiting --message "Claude stopped responding" >/dev/null 2>&1 || true
    ;;
esac

exit 0

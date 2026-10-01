#!/bin/sh
# Reliable completion signaling for a one-shot, non-interactive Claude Code invocation — the
# common shape for an autonomous background agent (`claude -p "task"` from a script or CI),
# as opposed to an interactive session a human is driving turn-by-turn.
#
# Unlike the hooks (mochi-claude-hook.sh), this knows the agent's actual process exit code,
# so it can report `done` or `error` with real confidence instead of inferring from a
# per-turn Stop event.
#
# Usage:
#   mochi-claude-wrapper.sh <project-name> <task description> -- <claude CLI args...>
#
# Example:
#   mochi-claude-wrapper.sh Huginn "Redesign Library page" -- -p "Redesign the Library page"
set -eu

PROJECT_NAME="$1"; shift
TASK="$1"; shift
if [ "${1:-}" = "--" ]; then shift; fi

ID=$(mochi start --agent claude --project "$PROJECT_NAME" --path "$(pwd)" --task "$TASK" --source claudeCode)
mochi status --id "$ID" --state working --message "Running claude" >/dev/null 2>&1 || true

if claude "$@"; then
    mochi done --id "$ID" --message "Finished." >/dev/null 2>&1 || true
else
    EXIT_CODE=$?
    mochi error --id "$ID" --message "claude exited with status $EXIT_CODE" >/dev/null 2>&1 || true
    exit "$EXIT_CODE"
fi

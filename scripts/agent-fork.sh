#!/usr/bin/env bash
# Fork the agent session running in the current pane into a new pane on the
# far left of the window.  prefix+c f for Claude, prefix+o f for Codex.
#
#   agent-fork.sh <claude|codex> <pane_pid> <pane_current_path>
#
# The pane's own session is found by walking its process tree:
#   claude - the running process's pid is looked up in `claude agents --json`,
#            which carries the session id.
#   codex  - the id is taken from the argv of `codex resume <id>` / `fork <id>`,
#            otherwise the rollout file whose name carries the process start
#            time (local, to the second) and whose header cwd matches the pane.
# If the pane has no agent, or the lookup fails, the fork falls back to the
# most recent session for the pane's directory.
#
# AGENT_FORK_DRY=1 prints the command it would run instead of opening a pane.
set -uo pipefail

engine="${1:?claude|codex}"
pane_pid="${2:?pane pid}"
path="${3:-$PWD}"

# Every descendant of the pane's shell, depth first. (ps rather than pgrep:
# pgrep silently skips its own ancestors, which hides an agent when this is
# run from inside one.)
descendants() {
	local p
	for p in $(ps -axo pid=,ppid= | awk -v pp="$1" '$2 == pp {print $1}'); do
		echo "$p"
		descendants "$p"
	done
}

# First descendant whose command line looks like the engine binary.
agent_pid() {
	local p cmd
	for p in $(descendants "$pane_pid"); do
		cmd="$(ps -o command= -p "$p" 2>/dev/null)"
		case "$engine" in
		claude) case "$cmd" in claude|claude\ *|*/claude|*/claude\ *) echo "$p"; return ;; esac ;;
		codex)  case "$cmd" in codex|codex\ *|*/codex|*/codex\ *)     echo "$p"; return ;; esac ;;
		esac
	done
}

claude_session() {
	local pid="$1"
	claude agents --json 2>/dev/null |
		jq -r --argjson pid "$pid" '.[] | select(.pid == $pid) | .sessionId // empty' 2>/dev/null |
		head -1
}

codex_session() {
	local pid="$1" cmd id start epoch off ts f cwd
	cmd="$(ps -o command= -p "$pid" 2>/dev/null)"
	# `codex resume <uuid>` / `codex fork <uuid>` name the session outright.
	id="$(printf '%s' "$cmd" | grep -oE '(resume|fork) +[0-9a-f-]{36}' | awk '{print $2}' | head -1)"
	if [ -n "$id" ]; then
		echo "$id"
		return
	fi
	# Otherwise match the rollout file stamped with the process start time.
	# Codex writes it a few seconds after launch, so scan forward from the
	# start second; the earliest hit wins.
	start="$(ps -o lstart= -p "$pid" 2>/dev/null)"
	[ -n "$start" ] || return 0
	epoch="$(date -j -f '%a %b %d %H:%M:%S %Y' "$start" +%s 2>/dev/null)" || return 0
	for off in $(seq 0 15); do
		ts="$(date -r $((epoch + off)) +%Y-%m-%dT%H-%M-%S)"
		for f in "${CODEX_HOME:-$HOME/.codex}"/sessions/*/*/*/rollout-"$ts"-*.jsonl; do
			[ -f "$f" ] || continue
			cwd="$(head -1 "$f" | jq -r '.payload.cwd // empty' 2>/dev/null)"
			[ "$cwd" = "$path" ] || continue
			head -1 "$f" | jq -r '.payload.id // empty' 2>/dev/null
			return
		done
	done
}

pid="$(agent_pid)"
sid=""
[ -n "$pid" ] && case "$engine" in
	claude) sid="$(claude_session "$pid")" ;;
	codex)  sid="$(codex_session "$pid")" ;;
esac

case "$engine" in
claude)
	if [ -n "$sid" ]; then cmd="claude --resume $sid --fork-session"
	else                   cmd="claude --continue --fork-session"; fi ;;
codex)
	if [ -n "$sid" ]; then cmd="codex fork $sid"
	else                   cmd="codex fork --last"; fi ;;
*)
	echo "unknown engine: $engine" >&2; exit 1 ;;
esac

if [ -n "${AGENT_FORK_DRY:-}" ]; then
	echo "$cmd"
	exit 0
fi

# -h side by side, -b before (left), -f full window height: always the far-left column.
tmux split-window -hbf -c "$path" "$cmd"
if [ -n "$sid" ]; then
	tmux display-message "forked $engine ${sid:0:8}"
else
	tmux display-message "no $engine in this pane - forking the latest session for $path"
fi

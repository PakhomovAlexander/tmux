#!/usr/bin/env sh
# Cycle the current window's manual colour tag. prefix+_ forward, prefix+[ back.
#
# The tag is one tmux window option, @wcolour, holding a colour or nothing at
# all. The status format paints the window *name* with it and leaves the agent
# glyph alone, so the two never argue: glyph shape is the engine, glyph colour
# is what the agent is doing, and the name colour is whatever you decide it
# means.
#
# Window options do not survive a server restart — tmux-resurrect saves layout,
# not arbitrary options — so tags last as long as the server does.
set -u

dir="${1:-next}"   # read before set-- overwrites the positional parameters

# The cycle. The first entry is empty: "no tag", which lets the format fall
# through to the colour the tab would have had anyway, and gives you a way back
# out of the cycle rather than only around it.
set -- "" colour245 colour223 colour109 colour142 colour167
count=$#

label() {
	case "$1" in
	"") echo auto ;;
	colour245) echo gray ;;
	colour223) echo white ;;
	colour109) echo blue ;;
	colour142) echo green ;;
	colour167) echo red ;;
	*) echo "$1" ;;
	esac
}

cur="$(tmux show-option -wqv @wcolour)"

# Find where we are. A value that is not in the list (someone set @wcolour by
# hand) counts as position 1, so the next press lands on a known entry.
idx=1
i=1
for c; do
	if [ "$c" = "$cur" ]; then
		idx=$i
		break
	fi
	i=$((i + 1))
done

case "$dir" in
prev) idx=$(((idx + count - 2) % count + 1)) ;;
*) idx=$((idx % count + 1)) ;;
esac
eval "sel=\${$idx}"

if [ -z "$sel" ]; then
	tmux set-option -wu @wcolour
else
	tmux set-option -w @wcolour "$sel"
fi

# -S redraws the status line only. The message is brief on purpose: display-time
# is 4s globally, which is a long time to stare at while tapping through six
# positions.
tmux refresh-client -S
tmux display-message -d 700 "window colour: $(label "$sel")"

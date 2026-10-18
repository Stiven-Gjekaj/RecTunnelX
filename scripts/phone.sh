#!/bin/sh
# Share the phone at "ssh iphone4s" with the other projects that test on it.
# A session holds the phone with a line in /tmp/phone.lock: its name and
# the time. A lock of another session that is less than 10 minutes old
# means that the phone is busy.
# Usage: scripts/phone.sh take | give | check
NAME=RecTunnelX
case "$1" in
take)
    LOCK=$(ssh iphone4s 'cat /tmp/phone.lock 2>/dev/null')
    if [ -n "$LOCK" ]; then
        OWNER=${LOCK% *}
        TIME=${LOCK##* }
        NOW=$(date +%s)
        if [ "$OWNER" != "$NAME" ] && [ $((NOW - TIME)) -lt 600 ]; then
            echo "phone: $OWNER uses the phone; try again later" >&2
            exit 1
        fi
    fi
    ssh iphone4s "echo '$NAME $(date +%s)' > /tmp/phone.lock"
    ;;
give)
    ssh iphone4s "grep -q '^$NAME ' /tmp/phone.lock 2>/dev/null && rm -f /tmp/phone.lock; true"
    ;;
check)
    ssh iphone4s 'cat /tmp/phone.lock 2>/dev/null || echo free'
    ;;
*)
    echo "usage: scripts/phone.sh take | give | check" >&2
    exit 2
    ;;
esac

#!/bin/sh
# Share the phone at "ssh iphone4s" with the other projects that test on it.
# A session holds the phone with a line in /tmp/phone.lock: its name and
# the time. A lock of another session that is less than 10 minutes old
# means that the phone is busy.
# Some projects do not use the lock. An ssh or scp connection to the phone
# from another process on this Mac also means that the phone is busy.
# Usage: scripts/phone.sh take | give | check | wait [SECONDS] | run COMMAND...
#   take  holds the phone, or fails if it is busy.
#   wait  tries take every 15 seconds until it works (default 1800 seconds).
#   run   waits, holds the phone, runs COMMAND, then gives the phone back.
NAME=RecTunnelX

# Print the other ssh and scp processes that talk to the phone.
others() {
    # Look only at the program name of each process, not at shell command lines.
    ps -axo pid=,comm= | awk '$2 ~ /(^|\/)(ssh|scp|sftp)$/ { print $1 }' | while read -r PID; do
        ps -o args= -p "$PID" | grep 'iphone4s' | sed "s/^/$PID /"
    done
}

take() {
    BUSY=$(others)
    if [ -n "$BUSY" ]; then
        echo "phone: another process uses the phone:" >&2
        echo "$BUSY" >&2
        return 1
    fi
    LOCK=$(ssh iphone4s 'cat /tmp/phone.lock 2>/dev/null')
    if [ -n "$LOCK" ]; then
        OWNER=${LOCK% *}
        TIME=${LOCK##* }
        NOW=$(date +%s)
        if [ "$OWNER" != "$NAME" ] && [ $((NOW - TIME)) -lt 600 ]; then
            echo "phone: $OWNER uses the phone; try again later" >&2
            return 1
        fi
    fi
    ssh iphone4s "echo '$NAME $(date +%s)' > /tmp/phone.lock"
}

give() {
    ssh iphone4s "grep -q '^$NAME ' /tmp/phone.lock 2>/dev/null && rm -f /tmp/phone.lock; true"
}

wait_take() {
    LIMIT=${1:-1800}
    START=$(date +%s)
    until take 2>/dev/null; do
        if [ $(($(date +%s) - START)) -ge "$LIMIT" ]; then
            echo "phone: still busy after $LIMIT seconds" >&2
            return 1
        fi
        sleep 15
    done
}

case "$1" in
take) take ;;
give) give ;;
check)
    others
    ssh iphone4s 'cat /tmp/phone.lock 2>/dev/null || echo free'
    ;;
wait)
    wait_take "$2"
    ;;
run)
    shift
    wait_take || exit 1
    "$@"
    STATUS=$?
    give
    exit $STATUS
    ;;
*)
    echo "usage: scripts/phone.sh take | give | check | wait [SECONDS] | run COMMAND..." >&2
    exit 2
    ;;
esac

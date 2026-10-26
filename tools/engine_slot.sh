#!/bin/bash
# Run one heavy Summer/Godot session (authority + clients, renders, full-course
# runs) under a shared machine-wide slot, so parallel agents do not overload
# the machine. Usage: tools/engine_slot.sh <command> [args...]
# FRIENDS_SLOTS (default 2) sets how many shared slots a caller may use.
# FRIENDS_PRIORITY=1 also lets the caller take one reserved slot that normal
# callers never use (for the work you are waiting on right now).
# Light checks (--check-only, small headless unit fixtures) do not need a slot.
set -u
slots=${FRIENDS_SLOTS:-2}
names=()
if [ "${FRIENDS_PRIORITY:-0}" = 1 ]; then names+=(priority); fi
for ((i = 0; i < slots; i++)); do names+=("$i"); done
dir=${XDG_STATE_HOME:-$HOME/.local/state}/friends-slots
mkdir -p "$dir"
waited=0
while :; do
  for name in "${names[@]}"; do
    # lockf -s -t 0: fail silently at once if the slot is held; -k keeps the lock file.
    lockf -s -k -t 0 "$dir/slot$name.lock" "$@"
    status=$?
    # lockf exits 75 (EX_TEMPFAIL) when it could not take the lock.
    if [ $status -ne 75 ]; then
      exit $status
    fi
  done
  if [ $((waited % 60)) -eq 0 ]; then
    echo "engine_slot: all $slots slots busy, waiting (${waited}s)" >&2
  fi
  sleep 5
  waited=$((waited + 5))
done

#!/bin/sh
# The machine's half of `apk`: reads words from a named pipe and runs one of two fixed jobs, each
# under a lock and logged, writing each job's state to a file the container reads back. Installed
# by infra's `mise run node` as /usr/local/libexec/apk-door and kept up by /etc/init.d/apk-door.
# See platform's spec/architecture/packages.md, "`apk` reaches the machine through a named pipe".
# The environment moves the paths for a test; the defaults are the machine's.
set -u
umask 077

DIR=${APK_DOOR_DIR:-/var/lib/apk-door}
LOCK=${APK_DOOR_LOCK:-/run/apk-door.lock}
APK=${APK_DOOR_APK:-apk}
MODULES=${APK_DOOR_MODULES:-/lib/modules}
# Seconds a job waits for apk's own lock, held by somebody running apk by hand.
WAIT=600
TAG=apk-door

say() {
	logger -t "$TAG" -- "$*"
}

# A field of a job's state file, empty when the file or the field is missing.
field() {
	sed -n "s/^$2=//p" "$DIR/$1.state" 2>/dev/null
}

# Writes a job's whole state beside the file and renames it over, so it is never read half-written.
# Arguments: job, seq, running, started_at, finished_at, exit_status, result, reboot_required.
record() {
	printf 'seq=%s\nrunning=%s\nstarted_at=%s\nfinished_at=%s\nexit_status=%s\nresult=%s\nreboot_required=%s\n' \
		"$2" "$3" "$4" "$5" "$6" "$7" "$8" >"$DIR/.$1.state.tmp" &&
		mv -f "$DIR/.$1.state.tmp" "$DIR/$1.state"
}

# Alpine keeps one kernel package and replaces its modules on upgrade, so the running kernel's
# modules gone means a newer one waits for a reboot.
reboot_required() {
	if [ -d "$MODULES/$(uname -r)" ]; then echo 0; else echo 1; fi
}

# Runs its arguments with their output in the system log, and returns their exit status.
logged() {
	(
		set -o pipefail
		"$@" 2>&1 | logger -t "$TAG"
	)
}

update() {
	logged "$APK" --wait "$WAIT" update
}

upgrade() {
	logged "$APK" --wait "$WAIT" update && logged "$APK" --wait "$WAIT" upgrade --available
}

run() {
	job=$1
	seq=$(field "$job" seq)
	seq=$((${seq:-0} + 1))
	started=$(date +%s)
	record "$job" "$seq" 1 "$started" "" "" "" "$(reboot_required)"
	say "$job started"

	# The pipe is the door's own; a job holds the lock and nothing else.
	flock 9
	"$job" 3<&-
	status=$?
	flock -u 9

	if [ "$status" -eq 0 ]; then result=success; else result=failed; fi
	record "$job" "$seq" 0 "$started" "$(date +%s)" "$status" "$result" "$(reboot_required)"
	say "$job ended: $result, exit $status"
}

# A state still running when the door starts was cut short: nothing is left to write how it ended.
interrupted() {
	[ "$(field "$1" running)" = 1 ] || return 0
	record "$1" "$(field "$1" seq)" 0 "$(field "$1" started_at)" "$(date +%s)" "" interrupted \
		"$(reboot_required)"
	say "$1 was interrupted"
}

exec 9>"$LOCK"
# A job a stopped door left behind still holds the lock; it is over once the lock comes free.
flock 9
interrupted update
interrupted upgrade
flock -u 9

# Opened for reading and writing, so the pipe never reads as closed between two writers.
exec 3<>"$DIR/door"
say "reading $DIR/door"
while read -r word <&3; do
	case $word in
	update | upgrade) run "$word" ;;
	*) say "dropped a word that names no job" ;;
	esac
done

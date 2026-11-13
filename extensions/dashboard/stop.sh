#!/bin/sh
# Stops the dashboard and hands the screen back to the Kindle home screen.
# "stop.sh nohome" (used by start.sh) cleans up without opening the home screen.
DIR=${DASH_DIR:-/mnt/us/extensions/dashboard}
rm -f "$DIR/tap" "$DIR/tap.read"
# Kill every running copy of loop.sh (and its touch watcher), not just the one in the pid
# file: an older copy left running would keep drawing over the screen in its own format.
for p in /proc/[0-9]*; do
    [ "${p#/proc/}" = "$$" ] && continue
    grep -q 'dashboard/loop.sh' "$p/cmdline" 2>/dev/null && kill "${p#/proc/}"
done
rm -f "$DIR/pid" "$DIR/touch.pid"
killall -CONT cvm 2>/dev/null
lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
# The dashboard turns Wi-Fi off between refreshes and sets wake alarms: undo both.
lipc-set-prop com.lab126.cmd wirelessEnable 1
for a in /sys/class/rtc/rtc*/wakealarm; do echo 0 > "$a"; done 2>/dev/null
lipc-set-prop com.lab126.powerd preventScreenSaver 0
[ "$1" = nohome ] || lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home

#!/bin/sh
# Starts the dashboard. It runs from a copy in /var/tmp (the Kindle's internal memory), so
# plugging the Kindle into a computer, which takes /mnt/us away from the Kindle, can't
# pull the scripts out from under it. The log is kept with the copy and copied back to
# /mnt/us/extensions/dashboard/dashboard.log whenever the Kindle isn't a USB drive.
SRC=/mnt/us/extensions/dashboard
RUN=/var/tmp/dashboard
LOG=$RUN/dashboard.log
DASH_DIR=$SRC sh "$SRC/stop.sh" nohome
# Fresh copy of the scripts, icons and last run's data (weather, snow, surf, tide).
rm -rf "$RUN" && mkdir -p "$RUN" && cp -r "$SRC"/* "$RUN"/
rm -f "$LOG"
{
    echo "$(date) start.sh"
    echo "--- cgroups before"; cat /proc/$$/cgroup
} > "$LOG" 2>&1
# Leave the library's cgroups: the Kindle can kill everything in an app's cgroup when the
# app closes, which would stop the dashboard with the Kindle UI still paused.
awk '$3 == "cgroup" { print $2 }' /proc/mounts | while read -r m; do
    [ -w "$m/tasks" ] && echo $$ > "$m/tasks" 2>/dev/null
done
{ echo "--- cgroups after"; cat /proc/$$/cgroup; } >> "$LOG" 2>&1
cp -f "$LOG" "$SRC/dashboard.log" 2>/dev/null
export DASH_DIR=$RUN DASH_SRC=$SRC
if command -v setsid >/dev/null 2>&1; then
    setsid nohup sh "$RUN/loop.sh" >> "$LOG" 2>&1 &
else
    nohup sh "$RUN/loop.sh" >> "$LOG" 2>&1 &
fi

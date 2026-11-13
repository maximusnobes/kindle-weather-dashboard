#!/bin/sh
# Name: Dashboard Probe
# Author: Max
# DontUseFBInk
# Records what this Kindle has, so the weather dashboard can be adapted to it.
# Writes /mnt/us/dashboard-probe.txt (the top folder of the Kindle over USB).
# Takes about 30 seconds and includes a 12-second touch test at the end.

OUT=/mnt/us/dashboard-probe.txt
URL="api.open-meteo.com/v1/forecast?latitude=37.49&longitude=-122.24&current=temperature_2m&format=csv"

eips 0 38 "Probe running (about 30 s). Don't tap yet." >/dev/null 2>&1
{
    echo "--- time"; date; date -u
    echo "--- system"; uname -a; id; cat /etc/prettyversion.txt 2>/dev/null
    echo "--- cpu"; grep -E '^(Hardware|Features|model name)' /proc/cpuinfo
    echo "--- loaders"; ls -l /lib/ld-linux* 2>&1
    echo "--- tools"
    for c in curl wget eips fbink openssl awk od dd nohup killall mntroot lipc-set-prop lipc-get-prop; do
        printf '%s: ' "$c"; command -v "$c" || echo missing
    done
    echo "--- fbink copies on device"
    find /mnt/us /usr/bin /usr/local/bin /var/local -name 'fbink*' -type f 2>/dev/null
    for f in $(find /mnt/us /usr/bin /usr/local/bin /var/local -name 'fbink' -type f 2>/dev/null); do
        echo "## $f"; "$f" -e 2>&1 | head -20
    done
    echo "--- curl"; curl --version 2>&1 | head -3
    echo "--- eips"; eips -i 2>&1 | head -40
    echo "--- wifi"; lipc-get-prop com.lab126.wifid cmState; lipc-get-prop com.lab126.cmd wirelessEnable
    echo "--- curl http";  curl -s -m 10 "http://$URL" 2>&1 | head -5
    echo "--- curl https"; curl -s -m 10 "https://$URL" 2>&1 | head -5
    echo "--- curl https marine"; curl -s -m 10 "https://marine-api.open-meteo.com/v1/marine?latitude=37.59&longitude=-122.51&current=wave_height&format=csv" 2>&1 | head -5
    echo "--- curl https noaa"; curl -s -m 10 -o /dev/null -w '%{http_code}\n' "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&station=9414290&datum=MLLW&time_zone=lst_ldt&units=english&interval=hilo&format=csv&date=today" 2>&1
    echo "--- awk"; echo 'a,bc' | awk -F, '{ s = sprintf("[%2d]", 4); print $2, length($2), s }'
    echo "--- od"; printf 'ABCDEFGHIJKLMNOP' | od -An -t d2
    echo "--- upstart"; ls /etc/upstart 2>&1 | head -40
    echo "--- input"; cat /proc/bus/input/devices
    echo "--- ui process"; pidof cvm || ps | grep -i cvm
    echo "--- rtc"; ls /sys/class/rtc/ 2>&1; cat /sys/power/state 2>&1
    echo "--- fonts"; ls /usr/java/lib/fonts 2>&1
    echo "--- koreader"; ls /mnt/us/koreader 2>&1 | head -40
} > "$OUT" 2>&1

# Touch test: the Kindle UI is paused for 12 seconds so taps reach only this script.
echo "--- pause ui" >> "$OUT"
killall -STOP cvm >> "$OUT" 2>&1
eips -c >/dev/null 2>&1
eips 0 10 "TOUCH TEST (12 seconds)" >/dev/null 2>&1
eips 0 12 "1. Tap the TOP-LEFT corner" >/dev/null 2>&1
eips 0 13 "2. Tap the BOTTOM-RIGHT corner" >/dev/null 2>&1
eips 0 14 "3. Tap the middle of the BOTTOM edge" >/dev/null 2>&1
pids=""
for e in /dev/input/event*; do
    cat "$e" > "/mnt/us/dashboard-touch-${e##*/}.bin" &
    pids="$pids $!"
done
sleep 12
kill $pids 2>/dev/null
killall -CONT cvm >> "$OUT" 2>&1
echo "--- touch capture sizes" >> "$OUT"
ls -l /mnt/us/dashboard-touch-*.bin >> "$OUT" 2>&1
for f in /mnt/us/dashboard-touch-*.bin; do
    echo "## $f" >> "$OUT"
    od -An -t d2 "$f" 2>/dev/null | head -60 >> "$OUT"
done
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
sleep 3
eips 0 38 "Probe done. Plug the Kindle into the Mac." >/dev/null 2>&1

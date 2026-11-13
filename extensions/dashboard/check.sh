#!/bin/sh
# Mac-side check of render.awk and extras.awk against fixed data: sh extensions/dashboard/check.sh
cd "$(dirname "$0")" || exit 1
fixture() {  # Redwood City, °F / mph / inches, local time UTC-8, current time 09:45 on Wed 11 Nov 2026
    printf 'latitude,longitude,elevation,utc_offset_seconds,timezone,timezone_abbreviation\r\n37.49,-122.24,7.0,-28800,America/Los_Angeles,GMT-8\r\n\r\n'
    printf 'time,temperature_2m (°F),weather_code (wmo code),relative_humidity_2m (%%),is_day (),apparent_temperature (°F),wind_speed_10m (mp/h)\n2026-11-11T09:45,61.2,0,54,1,59.1,7.3\n\n'
    printf 'time,temperature_2m (°F),weather_code (wmo code),precipitation_probability (%%),is_day ()\n'
    awk 'BEGIN { for (h = 0; h < 48; h++) printf "2026-11-%02dT%02d:00,-3.6,999,,%d\n", 11 + int(h / 24), h % 24, (h % 24 >= 7 && h % 24 < 17) }'
    printf '\ntime,weather_code (wmo code),temperature_2m_max (°F),temperature_2m_min (°F),precipitation_probability_max (%%),precipitation_sum (inch),sunrise (iso8601),sunset (iso8601)\n'
    printf '2026-11-11,0,66.0,47.0,5,0.0,2026-11-11T06:47,2026-11-11T17:01\n2026-11-12,3,63.0,49.0,0,0.0,,\n'
    printf '2026-11-13,63,59.0,50.0,62,0.21,,\n2026-11-14,61,57.0,48.0,30,0.02,,\n'
    awk 'BEGIN { for (d = 15; d <= 20; d++) printf "2026-11-%02d,0,64.0,45.0,0,0.0,,\n", d }'
}
extra() {
    printf 'snow_new,6\nsnow_depth,41\nsnow_temp,24\nwave,4.1\nperiod,12\ndir,WNW\n'
    printf 'tide,2026-11-11 04:39,L\ntide,2026-11-11 10:37,H\ntide,2026-11-11 18:09,L\ntide,2026-11-12 01:11,H\n'
    printf 'holiday,Example Day, with a comma\n'
}
X=$(mktemp); extra > "$X"; E=$(mktemp); : > "$E"
render() { awk -v place="Redwood City" -v batt=87 -v paul=2026-06-21 "$@"; }  # call as: render -v var=... -f render.awk files
out=$(fixture | render -v stale=0 -v utc=1704 -v clock=1745 -f render.awk - "$X")
fail=0
expect() { printf '%s\n' "$1" | grep -qF -- "$2" || { echo "missing: $2"; fail=1; }; }
expect "$out" "T|B|22|20|300|16||Redwood City"
expect "$out" "||87%"
expect "$out" "|g|Updated 9:04 am"           # device UTC 17:04 - 8 h, 12-hour clock
awake=$(fixture | render -v utc=1704 -v awake=1 -f render.awk - "$X")
expect "$awake" "R|292|12|192|30|B"          # awake badge replaces the update time
expect "$awake" "|ci|Awake · hold to exit"
case "$awake" in *"Updated "*) echo "awake screen still shows the update time"; fail=1 ;; esac
expect "$out" "||61°"
expect "$out" "|cg|Feels like 59° · Humidity 54%"
expect "$out" "|g|5% rain · 7 mph"
expect "$out" "|cg|10am"                    # first hourly slot after 09:45
expect "$out" "|cg|1pm"
# Bottom card
expect "$out" "R|20|653|560|1|GRAYA"        # rule between the two rows of tiles
expect "$out" "|cg|Days since Paul left"
expect "$out" "|c|143"                       # 21 June to 11 November
expect "$out" "|c|Example Day, with a comma"
expect "$out" "|c|6:47 am"
expect "$out" "|c|5:01 pm"
expect "$out" "|c|6\" new"
expect "$out" "|cg|41\" base · 24°"
expect "$out" "|c|4.1 ft"
expect "$out" "|cg|12s WNW"
expect "$out" "|cg|High 10:37 am"            # next tide after 09:45
late=$(fixture | render -v utc=1704 -v clock=0300 -f render.awk - "$X")  # 19:00 local
expect "$late" "|cg|High 1:11 am"            # tomorrow's first tide
bare=$(fixture | render -v utc=1704 -f render.awk - "$E")
expect "$bare" "|cg|Just a regular Wednesday"
expect "$bare" "|cg|No data yet"
expect "$(fixture | awk -v place=X -v paul=CHANGEME -f render.awk - "$E")" "Set PAUL_DATE"
case "$out" in *"km/h"*|*" mm"*) echo "metric units left over"; fail=1 ;; esac
# 10-day tab
week=$(fixture | render -v stale=0 -v utc=1704 -v tab=10d -f render.awk - "$X")
expect "$week" "T|B|22|300|20|60|c|10 days"
expect "$week" "|g|dry"
expect "$week" "|g|0.2 in"
expect "$week" "|g|<0.1 in"
[ "$(printf '%s\n' "$week" | grep -c '^I|dots-')" = 10 ] || { echo "10d tab should have 10 rows"; fail=1; }
empty=$(printf "" | render -f render.awk)
expect "$empty" "||Redwood City"            # the place name is the way Home
expect "$empty" "No weather data yet"

# extras.awk on the three downloads
tide=$(printf 'Date Time, Prediction, Type\n2026-11-11 00:23,4.105,H\n2026-11-11 04:39,2.924,L\n' | awk -v kind=tide -f extras.awk)
expect "$tide" "tide,2026-11-11 00:23,H"
expect "$tide" "tide,2026-11-11 04:39,L"
snow=$(printf 'latitude,longitude,elevation,utc_offset_seconds,timezone,timezone_abbreviation\n38.68,-120.07,2600.0,-28800,America/Los_Angeles,GMT-8\n\ntime,temperature_2m (°F),snow_depth (m)\n2026-11-11T09:45,23.6,1.04\n\ntime,snowfall (inch)\n2026-11-10T10:00,1.5\n2026-11-11T09:00,4.4\n2026-11-11T10:00,9.0\n' | awk -v kind=snow -f extras.awk)
expect "$snow" "snow_temp,24"
expect "$snow" "snow_depth,41"              # 1.04 m
expect "$snow" "snow_new,6"                 # 10:00 is after 09:45, so not counted
surf=$(printf 'latitude,longitude,elevation,utc_offset_seconds,timezone,timezone_abbreviation\n37.6,-122.6,0.0,-28800,America/Los_Angeles,GMT-8\n\ntime,wave_height (ft),swell_wave_height (ft),swell_wave_period (s),swell_wave_direction (°)\n2026-11-11T09:45,4.13,3.5,12.3,290\n' | awk -v kind=surf -f extras.awk)
expect "$surf" "wave,4.1"
expect "$surf" "period,12"
expect "$surf" "dir,WNW"
expect "$(printf 'latitude\n0\n\ntime,wave_height (m)\n2026-11-11T09:45,2.02\n' | awk -v kind=surf -f extras.awk)" "wave,6.6"

# Battery scheduling from loop.sh: hourly refreshes, none at night.
eval "$(sed -n '/^utc_offset()/p;/^next_refresh()/,/^}/p' loop.sh)"
DIR=$(mktemp -d); fixture > "$DIR/weather.csv"  # UTC-8
INTERVAL=3600; NIGHT="1 7"
same() { [ "$1" = "$2" ] || { echo "$3: got $1, want $2"; fail=1; }; }
same "$(next_refresh 1794419100)" 1794422700 "09:45 local -> 10:45"
same "$(next_refresh 1794385800)" 1794409200 "00:30 local -> 07:00"
rm -rf "$DIR" "$X" "$E"
# Everything must fit on the 600x800 screen.
printf '%s\n%s\n' "$out" "$week" | awk -F'|' '
    $1 == "R" { x = $2; y = $3; r = $2 + $4; b = $3 + $5 }
    $1 == "I" { n = split($2, p, "-"); w = h = p[n] + 0; if ($2 ~ /^dots/) { w = 110; h = 14 }
                x = $3; y = $4; r = $3 + w; b = $4 + h }
    $1 == "T" { x = $4; y = $6; r = 600 - $5; b = $6 + $3 * 1.2 }
    x < 0 || y < 0 || r > 600 || b > 800 { print "off screen: " $0; bad = 1 }
    END { exit bad }' || fail=1
[ $fail = 0 ] && echo ok || exit 1

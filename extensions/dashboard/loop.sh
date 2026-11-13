#!/bin/sh
# Fetches the weather over Wi-Fi and draws the dashboard with FBInk, forever.
# Adapted from re-kindle (abdenourgnx) for a Kindle Basic 3 (10th gen) on firmware 5.18,
# jailbroken with SpiderCat: hard-float FBInk from KOReader, touchscreen on event2,
# Redwood City in °F / mph / inches, and a six-tile bottom card instead of prayer times.
# Pauses the Kindle's own UI (cvm) and its top/bottom pop-up bars (pillow) so nothing
# draws over it; tapping the place name at the top left runs stop.sh, which brings them
# back and goes to the home screen.
# To save battery, between refreshes Wi-Fi is off and the Kindle is suspended (the e-ink
# keeps showing the dashboard); an RTC alarm wakes it for the next refresh. Taps don't
# work while it sleeps: the power button wakes it for IDLE seconds of tabs/Home.

# ---------------------------------------------------------------- Tuning knobs
PLACE="Redwood City"
LAT=37.4852
LON=-122.2364
TIMEZONE="America%2FLos_Angeles"
PAUL_DATE="2026-01-01"      # CHANGE ME: the day Paul left (YYYY-MM-DD). Day 0 is that day.
INTERVAL=3600               # seconds between weather refreshes (forecasts update about hourly)
EXTRA_EVERY=10800           # seconds between Kirkwood / surf / tide refreshes (3 hours)
NIGHT="1 7"                 # local hours with no refreshes: from 01:00 it sleeps until 07:00
                            # (empty = refresh all night)
IDLE=20                     # seconds after the last touch (or a power-button wake) before going
                            # back to Today and to sleep
WIFI_WAIT=60                # longest wait for Wi-Fi to bring data after turning it on
SLEEP=1                     # 1 = suspend between refreshes, 0 = stay awake (Wi-Fi still goes off)
TOUCH=/dev/input/event2     # touchscreen device (cyttsp5_mt on this Kindle)
# Touch, while awake (press the power button to wake it): tap the right half or swipe left
# for 10 days, tap the left half or swipe right for Today, hold a finger down to exit.
HOLD=3                      # seconds a finger must stay down to exit to the Kindle home screen
SWIPE=100                   # pixels sideways that make a touch a swipe instead of a tap
EDGE_TOP=130                # taps above this y or below EDGE_BOTTOM are ignored: the Kindle's own
EDGE_BOTTOM=690             # menus live at the top and bottom edges, so keep taps in the middle
FONT=""                     # leave empty to pick a Kindle system font automatically
FONT_BOLD=""
GREY=BLACK                  # colour of secondary text: BLACK, or a grey from GRAY1 (darkest) to GRAYE

# Bottom-card sources
SNOW_LAT=38.6849            # Kirkwood
SNOW_LON=-120.0654
SNOW_ELEV=2600              # metres (Kirkwood runs from about 2,380 m at the base to 3,010 m)
SURF_LAT=37.595             # Linda Mar, Pacifica
SURF_LON=-122.505
TIDE_STATION=9414131        # NOAA Pillar Point Harbor (Half Moon Bay); 9414290 = San Francisco

DIR=${DASH_DIR:-/mnt/us/extensions/dashboard}  # overridable for a Mac rehearsal
POWER_STATE=${POWER_STATE:-/sys/power/state}
RTC=${RTC:-/sys/class/rtc}
# This Kindle runs hard-float firmware; the FBInk shipped with KOReader is built for it.
FBINK=/mnt/us/koreader/fbink
[ -x "$FBINK" ] || FBINK="$DIR/bin/fbink"
U="temperature_unit=fahrenheit&wind_speed_unit=mph&precipitation_unit=inch"
URL="http://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&timezone=$TIMEZONE&$U&forecast_days=10&format=csv&current=temperature_2m,weather_code,relative_humidity_2m,is_day,apparent_temperature,wind_speed_10m&hourly=temperature_2m,weather_code,precipitation_probability,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset"
SNOW_URL="https://api.open-meteo.com/v1/forecast?latitude=$SNOW_LAT&longitude=$SNOW_LON&elevation=$SNOW_ELEV&timezone=$TIMEZONE&$U&format=csv&current=temperature_2m,snow_depth&hourly=snowfall&past_hours=24&forecast_hours=1"
SURF_URL="https://marine-api.open-meteo.com/v1/marine?latitude=$SURF_LAT&longitude=$SURF_LON&timezone=$TIMEZONE&length_unit=imperial&format=csv&current=wave_height,swell_wave_height,swell_wave_period,swell_wave_direction"

fetch() {
    curl -s -f -m 15 -o "$1" "$URL" 2>/dev/null || wget -q -T 15 -O "$1" "$URL"
}

# One bottom-card source: download $2 into $1.csv, turn it into key,value lines with
# extras.awk (kind $1) and keep them in $1.txt. A failed download keeps the old $1.txt.
fetch_part() {
    curl -s -S -f -m 20 -o "$DIR/$1.csv" "$2" || { echo "$(date) $1: fetch failed"; return 1; }
    awk -v kind="$1" -f "$DIR/extras.awk" "$DIR/$1.csv" > "$DIR/$1.new"
    if [ -s "$DIR/$1.new" ]; then mv -f "$DIR/$1.new" "$DIR/$1.txt"; else echo "$(date) $1: unexpected reply"; return 1; fi
}

# Kirkwood, surf and tides, every EXTRA_EVERY seconds while Wi-Fi is on anyway.
# $1 = local date (YYYY-MM-DD), from the weather data (the Kindle's clock is UTC).
fetch_extras() {
    fetch_part snow "$SNOW_URL"
    fetch_part surf "$SURF_URL"
    fetch_part tide "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?product=predictions&station=$TIDE_STATION&datum=MLLW&time_zone=lst_ldt&units=english&interval=hilo&format=csv&begin_date=$(echo "$1" | tr -d -)&range=48"
}

# The bottom card's inputs in one file for render.awk: the downloaded parts plus today's
# fun holiday from holidays.txt ("MM-DD,Name" lines, first match wins). $1 = local date.
build_extra() {
    md=$(echo "$1" | cut -c6-10)
    {
        cat "$DIR/snow.txt" "$DIR/surf.txt" "$DIR/tide.txt" 2>/dev/null
        h=$(grep "^$md," "$DIR/holidays.txt" 2>/dev/null | head -1 | cut -d, -f2-)
        [ -n "$h" ] && echo "holiday,$h"
    } > "$DIR/extra.txt"
}

pick_font() {  # first /usr/java/lib/fonts TTF matching one of the patterns, in order
    for want in "$@"; do
        f=$(ls /usr/java/lib/fonts 2>/dev/null | grep -i '\.ttf$' | grep -vi italic | grep -i -e "$want" | head -1)
        [ -n "$f" ] && { echo "/usr/java/lib/fonts/$f"; return; }
    done
}

# Runs render.awk's commands (see the top of render.awk) through FBInk.
# Every text argument goes after "--" so a leading "-" (like -4°) isn't read as an option.
draw_fbink() {
    "$FBINK" -q -b -k
    while IFS='|' read -r kind a b c d e f text; do
        case "$kind" in
        R)  case "$e" in B) bg=BLACK ;; W) bg=WHITE ;; *) bg=$e ;; esac
            "$FBINK" -q -b -B "$bg" -k "top=$b,left=$a,width=$c,height=$d" ;;
        # Icons go through the Kindle's own eips, as in the original project.
        I)  eips -g "$DIR/icons/$a.png" -x "$b" -y "$c" >/dev/null ;;
        T)  font=$FONT; [ "$a" = B ] && font=$FONT_BOLD
            set -- -q -b -O
            case "$f" in *c*) set -- "$@" -m ;; esac
            case "$f" in *i*) set -- "$@" -h ;; esac
            case "$f" in *g*) set -- "$@" -C "$GREY" ;; esac
            "$FBINK" "$@" -t "regular=$font,px=$b,top=$e,left=$c,right=$d" -- "$text" ;;
        esac
    done
    # Full flashing refresh, and wait (-w) until the panel has finished it: suspending
    # mid-update would leave a half-drawn screen until the next refresh.
    "$FBINK" -q -f -s -w
}

draw_eips() {  # fallback when FBInk can't run: plain text
    eips -c
    eips 1 2 "FBInk failed to start" >/dev/null
    eips 1 4 "$(sed -n 5p "$DIR/weather.csv" 2>/dev/null | cut -d, -f1,2)" >/dev/null
    eips 1 23 "Tap the top-left corner for the Kindle Home" >/dev/null
}

# Reads raw touch events (16 bytes each on this 32-bit Kindle). Fields after od:
# sec sec usec usec type code value value. Finger down/up is BTN_TOUCH (type 1, code 330);
# positions are ABS_MT_POSITION_X/Y (type 3, codes 53/54) in screen pixels. Each touch is
# judged when the finger lifts: held -> stop.sh (Home); swipe or tap -> writes the wanted
# tab to $DIR/tap for the main loop, which does all the drawing ("-" just keeps it awake).
# The device stays open on fd 3: evdev only queues events for an open reader.
watch_touch() {
    x=-1; y=-1; sx=-1; sy=-1; t0=0
    while :; do
        set -- $(dd bs=16 count=1 2>/dev/null <&3 | od -An -t d2)
        [ $# -ge 7 ] || { sleep 1; continue; }
        if [ "$5" = 3 ]; then
            case "$6" in
            53) x=$7; [ "$sx" -ge 0 ] || sx=$7 ;;
            54) y=$7; [ "$sy" -ge 0 ] || sy=$7 ;;
            esac
        elif [ "$5" = 1 ] && [ "$6" = 330 ]; then
            if [ "$7" = 1 ]; then sx=-1; sy=-1; t0=$(date +%s); continue; fi
            [ "$sx" -ge 0 ] && [ "$sy" -ge 0 ] || continue
            held=$(($(date +%s) - t0)); dx=$((x - sx)); adx=${dx#-}
            t=-
            if [ "$held" -ge "$HOLD" ] && [ "$adx" -lt "$SWIPE" ]; then
                echo "$(date) held $held s: exiting"
                sh "$DIR/stop.sh"
                exit 0
            elif [ "$dx" -le "-$SWIPE" ]; then t=10d
            elif [ "$dx" -ge "$SWIPE" ]; then t=today
            elif [ "$sy" -ge "$EDGE_TOP" ] && [ "$sy" -le "$EDGE_BOTTOM" ]; then
                if [ "$sx" -lt 300 ]; then t=today; else t=10d; fi
            fi
            echo "$(date) touch x=$sx->$x y=$sy dx=$dx held=$held -> $t"
            echo "$t" > "$DIR/tap"
        fi
    done
}

echo $$ > "$DIR/pid"
# If this script is stopped by anything other than stop.sh, hand the Kindle back instead
# of leaving its UI paused (which looks like a frozen Kindle).
cleanup() {
    echo "$(date) stopped by signal $1: giving the screen back to the Kindle"
    [ -f "$DIR/touch.pid" ] && kill "$(cat "$DIR/touch.pid")" 2>/dev/null
    killall -CONT cvm 2>/dev/null
    lipc-set-prop com.lab126.pillow disableEnablePillow enable 2>/dev/null
    lipc-set-prop com.lab126.cmd wirelessEnable 1 2>/dev/null
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
    for a in "$RTC"/rtc*/wakealarm; do echo 0 > "$a"; done 2>/dev/null
    save_log
    exit 1
}
trap 'cleanup TERM' TERM
trap 'cleanup HUP' HUP
trap 'cleanup INT' INT
echo "$(date) starting, fbink $FBINK"
[ -n "$FONT" ] || FONT=$(pick_font 'ember.*regular' 'helvetica.*55' 'helvetica.*roman' 'futura.*book' 'futura.*medium' 'caecilia.*55' 'caecilia.*roman' '.')
[ -n "$FONT_BOLD" ] || FONT_BOLD=$(pick_font 'ember.*bold' 'helvetica.*75' 'helvetica.*bold' 'futura.*bold' 'caecilia.*75' 'caecilia.*bold')
[ -n "$FONT_BOLD" ] || FONT_BOLD=$FONT
echo "fonts: $FONT / $FONT_BOLD"
if "$FBINK" -e > /dev/null 2>&1 && [ -n "$FONT" ]; then draw=draw_fbink; else draw=draw_eips; echo "fbink or fonts unavailable, using eips"; fi

# Let the library close cleanly before the UI is paused.
sleep 5
# Only pause the Kindle UI when the Home button can work; otherwise there'd be no way back.
# (A failed "exec 3<" would end this shell, so check the device first.)
if [ -c "$TOUCH" ] && [ -r "$TOUCH" ] && exec 3< "$TOUCH"; then
    # The top/bottom pop-up bars (quick settings) are drawn by pillow, not cvm: switch
    # them off too, or a tap near the edges opens them over the dashboard.
    lipc-set-prop com.lab126.pillow disableEnablePillow disable 2>/dev/null
    killall -STOP cvm 2>/dev/null
    watch_touch &
    echo $! > "$DIR/touch.pid"
else
    echo "$(date) can't open $TOUCH: Kindle UI left running, no Home button"
fi

# Plugged into a computer or charger: never suspend then (suspending drops the USB
# connection), and leave /mnt/us alone while the computer has it as a drive.
drive_mode() { [ "$(lipc-get-prop com.lab126.volumd driveModeState 2>/dev/null)" = 1 ]; }
plugged() { drive_mode || [ "$(lipc-get-prop com.lab126.powerd isCharging 2>/dev/null)" = 1 ]; }
# The log lives with the running copy; a copy goes to the Kindle drive when it's safe.
save_log() { [ -n "$DASH_SRC" ] && ! drive_mode && cp -f "$DIR/dashboard.log" "$DASH_SRC/dashboard.log" 2>/dev/null; }

wifi() { lipc-set-prop com.lab126.cmd wirelessEnable "$1" 2>/dev/null; }

# Wi-Fi on, fetch as soon as it works (or give up after WIFI_WAIT), Wi-Fi off.
refresh() {
    wifi 1
    t0=$(date +%s); stale=1
    while :; do
        if fetch "$DIR/weather.new" && grep -q '^time' "$DIR/weather.new"; then
            mv "$DIR/weather.new" "$DIR/weather.csv"
            stale=0; good_utc=$(date -u +%H%M)
            day=$(sed -n 5p "$DIR/weather.csv" | cut -c1-10)
            if [ "$(date +%s)" -ge "$extra_due" ]; then
                fetch_extras "$day"
                extra_due=$(($(date +%s) + EXTRA_EVERY))
            fi
            break
        fi
        [ $(($(date +%s) - t0)) -ge "$WIFI_WAIT" ] && { echo "$(date) fetch failed for $WIFI_WAIT s"; break; }
        sleep 5
    done
    wifi 0
    [ -f "$DIR/weather.csv" ] || : > "$DIR/weather.csv"
    build_extra "$(sed -n 5p "$DIR/weather.csv" | cut -c1-10)"
    batt=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
    echo "$(date) refreshed in $(($(date +%s) - t0)) s, battery $batt%"
}

utc_offset() { o=$(sed -n 2p "$DIR/weather.csv" 2>/dev/null | cut -d, -f4); echo "${o:-0}"; }

# Epoch of the next weather refresh after epoch $1: INTERVAL later, or the end of NIGHT
# if that falls inside it. Local time = UTC (the Kindle's clock) + the forecast's offset.
next_refresh() {
    set -- "$1" $NIGHT
    awk -v n=$(($1 + INTERVAL)) -v off="$(utc_offset)" -v a="$2" -v b="$3" 'BEGIN {
        l = n + off; h = int((l % 86400) / 3600)
        if (a != "" && (a > b ? h >= a || h < b : h >= a && h < b)) {
            t = l - l % 86400 + b * 3600; if (t <= l) t += 86400; n = t - off
        }
        printf "%d\n", n }'
}

# Suspends until epoch $1 (RTC alarm) or the power button, whichever comes first.
# After 3 suspends in a row that fail or return at once, stays awake for good (SLEEP=0).
suspend_until() {
    left=$(($1 - $(date +%s)))
    [ "$left" -gt 10 ] || { sleep 1; return; }  # too close to bother: don't spin the loop
    for a in "$RTC"/rtc*/wakealarm; do echo 0 > "$a" && echo "+$left" > "$a"; done 2>/dev/null
    sync
    t0=$(date +%s)
    if echo mem > "$POWER_STATE" && [ $(($(date +%s) - t0)) -ge 3 ]; then
        fails=0
        now=$(date +%s)
        echo "$(date) slept $((now - t0)) of $left s, powerd $(lipc-get-prop com.lab126.powerd state 2>/dev/null)"
        # Woken well before the alarm: the power button. Give the user IDLE seconds.
        [ "$now" -lt $(($1 - 10)) ] && touched=$now
    else
        fails=$((fails + 1))
        echo "$(date) suspend failed ($fails)"
        [ "$fails" -ge 3 ] && { SLEEP=0; echo "$(date) can't suspend: staying awake between refreshes"; }
    fi
}

# One loop does all the drawing, so the touch watcher never draws over it.
# Awake, it checks for taps every second; once idle on Today it sleeps until the next refresh.
awake_drawn=""
tab=today; touched=$(date +%s); due=0; extra_due=0; stale=0; good_utc=""; fails=0
rm -f "$DIR/tap" "$DIR/screen.key"  # no screen.key: the first draw always happens
[ -f "$DIR/extra.txt" ] || : > "$DIR/extra.txt"  # awk needs it to exist
# Keep powerd from blanking the screen or suspending on its own timer while we are awake.
lipc-set-prop com.lab126.powerd preventScreenSaver 1
while :; do
    now=$(date +%s); redraw=""
    if mv -f "$DIR/tap" "$DIR/tap.read" 2>/dev/null; then
        touched=$now
        t=$(cat "$DIR/tap.read")
        if [ "$t" != - ] && [ "$t" != "$tab" ]; then tab=$t; redraw=1; fi
    fi
    if [ "$tab" != today ] && [ $((now - touched)) -ge "$IDLE" ]; then tab=today; redraw=1; fi
    # Awake (after a touch or the power button) shows a badge in the header; the redraw
    # on waking and on going back to sleep is a full flashing refresh, so it's visible.
    awake=0; [ $((now - touched)) -lt "$IDLE" ] && awake=1
    [ "$awake" = "$awake_drawn" ] || redraw=1
    if [ "$now" -ge "$due" ]; then
        refresh
        due=$(next_refresh "$(date +%s)")
        echo "$(date) next refresh in $(((due - $(date +%s)) / 60)) min"
        redraw=1
    fi
    if [ -n "$redraw" ]; then
        t0=$(date +%s)
        awk -v place="$PLACE" -v stale="$stale" -v utc="$good_utc" -v clock="$(date -u +%H%M)" -v tab="$tab" -v batt="$batt" -v paul="$PAUL_DATE" -v awake="$awake" \
            -f "$DIR/render.awk" "$DIR/weather.csv" "$DIR/extra.txt" > "$DIR/screen.new"
        # A full e-ink redraw costs battery: skip it when the screen would come out the same
        # (the "Updated" time alone doesn't count).
        key=$(grep -v '|Updated ' "$DIR/screen.new")
        if [ -f "$DIR/screen.key" ] && [ "$key" = "$(cat "$DIR/screen.key")" ]; then
            echo "$(date) $tab unchanged, not redrawn"
            awake_drawn=$awake
        else
            echo "$(date) drawing $tab"
            $draw < "$DIR/screen.new"
            printf '%s\n' "$key" > "$DIR/screen.key"
            awake_drawn=$awake
            echo "$(date) drew $tab in $(($(date +%s) - t0)) s"
            save_log
        fi
    fi
    if [ "$SLEEP" = 1 ] && [ "$tab" = today ] && [ "$awake" = 0 ] && [ $(($(date +%s) - touched)) -ge "$IDLE" ]; then
        if plugged; then
            [ "$said_plugged" = 1 ] || echo "$(date) plugged in: staying awake (no suspend)"
            said_plugged=1; sleep 2
        else
            said_plugged=0
            echo "$(date) idle: sleeping until the next refresh"
            save_log
            suspend_until "$due"
        fi
    else
        sleep 1
    fi
done

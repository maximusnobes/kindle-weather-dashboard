# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An e-ink weather dashboard for a jailbroken **Kindle Basic 3 (10th gen, firmware 5.18.1.1.1, jailbroken with SpiderCat)**: 600×800, 8-bit grey framebuffer, busybox userland, hard-float. It fetches Open-Meteo weather for Redwood City (°F, mph, inches) plus Kirkwood snow, Linda Mar surf and NOAA tides over Wi-Fi, and draws with FBInk.

It's a fork of [abdenourgnx/re-kindle](https://github.com/abdenourgnx/re-kindle), which targets a Kindle 7th gen (KT2, 5.12, soft-float, KUAL) and shows Vienna weather and prayer times. The upstream repo has no license, so the README credits it and leaves reuse to the original author. `server.py` is upstream's older, separate approach (an HTML page for the Kindle browser) and isn't part of the extension.

## Commands (Mac side)

```sh
sh extensions/dashboard/check.sh          # all checks: render.awk, extras.awk, scheduling helpers, on-screen bounds; prints "ok"
sh -n extensions/dashboard/loop.sh        # syntax check the device loop
python3 tools/make_icons.py               # regenerate icons/*.png (stdlib PNG writer)
# Preview a screen as SVG/HTML (run from the repo root; icon paths are relative to it).
# extra.txt holds bottom-card key,value lines (format under render.awk below); an empty file works.
awk -v place="Redwood City" -v batt=87 -v utc=1704 -v clock=1745 -v paul=2026-06-21 -v tab=today -v awake=0 \
    -f extensions/dashboard/render.awk weather.csv extra.txt | python3 tools/preview.py > preview.html
# Screenshot it at the Kindle's size:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
    --window-size=600,800 --screenshot="$PWD/preview.png" "file://$PWD/preview.html"
```

There is no single-test runner: `check.sh` is one script of `expect "<output>" "<substring>"` lines; add a case there next to the feature it covers. Its `render` helper takes the `-v` variables first, then `-f render.awk`, then the input files (awk stops reading options at the first file). Run checks with `sh` (the Kindle's shell), not zsh: zsh doesn't word-split `$NIGHT`, so the scheduling helpers give wrong answers under it. README screenshots live in `screenshots/` (named so `.gitignore`'s `preview*.png` doesn't hide them).

## Deploying to the Kindle

The user exits the dashboard first (hold a finger on the screen for 3 s, or run the `Weather Dashboard Stop` scriptlet), then plugs the Kindle into the Mac. With it mounted at `/Volumes/Kindle`, copy changed files and delete macOS `._*` files:

```sh
K=/Volumes/Kindle/extensions/dashboard
cp -X f "$K/f" && cmp f "$K/f"
find /Volumes/Kindle/extensions /Volumes/Kindle/documents -name '._*' -delete
```

Scriptlets (`scriptlets/*.sh`) go in the Kindle's `documents` folder and appear in the library. Changes take effect after ejecting and tapping `Weather Dashboard` again: `start.sh` copies the whole extension to `/var/tmp/dashboard` and runs it from there, so a running dashboard never re-reads files on `/mnt/us` (not even `render.awk`).

Each user keeps their own `PAUL_DATE` in `loop.sh` and their own `holidays.txt` on the device; the repo ships a placeholder date and a short example holidays list. Don't overwrite the device copies of these without saying so.

## Architecture

- **Launch:** the `Weather Dashboard` scriptlet runs `start.sh` (the upstream KUAL `menu.json` also still works). Scriptlets carry `# DontUseFBInk` in their header, or the launcher prints eips debug lines over the screen. `start.sh` stops any old copy, moves itself out of the library's cgroups (closing the library can otherwise kill everything it started, leaving the Kindle UI paused), copies the extension to `/var/tmp/dashboard` (plugging into USB takes `/mnt/us` away) and starts `loop.sh` with `DASH_DIR=/var/tmp/dashboard DASH_SRC=/mnt/us/extensions/dashboard`.
- **`loop.sh`** is the only process that draws. Schedule: Wi-Fi on → fetch weather (plain http) → every `EXTRA_EVERY` s also fetch snow, surf and tide (`fetch_part`, https, `curl -f`) → Wi-Fi off → `build_extra` writes `extra.txt` (the parts plus today's line from `holidays.txt`) → render → suspend to RAM with an RTC wake alarm (`echo mem > /sys/power/state`). Knobs at the top (`PLACE`, coordinates, `PAUL_DATE`, `INTERVAL`, `EXTRA_EVERY`, `NIGHT`, `IDLE`, touch thresholds, `GREY`, the snow/surf/tide sources). Battery savers: hourly refresh, none in the `NIGHT` hours, and a redraw is skipped when the rendered commands equal `screen.key` (ignoring the "Updated" line). It never suspends while plugged in (`plugged()`: `com.lab126.volumd driveModeState` or `com.lab126.powerd isCharging`), because suspending drops USB. A `trap` on TERM/HUP/INT resumes `cvm`, re-enables Wi-Fi and clears alarms if anything other than `stop.sh` kills it.
- **Awake state:** a touch or a power-button wake makes the screen "awake" for `IDLE` s. `render.awk` then shows an inverted "Awake · hold to exit" badge in place of the update time, and the change in and out of that state forces a full redraw (visible flash). When idle it returns to the Today tab before suspending, so the sleeping screen is always Today.
- **Touch** is a background `watch_touch` reading raw evdev from `/dev/input/event2` (cyttsp5_mt), 16-byte events via `dd | od -t d2`. Finger down/up is `BTN_TOUCH` (type 1, code 330); positions are `ABS_MT_POSITION_X/Y` (type 3, codes 53/54) in screen pixels. Each touch is judged on lift: held ≥ `HOLD` s without moving → `stop.sh` (Home); horizontal move ≥ `SWIPE` px → swipe left = `10d`, right = `today`; otherwise a tap between `EDGE_TOP` and `EDGE_BOTTOM` picks a tab by half (left `today`, right `10d`), and any other touch writes `-` (just keeps it awake). It never draws: it writes the request to `$DIR/tap`, which the main loop picks up with `mv tap tap.read`. The Kindle UI (`cvm`) is SIGSTOPped while the dashboard runs; `stop.sh` resumes it and undoes Wi-Fi, alarm and screensaver changes.
- **Edge menus:** the Kindle's top and bottom pull-down menus (pillow) still respond to edge touches even with `cvm` stopped and `disableEnablePillow disable` sent, which is why every control sits in the middle of the screen. Don't put tap targets near the top or bottom edge.
- **`render.awk`** turns `weather.csv` plus `extra.txt` (second input, detected with `NR != FNR`) into a line protocol, `T|style|px|left|right|top|flags|text`, `R|x|y|w|h|color`, `I|name|x|y`, which `loop.sh`'s `draw_fbink` executes. Variables: `place`, `batt`, `utc` (device UTC HHMM of the last good fetch), `clock` (device UTC HHMM now), `stale`, `tab` (`today`/`10d`), `paul` (YYYY-MM-DD), `awake`. `weather.csv` is Open-Meteo CSV (meta, current, hourly, daily sections separated by blank lines, columns positional, in °F/mph/inch; daily ends with `sunrise,sunset`). New API fields must be appended to the end of the URL's field lists so old CSVs keep their column positions. `extra.txt` lines: `snow_new,N`, `snow_depth,N`, `snow_temp,N`, `wave,N.N`, `period,N`, `dir,WNW`, `tide,YYYY-MM-DD HH:MM,H|L` (repeated), `holiday,Name` (may contain commas). Times are 12-hour (`t12()`). The bottom card is a 3 × 2 grid placed by `tile_x(c)`/`tile_y(r)`: days since Paul left, Today is, Sunrise / Kirkwood, Linda Mar (with next tide), Sunset. Text flags: `c` centred, `i` inverted, `g` secondary (`-C $GREY`).
- **`extras.awk`** turns one download into `extra.txt`-style lines, chosen with `-v kind=snow|surf|tide`. Open-Meteo columns are found by header name and units read from the header (`(m)`, `(cm)`, `(inch)`, `(ft)`), so field order and units can change; snow sums hourly snowfall up to the current time; tide keeps NOAA's high/low rows.
- **FBInk:** the KOReader build at `/mnt/us/koreader/fbink` (hard-float, matches 5.18 firmware) is used; `bin/fbink` (upstream's soft-float v1.25) is only a fallback and segfaults on this firmware. Icons are drawn with the Kindle's `eips -g`. FBInk can't right-align or measure text, so widths are estimated in awk (`rtext()`, the big-temperature width heuristic). Overflowing text wraps onto a second line rather than clipping.
- **`tools/preview.py`** mirrors the protocol as SVG with Helvetica (the device uses Amazon Ember), so spacing on the device differs slightly.
- **`scriptlets/Dashboard-Probe.sh`** records a Kindle's firmware, FBInk builds, input devices, fonts and network access to `/mnt/us/dashboard-probe.txt`, with a 12-second raw touch capture. Use it when adapting to another model. (`extensions/dashboard/probe.sh` is upstream's KUAL probe.)

## Constraints that have bitten before

- The device awk is **busybox awk**. Never join a variable and a parenthesised expression as `name (expr)`: busybox parses it as a call to function `name` and aborts the render mid-screen. Start with the paren or use a temp variable. Mac awk accepts both, so `check.sh` won't catch this.
- awk counts the UTF-8 `°` as 2 bytes; width estimates count digits/`-` with `gsub` and add the degree sign once.
- Use `date -u` on the device and add `utc_offset_seconds` from line 2 of `weather.csv` for local time; the local date comes from line 5 of `weather.csv` (`cut -c1-10`).
- Snow, surf and tide use verified https only (`curl -f`); don't add `-k`. Open-Meteo weather is fetched over plain http on purpose.
- The log is written in `/var/tmp/dashboard/dashboard.log` and copied to `/mnt/us/extensions/dashboard/dashboard.log` (`save_log`) after each draw, before each suspend and on exit, but never while the Kindle is in USB drive mode. Ask the user for that file when debugging.
- Wi-Fi is off (the Kindle shows Airplane Mode) except during fetches; that's by design.
- Git: `origin` is `maximusnobes/kindle-weather-dashboard` (a GitHub fork of `abdenourgnx/re-kindle`), branch `main`.

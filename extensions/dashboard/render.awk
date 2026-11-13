# Turns an Open-Meteo CSV (sections: meta, current, hourly, daily) into drawing
# commands for a 600x800 portrait screen, run by loop.sh through FBInk:
#   T|style|px|left|right|top|flags|text   style R/B; flags: c = centred between margins, i = white text, g = grey text
#   R|x|y|w|h|color                        filled box: B (black), W (white) or an FBInk grey like GRAYA
#   I|name|x|y                             icons/<name>.png
# Plain POSIX awk so busybox on the Kindle runs it. Never write `name (...)` to join a
# variable and a bracketed expression: busybox reads it as a call to a function "name".
# Vars: place, stale (1 = last fetch failed), utc (HHMM UTC of the last good fetch), clock (HHMM UTC now),
#       tab ("today" or "10d"), batt (battery %, empty to hide), paul (YYYY-MM-DD the day counter counts from),
#       awake (1 = show the "Awake" badge in place of the update time).
# Input: weather.csv (°F, mph, inches), then optionally extra.txt (see loop.sh's build_extra):
#        key,value lines for the bottom card: snow_new, snow_depth, snow_temp, wave, period,
#        dir, tide,YYYY-MM-DD HH:MM,H|L (several), holiday,Name.

function cond(c) {
    c = int(c)
    if (c == 0) return "Clear"
    if (c == 1) return "Mostly clear"
    if (c == 2) return "Partly cloudy"
    if (c == 3) return "Cloudy"
    if (c == 45 || c == 48) return "Fog"
    if (c >= 51 && c <= 57) return "Drizzle"
    if (c >= 61 && c <= 67) return "Rain"
    if (c >= 71 && c <= 77) return "Snow"
    if (c >= 80 && c <= 82) return "Showers"
    if (c == 85 || c == 86) return "Snow showers"
    if (c >= 95) return "Storm"
    return "-"
}

function icon(c, day) {
    c = int(c)
    if (c <= 1) return day == "0" ? "moon" : "sun"
    if (c == 2) return day == "0" ? "partly-night" : "partly"
    if (c == 3) return "cloud"
    if (c == 45 || c == 48) return "fog"
    if (c >= 51 && c <= 57) return "drizzle"
    if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
    if ((c >= 71 && c <= 77) || c == 85 || c == 86) return "snow"
    if (c >= 95) return "storm"
    return "cloud"
}

function deg(x) { return x == "" ? "-" : sprintf("%d", x < 0 ? x - 0.5 : x + 0.5) "°" }
function pct(x) { return x == "" ? "-" : x "%" }

function weekday(y, m, d,   t) {  # 0 = Monday
    split("0 3 2 5 0 3 5 1 4 6 2 4", t, " ")
    if (m < 3) y--
    return (y + int(y / 4) - int(y / 100) + int(y / 400) + t[m] + d + 6) % 7
}

function text(style, px, left, right, top, flags, s) { print "T|" style "|" px "|" left "|" right "|" top "|" flags "|" s }
function box(x, y, w, h, color) { print "R|" x "|" y "|" w "|" h "|" color }
function frame(x, y, w, h, t) { box(x, y, w, h, "B"); box(x + t, y + t, w - 2 * t, h - 2 * t, "W") }
function img(name, x, y) { print "I|" name "|" x "|" y }
# Right-aligned regular text ending at x = edge. FBInk can't right-align, so estimate the
# width from Helvetica's advances (Amazon Ember is close); the 4 px right margin is slack
# so a slight underestimate doesn't wrap the text onto a second line.
function rtext(px, edge, top, flags, s,   w, i, p) {
    for (i = 1; i <= length(s); i++) { p = index(ADVCHARS, substr(s, i, 1)); w += p ? adv[p] : 0.556 }
    text("R", px, int(edge - w * px), 4, top, flags, s)
}
function hm(t) { return substr(t, 12, 5) }  # "2026-11-07T06:58" -> "06:58"
# 12-hour clock from minutes after midnight: "6:58 am"; short = 1 gives "7am" (hourly labels).
function t12(mins, short,   h, m, ap) {
    h = int(mins / 60) % 24; m = mins % 60; ap = h < 12 ? "am" : "pm"
    h = h % 12; if (h == 0) h = 12
    if (short) return h ap
    return h ":" sprintf("%02d", m) " " ap
}
function hmm(t) { return substr(t, 12, 2) * 60 + substr(t, 15, 2) }  # "…T06:58" -> 418
function jdn(y, m, d,   a) {  # day number, for counting days between dates
    a = int((14 - m) / 12); y = y + 4800 - a; m = m + 12 * a - 3
    return d + int((153 * m + 2) / 5) + 365 * y + int(y / 4) - int(y / 100) + int(y / 400) - 32045
}
# The bottom card's 3 x 2 tiles: column c (0-2), row r (0-1).
function tile_x(c) { return 20 + 187 * c }
function tile_y(r) { return 506 + 147 * r }
function tlabel(c, r, s) { text("R", 18, tile_x(c), 600 - tile_x(c) - 187, tile_y(r) + 16, "cg", s) }
function tline(c, r, style, px, dy, flags, s) { text(style, px, tile_x(c), 600 - tile_x(c) - 187, tile_y(r) + dy, flags, s) }

BEGIN {
    FS = ","; sec = 0; nh = 0; nd = 0; offset = 0; ntide = 0
    ADVCHARS = " 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    split(".278 .556 .556 .556 .556 .556 .556 .556 .556 .556 .556 " \
          ".556 .556 .5 .556 .556 .278 .556 .556 .222 .222 .5 .222 .833 .556 .556 .556 .556 .333 .5 .278 .556 .5 .722 .5 .5 .5 " \
          ".667 .667 .722 .722 .667 .611 .778 .722 .278 .5 .667 .556 .833 .722 .778 .667 .778 .722 .667 .611 .722 .667 .944 .667 .667 .611", adv, " ")
}  # counters must start numeric: an unset one indexes as ""
{ sub(/\r$/, "") }
NR != FNR {  # second file, extra.txt
    if ($1 == "tide") { tt[ntide] = $2; tk[ntide] = $3; ntide++ }
    else if ($1 == "holiday") { s = $0; sub(/^holiday,/, "", s); ex["holiday"] = s }
    else ex[$1] = $2
    next
}
/^$/ { sec++; next }
$1 == "time" || $1 == "latitude" { next }
sec == 0 { offset = $4 }
sec == 1 { now = $1; temp = $2; code = $3; hum = $4; isday = $5; feel = $6; wind = $7 }
sec == 2 { ht[nh] = $1; htemp[nh] = $2; hcode[nh] = $3; hrain[nh] = $4; hday[nh] = $5; nh++ }
sec == 3 { dt[nd] = $1; dcode[nd] = $2; dmax[nd] = $3; dmin[nd] = $4; drain[nd] = $5; dsum[nd] = $6; drise[nd] = $7; dset[nd] = $8; nd++ }

END {
    # The place name doubles as the Home button (loop.sh maps taps on it), so draw it first.
    text("B", 22, 20, 300, 16, "", place)
    if (now == "") {
        text("B", 28, 20, 20, 90, "", "No weather data yet")
        text("R", 20, 20, 20, 134, "g", "It appears after the first refresh over Wi-Fi.")
        exit
    }

    split("Monday Tuesday Wednesday Thursday Friday Saturday Sunday", dayname, " ")
    split("January February March April May June July August September October November December", monname, " ")
    y = substr(now, 1, 4) + 0; m = substr(now, 6, 2) + 0; d = substr(now, 9, 2) + 0
    today = substr(now, 1, 10); ti = -1
    for (i = 0; i < nd; i++) if (dt[i] == today) ti = i

    # Header: update time and battery beside the place, then the tabs (loop.sh maps taps
    # between y=52 and y=110 to them: left half Today, right half 10 days).
    if (utc != "") {
        mins = (int(utc / 100) * 60 + utc % 100 + int(offset / 60) + 1440) % 1440
        stamp = t12(mins)
    } else stamp = t12(hmm(now))
    ck = clock != "" ? clock : utc  # the tide tile needs the time now, not the time of the fetch
    if (ck != "") nowm = (int(ck / 100) * 60 + ck % 100 + int(offset / 60) + 1440) % 1440
    else nowm = substr(now, 12, 2) * 60 + substr(now, 15, 2)
    if (awake) { box(292, 12, 192, 30, "B"); text("B", 16, 292, 116, 18, "ci", "Awake · hold to exit") }
    else if (stale) text("B", 18, 330, 120, 19, "", "Offline · " stamp)
    else text("R", 18, 330, 120, 19, "g", "Updated " stamp)
    if (batt != "") {  # battery outline with a level bar, then the percentage (bold when low)
        frame(490, 21, 30, 15, 2); box(520, 25, 3, 7, "B")
        box(493, 24, int(24 * (batt > 100 ? 100 : batt) / 100), 9, "B")
        text(batt <= 20 ? "B" : "R", 18, 528, 20, 19, "", batt "%")
    }
    box(20, 48, 560, 1, "B")  # separates the place/update row from the tabs
    week = tab == "10d"
    text(week ? "R" : "B", 22, 20, 300, 60, week ? "cg" : "c", "Today")
    text(week ? "B" : "R", 22, 300, 20, 60, week ? "c" : "cg", "10 days")
    box(week ? 370 : 90, 90, 140, 4, "B")
    box(20, 94, 560, 1, "B")

    if (week) {
        # One row per day: label, icon, rain-chance dots, rain amount, then min, a bar
        # placing the day's range within the 10 days' coldest-to-warmest, and max.
        lo = 999; hi = -999
        for (k = 0; k < 10 && ti >= 0 && ti + k < nd; k++) {
            i = ti + k
            if (dmin[i] != "" && dmin[i] + 0 < lo) lo = dmin[i] + 0
            if (dmax[i] != "" && dmax[i] + 0 > hi) hi = dmax[i] + 0
        }
        for (k = 0; k < 10 && ti >= 0 && ti + k < nd; k++) {
            i = ti + k; r = 100 + 68 * k
            if (k == 0) text("B", 24, 20, 470, r + 20, "", "Today")
            else {
                dd = substr(dt[i], 9, 2) + 0
                text("R", 22, 20, 500, r + 22, "g", substr(dayname[weekday(substr(dt[i], 1, 4) + 0, substr(dt[i], 6, 2) + 0, dd) + 1], 1, 3))
                text("B", 24, 72, 480, r + 20, "", dd)
            }
            img(icon(dcode[i], 1) "-48", 124, r + 10)
            dots = int((drain[i] + 10) / 20); if (dots > 5) dots = 5
            img("dots-" dots, 184, r + 27)
            if (dsum[i] == "" || dsum[i] < 0.005) rain = dots ? "0 in" : "dry"  # "dry" beside filled dots reads as a contradiction
            else rain = (dsum[i] < 0.05 ? "<0.1" : sprintf("%.1f", dsum[i])) " in"
            text("R", 18, 304, 228, r + 24, "g", rain)
            text("R", 26, 364, 172, r + 21, "c", deg(dmin[i]))
            text("R", 26, 520, 20, r + 21, "c", deg(dmax[i]))
            box(434, r + 31, 80, 6, "GRAYD")
            if (dmin[i] != "" && dmax[i] != "") {
                span = hi > lo ? hi - lo : 1
                x1 = 434 + int((dmin[i] - lo) * 80 / span + 0.5); x2 = 434 + int((dmax[i] - lo) * 80 / span + 0.5)
                if (x2 - x1 < 6) { x1 = x2 - 6 < 434 ? 434 : x2 - 6; x2 = x1 + 6 }
                box(x1, r + 31, x2 - x1, 6, "B")
            }
            if (k < 9) box(20, r + 67, 560, 1, "GRAYA")
        }
        if (ti < 0) text("R", 22, 20, 20, 130, "", "No forecast for today")
        exit
    }

    # Now: big icon and temperature, then today and tomorrow.
    # Icon + temperature centred as a group between the frame line (x=20) and the
    # Today column (x=360). FBInk can't measure text, so estimate the temperature's
    # width from Amazon Ember Bold's rough advances (digits ~0.56 em, "-" ~0.36, "°" ~0.40).
    # Count digits and "-" only: awk counts the UTF-8 "°" as 2 bytes, so add it once.
    t = deg(temp); n = t; tw = 0.40
    tw += 0.56 * gsub(/[0-9]/, "", n) + 0.36 * gsub(/-/, "", n)
    # Icon art is ~124 px wide inside its 160 px box, 18 px in; 14 px gap to the number.
    # Shrink the number when it wouldn't fit (like -12°) instead of running into the column.
    px = 124; if (124 + 14 + tw * px > 336) px = int((336 - 138) / tw)
    gx = int(20 + (340 - (138 + tw * px)) / 2)
    img(icon(code, isday) "-160", gx - 18, 104)
    text("B", px, gx + 138, 240, 132 + int((124 - px) / 2), "", t)
    text("R", 26, 20, 240, 268, "c", cond(code))
    s = feel == "" ? "" : "Feels like " deg(feel)
    if (hum != "") s = (s == "" ? "" : s " · ") "Humidity " pct(hum)
    text("R", 20, 20, 240, 304, "cg", s)
    if (ti < 0) text("R", 22, 360, 20, 120, "", "No forecast for today")
    else {
        text("R", 18, 360, 20, 112, "g", "Today")
        text("B", 32, 360, 20, 132, "", deg(dmax[ti]) " / " deg(dmin[ti]))
        text("R", 22, 360, 20, 174, "", cond(dcode[ti]))
        w = wind == "" ? "" : " · " sprintf("%.0f", wind) " mph"
        text("R", 18, 360, 20, 204, "g", pct(drain[ti]) " rain" w)
        if (ti + 1 < nd) {
            box(360, 238, 220, 1, "GRAYA")
            img(icon(dcode[ti + 1], 1) "-48", 356, 256)
            text("R", 18, 414, 20, 248, "g", "Tomorrow")
            text("B", 24, 414, 20, 270, "", deg(dmax[ti + 1]) " / " deg(dmin[ti + 1]))
            text("R", 18, 414, 20, 302, "g", pct(drain[ti + 1]) " rain")
        }
    }

    # Next hours, every 3 h. Widgets are separated by single rules, not boxed.
    box(20, 334, 560, 1, "B")
    start = nh
    for (i = nh - 1; i >= 0; i--) if (ht[i] > now) start = i
    for (s = 0; s < 7 && start + 3 * s < nh; s++) {
        i = start + 3 * s; x = 20 + 80 * s; r = 600 - x - 80
        text("R", 18, x, r, 354, "cg", t12(hmm(ht[i]), 1))
        img(icon(hcode[i], hday[i]) "-48", x + 16, 378)
        text("B", 24, x, r, 430, "c", deg(htemp[i]))
        text("R", 18, x, r, 466, "cg", pct(hrain[i]))
    }

    # Bottom card: six tiles in a 3 x 2 grid, separated by grey rules.
    box(20, 506, 560, 1, "B")
    box(20, tile_y(1), 560, 1, "GRAYA")
    for (c = 1; c < 3; c++) for (r = 0; r < 2; r++) box(tile_x(c), tile_y(r) + 14, 1, 119, "GRAYA")

    # Days since Paul left: day 0 is the day itself.
    tlabel(0, 0, "Days since Paul left")
    if (paul ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) {
        n = jdn(y, m, d) - jdn(substr(paul, 1, 4) + 0, substr(paul, 6, 2) + 0, substr(paul, 9, 2) + 0)
        tline(0, 0, "B", n > 9999 || n < -999 ? 44 : 64, 46, "c", n)
    } else tline(0, 0, "R", 20, 64, "cg", "Set PAUL_DATE")

    # Today is: the day's fun holiday from holidays.txt. Long names drop a size and wrap.
    tlabel(1, 0, "Today is")
    h = ex["holiday"]
    if (h == "") tline(1, 0, "R", 20, 56, "cg", "Just a regular " dayname[weekday(y, m, d) + 1])
    else tline(1, 0, "B", length(h) > 30 ? 20 : 24, 50, "c", h)

    # Sunrise and sunset, today's.
    tlabel(2, 0, "Sunrise")
    tline(2, 0, "B", 38, 54, "c", ti >= 0 && drise[ti] != "" ? t12(hmm(drise[ti])) : "-")
    tlabel(2, 1, "Sunset")
    tline(2, 1, "B", 38, 54, "c", ti >= 0 && dset[ti] != "" ? t12(hmm(dset[ti])) : "-")

    # Kirkwood: new snow in the last 24 h, then base depth and temperature (Open-Meteo model).
    tlabel(0, 1, "Kirkwood")
    if (ex["snow_new"] == "" && ex["snow_depth"] == "") tline(0, 1, "R", 20, 64, "cg", "No data yet")
    else {
        tline(0, 1, "B", 32, 46, "c", (ex["snow_new"] == "" ? "-" : ex["snow_new"]) "\" new")
        s = (ex["snow_depth"] == "" ? "-" : ex["snow_depth"]) "\" base"
        if (ex["snow_temp"] != "") s = s " · " ex["snow_temp"] "°"
        tline(0, 1, "R", 20, 92, "cg", s)
    }

    # Linda Mar: wave height, swell period and direction, and the next tide.
    tlabel(1, 1, "Linda Mar")
    if (ex["wave"] == "") tline(1, 1, "R", 20, 64, "cg", "No data yet")
    else {
        tline(1, 1, "B", 32, 46, "c", ex["wave"] " ft")
        s = ex["period"] == "" ? "" : ex["period"] "s"
        if (ex["dir"] != "") s = (s == "" ? "" : s " ") ex["dir"]
        if (s != "") tline(1, 1, "R", 20, 88, "cg", s)
    }
    # Next tide after now (tide times are local "YYYY-MM-DD HH:MM").
    nt = -1
    for (k = ntide - 1; k >= 0; k--) {
        td = substr(tt[k], 1, 10); tm = substr(tt[k], 12, 2) * 60 + substr(tt[k], 15, 2)
        if (td > today || (td == today && tm > nowm)) nt = k
    }
    if (nt >= 0) tline(1, 1, "R", 20, 114, "cg", (tk[nt] == "H" ? "High " : "Low ") t12(substr(tt[nt], 12, 2) * 60 + substr(tt[nt], 15, 2)))
}

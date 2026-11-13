# Turns one downloaded data file into "key,value" lines for render.awk's bottom card.
# Run with -v kind=snow (Open-Meteo forecast CSV for Kirkwood), kind=surf (Open-Meteo marine
# CSV for Linda Mar) or kind=tide (NOAA high/low tide predictions CSV).
# Open-Meteo CSVs have sections separated by blank lines: meta, current, then hourly.
# Columns are found by name and units are read from the header, so the order doesn't matter.
# Plain POSIX awk for busybox: never write `name (...)` (busybox reads it as a function call).

function col(name,   i) { for (i = 1; i <= NF; i++) if (index(hdr[i], name " (") == 1 || hdr[i] == name) return i; return 0 }
function unit(name,   i, u) { i = col(name); if (!i) return ""; u = hdr[i]; sub(/^[^(]*\(/, "", u); sub(/\).*$/, "", u); return u }
function to_in(v, u) { if (u == "m") return v * 39.37; if (u == "cm") return v / 2.54; if (u == "mm") return v / 25.4; if (u == "ft") return v * 12; return v }
function to_ft(v, u) { if (u == "m") return v * 3.281; return v }
function compass(dg,   n) { split("N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW", n, " "); return n[int((dg + 11.25) / 22.5) % 16 + 1] }

BEGIN { FS = ","; sec = 0; newsnow = 0; got = 0 }
{ sub(/\r$/, "") }

kind == "tide" {
    # "2026-11-11 10:37,5.768,H": keep the time and H/L
    if ($1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]$/ && ($3 == "H" || $3 == "L")) print "tide," $1 "," $3
    next
}
/^$/ { sec++; next }
$1 == "latitude" { next }
$1 == "time" { delete hdr; for (i = 1; i <= NF; i++) hdr[i] = $i; next }

sec == 1 {  # current conditions: one row
    now = $1
    if (kind == "snow") {
        if ((i = col("temperature_2m")) && $i != "") print "snow_temp," sprintf("%d", $i < 0 ? $i - 0.5 : $i + 0.5)
        if ((i = col("snow_depth")) && $i != "") print "snow_depth," sprintf("%d", to_in($i, unit("snow_depth")) + 0.5)
    }
    if (kind == "surf") {
        if ((i = col("wave_height")) && $i != "") print "wave," sprintf("%.1f", to_ft($i, unit("wave_height")))
        if ((i = col("swell_wave_period")) && $i != "") print "period," sprintf("%d", $i + 0.5)
        if ((i = col("swell_wave_direction")) && $i != "") print "dir," compass($i)
    }
    next
}
sec == 2 && kind == "snow" {  # hourly snowfall: add up the hours up to now (the last 24 h)
    if ((i = col("snowfall")) && $1 <= now && $i != "") { newsnow += to_in($i, unit("snowfall")); got = 1 }
}
END { if (kind == "snow" && got) print "snow_new," sprintf("%d", newsnow + 0.5) }

#!/bin/bash
# Tell me when GammaOS has really finished starting: booted, its menu up,
# Wi-Fi connected (with internet), and the start-up work (app optimizing,
# media scan, disk reads) settled. Ends with a Mac notification and a sound.
#
#   tools/gammaos-ready.sh              over USB (USB debugging on)
#   tools/gammaos-ready.sh 10.0.0.5     over Wi-Fi (ADB on port 5555)
#
# Start it before (or while) turning the handheld on.
set -u
ADDR="${1:-}"
T0=$(date +%s)

say() {       # one status line, rewritten in place
    local s=$(( $(date +%s) - T0 ))
    printf '\r\033[K[%d:%02d] %s' $((s / 60)) $((s % 60)) "$1"
}
done_step() { printf '\r\033[K[%d:%02d] ✓ %s\n' $(( ($(date +%s) - T0) / 60 )) $(( ($(date +%s) - T0) % 60 )) "$1"; }

ADB=(adb)
if [ -n "$ADDR" ]; then
    SERIAL="$ADDR:5555"
    ADB=(adb -s "$SERIAL")
    until adb connect "$SERIAL" 2>/dev/null | grep -q "connected to"; do
        say "Waiting for the handheld at $ADDR…"
        sleep 2
    done
else
    until adb get-state 2>/dev/null | grep -q device; do
        say "Waiting for the handheld on USB (USB debugging on?)…"
        sleep 2
    done
fi
sh() { "${ADB[@]}" shell "$@" 2>/dev/null | tr -d '\r'; }
done_step "Connected"

until [ "$(sh getprop sys.boot_completed)" = 1 ]; do say "Android is booting…"; sleep 2; done
done_step "Android booted"

# (GammaOS's menu is its own program, not an Android app.)
until [ -n "$(sh pidof gammaos-nano)" ]; do
    say "Waiting for GammaOS's menu…"
    sleep 2
done
done_step "Menu is up"

until [ -n "$(sh ip -4 -o addr show wlan0 | awk '{print $4}')" ]; do say "Waiting for Wi-Fi…"; sleep 2; done
IP=$(sh ip -4 -o addr show wlan0 | awk '{print $4}' | cut -d/ -f1)
until sh ping -c 1 -W 2 8.8.8.8 | grep -q "1 received"; do say "Wi-Fi connected ($IP), waiting for internet…"; sleep 2; done
done_step "Wi-Fi and internet ($IP)"

# Settled: no app optimizing (dex2oat), and little waiting on the card, for
# 3 checks in a row.
calm=0
while [ $calm -lt 3 ]; do
    io=$(sh cat /proc/pressure/io | awk '/^some/ { sub("avg10=", "", $2); print int($2) }')
    busy=$(sh pidof dex2oat dex2oat64)
    if [ -z "$busy" ] && [ "${io:-100}" -lt 10 ]; then calm=$((calm + 1)); else calm=0; fi
    say "Settling (disk waiting ${io:-?}%${busy:+, optimizing apps})…"
    sleep 3
done
done_step "Settled"

s=$(( $(date +%s) - T0 ))
printf '\nGammaOS is ready (%d:%02d). Address: %s\n' $((s / 60)) $((s % 60)) "$IP"
osascript -e "display notification \"Ready at $IP\" with title \"GammaOS is ready\" sound name \"Glass\"" 2>/dev/null

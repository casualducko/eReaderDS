#!/bin/bash
# Talk to the device over SSH (address in .device, or DEVICE=ip).
#   tools/device.sh log      show Ports/eReaderDS/log.txt
#   tools/device.sh data     show saved settings, progress and bookmarks
#   tools/device.sh shell    open a shell on the device
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOST="${DEVICE:-$(cat "$ROOT/.device" 2>/dev/null)}"
[ -n "$HOST" ] || { echo "Set the device IP: echo 192.168.x.y > .device"; exit 1; }
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8 root@$HOST"
case "${1:-log}" in
    log)   $SSH cat /mnt/mmc/Ports/eReaderDS/log.txt ;;
    data)  $SSH 'cd /mnt/mmc/Ebook/.ereaderds && for f in *.txt; do echo "== $f"; cat "$f"; done' ;;
    shell) exec ssh root@$HOST ;;
    *)     echo "usage: tools/device.sh [log|data|shell]"; exit 1 ;;
esac

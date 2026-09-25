#!/bin/sh
# Ports menu entry for eReaderDS.
PORTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
exec /bin/bash "$PORTS_DIR/eReaderDS/launch.sh" "$@"

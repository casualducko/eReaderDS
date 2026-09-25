#!/bin/sh
# Ports menu entry for Book Reader.
PORTS_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || exit 1
exec /bin/bash "$PORTS_DIR/BookReader/launch.sh" "$@"

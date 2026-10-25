#!/bin/sh
set -eu
DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
export PORT="$LISTEN_PORT" KEY="$SHARED_KEY" MAX_ITEMS STORE=/var/lib/clipsync/clips.json
exec "$DIR/venv/bin/python3" -u "$DIR/src/server.py"

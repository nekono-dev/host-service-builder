#!/bin/sh
set -eu
set -a
# shellcheck source=/dev/null
. "$HS_CONF_FILE"
set +a
exec "$HS_DIR/bin/app"

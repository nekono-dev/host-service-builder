#!/bin/sh
UNIT=/etc/systemd/system/clipsync.service

load_config() {
  # shellcheck source=/dev/null
  . "$CONF_FILE"
}

check_values() {
  case "$LISTEN_PORT" in ''|*[!0-9]*) die "LISTEN_PORT は数字で指定してください: $LISTEN_PORT" ;; esac
  case "$MAX_ITEMS" in ''|*[!0-9]*) die "MAX_ITEMS は数字で指定してください: $MAX_ITEMS" ;; esac
  [ "$MAX_ITEMS" -ge 1 ] || die "MAX_ITEMS は 1 以上にしてください"
}

app_install() {
  load_config
  check_values
  [ -d /run/systemd/system ] || die "systemd が動作していません"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3 python3-venv
  id clipsync >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin clipsync
  mkdir -p "$DATA_DIR"
  chown clipsync:clipsync "$DATA_DIR"
  [ -x "$DIR/venv/bin/python3" ] || python3 -m venv "$DIR/venv"
  "$DIR/venv/bin/pip" install -q -r "$DIR/requirements.txt"
  sed "s|@@DIR@@|$DIR|g" "$SCRIPT_DIR/units/clipsync.service" > "$UNIT"
  systemctl daemon-reload
  systemctl enable clipsync
  systemctl restart clipsync
}

app_uninstall() {
  systemctl disable --now clipsync
  rm "$UNIT"
  systemctl daemon-reload
}

app_purge() {
  userdel clipsync
}

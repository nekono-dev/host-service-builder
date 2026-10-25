# shellcheck shell=sh disable=SC2154
# shellcheck source=/dev/null
. "$SCRIPT_DIR/host-service.sh"

SVC_USER=$APP

app_check() {
  hs_init
}

app_install() {
  hs_init
  case "$HS_OS" in
    debian) hs_pkg ca-certificates ;;
    alpine) hs_pkg ca-certificates ;;
  esac
  hs_user "$SVC_USER"
  hs_dir "$DATA_DIR" "$SVC_USER" 750
  hs_service "$APP" --description "$APP" --user "$SVC_USER" -- "$DIR/installer/run/main.sh"
  hs_start "$APP"
  hs_prune
}

app_uninstall() {
  hs_remove_all
}

app_purge() {
  hs_user_remove "$SVC_USER"
}

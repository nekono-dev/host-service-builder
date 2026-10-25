#!/bin/sh
# 責務: 共通ライブラリ（assets/core/installer/host-service.sh）を、bootstrap-ci-builder のコアと組み合わせて実際に動かし、
#       サービスの導入・再適用・設定の反映・任意サービスの収束・自動再起動・削除・完全削除を確かめる。
#       systemd（Debian 系）と OpenRC（Alpine）のどちらでも同じ検査を行う。
# 使い方: sudo sh tests/e2e.sh <bootstrap-ci-builder のパス>
#         root 権限が要る。/opt・/etc・/var/lib・/usr/local/bin に e2eapp-hsb の導入物とユーザーを作り、最後に消す。
#         パッケージ jq を導入する（ネットワークが要る）。OpenRC では syslog（/var/log/messages）が動いていること。
# 出力: 検査ごとに ok / NG を1行。NG が1つでもあれば終了コード1。

set -eu

[ "$#" -eq 1 ] || { echo "使い方: sudo sh $0 <bootstrap-ci-builder のパス>" 1>&2; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "root で実行してください" 1>&2; exit 1; }
BCB=$(CDPATH='' cd -- "$1" && pwd)
[ -f "$BCB/scripts/sync.sh" ] || { echo "bootstrap-ci-builder ではありません: $BCB" 1>&2; exit 1; }

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d)
APP=e2eapp-hsb
SRC="$WORK/src"
DIR="/opt/$APP"
CONF="/etc/$APP/$APP.env"
DATA="/var/lib/$APP"
CTL="/usr/local/bin/$APP-ctl"
FAIL=0

if [ -d /run/systemd/system ]; then
  INIT=systemd
  DEF_DIR=/etc/systemd/system
  DEF_SUFFIX=.service
else
  INIT=openrc
  DEF_DIR=/etc/init.d
  DEF_SUFFIX=''
fi
FOREIGN="$DEF_DIR/$APP-foreign$DEF_SUFFIX"

cleanup() {
  [ ! -x "$CTL" ] || "$CTL" uninstall --purge >/dev/null 2>&1 || true
  for _f in "$DEF_DIR/$APP$DEF_SUFFIX" "$DEF_DIR/$APP-extra$DEF_SUFFIX"; do
    [ -f "$_f" ] || continue
    if [ "$INIT" = systemd ]; then systemctl disable --now "$(basename "$_f")" >/dev/null 2>&1 || true
    else rc-service "$(basename "$_f")" stop >/dev/null 2>&1 || true; rc-update del "$(basename "$_f")" default >/dev/null 2>&1 || true
    fi
    rm -f "$_f"
  done
  rm -f "$FOREIGN"
  [ "$INIT" != systemd ] || systemctl daemon-reload
  if id "$APP" >/dev/null 2>&1; then deluser "$APP" >/dev/null 2>&1 || userdel "$APP" >/dev/null 2>&1 || true; fi
  if grep -q "^$APP:" /etc/group; then delgroup "$APP" >/dev/null 2>&1 || groupdel "$APP" >/dev/null 2>&1 || true; fi
  rm -rf "/etc/${APP:?}" "$DATA" "/var/lib/$APP-installer" "$CTL" "$DIR" "$WORK"
}
trap cleanup EXIT
cleanup_before() {
  _w=$WORK; WORK=/nonexistent-hsb; cleanup; WORK=$_w
}
cleanup_before

ok() { echo "ok  $*"; }
ng() { echo "NG  $*"; FAIL=1; }
check() { _d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$_d"; else ng "$_d"; fi; }
check_not() { _d=$1; shift; if "$@" >/dev/null 2>&1; then ng "$_d"; else ok "$_d"; fi; }
g() { git -C "$SRC" -c user.name=e2e -c user.email=e2e@example.test "$@"; }

wait_for() {
  _n=0
  while [ "$_n" -lt 20 ]; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    _n=$((_n + 1)); sleep 1
  done
  return 1
}
out_is() { [ "$(cat "$DATA/$1.out" 2>/dev/null)" = "$2" ]; }
ps_all() { ps -eo pid,args 2>/dev/null || ps -o pid,args; }
wrapper_pids() { ps_all | awk -v c="$DIR/installer/run/main.sh $1" '{ p = $1; $1 = ""; sub(/^ /, ""); sub(/^[{][^}]*[}] /, ""); if ($0 == "/bin/sh " c) print p }'; }
running() { [ "$(wrapper_pids "$1" | wc -l)" -eq 1 ]; }
stopped() { [ -z "$(wrapper_pids "$1")" ]; }
replaced() { _p=$(wrapper_pids "$1"); [ -n "$_p" ] && [ "$_p" != "$2" ]; }
active() {
  if [ "$INIT" = systemd ]; then systemctl is-active -q "$1"; else rc-service "$1" status >/dev/null 2>&1; fi
}
logged() {
  if [ "$INIT" = systemd ]; then journalctl -u "$1" --no-pager 2>/dev/null | grep -q "$2"
  else grep -q "$1.*$2" /var/log/messages
  fi
}
install_sh() { sh "$WORK/install.sh" "$@"; }

mkdir -p "$SRC"
git -C "$SRC" -c init.defaultBranch=main init -q
sh "$ROOT/scripts/sync.sh" "$SRC" >/dev/null
sh "$BCB/scripts/sync.sh" "$SRC" >/dev/null
printf "APP_NAME='%s'\nINSTALL_MODE='system'\n" "$APP" > "$SRC/installer/app.conf"
cat > "$SRC/installer/config.schema" <<'EOF'
GREETING||required|書き込む文字列
INTERVAL|1|optional|書き込みの間隔（秒）
WITH_EXTRA|0|optional|1 で追加のサービスを動かす
EOF
cat > "$SRC/installer/app.sh" <<'EOF'
# shellcheck shell=sh disable=SC2154
# shellcheck source=/dev/null
. "$SCRIPT_DIR/host-service.sh"

SVC_USER=$APP

app_check() {
  hs_init
  hs_expect_int INTERVAL "$(config_value INTERVAL)" 1 60
  hs_expect_bool WITH_EXTRA "$(config_value WITH_EXTRA)"
}

app_install() {
  hs_init
  # shellcheck source=/dev/null
  . "$CONF_FILE"
  hs_pkg jq
  hs_user "$SVC_USER"
  hs_dir "$DATA_DIR" "$SVC_USER" 750
  hs_service "$APP" --description "e2e main" --user "$SVC_USER" --dir "$DATA_DIR" -- "$DIR/installer/run/main.sh" main
  if [ "$WITH_EXTRA" = 1 ]; then
    hs_service "$APP-extra" --user "$SVC_USER" --after "$APP" --env EXTRA_TAG=x1 -- "$DIR/installer/run/main.sh" extra
    hs_start "$APP" "$APP-extra"
  else
    hs_start "$APP"
  fi
  hs_prune
}

app_uninstall() {
  hs_remove_all
}

app_purge() {
  hs_user_remove "$SVC_USER"
}
EOF
cat > "$SRC/installer/run/main.sh" <<'EOF'
#!/bin/sh
set -eu
set -a
# shellcheck source=/dev/null
. "$HS_CONF_FILE"
set +a
echo "started $1 ${EXTRA_TAG:-}"
while :; do
  printf '%s %s %s %s\n' "$GREETING" "$1" "$(pwd)" "${EXTRA_TAG:-}" > "$HS_DATA_DIR/$1.out"
  sleep "$INTERVAL"
done
EOF
chmod 755 "$SRC/installer/run/main.sh"
g add -A
g commit -qm init
sh "$SRC/installer/build-bootstrap.sh" refs/heads/main "$(g rev-parse HEAD)" "file://$SRC" > "$WORK/install.sh"

echo "--- 初期化: $INIT"

check "sync.sh が空のひな形の app.sh を置き換える" sh -c "
  T=\$(mktemp -d); mkdir -p \$T/installer
  printf '# shellcheck shell=sh disable=SC2154\n\napp_install() {\n  :\n}\n' > \$T/installer/app.sh
  sh '$ROOT/scripts/sync.sh' \$T >/dev/null && grep -q host-service.sh \$T/installer/app.sh; r=\$?; rm -rf \$T; exit \$r"
check "sync.sh が書き込み済みの app.sh を変えない" sh -c "
  T=\$(mktemp -d); mkdir -p \$T/installer/run
  printf 'app_install() {\n  echo x\n}\n' > \$T/installer/app.sh; echo x > \$T/installer/run/a.sh
  sh '$ROOT/scripts/sync.sh' \$T >/dev/null && grep -q 'echo x' \$T/installer/app.sh && test ! -e \$T/installer/run/main.sh; r=\$?; rm -rf \$T; exit \$r"

lib() {
  APP=$APP INSTALL_MODE=system DIR=$DIR CONF_FILE=$CONF DATA_DIR=$DATA sh -c '
    log() { :; }; warn() { :; }; die() { echo "$*" 1>&2; exit 1; }
    . "$0"; '"$1" "$ROOT/assets/core/installer/host-service.sh"
}
check_not "サービス名が $APP で始まらなければ止まる" lib 'hs_service other -- /bin/true'
check_not "コマンドが相対パスなら止まる" lib "hs_service $APP -- bin/true"
check_not "引数に空白や引用符があれば止まる" lib "hs_service $APP -- /bin/true 'a b'"
check_not "--env が KEY=VALUE でなければ止まる" lib "hs_service $APP --env novalue -- /bin/true"
check_not "hs_expect_port が範囲外を拒む" lib 'hs_expect_port P 70000'
check "hs_expect_one_of が候補を受け付ける" lib 'hs_expect_one_of K b a b c'
check_not "INSTALL_MODE=user なら止まる" sh -c "APP=$APP INSTALL_MODE=user sh -c 'die() { exit 1; }; . \"\$0\"; hs_init' '$ROOT/assets/core/installer/host-service.sh'"

echo "--- 導入前の検査"
install_sh install --set GREETING=hi --set INTERVAL=abc >/dev/null 2>&1 && ng "app_check で不正な値を拒む" || ok "app_check で不正な値を拒む"
check_not "拒んだときは設定ファイルを作らない" test -e "$CONF"

echo "--- 導入"
if install_sh install --set GREETING=hello > "$WORK/install1.log" 2>&1; then ok "install が成功する"; else ng "install が成功する"; cat "$WORK/install1.log"; fi
check "パッケージが導入される" command -v jq
check "ユーザーが作られる" id "$APP"
check "サービス定義が置かれる" test -f "$DEF_DIR/$APP$DEF_SUFFIX"
check "サービスが動いている" active "$APP"
check "ラッパーが設定を読み、作業ディレクトリで動く" wait_for out_is main "hello main $DATA "
check "サービスはアプリのユーザーで動く" sh -c "[ \"\$(stat -c %U '$DATA/main.out')\" = '$APP' ]"
check "設定ファイルはアプリのグループだけが読める（640）" sh -c "[ \"\$(stat -c %a:%G '$CONF')\" = '640:$APP' ]"
check "標準出力がログ（$INIT）へ出る" wait_for logged "$APP" "started main"
check "常設コマンドが置かれる" test -x "$CTL"

echo "--- 再適用"
pid1=$(wrapper_pids main)
check "install の再実行が成功する" install_sh install
check "再実行でサービスが再起動される" wait_for replaced main "$pid1"
check "二重に起動しない" wait_for running main

sed -i "s/^GREETING=.*/GREETING='bye'/" "$CONF"
check "手で編集した設定で install を再実行できる" install_sh install
check "編集した値がサービスに反映される" wait_for out_is main "bye main $DATA "

echo "--- 任意サービスの収束"
check "update --set WITH_EXTRA=1 が成功する" "$CTL" update --set WITH_EXTRA=1
check "追加のサービスが動く" wait_for out_is extra "bye extra $DIR x1"
check "追加のサービスの定義が置かれる" test -f "$DEF_DIR/$APP-extra$DEF_SUFFIX"
printf '%s\n' "[Unit]" "Description=foreign" > "$FOREIGN"
check "update --set WITH_EXTRA=0 が成功する" "$CTL" update --set WITH_EXTRA=0
check_not "外したサービスの定義が消える" test -e "$DEF_DIR/$APP-extra$DEF_SUFFIX"
check "外したサービスが止まる" wait_for stopped extra
check "このライブラリが作っていない同名の定義は消さない" test -f "$FOREIGN"

echo "--- 新しい版への更新"
sed -i 's/started \$1/booted $1/' "$SRC/installer/run/main.sh"
g commit -qam "ラッパーの変更"
check "新しいコミットへの update が成功する" "$CTL" update
check "新しい版のラッパーで動く" wait_for logged "$APP" "booted main"

echo "--- 自動再起動"
pid=$(wrapper_pids main)
[ -z "$pid" ] || kill -9 "$pid"
check "異常終了したサービスが再起動される" wait_for replaced main "$pid"

echo "--- 削除"
check "uninstall が成功する" "$CTL" uninstall
check_not "サービス定義が消える" test -e "$DEF_DIR/$APP$DEF_SUFFIX"
check "サービスが止まる" wait_for stopped main
check "uninstall ではユーザーを残す" id "$APP"
check "uninstall では設定・データを残す" sh -c "test -f '$CONF' && test -f '$DATA/main.out'"
check "このライブラリが作っていない同名の定義は消さない（uninstall）" test -f "$FOREIGN"
check "撤去済みのものを撤去しても失敗しない" lib "hs_remove_all && hs_remove $APP-extra && hs_user_remove $APP-none"

echo "--- 再導入と完全削除"
check "残った設定で再導入できる" install_sh install
check "再導入したサービスが動く" wait_for out_is main "bye main $DATA "
check "uninstall --purge が成功する" "$CTL" uninstall --purge
check_not "--purge でユーザーが消える" id "$APP"
check_not "--purge でグループが消える" grep -q "^$APP:" /etc/group
check_not "--purge で設定・データが消える" sh -c "test -e '/etc/${APP:?}' || test -e '$DATA'"
check_not "--purge でサービス定義が残らない" test -e "$DEF_DIR/$APP$DEF_SUFFIX"

[ "$FAIL" -eq 0 ] && echo "すべて成功" || { echo "失敗があります"; exit 1; }

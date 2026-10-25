#!/bin/sh
# 責務: 対象リポジトリへ、ホストのサービスとして動かすための共通ライブラリとアプリ側のひな形を配置する。
#       共通ライブラリ（assets/core）は毎回上書きする。アプリ側（assets/app）は無いときだけ置く。
#       ただし installer/app.sh が bootstrap-ci-builder の空のひな形のままなら、このスキルのひな形で置き換える。
#       起動ラッパーのひな形（installer/run/main.sh）は、installer/run/ が無いときだけ置く。
# 使い方: sh scripts/sync.sh <対象リポジトリのパス>
# 出力: 配置したファイルごとに「上書き」「作成」「置換」「既存のため変更なし」を1行ずつ出す。

set -eu

[ "$#" -eq 1 ] || { echo "使い方: sh $0 <対象リポジトリのパス>" 1>&2; exit 1; }
TARGET=$1
[ -d "$TARGET" ] || { echo "対象のディレクトリがありません: $TARGET" 1>&2; exit 1; }
ASSETS=$(CDPATH='' cd -- "$(dirname -- "$0")/../assets" && pwd)

# bootstrap-ci-builder が置く空の app.sh（フックが : だけのもの）か
is_placeholder() {
  [ -f "$1" ] || return 1
  [ "$(grep -v -e '^[[:space:]]*$' -e '^#' -e '^[[:space:]]*:[[:space:]]*$' -e '^}$' -e '^app_[a-z]*() {$' "$1" | wc -l)" -eq 0 ]
}

place() {
  _src=$1; _rel=$2; _mode=$3
  _dst="$TARGET/$_rel"
  mkdir -p "$(dirname -- "$_dst")"
  if [ "$_mode" = core ]; then
    if [ -f "$_dst" ] && cmp -s "$_src" "$_dst"; then
      echo "変更なし: $_rel"
    elif [ -f "$_dst" ]; then
      cp "$_src" "$_dst"; echo "上書き:   $_rel"
    else
      cp "$_src" "$_dst"; echo "作成:     $_rel"
    fi
    return 0
  fi
  case "$_rel" in
    installer/run/*)
      if [ -d "$TARGET/installer/run" ] && [ ! -e "$_dst" ] && [ -n "$(ls -A "$TARGET/installer/run")" ]; then
        echo "既存のため変更なし: installer/run/"
        return 0
      fi
      ;;
  esac
  if [ "$_rel" = installer/app.sh ] && is_placeholder "$_dst"; then
    cp "$_src" "$_dst"; echo "置換:     $_rel（空のひな形だったため）"
  elif [ -e "$_dst" ]; then
    echo "既存のため変更なし: $_rel"
  else
    cp "$_src" "$_dst"; echo "作成:     $_rel"
  fi
}

for _mode in core app; do
  (cd "$ASSETS/$_mode" && find . -type f | sed 's|^\./||' | sort) | while IFS= read -r _rel; do
    place "$ASSETS/$_mode/$_rel" "$_rel" "$_mode"
  done
done

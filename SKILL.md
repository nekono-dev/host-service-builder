---
name: host-service-builder
description: Docker（docker-compose.yaml・Dockerfile）で動いているアプリを、コンテナを使わずにホストのサービス（Debian 系・Ubuntu＋systemd、Alpine＋OpenRC）として動かせるようにする。bootstrap-ci-builder のインストーラの上に、installer/app.sh のフック（パッケージ導入・専用ユーザー・サービス定義・起動・撤去）、起動ラッパー（installer/run/*.sh）、OS 差を吸収する共通ライブラリ（installer/host-service.sh）を整備し、Docker 版と環境変数・ポート・データの置き場を揃える。「Docker なしで動かしたい」「LXC や VM に直接入れたい」「systemd のサービスにしたい」「OpenRC で常駐させたい」「compose をホストのサービスに変換」「Alpine でも Debian でも動くインストーラ」「app.sh を整備・作り直したい」といった依頼や、installer/host-service.sh を持つリポジトリの app.sh・ラッパーを直す・このスキルの新しい版へ追従させるときに使う。Docker を使わない導入の話が出たら、install.sh の頒布の仕組み（bootstrap-ci-builder）と合わせてこのスキルを使う。
---

# ホストサービス化（Docker 構成からの変換）

Docker で動いているアプリを、同じリポジトリのままホストのサービスとしても動かせるようにする。Docker 版（compose・Dockerfile）は残し、ホスト版を足す。

役割の分担:

- **bootstrap-ci-builder**（別スキル）: `install.sh` の頒布、取得・更新・`--ref` の切り替え、設定ファイル、uninstall。`installer/main.sh` などのコア。
- **このスキル**: そのフック（`installer/app.sh`）の中身と、起動ラッパー、OS 差を吸収する共通ライブラリ。単独のインストーラは作らない。

```
install.sh → main.sh（bootstrap-ci-builder のコア）
               ├ app_check   … hs_init（OS 判定）・値の検査（hs_expect_*）
               ├ app_install … hs_pkg → hs_user → hs_dir → ビルド → hs_service → hs_start → hs_prune
               ├ app_uninstall … hs_remove_all
               └ app_purge   … hs_user_remove
                     ▲ installer/host-service.sh（このスキルのコア。systemd / OpenRC・apt / apk の差を吸収）
サービス定義 → installer/run/<名前>.sh（起動ラッパー。設定を読んで exec）→ アプリ
```

## ファイル構成

| 区分 | ファイル | 内容 |
|---|---|---|
| コア（編集しない） | `installer/host-service.sh` | OS・init の判定、パッケージ、ユーザー、サービス定義の生成・起動・撤去・収束、値の検査 |
| アプリ側（プロジェクトが書く） | `installer/app.sh` | フック。ライブラリの関数を呼ぶ |
| | `installer/run/<名前>.sh` | 起動ラッパー。サービスごとに1つ |
| | `installer/config.schema` | 設定キー（bootstrap-ci-builder の書式）。compose の `environment:` から作る |
| | README の「Docker 版とホスト版の対応」 | 環境変数・ポート・データ・ログ・依存・実行ユーザーの対応表 |

コアを編集しないのは、`scripts/sync.sh` で上書きするだけでこのスキルの更新に追従できるようにするためである。足りない機能・不具合は、利用先ではなくこのスキルの `assets/core/installer/host-service.sh` を直し、`tests/e2e.sh` を systemd・OpenRC の両方で通してから配る。直すときは特定のアプリに寄せず、どのアプリでも使える形にする。

関数の一覧と生成される定義は [references/library.md](references/library.md) にある。`app.sh` を書く前に読む。

## 着手前に確認する事項

まず Docker の構成（compose ファイルすべてと各 Dockerfile）と、既存の `installer/` を読む。読み替え方は [references/docker-mapping.md](references/docker-mapping.md)。

読み取れない部分は、docker-mapping.md の「自動で決めることと、確認すること」の既定で決める（実行ユーザーはアプリ名の専用ユーザー、データは `$DATA_DIR`、ログは標準出力のまま journald／syslog、ビルドは Dockerfile の `RUN` の順）。決めた内容は対応表に書いて示す。次のものだけは推測で進めず、実装の前にユーザーへ確認する。

1. **対象 OS**。Debian 系・Alpine の両方か、片方か。特定の版だけか（`hs_supported`）。
2. **曖昧な点**。root が要りそうな処理、OS のパッケージで揃わないランタイムの版、Docker API など Docker の機能への依存、大きなビルド、`--purge` で消してはいけないデータ。
3. bootstrap-ci-builder の「着手前に確認する事項」のうち未確定のもの（アプリ名、秘匿値、頒布前の検査）。導入方式は `system` に限る（サービスの登録に root が要る）。

## 作業手順

1. 配置する。先にこのスキル、次に bootstrap-ci-builder の順に実行する（このスキルの `app.sh` のひな形が先に置かれる。bootstrap-ci-builder の空のひな形が既にあれば、このスキルの `sync.sh` が置き換える）。
   ```sh
   sh <このスキル>/scripts/sync.sh <対象リポジトリ>
   sh <bootstrap-ci-builder>/scripts/sync.sh <対象リポジトリ>
   ```
2. `installer/app.conf`（`APP_NAME`・`INSTALL_MODE='system'`）と `installer/config.schema` を書く。キーは compose の `environment:` の名前のままにする（docker-mapping.md）。
3. `installer/app.sh` を書く（下記）。
4. 起動ラッパー `installer/run/<名前>.sh` を書き、実行権限を付ける（`chmod 755`、git にもその権限で入れる）。
5. `.github/workflows/installer-check.yml` に、起動ラッパーの構文検査・shellcheck と、プロジェクトのテストを書く。
6. Docker 版と食い違いが無いか見直す。compose・Dockerfile の側で直すべき点（ホスト名の決め打ちなど）があれば、Docker 版の動作を変えない範囲で直す。
7. 検証する（[references/verification.md](references/verification.md)）。対象 OS ごとに、実際の init が動く使い捨ての環境で導入・更新・削除まで通す。
8. README に導入手順（bootstrap-ci-builder の spec.md「README に書くこと」）と「Docker 版とホスト版の対応」の表、ログの見方を書く。

## app.sh の形

ひな形は `assets/app/installer/app.sh`。複数サービス・依存サービス・任意の構成を持つ形は次のとおり。

```sh
# shellcheck shell=sh disable=SC2154
# shellcheck source=/dev/null
. "$SCRIPT_DIR/host-service.sh"

SVC_USER=$APP

app_check() {
  hs_init
  hs_expect_port API_PORT "$(config_value API_PORT)"
  hs_expect_bool WITH_WORKER "$(config_value WITH_WORKER)"
}

app_install() {
  hs_init
  # shellcheck source=/dev/null
  . "$CONF_FILE"
  case "$HS_OS" in
    debian) hs_pkg python3 python3-venv redis-server; REDIS=redis-server ;;
    alpine) hs_pkg python3 redis; REDIS=redis ;;
  esac
  hs_ensure "$REDIS"
  hs_user "$SVC_USER"
  hs_dir "$DATA_DIR" "$SVC_USER" 750
  [ -x "$DIR/venv/bin/python3" ] || python3 -m venv "$DIR/venv"
  "$DIR/venv/bin/pip" install -q --no-cache-dir -r "$DIR/requirements.txt"
  hs_service "$APP-api" --description "$APP API" --user "$SVC_USER" --requires "$REDIS" -- "$DIR/installer/run/api.sh"
  hs_start "$APP-api"
  if [ "$WITH_WORKER" = 1 ]; then
    hs_service "$APP-worker" --user "$SVC_USER" --requires "$REDIS" --after "$APP-api" -- "$DIR/installer/run/worker.sh"
    hs_start "$APP-worker"
  fi
  hs_prune
  log "ログ: $(hs_logs "$APP-api")"
}

app_uninstall() {
  hs_remove_all
}

app_purge() {
  hs_user_remove "$SVC_USER"
}
```

要点と理由:

- **値の検査は `app_check` に置く。** `app_install` で止めると、不正な値が設定ファイルに書き込まれた後になる。`app_check` では値を `config_value KEY` で読む（設定ファイルはまだ古い）。
- **`app_install` は何度実行しても同じ結果にする。** update のたびに新しい版で呼ばれる。`hs_pkg`・`hs_user`・`hs_service` は済んでいれば何もしない。時間のかかるビルドは、入力が変わらなければ省く判定を入れる（版の記録ファイル、ロックファイルの比較など）。
- **自分のサービスは毎回 `hs_start`（再起動）する。** 新しいコード・設定で動かし直すため。パッケージのサービスは `hs_ensure` にし、その設定を書き換えたときだけ再起動する。
- **最後に `hs_prune` を呼ぶ。** 設定で外したサービスや、新しい版で無くなったサービスが残らない。外す側の処理を個別に書かずに済む。
- **`app_uninstall` は `hs_remove_all` と、`$DIR` の外に置いた物の片付けだけ。** 無くても失敗しないこと。パッケージとそのサービスは他のアプリも使い得るので残す。
- `$DIR`（取得先）に venv・`node_modules`・ビルド成果物を置いてよい。git の追跡外のファイルは update でも残る。追跡しているファイルは書き換えない（update が未コミットの変更として止まる）。書き換えた写しが要るなら `$DIR` の外か、追跡外のパスに置く。

## 起動ラッパーの形

ひな形は `assets/app/installer/run/main.sh`。

```sh
#!/bin/sh
set -eu
set -a
# shellcheck source=/dev/null
. "$HS_CONF_FILE"
set +a
export DB_PATH="$HS_DATA_DIR/app.db" REDIS_URL='redis://127.0.0.1:6379'
cd "$HS_DIR/src"
exec "$HS_DIR/venv/bin/python3" -u main.py
```

- 設定キーを Docker 版の環境変数と同じ名前にしておけば、`set -a` で読むだけでアプリに渡る。名前が違うもの・固定値・パスの読み替え（Docker のボリューム → `$HS_DATA_DIR`、サービス名のホスト → `127.0.0.1`）は `export` で書く。
- 最後は `exec` にする。監視（systemd・supervise-daemon）がアプリのプロセスを直接扱えるようにするため（停止のシグナルが届く、終了が検知される）。
- 標準出力・標準エラーへ書かせる。それがそのまま journald／syslog に入る。
- 使える変数は `HS_APP`・`HS_DIR`・`HS_CONF_FILE`・`HS_DATA_DIR`（library.md）。設定ファイルのパスを決め打ちしない。

## 書き方の決まり

- `app.sh`・ラッパー・ライブラリは利用者に頒布される。コメントやアプリ固有の説明を入れない（shellcheck の指示行は残す）。説明は README と、`config.schema` の1行説明に書く。
- `/bin/sh` は dash（Debian 系）か busybox ash（Alpine）。POSIX sh の範囲で書く。
- 秘匿値（トークン・パスワード）は設定キー（`required`）にする。端末から入力させない（`curl | sh` や `<アプリ名>-ctl update` から非対話で動かすため）。`hs_service --env` にも書かない（定義ファイルは誰でも読める）。設定ファイルは実行ユーザーのグループだけが読める（640）。
- 生成物に「このスキルのテンプレートから作った」といった自己言及を残さない。

## 既存の app.sh があるリポジトリ

- `installer/host-service.sh` があるなら、`scripts/sync.sh` で上書きし、`git diff` で差分を確かめる。関数の使い方が変わっていれば `app.sh` を合わせる。
- ライブラリを使わずに OS 差を直接書いた `app.sh`（`systemctl`・`rc-service`・`apt-get` を直に呼ぶ形、unit のひな形を `sed` で埋める形）なら、上の形へ作り直す。手順は次のとおり。
  1. 今の `app.sh` が行っていること（パッケージ・ユーザー・ディレクトリ・ビルド・サービス・任意の構成・削除の範囲）を一覧にする。プロジェクトの受け入れテストがあれば、その観点も拾う。
  2. ライブラリの関数に置き換えられるものは置き換え、unit のひな形（`installer/units/` など）は `hs_service` のオプションにして消す。置き換えられないアプリ固有の処理（ビルド、アプリの設定ファイルの生成）は `app.sh` に残す。
  3. 値の検査を `app_check` へ移す。
  4. 導入先のパス・サービス名・設定キーは変えない（導入済みの環境が `update` でそのまま移れるように）。変えるなら、その影響をユーザーに確認する。
  5. 受け入れテストと verification.md の観点で、作り直す前と同じ動作になることを確かめる。

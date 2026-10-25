# 共通ライブラリ（installer/host-service.sh）

`app.sh` の先頭で `. "$SCRIPT_DIR/host-service.sh"` として読み込み、フックの中から呼ぶ。bootstrap-ci-builder のコアと同じ扱いで、利用先では編集しない（`scripts/sync.sh` で上書きされる）。足りない機能があれば、このスキルの `assets/core/installer/host-service.sh` を直し、`tests/e2e.sh` を systemd・OpenRC の両方で通してから配る。

## 目次

- 前提と変数
- OS の判定
- パッケージ・ユーザー・ディレクトリ
- サービスの定義
- 起動・撤去・収束
- 値の検査（app_check 用）
- 生成されるサービス定義
- 起動ラッパーに渡る環境変数

## 前提と変数

- `INSTALL_MODE='system'`（root で導入）であること。`user` 方式ではサービスを登録できないので、`hs_init` が止める。
- コアが用意する `$APP` `$DIR` `$CONF_FILE` `$DATA_DIR` と、`log` `warn` `die` を使う。
- ライブラリの内部変数は `_hs_` で始まる。`app.sh` の変数をこの名前にしない。
- `hs_init` の後に使える変数:

| 変数 | 値 |
|---|---|
| `HS_OS` | `debian`（Ubuntu・Debian とその派生）か `alpine` |
| `HS_INIT` | `systemd` か `openrc`（実際に動いているもので判定する） |
| `HS_OS_ID` `HS_OS_VERSION` | `/etc/os-release` の `ID`・`VERSION_ID`（例 `ubuntu` `24.04`） |

## OS の判定

| 関数 | 内容 |
|---|---|
| `hs_init` | OS と init を判定する。2回目以降は何もしない。他の関数も最初に呼ぶので、明示するのは `$HS_OS` を参照する前だけでよい。`app_check` で呼ぶと、未対応の環境では設定を書く前に止まる |
| `hs_supported ID[:VERSION] …` | いずれにも一致しなければ止まる。例 `hs_supported ubuntu:24.04`、`hs_supported debian ubuntu alpine` |

## パッケージ・ユーザー・ディレクトリ

| 関数 | 内容 |
|---|---|
| `hs_pkg PKG …` | 未導入のものがあるときだけ導入する。Debian 系は `apt-get update`（1回の実行で1度だけ）と `apt-get install --no-install-recommends`、Alpine は `apk add --no-cache`。名前は OS ごとに違うので、呼び出し側で `case "$HS_OS"` で書き分ける |
| `hs_user NAME [HOME]` | システムユーザーと同名のグループを作る（ログイン不可・ホームは作らない。既定のホームは `$DATA_DIR`）。既にあれば何もしない。`root` なら何もしない |
| `hs_user_remove NAME` | ユーザーとグループを消す。無くても失敗しない。`app_purge` で使う |
| `hs_dir PATH [OWNER] [MODE]` | ディレクトリを作り、所有者（`OWNER:OWNER`、既定 root）と権限を毎回そろえる |

## サービスの定義

```sh
hs_service NAME [オプション …] -- COMMAND [ARG …]
```

- `NAME` は `$APP` か `$APP-<名前>`。撤去・収束はこの名前の範囲だけを対象にする。
- `COMMAND` は実行できる絶対パス（通常は `$DIR/installer/run/<名前>.sh`）。引数とパスに使えるのは英数字と `_ . / : = @ + , -` だけ（systemd と OpenRC の両方で同じ意味になる範囲）。込み入った引数は起動ラッパーの中で組み立てる。
- 定義の内容が前回と同じなら書き換えない（systemd の `daemon-reload` も省く）。起動はしないので、続けて `hs_start` を呼ぶ。
- `--user` が root 以外なら、`$CONF_FILE` をそのグループで読めるようにする（640）。ラッパーが設定を読むために要る。1つのアプリで root 以外の実行ユーザーは1つにする。

| オプション | 内容 | systemd | OpenRC |
|---|---|---|---|
| `--description TEXT` | 説明（既定は NAME）。`" $ \` \ %` と改行は不可 | `Description=` | `description=` |
| `--user USER` | 実行ユーザー（既定 root）。先に `hs_user` で作る | `User=` `Group=` | `command_user=` |
| `--dir PATH` | 作業ディレクトリ（既定 `$DIR`） | `WorkingDirectory=` | `directory=` |
| `--requires SVC` | 必須の依存（繰り返し可）。止まると一緒に止まる | `Requires=` `After=` | `need` |
| `--wants SVC` | 任意の依存（繰り返し可） | `Wants=` `After=` | `use` |
| `--after SVC` | 起動順だけ（繰り返し可） | `After=` | `after` |
| `--env KEY=VALUE` | 追加の環境変数（繰り返し可）。秘匿値は渡さない（定義ファイルは誰でも読める） | `Environment=` | `--env` |
| `--systemd LINE` | systemd の `[Service]` に足す1行（例 `LimitNOFILE=65536`）。OpenRC では無視 | そのまま | — |
| `--openrc LINE` | OpenRC の init スクリプトに足す1行（例 `rc_ulimit="-n 65536"`）。systemd では無視 | — | そのまま |

依存先 `SVC` は、OS のパッケージが入れるサービス名（例 Debian 系 `redis-server`、Alpine `redis`）か、同じアプリの別のサービス名。名前が OS で違うものは変数に入れて渡す。

## 起動・撤去・収束

| 関数 | 内容 |
|---|---|
| `hs_start SVC …` | 有効化して再起動する（止まっていれば起動）。`install`・`update` のたびに新しい版で動かし直すため、自分のサービスにはこれを使う。起動できなければ、ログの見方を添えて止まる |
| `hs_ensure SVC …` | 有効化し、止まっていれば起動する（動いていれば再起動しない）。パッケージのサービス（Redis・PostgreSQL など）に使う。その設定を変えたときだけ `hs_start` で再起動する |
| `hs_remove SVC …` | 停止・無効化して定義を消す。このライブラリが作った定義だけを対象にし、無くても失敗しない |
| `hs_prune` | この実行で `hs_service` しなかった `$APP`・`$APP-*` の定義を撤去する。`app_install` の最後に呼ぶと、設定で外したサービスや、新しい版で無くなったサービスが残らない |
| `hs_remove_all` | このライブラリが作った `$APP`・`$APP-*` の定義をすべて撤去する。`app_uninstall` で使う |
| `hs_logs SVC` | ログの見方を返す（systemd: `journalctl -u SVC`、OpenRC: syslog の `/var/log/messages`）。案内の表示に使う |

「このライブラリが作った定義」は、systemd の unit の `X-HostService=<アプリ名>` 行、OpenRC の init スクリプトの `hs_app="<アプリ名>"` 行で見分ける。同じ名前の手書きの定義やパッケージの定義は撤去しない。

## 値の検査（app_check 用）

`app_check` では `config_value KEY` で値を取り、次の関数に「キー名・値」を渡す。不正なら `die` するので、設定ファイルは書き換わらない。

| 関数 | 合格する値 |
|---|---|
| `hs_expect_int KEY VALUE [MIN [MAX]]` | 0 以上の整数（範囲つき） |
| `hs_expect_port KEY VALUE` | 1〜65535 |
| `hs_expect_bool KEY VALUE` | `0` か `1` |
| `hs_expect_one_of KEY VALUE 候補 …` | 候補のどれか |
| `hs_expect_abs_path KEY VALUE` | `/` で始まるパス |

これで足りない検査（`所有者/リポジトリ` の形、他のキーとの組み合わせなど）は `app.sh` に `case` で書く。

## 生成されるサービス定義

| | systemd | OpenRC |
|---|---|---|
| 置き場所 | `/etc/systemd/system/<NAME>.service` | `/etc/init.d/<NAME>` |
| 監視 | `Restart=always`・`RestartSec=3` | `supervise-daemon`・`respawn_delay=3`・`respawn_max=0`（無制限） |
| ログ | journald（`SyslogIdentifier=<NAME>`）。`journalctl -u <NAME>` | `logger -t <NAME>` で syslog へ（標準出力は `daemon.info`、標準エラーは `daemon.err`）。Alpine の既定では `/var/log/messages` |
| 自動起動 | `WantedBy=multi-user.target`（`hs_start` が enable） | `default` ランレベル（`hs_start` が `rc-update add`） |
| ネットワーク | `After=`・`Wants=network-online.target` | `use net` |

ログはどちらも、アプリが標準出力・標準エラーへ書いたものをそのまま集める。アプリが自前でログファイルを書く設定なら、標準出力へ書く設定に変える（Docker 版も標準出力へ出していることが多い）。

## 起動ラッパーに渡る環境変数

サービス定義は、起動ラッパーに次の4つを渡す。ラッパーはこれだけを頼りに設定を読み、アプリを `exec` する。

| 変数 | 値 |
|---|---|
| `HS_APP` | アプリ名 |
| `HS_DIR` | 取得先（`/opt/<アプリ名>`） |
| `HS_CONF_FILE` | 設定ファイル（`/etc/<アプリ名>/<アプリ名>.env`） |
| `HS_DATA_DIR` | データディレクトリ（`/var/lib/<アプリ名>`） |

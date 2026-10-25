# Alpine ＋ OpenRC

## パッケージ

`hs_pkg` は `apk add --no-cache` で入れる。

| 用途 | パッケージ | 備考 |
|---|---|---|
| Python | `python3` | venv は `python3` だけで作れる。Docker 版で `py3-pip` を入れていても、venv の中の pip を使えば要らない |
| Node.js | `nodejs npm` | Alpine 3.22 は 22 系 |
| ビルド | `build-base` | C 拡張のビルドなど。Python の C 拡張には `python3-dev` も要ることがある |
| タイムゾーン | `tzdata` | busybox は `TZ=Asia/Tokyo` の形を `tzdata` なしでは解釈できない |
| 証明書 | `ca-certificates` | |
| Redis | `redis` | サービス名 `redis`（Debian 系と違う）。設定 `/etc/redis.conf` |
| PostgreSQL | `postgresql17` など版つき | `postgresql` は別物（bdr）なので版つきの名前を使う |
| SQLite の CLI | `sqlite` | |
| ffmpeg | `ffmpeg` | |

musl なので、glibc 向けの配布バイナリ（Playwright のブラウザなど）は動かないことが多い。そうした依存があるアプリは、Alpine に対応させるかを確認する。

## ユーザー

`hs_user` は busybox の `addgroup -S`・`adduser -S -D -H -s /sbin/nologin -G` で作る。`hs_user_remove` は `deluser` と `delgroup`。

## サービス

- 定義は `/etc/init.d/<名前>`（`#!/sbin/openrc-run`）。`supervise-daemon` が監視し、落ちたら3秒後に起動し直す（回数の上限なし）。
- `hs_start` が `rc-update add <名前> default` と `rc-service <名前> restart` を行う。
- init スクリプトの変数（`export` など）は、`supervise-daemon` が起動するプロセスへは渡らない。環境変数は `supervise_daemon_args` の `--env` で渡す（ライブラリが `HS_*` と `--env` の値をここに書く）。
- ログは `logger -t <名前>` で syslog へ送る。Alpine の既定の syslog（busybox `syslogd`、`boot` ランレベル）は `/var/log/messages` に書く。`grep <名前> /var/log/messages`、追うなら `tail -f /var/log/messages | grep <名前>`。
- `rc-service <名前> status`・`rc-status` で状態を見る。

## 確かめるときの注意

- `/bin/sh` は busybox の ash。`ps` は `-e` を受け付けない（`ps -o pid,args` を使う）。コマンド行の先頭に `{スクリプト名}` が付く。
- `sed -i`・`stat -c`・`mktemp -d` は busybox でも使える。`getent` は無いことがあるので、グループの有無は `/etc/group` を見る。
- LXC のイメージは `images:alpine/3.22`。コンテナ（Docker）で OpenRC を試すときは、PID 1 が終了したプロセスを回収しないと停止が終わらなくなるので `docker run --init` にし、`/etc/rc.conf` の `rc_sys="docker"` と `/run/openrc/softlevel` を用意する（`.github/workflows/test.yml` の `e2e-openrc` の手順）。

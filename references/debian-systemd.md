# Debian 系（Ubuntu・Debian）＋ systemd

## パッケージ

`hs_pkg` は `apt-get install -y --no-install-recommends` で入れる。推奨パッケージに頼るもの（フォント・証明書など）は明示する。

| 用途 | パッケージ | 備考 |
|---|---|---|
| Python | `python3 python3-venv` | venv に `python3-venv` が要る（最小構成のイメージには `python3` も無い）。pip は venv の中のものを使う |
| Node.js | `nodejs npm` | 版はディストリ次第（Debian 13 は 20 系、Ubuntu 24.04 は 18 系）。足りなければ NodeSource などの外部リポジトリを足すか確認する |
| ビルド | `build-essential` | C 拡張のビルドなど |
| タイムゾーン | `tzdata` | `TZ` を使うアプリ |
| 証明書 | `ca-certificates` | HTTPS で外部へつなぐアプリ |
| Redis | `redis-server` | サービス名 `redis-server`。設定 `/etc/redis/redis.conf`（既定で 127.0.0.1 待ち受け） |
| PostgreSQL | `postgresql` | サービス名 `postgresql` |
| SQLite の CLI | `sqlite3` | |
| ffmpeg | `ffmpeg` | |

Ubuntu と Debian で版が違うだけで名前は同じことが多い。特定の版が要るなら `hs_supported ubuntu:24.04` のように絞る。

## ユーザー

`hs_user` は `useradd --system --user-group --no-create-home --shell /usr/sbin/nologin` で作る。`hs_user_remove` は `userdel`（同名のグループも消える）。

## サービス

- 定義は `/etc/systemd/system/<名前>.service`。`hs_start` が `daemon-reload`（定義が変わったときだけ）・`enable`・`reset-failed`・`restart` を行う。
- 設定は起動ラッパーが `HS_CONF_FILE` から読む。systemd の `EnvironmentFile=` は使わない（OpenRC と同じラッパーで動かすため）。
- `systemctl status <名前>`・`journalctl -u <名前> -f` で状態とログを見る。
- `Restart=always` なので、起動直後に落ちるアプリは再起動を繰り返す（`systemctl status` が `activating (auto-restart)` になる）。導入は成功するので、検証ではサービスが `active` で留まることまで確かめる。

## 確かめるときの注意

- `/bin/sh` は dash。bash 固有の書き方（`[[ ]]`・配列・`local` 以外の拡張）は `app.sh`・ラッパーで使わない。
- LXC の Ubuntu では cloud-init の終了を待ってから `apt-get` する（`cloud-init status --wait`）。

# 検証の進め方

ライブラリの動作（定義の生成・起動・撤去・収束・自動再起動・ログの行き先）は、このスキルの `tests/e2e.sh` で systemd・OpenRC の両方について確かめてある。利用先で確かめるのは、**アプリが実際にホストのサービスとして動くこと**と、**対応表どおりに Docker 版と揃っていること**である。

bootstrap-ci-builder の `references/verification.md`（生成と静的検査、導入・冪等性・設定の反映・更新・削除・完全削除・再導入の各観点）を基本にし、ここでは追加の観点だけを書く。

## 1. 静的検査

```sh
sh installer/build-bootstrap.sh refs/heads/main "$(git rev-parse HEAD)" "file://$PWD" > /tmp/install.sh
for f in installer/*.sh installer/run/*.sh /tmp/install.sh; do sh -n "$f"; done
shellcheck -S warning installer/*.sh installer/run/*.sh /tmp/install.sh
```

起動ラッパーは、bootstrap-ci-builder の `release-installer.yml` の検査（`installer/*.sh`）に入らない。`installer-check.yml` に同じ検査を足す。

## 2. 使い捨ての環境で導入する

対象 OS ごとに、実際の init が動く環境で行う。LXC（LXD）が使えるなら、OS ごとにコンテナを作る。

| 対象 | イメージの例 |
|---|---|
| Ubuntu | `ubuntu:24.04` |
| Debian | `images:debian/13` |
| Alpine | `images:alpine/3.22` |

- 手元の未 push のコミットを試すときは、リポジトリをコンテナへコピーし、そこで `build-bootstrap.sh` を `file://` の取得元で実行する。
- 検証のスクリプトは、ファイルとして置いて実行する。`ssh … 'bash -s' < script` のように標準入力で送ると、中の `lxc launch` が標準入力を設定（YAML）として読んでしまう。`lxc launch … </dev/null` とするか、scp で置く。

## 3. 追加で確かめること

| 観点 | 確かめ方 |
|---|---|
| 起動して留まる | `install` の直後だけでなく、数十秒後も `systemctl is-active <名前>`／`rc-service <名前> status` が動作中。起動直後に落ちて再起動を繰り返していないか、ログで確かめる |
| アプリとして動く | Docker 版の `HEALTHCHECK` やテストと同じ確かめ方（HTTP の応答、ボットのログイン成功のログなど）。外部の資格情報が要るなら、偽の値で「設定を読んで外部へつなぎに行く」ところまでをログで確かめる |
| 実行ユーザー | `ps -o user,args` でアプリのユーザーで動いている。データディレクトリに書けている |
| 設定の読み込み | 設定ファイルの値を変えて `install` を再実行すると、アプリの挙動に反映される |
| ログ | systemd は `journalctl -u <名前>`、OpenRC は `/var/log/messages` にアプリの出力が出る |
| 依存サービス | パッケージのサービス（Redis など）が有効化・起動され、127.0.0.1 だけで待ち受けている |
| 任意の構成 | `WITH_*` を 1→0 にして `update` すると、そのサービスの定義が消えてプロセスが止まる |
| 自動再起動 | アプリのプロセスを `kill -9` すると、数秒で起動し直す |
| 削除 | `uninstall` でサービスの定義とプロセスが消え、ユーザー・設定・データが残る。`--purge` でユーザーも消える。パッケージのサービスは残る |
| Docker 版との対応 | 対応表のキー名・既定値・ポートが、compose の `environment:`・`ports:` と一致している |

## 4. CI

利用先の CI では、`installer-check.yml` で起動ラッパーの検査とアプリのテストを通す。実機での導入は CI では行わず（init と root が要るため）、上の手順で確かめた結果を報告する。プロジェクトに LXC での受け入れテスト（`tests/installer/e2e.sh` など）があれば、それを通す。

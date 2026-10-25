# Docker の構成からホストのサービスへの読み替え

`docker-compose.yaml`（`compose.yaml`・`docker-compose.*.yml` を含む）と各 `Dockerfile` を読み、ホストでの導入手順・サービス定義・起動ラッパー・設定キーへ読み替える。Docker 版は残すので、読み替えた結果は「Docker 版とホスト版の対応表」（下記）にまとめ、両者の環境変数・ポート・データの置き場を揃える。

## 目次

- Dockerfile の命令
- compose の項目
- image だけのサービス（Redis・PostgreSQL など）
- 自動で決めることと、確認すること
- Docker 版とホスト版の対応表

## Dockerfile の命令

| 命令 | ホストでの扱い |
|---|---|
| `FROM <ディストリ>` | 対象 OS の手がかり。`alpine` なら Alpine＋OpenRC と Debian 系の両方、`debian`・`ubuntu`・`python:*-slim` などなら Debian 系を既定にする。どちらに対応させるかは依頼に従う |
| `FROM python:3.x` などの言語イメージ | OS のパッケージ（`python3`）で足りるか確かめる。ディストリの版が要件に届かなければ確認する（下記） |
| `RUN apk add` / `apt-get install` | `hs_pkg` に読み替える。ビルドにだけ要るもの（`build-base`・`gcc` など）も、ホストでは同じ環境でビルドするので入れる。名前は OS ごとに対応させる（[debian-systemd.md](debian-systemd.md)・[alpine-openrc.md](alpine-openrc.md)） |
| `RUN pip install -r …` | `$DIR/venv` に venv を作って入れる（システムの Python を汚さない。Alpine・新しい Debian では `--break-system-packages` が要らなくなる）。`[ -x "$DIR/venv/bin/python3" ] \|\| python3 -m venv "$DIR/venv"` の後に `pip install -q --no-cache-dir -r` |
| `RUN npm ci` / `npm install` | `$DIR` の該当ディレクトリで実行する。Node.js の版が OS のパッケージで足りなければ確認する |
| その他の `RUN`（ビルド・生成） | `app_install` で同じことをする。時間のかかるビルドは、入力（版・ロックファイルのハッシュ）が変わらなければ省く判定を入れる |
| `COPY` / `ADD`（ソース） | 写さない。`$DIR` が取得先（git の作業ツリー）なので、そこから直接使う |
| `WORKDIR` | ラッパーの `cd`（`hs_service --dir` でもよい）。パスは `/workspace` などから `$HS_DIR/…` に読み替える |
| `ENV KEY=VALUE` | 利用者が変えるものなら設定キー、固定ならラッパーの `export`。パス（`/workspace/data/…`）は `$HS_DATA_DIR/…` に読み替える |
| `VOLUME` | `$DATA_DIR` の下へ（`hs_dir "$DATA_DIR" "$SVC_USER" 750`）。`--purge` で消える |
| `EXPOSE` | 待ち受けポート。アプリが環境変数でポートを変えられるなら設定キーにする |
| `USER` | 実行ユーザー。無ければ、アプリ名の専用ユーザーを既定にする（`hs_user "$APP"`） |
| `ENTRYPOINT` / `CMD` | ラッパーの最後の `exec`。`python3 -u` のように標準出力をバッファしない指定は残す（ログが遅れないように） |
| `HEALTHCHECK` | 定義には入れない。検証の手順（起動後に叩く URL など）として使う |

多段ビルド（`FROM … AS build` から成果物だけを写す）は、ホストでは同じ場所でビルドして成果物を使う。ビルドの道具を入れたままでよいか、ビルド後に消すかは確認する。

## compose の項目

| 項目 | ホストでの扱い |
|---|---|
| `services.<名前>`（`build:`） | `hs_service`。1つだけなら名前は `$APP`、複数なら `$APP-<名前>` |
| `environment:` | 設定キーの候補。`${VAR}`（既定なし）は `required`、`${VAR:-x}` は既定 `x` の `optional`、固定値はラッパーの `export`（利用者が変えたいものなら設定キー） |
| `env_file:` | 中身のキーを同じように設定キーへ |
| `ports:` | 待ち受けポート。ホスト側の番号を既定値にする。コンテナ間だけで使うポート（公開していないもの）は 127.0.0.1 で待ち受けさせる |
| `volumes:`（名前付き） | `$DATA_DIR/<名前>`（アプリのデータ）。バインドマウント（`./cookies:/cookies`・`/mnt:/download`）は、利用者が場所を選ぶものなら絶対パスの設定キーにする |
| `depends_on:` | `hs_service --requires`（起動順だけなら `--after`） |
| サービス名でのホスト指定（`redis://redis`・`http://api:5000`） | `127.0.0.1` と実際のポートに読み替える。値が設定ファイル由来ならラッパーで、アプリの設定ファイルなら `app_install` で書き換えた写しを置く |
| `restart:` | ライブラリが常に自動再起動する |
| `command:` | ラッパーの `exec` の引数 |
| `user:` | 実行ユーザー |
| `shm_size:`・`ulimits:` など | `--systemd`・`--openrc` の行で足す。対応する指定が無いものは確認する |
| 複数の compose ファイル（`docker-compose.nginx.yml` など） | 追加の構成は `WITH_<名前>`（`0`/`1`）の設定キーにし、`0` なら `hs_service` せず `hs_prune` で撤去させる |

## image だけのサービス（Redis・PostgreSQL など）

ビルドせずに公開イメージを使うサービスは、OS のパッケージに置き換える。

- `hs_pkg` で入れ、`hs_ensure` で起動する。待ち受けを 127.0.0.1 に限る・パスワードを設定するなど、パッケージの設定ファイルを書き換えたときだけ `hs_start` で再起動する（毎回再起動するとデータの読み込みで止まる時間が増える）。
- 自分のサービスからは `--requires <パッケージのサービス名>` で依存させる。名前は OS で違う（Redis: Debian 系 `redis-server`、Alpine `redis`）。
- パッケージのサービスとそのデータは、`uninstall` では止めない・消さない（他のアプリも使い得る）。アプリが書いたデータを `--purge` で消すかは確認する。
- パッケージに無いもの（配布バイナリ・npm のグローバル導入など）は、取得元と検証方法（SHA256 など）を確かめてから入れる。

## 自動で決めることと、確認すること

Docker の構成から読み取れない部分は、次の既定で決め、決めた内容を対応表に書いて利用者に示す。

| 項目 | 既定 |
|---|---|
| 実行ユーザー | `USER` があればそれに相当する専用ユーザー、無ければアプリ名の専用ユーザー（`hs_user "$APP"`） |
| データの置き場 | `$DATA_DIR`（`/var/lib/<アプリ名>`）の下。所有者は実行ユーザー、権限 750 |
| ログ | 標準出力・標準エラーをそのまま（systemd は journald、OpenRC は syslog） |
| ビルド手順 | Dockerfile の `RUN` を同じ順に。依存は venv・`node_modules` など取得先の中に置く |
| 対象 OS | `FROM` のディストリ（上記） |

次のような曖昧な点だけは、実装の前に確認する。

- 実行に root が要りそうなもの（1024 未満のポート、デバイス・ホストのディレクトリへの書き込み、`privileged`・`cap_add`）。
- 言語ランタイムの版が OS のパッケージで揃わないもの（外部リポジトリを足すか、版を下げてよいか）。
- Docker の機能に頼っているもの（Docker API を叩く、コンテナを起動する、`network_mode: host` 前提）。
- ビルドに大きな資源（メモリ・ディスク・時間）が要るもの。
- データのうち、`--purge` で消すべきでないもの（利用者のファイルの置き場など）。

## Docker 版とホスト版の対応表

README に次の表を置き、両方の版で何が同じで何が違うかを示す（Docker 版を残すので、片方だけ変えるとずれる）。

```markdown
## Docker 版とホスト版の対応

| 項目 | Docker 版 | ホスト版 |
|---|---|---|
| 設定 | `.env`／compose の `environment:` の `TOKEN` | `/etc/<アプリ名>/<アプリ名>.env` の `TOKEN` |
| ポート | `5000:5000` | `API_PORT`（既定 5000） |
| データ | ボリューム `app-data`（`/workspace/data`） | `/var/lib/<アプリ名>` |
| ログ | `docker compose logs` | `journalctl -u <アプリ名>`（Alpine は `/var/log/messages`） |
| 依存サービス | `redis` コンテナ | パッケージ `redis-server`（127.0.0.1:6379） |
| 実行ユーザー | コンテナの root | `<アプリ名>` |
```

キーの名前は、Docker 版の環境変数と同じにする（`set -a` で読み込むだけでアプリに渡るようにするため、また利用者が両方を行き来しても迷わないため）。名前を変える・Docker 版に無い設定を足すときは、その理由を表に書く。

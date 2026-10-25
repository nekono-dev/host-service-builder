# host-service-builder

Docker（docker-compose・Dockerfile）で動いているアプリを、コンテナを使わずにホストのサービスとして動かせるようにする Claude Code のスキル（プラグイン）。対象は Debian 系（Ubuntu・Debian）＋ systemd と、Alpine ＋ OpenRC。

[bootstrap-ci-builder](https://github.com/nekono-dev/bootstrap-ci-builder) のインストーラの上に乗り、そのフック（`installer/app.sh`）の中身・起動ラッパー（`installer/run/*.sh`）・OS 差を吸収する共通ライブラリ（`installer/host-service.sh`）を整備する。頒布・更新・設定ファイル・uninstall は bootstrap-ci-builder が受け持つ。Docker 版は残し、環境変数・ポート・データの置き場を対応表で揃える。

## 導入

```
/plugin marketplace add nekono-dev/claude-plugins
/plugin install host-service-builder@nekono-dev
/plugin install bootstrap-ci-builder@nekono-dev
```

「Docker なしで動かしたい」「systemd / OpenRC のサービスにしたい」「LXC に直接入れたい」といった依頼でスキルが使われる。

## 構成

| パス | 内容 |
|---|---|
| `SKILL.md` | スキル本体（作業の進め方・app.sh と起動ラッパーの形） |
| `references/library.md` | 共通ライブラリの関数と、生成されるサービス定義 |
| `references/docker-mapping.md` | Dockerfile・compose の項目の読み替え、既定で決めること・確認すること、対応表の書式 |
| `references/debian-systemd.md` | Debian 系＋systemd のパッケージ名・ユーザー・サービス・ログ |
| `references/alpine-openrc.md` | Alpine＋OpenRC のパッケージ名・ユーザー・サービス・ログ |
| `references/verification.md` | 利用先での検証の進め方 |
| `assets/core/` | 共通ライブラリ。利用先では編集せず、`scripts/sync.sh` で上書きする |
| `assets/app/` | アプリ側のひな形（`app.sh`・`run/main.sh`）。利用先で書き換える |
| `scripts/sync.sh` | 利用先へ共通ライブラリを上書きし、アプリ側のひな形を無いときだけ置く |
| `tests/e2e.sh` | 共通ライブラリを bootstrap-ci-builder のコアと組み合わせて実際に動かす検査 |
| `evals/` | スキルの評価ケース（`claude plugin eval` の形式） |

## 開発

共通ライブラリを変えたら、systemd と OpenRC の両方で E2E を通す（CI の `test` ワークフローでも実行される）。root 権限が要り、`e2eapp-hsb` の導入物とユーザーを作って最後に消す。

```sh
git clone https://github.com/nekono-dev/bootstrap-ci-builder .bcb
sudo sh tests/e2e.sh .bcb
```

使い捨ての LXC コンテナ（`ubuntu:24.04`・`images:debian/13`・`images:alpine/3.22`）の中で実行するのがよい。Alpine の Docker コンテナで試す手順は `.github/workflows/test.yml` の `e2e-openrc` にある。

## ライセンス

[Unlicense](LICENSE)

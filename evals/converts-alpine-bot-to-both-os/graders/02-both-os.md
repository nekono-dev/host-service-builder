---
type: llm
focus: trace
weight: 1
---

installer/app.sh（またはそこから読み込むファイル）が、Debian 系では apt、Alpine では apk でパッケージを入れ、systemd と OpenRC の両方でサービスを定義・有効化・起動する

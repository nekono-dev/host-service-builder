---
tags: [skill-creator]
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

shortlink を、Ubuntu 24.04 のサーバに Docker なしで入れられるようにしたいです。installer/ には bootstrap-ci-builder のコアを置いてあり、app.sh と config.schema はまだ空です。アプリ名は shortlink、SECRET_KEY は必須の秘匿値です。Redis はコンテナではなく OS のパッケージを使ってください。worker は docker-compose.worker.yml を重ねたときだけ動く任意の構成なので、ホスト版でも設定で on/off できるようにしてください（既定は off）。Docker 版は残します。必要な情報はこれで全部なので、質問せずに進めてください。検証は静的な検査までで構いません（実機への導入はしないでください）。

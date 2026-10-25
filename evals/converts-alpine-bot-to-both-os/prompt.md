---
tags: [skill-creator]
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

このリポジトリの notes-bot を、Docker を使わずに LXC コンテナへ直接入れて常駐させたいです。対象は Alpine と Ubuntu の両方です。インストーラは bootstrap-ci-builder の形で installer/ にコアを置いてあります（app.sh・config.schema はまだ空です）。アプリ名は notes-bot、TOKEN は必須の秘匿値です。Docker 版はそのまま使い続けるので残してください。必要な情報はこれで全部なので、質問せずに進めてください。検証は静的な検査までで構いません（実機への導入はしないでください）。

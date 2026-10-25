---
tags: [skill-creator]
max_turns: 80
timeout_seconds: 1800
allowed_tools: [Read, Glob, Grep, Skill, Write, Edit, Bash]
---

installer/app.sh を整備し直したいです。今は systemctl や unit のひな形を直に扱っていて、Alpine（OpenRC）の LXC では動きません。Ubuntu・Debian の systemd に加えて Alpine＋OpenRC でも動くようにしてください。また、不正な値（MAX_ITEMS=abc など）を渡すと、止まりはするものの設定ファイルにその値が残ってしまう問題も直してください。すでにこのインストーラで導入済みのサーバがあるので、update でそのまま移れるよう、導入先のパス・サービス名・設定キーは変えないでください。必要な情報はこれで全部なので、質問せずに進めてください。検証は静的な検査までで構いません（実機への導入はしないでください）。

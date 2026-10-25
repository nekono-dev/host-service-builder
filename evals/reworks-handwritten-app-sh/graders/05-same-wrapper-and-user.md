---
type: llm
focus: trace
weight: 1
---

systemd と OpenRC のどちらでも、同じ起動ラッパーを同じ専用ユーザー clipsync で動かし、ラッパーが設定ファイルを読んで PORT・KEY・MAX_ITEMS・STORE をアプリへ渡す

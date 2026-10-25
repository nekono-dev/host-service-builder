---
type: llm
focus: trace
weight: 1
---

Redis を apt の redis-server パッケージで入れて有効化し、api（と worker）のサービスが redis-server に依存（systemd の Requires= 相当）している

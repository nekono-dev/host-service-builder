#!/usr/bin/env bash
set -eu
cp -R "$(dirname "$0")/files/." .
git -c init.defaultBranch=main init -q
git add -A
git -c user.name=eval -c user.email=eval@example.test commit -qm "初期状態"

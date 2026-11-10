#!/usr/bin/env bash
# 跑全部测试。用法：./tests/run.sh [nvim 路径]
set -u
cd "$(dirname "$0")/.."
NVIM=${1:-nvim}
fail=0
for f in tests/*.lua; do
	echo "== $f"
	if ! "$NVIM" --headless -u NONE -l "$f"; then
		fail=1
	fi
done
exit $fail

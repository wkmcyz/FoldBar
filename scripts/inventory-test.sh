#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if pgrep -x FoldBar >/dev/null; then
    echo "请先退出 FoldBar，再运行独立图标面板测试。" >&2
    exit 1
fi
REPORT="$ROOT/dist/inventory-test.json"
rm -f "$REPORT"
"$ROOT/dist/FoldBar.app/Contents/MacOS/FoldBar" --inventory-self-test "$REPORT"
python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
for check in result["checks"]:
    print(("PASS" if check["passed"] else "FAIL") + "  " + check["name"])
sys.exit(0 if result["passed"] else 1)
PY

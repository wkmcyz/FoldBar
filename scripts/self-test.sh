#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/FoldBar.app/Contents/MacOS/FoldBar"
REPORT="$ROOT/dist/self-test.json"
if pgrep -x FoldBar >/dev/null; then
    echo "请先退出正在运行的 FoldBar，再运行菜单栏集成测试。" >&2
    exit 1
fi
if [ ! -x "$APP" ]; then "$ROOT/scripts/build.sh"; fi
rm -f "$REPORT"
"$APP" --self-test "$REPORT"
python3 - "$REPORT" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
for check in result["checks"]:
    print(("PASS" if check["passed"] else "FAIL") + "  " + check["name"])
sys.exit(0 if result["passed"] else 1)
PY

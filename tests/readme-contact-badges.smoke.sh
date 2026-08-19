#!/usr/bin/env zsh
# README Contact social badges: HTML <img height="40"> only (DR-011)
setopt errexit pipefail nounset

typeset -r REPO_ROOT="${0:A:h:h}"
typeset -r README="$REPO_ROOT/README.md"

[[ -f "$README" ]] || { print -u2 "🔴 missing $README"; exit 1 }

python3 - "$README" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
rx = re.compile(
    r"(!\[[^\]]*\]\[badge-(vd7|x)\])"
    r"|(!\[[^\]]*\]\([^\)]*readme-badge-(vd7|x))"
    r"|(readme-badge-(vd7|x)\.png(?![^\n]{0,120}height=\"40\"))"
)
m = rx.search(text)
if m:
    print("🔴 README Contact social badges must be HTML <img height=\"40\">; markdown/unscaled forbidden", file=sys.stderr)
    print(m.group(0)[:160], file=sys.stderr)
    sys.exit(1)
need = ("readme-badge-vd7.png", "readme-badge-x.png", 'height="40"')
missing = [s for s in need if s not in text]
if missing:
    print("🔴 README Contact missing", missing, file=sys.stderr)
    sys.exit(1)
print("🟢 README Contact social badges HTML height=40")
PY

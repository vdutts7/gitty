#!/usr/bin/env zsh
# README images: Contact height=40 (DR-011) + table icons width/height 40 (DR-012)
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
if re.search(r"^\|.*!\[[^\]]*\]", text, re.M):
    print("🔴 README table icon column: markdown images forbidden; use HTML <img width=\"40\" height=\"40\">", file=sys.stderr)
    sys.exit(1)
if not re.search(r'<img [^>]*width="40"[^>]*height="40"', text):
    print("🔴 README missing table icon HTML width=40 height=40", file=sys.stderr)
    sys.exit(1)
print("🟢 README table icons HTML width=40 height=40")
PY

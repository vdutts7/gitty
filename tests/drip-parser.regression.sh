#!/usr/bin/env bash
# Fixture-driven regression for the drip parser algorithm (isolated from the
# gitty CLI). Mirrors the candidate-extraction + first-relative-match logic in
# bin/gitty.sh: skip absolute-path noise, match a staged relative path, prefer
# violation-signal lines.
set -euo pipefail
declare -i PASS=0 FAIL=0

_extract_first_relative_match() {
  local stderr="$1" staged="$2"
  local cands
  cands=$(printf '%s\n' "$stderr" \
    | grep -oE '(^|[[:space:]:(])([A-Za-z0-9_./+-]+\.(sh|zsh|py|md|json|yaml|yml|txt|toml|ini|wasm|lua|zig|nix|env|conf|properties|proto|rs|go|rb))' \
    | sed -E 's/^[[:space:]:(]+//; s|^\./||')
  while IFS= read -r cand; do
    [[ -z "$cand" ]] && continue
    case "$cand" in /*) continue;; esac
    while IFS= read -r p; do
      [[ "$p" == "$cand" ]] && { echo "$p"; return 0; }
    done <<< "$staged"
  done <<< "$cands"
  return 1
}

_assert() {
  local id="$1" expect="$2" got="$3"
  if [[ "$got" == "$expect" ]]; then
    echo "🟢 PASS $id"; PASS=$((PASS+1))
  else
    echo "🔴 FAIL $id — expected [$expect] got [$got]"; FAIL=$((FAIL+1))
  fi
}

# R1: clearmeta absolute-path noise + relative gate line -> pick the relative one
got=$(_extract_first_relative_match \
  $'CLEARING METADATA: /home/x/a.yaml\ncontext-pollution: tools/foo.sh:12' \
  $'tools/foo.sh\ndocs/other.md' || echo NONE)
_assert "R1 skip clearmeta absolute noise" "tools/foo.sh" "$got"

# R2: multi-offender picks first candidate that matches a staged path
got=$(_extract_first_relative_match \
  $'error: docs/skip.md not-in-staged\nBLOCKED: tools/bar.sh' \
  $'tools/bar.sh\ndocs/kept.md' || echo NONE)
_assert "R2 first-relative-match" "tools/bar.sh" "$got"

# R3: no match falls through
got=$(_extract_first_relative_match \
  $'CLEARING METADATA: /home/x/a.yaml' \
  $'tools/foo.sh' || echo NONE)
_assert "R3 no-match falls through" "NONE" "$got"

# R4: broadened extension whitelist (.wasm)
got=$(_extract_first_relative_match \
  $'error: pkg/mod.wasm invalid' \
  $'pkg/mod.wasm' || echo NONE)
_assert "R4 extension broadened .wasm" "pkg/mod.wasm" "$got"

# R5: colon-in-name — candidate becomes "name.sh", staged is "weird:name.sh";
# no exact match -> safe fall-through (never crashes)
got=$(_extract_first_relative_match \
  $'context-pollution: weird:name.sh at line 1' \
  $'weird:name.sh' || echo NONE)
_assert "R5 colon-in-name safe fall-through" "NONE" "$got"

echo "drip-parser regression: $PASS passed, $FAIL failed"
(( FAIL == 0 )) && exit 0 || exit 1

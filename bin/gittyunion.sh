#!/usr/bin/env zsh
# gittyunion - union merge driver for append-only NDJSON/JSONL ledgers.
# Part of @vd7/gitty - https://github.com/vdutts7/gitty
#
# Problem it solves:
#   Two machines both append a record to the same ledger between syncs. Git's
#   default line-based 3-way merge sees two different lines occupying the same
#   slot at EOF and raises a conflict. Text diffing cannot infer that, for an
#   append-only log, "both sides appended" means "keep both". The conflict is
#   deterministic, not bad luck: it recurs on every concurrent append.
#
#   This driver resolves that class losslessly: union of both sides, deduped by
#   exact line identity, with newly-appended records stable-sorted by the
#   ledger's total-order key. Pre-existing history order is never rewritten.
#
# Subcommands:
#   install [repo]   register the driver + declare .gitattributes rules
#   verify  [repo]   check registration (driver config is NOT cloned; see below)
#   merge <O> <A> <B> <P>   driver entry point, invoked by git

setopt pipefail 2>/dev/null || true

DRIVER_NAME="ndjson-union"

# ---------- Help ----------
show_help() {
  cat << 'EOF'
Usage: gittyunion <command> [root_dir]

Union merge driver for append-only NDJSON/JSONL ledgers. Resolves the
"both sides appended" conflict that git's default text merge cannot.

Commands:
  install [root_dir]   Register the merge driver and declare .gitattributes rules
  verify  [root_dir]   Check that the driver is registered in this clone
  merge <O> <A> <B> <P>  Driver entry point (invoked by git, not by you)

Arguments:
  root_dir  Absolute path to git repo (defaults to $PWD)

Why 'install' is needed per clone:
  .gitattributes IS versioned and clones fine, but the merge.<name>.driver
  config lives in .git/config and is NOT cloned. A fresh clone therefore reads
  the attribute, finds no driver, and SILENTLY falls back to the conflicting
  default. Run 'gittyunion install' once per clone, or 'verify' to detect it.

Examples:
  gittyunion install /path/to/repo
  gittyunion verify
EOF
  exit 0
}

# ---------- Resolve repo root ----------
_resolve_repo() {
  local d="$1"
  [ -z "$d" ] && d="$PWD"
  d=$(echo "$d" | sed "s/^[\"']//; s/[\"']$//")
  d=$(eval "echo $d")
  case "$d" in
    /*) ;;
    *) echo "🔴 - Root directory must be an absolute path: $d" >&2; return 1 ;;
  esac
  [ ! -d "$d" ] && { echo "🔴 - Directory does not exist: $d" >&2; return 1; }
  if [ ! -d "$d/.git" ] && [ ! -f "$d/.git" ]; then
    echo "🔴 - Not a git repository: $d" >&2; return 1
  fi
  printf '%s' "$d"
}

# ---------- merge: the driver ----------
# git calls: gittyunion merge %O %A %B %P
#   %O ancestor  %A ours (MUST be overwritten with the result)  %B theirs  %P path
cmd_merge() {
  local o="$1" a="$2" b="$3" p="$4"
  [ -z "$a" ] && { echo "🔴 - gittyunion merge: missing %A" >&2; return 1; }
  command -v python3 >/dev/null 2>&1 || {
    echo "🔴 - gittyunion: python3 not found; cannot union '$p'" >&2; return 1; }

  python3 - "$o" "$a" "$b" "$p" << 'PYEOF'
import json, sys, hashlib

o_path, a_path, b_path, pname = sys.argv[1:5]

def load(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return [ln.rstrip('\n') for ln in fh if ln.strip()]
    except (FileNotFoundError, IsADirectoryError):
        return []

def parse(lines, label):
    out = []
    for i, ln in enumerate(lines, 1):
        try:
            out.append(json.loads(ln))
        except ValueError as e:
            sys.stderr.write(
                "gittyunion: %s line %d of '%s' is not valid JSON (%s); "
                "leaving conflict for manual resolution\n" % (label, i, pname, e))
            return None
    return out

base, ours, theirs = load(o_path), load(a_path), load(b_path)

# Every side must parse. A malformed ledger is a real conflict, not a union.
recs = {}
for lbl, lines in (("base", base), ("ours", ours), ("theirs", theirs)):
    parsed = parse(lines, lbl)
    if parsed is None:
        sys.exit(1)
    recs[lbl] = parsed

# --- union, deduped by exact line identity, ours-order then theirs-only ---
seen, merged = set(), []
for ln in ours + theirs:
    if ln not in seen:
        seen.add(ln)
        merged.append(ln)

baseset = set(base)
head = [ln for ln in merged if ln in baseset]      # pre-existing: order untouched
tail = [ln for ln in merged if ln not in baseset]  # newly appended by either side

# --- stable-sort ONLY the new tail by the ledger's total-order key ---
# Historical order is never rewritten: real ledgers are not always monotonic,
# and reordering committed history would be a rewrite, not a merge.
KEYS = ("ts", "timestamp", "issued_utc", "created_at", "seq", "lamport")
def total_order_key(objs):
    for k in KEYS:
        if objs and all(isinstance(o, dict) and k in o for o in objs):
            return k
    return None

tail_objs = [json.loads(ln) for ln in tail]
key = total_order_key(tail_objs)
if key:
    order = sorted(range(len(tail)), key=lambda i: (tail_objs[i][key], i))
    tail = [tail[i] for i in order]
    tail_objs = [tail_objs[i] for i in order]

result = head + tail

# --- optional chain repair for hash-linked ledgers ---
# Only attempted when the record hash provably EXCLUDES the chain field, so
# re-pointing a predecessor invalidates nothing. Verified before writing.
def canon(body):
    return json.dumps({k: v for k, v in body.items() if k != "chain"},
                      sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode("utf-8")

ID_KEYS = ("certificate_id", "id", "uuid")
def id_key(objs):
    for k in ID_KEYS:
        if objs and all(isinstance(o, dict) and k in o for o in objs):
            return k
    return None

all_objs = [json.loads(ln) for ln in result]
idk = id_key(all_objs)
chained = idk and all(
    isinstance(o.get("chain"), dict)
    and "prev_certificate_id" in o["chain"]
    and "record_sha256" in o["chain"] for o in all_objs)

repaired = 0
if chained and tail:
    # Prove the hash is independent of the chain field before touching anything.
    safe = all(hashlib.sha256(canon(o)).hexdigest() == o["chain"]["record_sha256"]
               for o in all_objs)
    if safe:
        # Infer the file's separator style so rewritten lines match neighbours.
        seps = (",", ":")
        for ln, o in zip(result, all_objs):
            if json.dumps(o, ensure_ascii=False, separators=(", ", ": ")) == ln:
                seps = (", ", ": ")
                break
        start = len(head)
        for i in range(start, len(all_objs)):
            if i == 0:
                continue
            want = all_objs[i - 1][idk]
            if all_objs[i]["chain"]["prev_certificate_id"] != want:
                all_objs[i]["chain"]["prev_certificate_id"] = want
                # Re-verify: the rewrite must not have changed the record hash.
                if hashlib.sha256(canon(all_objs[i])).hexdigest() != \
                        all_objs[i]["chain"]["record_sha256"]:
                    repaired = 0
                    break
                result[i] = json.dumps(all_objs[i], ensure_ascii=False,
                                       separators=seps)
                repaired += 1
    else:
        sys.stderr.write(
            "gittyunion: '%s' record hash depends on the chain field; "
            "skipping chain repair (union still applied, nothing lost)\n" % pname)

with open(a_path, 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(result) + '\n')

note = " chain-relinked %d" % repaired if repaired else ""
sys.stderr.write("gittyunion: %s union %d records (+%d new)%s\n"
                 % (pname, len(result), len(tail), note))
sys.exit(0)
PYEOF
}

# ---------- install ----------
cmd_install() {
  local root; root=$(_resolve_repo "$1") || return 1
  local self="${${(%):-%x}:A}"

  git -C "$root" config "merge.${DRIVER_NAME}.name" \
    "union merge for append-only NDJSON ledgers" || return 1
  git -C "$root" config "merge.${DRIVER_NAME}.driver" \
    "'$self' merge %O %A %B %P" || return 1
  git -C "$root" config "merge.${DRIVER_NAME}.recursive" binary || return 1

  local ga="$root/.gitattributes"
  if ! grep -q "merge=${DRIVER_NAME}" "$ga" 2>/dev/null; then
    {
      printf '\n# Append-only ledgers: keep BOTH sides instead of stalling the sync.\n'
      printf '# Registered per clone via: gittyunion install\n'
      printf '*.ndjson    merge=%s\n' "$DRIVER_NAME"
      printf '*.jsonl     merge=%s\n' "$DRIVER_NAME"
    } >> "$ga"
    echo "🟢 - Declared *.ndjson / *.jsonl in .gitattributes"
  else
    echo "ℹ️  - .gitattributes already declares merge=${DRIVER_NAME}"
  fi

  echo "🟢 - Registered merge driver '${DRIVER_NAME}' in $root"
  echo "   driver: $self"
  return 0
}

# ---------- verify ----------
cmd_verify() {
  local root; root=$(_resolve_repo "$1") || return 1
  local issues=0

  local drv; drv=$(git -C "$root" config --get "merge.${DRIVER_NAME}.driver" 2>/dev/null)
  if [ -n "$drv" ]; then
    echo "🟢 Driver registered:  $drv"
  else
    echo "🔴 Driver NOT registered in this clone — ledger merges will conflict"
    echo "   fix: gittyunion install $root"
    issues=$((issues + 1))
  fi

  if grep -q "merge=${DRIVER_NAME}" "$root/.gitattributes" 2>/dev/null; then
    echo "🟢 .gitattributes declares merge=${DRIVER_NAME}"
  else
    echo "⚠️  No .gitattributes rule uses merge=${DRIVER_NAME}"
    issues=$((issues + 1))
  fi

  local unguarded=0 f attr
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    attr=$(git -C "$root" check-attr merge -- "$f" 2>/dev/null | sed 's/.*merge: //')
    if [ "$attr" = "unspecified" ]; then
      unguarded=$((unguarded + 1))
      [ $unguarded -le 5 ] && echo "   ⚠️  unguarded ledger: $f"
    fi
  done < <(git -C "$root" ls-files '*.ndjson' '*.jsonl' 2>/dev/null)

  if [ $unguarded -gt 0 ]; then
    echo "⚠️  $unguarded ledger file(s) have no merge strategy declared"
    issues=$((issues + 1))
  fi

  [ $issues -eq 0 ] && { echo "🟢 - Union merge is wired correctly"; return 0; }
  echo "🟡 - $issues issue(s) detected"
  return 1
}

# ---------- Dispatch ----------
case "$1" in
  -h|--help|help|"") show_help ;;
  merge)   shift; cmd_merge "$@" ;;
  install) shift; cmd_install "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  *) echo "🔴 - Unknown command: $1 (try --help)" >&2; exit 1 ;;
esac

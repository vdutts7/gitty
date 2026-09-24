#!/usr/bin/env python3
"""Detect and remove oversized blobs from unpushed linear Git history."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple


DEFAULT_MAX_BYTES = 100 * 1024 * 1024
SCHEMA = "gitty.plunger/1.0"


class PlungerError(RuntimeError):
    pass


def run(
    repo: Path,
    *args: str,
    input_bytes: Optional[bytes] = None,
    env: Optional[Dict[str, str]] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    result = subprocess.run(
        ["/usr/bin/git", "-C", str(repo), *args],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    if check and result.returncode:
        raise PlungerError(
            "git {} failed: {}".format(
                " ".join(args),
                result.stderr.decode("utf-8", "replace").strip(),
            )
        )
    return result


def text(repo: Path, *args: str) -> str:
    return run(repo, *args).stdout.decode("utf-8", "surrogateescape").strip()


def nul_paths(value: bytes) -> Set[str]:
    return {
        item.decode("utf-8", "surrogateescape")
        for item in value.split(b"\0")
        if item
    }


def resolve_upstream(repo: Path, explicit: Optional[str], branch: str) -> str:
    if explicit:
        candidate = explicit
    else:
        result = run(
            repo,
            "rev-parse",
            "--abbrev-ref",
            "--symbolic-full-name",
            "@{upstream}",
            check=False,
        )
        candidate = (
            result.stdout.decode("utf-8", "surrogateescape").strip()
            if result.returncode == 0
            else "origin/{}".format(branch)
        )
    result = run(repo, "rev-parse", "--verify", "{}^{{commit}}".format(candidate), check=False)
    if result.returncode:
        raise PlungerError("upstream does not resolve to a commit: {}".format(candidate))
    return candidate


def commits_in_range(repo: Path, upstream_oid: str, head_oid: str) -> List[str]:
    if upstream_oid == head_oid:
        return []
    ancestor = run(
        repo,
        "merge-base",
        "--is-ancestor",
        upstream_oid,
        head_oid,
        check=False,
    )
    if ancestor.returncode:
        raise PlungerError("upstream is not an ancestor of HEAD; integrate first")
    output = text(
        repo,
        "rev-list",
        "--reverse",
        "--topo-order",
        "{}..{}".format(upstream_oid, head_oid),
    )
    return [line for line in output.splitlines() if line]


def assert_linear(
    repo: Path,
    upstream_oid: str,
    commits: Sequence[str],
) -> None:
    expected_parent = upstream_oid
    for commit in commits:
        fields = text(repo, "rev-list", "--parents", "-n", "1", commit).split()
        if len(fields) != 2 or fields[1] != expected_parent:
            raise PlungerError(
                "v1 repairs only a linear unpushed range; merge found at {}".format(
                    commit
                )
            )
        expected_parent = commit


def tree_blobs(repo: Path, commit: str) -> Iterable[Tuple[str, int, str]]:
    output = run(repo, "ls-tree", "-r", "-z", "-l", commit).stdout
    for record in output.split(b"\0"):
        if not record:
            continue
        metadata, raw_path = record.split(b"\t", 1)
        fields = metadata.split()
        if len(fields) != 4 or fields[1] != b"blob" or fields[3] == b"-":
            continue
        yield (
            fields[2].decode("ascii"),
            int(fields[3]),
            raw_path.decode("utf-8", "surrogateescape"),
        )


def scan(
    repo: Path,
    upstream: str,
    max_bytes: int,
) -> Dict[str, object]:
    head_oid = text(repo, "rev-parse", "HEAD")
    upstream_oid = text(repo, "rev-parse", "{}^{{commit}}".format(upstream))
    commits = commits_in_range(repo, upstream_oid, head_oid)
    occurrences = {}
    for commit in commits:
        for oid, size, path in tree_blobs(repo, commit):
            if size <= max_bytes:
                continue
            occurrences[(commit, path, oid)] = {
                "commit": commit,
                "path": path,
                "oid": oid,
                "bytes": size,
            }
    rows = sorted(
        occurrences.values(),
        key=lambda row: (str(row["path"]), str(row["commit"]), str(row["oid"])),
    )
    paths = sorted({str(row["path"]) for row in rows}, key=os.fsencode)
    return {
        "schema": SCHEMA,
        "repo": str(repo),
        "upstream": upstream,
        "upstream_oid": upstream_oid,
        "head_oid": head_oid,
        "max_bytes": max_bytes,
        "unpushed_commits": len(commits),
        "clog_paths": paths,
        "clog_path_count": len(paths),
        "oversized_occurrences": rows,
        "oversized_occurrence_count": len(rows),
        "clear": not rows,
    }


def operation_in_progress(repo: Path) -> Optional[str]:
    git_dir = Path(text(repo, "rev-parse", "--absolute-git-dir"))
    for name in (
        "MERGE_HEAD",
        "CHERRY_PICK_HEAD",
        "REVERT_HEAD",
        "rebase-merge",
        "rebase-apply",
    ):
        if (git_dir / name).exists():
            return name
    return None


def worktree_paths(repo: Path) -> Tuple[Set[str], Set[str], Set[str], Set[str]]:
    staged = nul_paths(run(repo, "diff", "--cached", "--name-only", "-z").stdout)
    unstaged = nul_paths(run(repo, "diff", "--name-only", "-z").stdout)
    untracked = nul_paths(
        run(repo, "ls-files", "--others", "--exclude-standard", "-z").stdout
    )
    unmerged = nul_paths(
        run(repo, "diff", "--name-only", "--diff-filter=U", "-z").stdout
    )
    return staged, unstaged, untracked, unmerged


def fingerprint(repo: Path, paths: Iterable[str]) -> Dict[str, Dict[str, object]]:
    result = {}
    for path in paths:
        absolute = repo / path
        if absolute.is_symlink():
            target = os.readlink(str(absolute))
            result[path] = {
                "kind": "symlink",
                "sha256": hashlib.sha256(os.fsencode(target)).hexdigest(),
            }
        elif absolute.is_file():
            digest = hashlib.sha256()
            with absolute.open("rb") as handle:
                for chunk in iter(lambda: handle.read(8 << 20), b""):
                    digest.update(chunk)
            result[path] = {
                "kind": "file",
                "bytes": absolute.stat().st_size,
                "sha256": digest.hexdigest(),
            }
        elif absolute.exists():
            result[path] = {"kind": "other"}
        else:
            result[path] = {"kind": "missing"}
    return result


def identity(raw: bytes, label: str) -> Tuple[str, str, str]:
    match = re.match(br"^(.*) <([^>]*)> ([0-9]+ [+-][0-9]{4})$", raw)
    if not match:
        raise PlungerError("cannot parse {} identity".format(label))
    return (
        match.group(1).decode("utf-8", "surrogateescape"),
        match.group(2).decode("utf-8", "surrogateescape"),
        match.group(3).decode("ascii"),
    )


def commit_record(repo: Path, commit: str) -> Dict[str, object]:
    raw = run(repo, "cat-file", "commit", commit).stdout
    headers, message = raw.split(b"\n\n", 1)
    author = next(
        (line[len(b"author ") :] for line in headers.splitlines() if line.startswith(b"author ")),
        None,
    )
    committer = next(
        (
            line[len(b"committer ") :]
            for line in headers.splitlines()
            if line.startswith(b"committer ")
        ),
        None,
    )
    if author is None or committer is None:
        raise PlungerError("commit lacks author or committer: {}".format(commit))
    return {
        "author": identity(author, "author"),
        "committer": identity(committer, "committer"),
        "message": message,
        "signed": b"\ngpgsig " in b"\n" + headers,
    }


def parent_entry(repo: Path, parent: str, path: str) -> Optional[Tuple[str, str]]:
    output = run(repo, "ls-tree", "-z", parent, "--", path).stdout
    if not output:
        return None
    metadata, _ = output.rstrip(b"\0").split(b"\t", 1)
    mode, kind, oid = metadata.split()
    if kind != b"blob":
        raise PlungerError("clog path is not a blob in repaired parent: {}".format(path))
    return mode.decode("ascii"), oid.decode("ascii")


def restore_parent_paths(
    repo: Path,
    parent: str,
    paths: Sequence[str],
    environment: Dict[str, str],
) -> None:
    for path in paths:
        entry = parent_entry(repo, parent, path)
        if entry is None:
            run(repo, "update-index", "--force-remove", "--", path, env=environment)
        else:
            mode, oid = entry
            run(
                repo,
                "update-index",
                "--add",
                "--cacheinfo",
                mode,
                oid,
                path,
                env=environment,
            )


def rewrite_commit(
    repo: Path,
    old_commit: str,
    new_parent: str,
    paths: Sequence[str],
    index: Path,
) -> Tuple[str, bool]:
    environment = os.environ.copy()
    environment["GIT_INDEX_FILE"] = str(index)
    run(repo, "read-tree", old_commit, env=environment)
    restore_parent_paths(repo, new_parent, paths, environment)
    tree = run(repo, "write-tree", env=environment).stdout.decode("ascii").strip()
    record = commit_record(repo, old_commit)
    author_name, author_email, author_date = record["author"]
    committer_name, committer_email, committer_date = record["committer"]
    commit_environment = os.environ.copy()
    commit_environment.update(
        {
            "GIT_AUTHOR_NAME": author_name,
            "GIT_AUTHOR_EMAIL": author_email,
            "GIT_AUTHOR_DATE": author_date,
            "GIT_COMMITTER_NAME": committer_name,
            "GIT_COMMITTER_EMAIL": committer_email,
            "GIT_COMMITTER_DATE": committer_date,
        }
    )
    new_commit = run(
        repo,
        "commit-tree",
        tree,
        "-p",
        new_parent,
        input_bytes=record["message"],
        env=commit_environment,
    ).stdout.decode("ascii").strip()
    return new_commit, bool(record["signed"])


def safe_component(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-") or "branch"


def report_path(repo: Path, operation_id: str) -> Path:
    git_dir = Path(text(repo, "rev-parse", "--absolute-git-dir"))
    path = git_dir / "gitty" / "plunger" / "{}.json".format(operation_id)
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def plunge(
    repo: Path,
    upstream: str,
    max_bytes: int,
    confirmed: bool,
) -> Dict[str, object]:
    if not confirmed:
        raise PlungerError("plunge requires --yes")
    if text(repo, "rev-parse", "--is-bare-repository") == "true":
        bare = True
        branch = text(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    else:
        bare = False
        branch = text(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    progress = operation_in_progress(repo)
    if progress:
        raise PlungerError("Git operation is already in progress: {}".format(progress))
    state = scan(repo, upstream, max_bytes)
    if state["clear"]:
        return {**state, "action": "noop", "repaired": False}
    commits = commits_in_range(
        repo,
        str(state["upstream_oid"]),
        str(state["head_oid"]),
    )
    assert_linear(repo, str(state["upstream_oid"]), commits)
    signed = [
        commit
        for commit in commits
        if bool(commit_record(repo, commit)["signed"])
    ]
    if signed:
        raise PlungerError(
            "v1 refuses signed unpushed commits: {}".format(
                ", ".join(commit[:12] for commit in signed)
            )
        )
    clog_paths = [str(path) for path in state["clog_paths"]]
    dirty_paths: Set[str] = set()
    dirty_before: Dict[str, Dict[str, object]] = {}
    if not bare:
        staged, unstaged, untracked, unmerged = worktree_paths(repo)
        if staged or unmerged:
            raise PlungerError("staged or unmerged paths block plunge")
        dirty_paths = unstaged | untracked
        unexpected = sorted(dirty_paths - set(clog_paths), key=os.fsencode)
        if unexpected:
            raise PlungerError(
                "dirty non-clog paths block plunge: {}".format(
                    ", ".join(unexpected[:5])
                )
            )
        dirty_before = fingerprint(repo, dirty_paths)
    timestamp = datetime.datetime.now(
        datetime.timezone.utc
    ).strftime("%Y%m%dT%H%M%SZ")
    operation_id = "{}-{}".format(timestamp, str(state["head_oid"])[:12])
    trap_ref = "refs/gitty/plunger/traps/{}/{}".format(
        safe_component(branch),
        operation_id,
    )
    run(repo, "update-ref", trap_ref, str(state["head_oid"]))
    mapping = {}
    new_parent = str(state["upstream_oid"])
    with tempfile.TemporaryDirectory(prefix="gittyplunger-") as temporary:
        index = Path(temporary) / "index"
        for old_commit in commits:
            new_commit, _ = rewrite_commit(
                repo,
                old_commit,
                new_parent,
                clog_paths,
                index,
            )
            mapping[old_commit] = new_commit
            new_parent = new_commit
    new_head = new_parent
    changed = nul_paths(
        run(
            repo,
            "diff",
            "--name-only",
            "-z",
            str(state["head_oid"]),
            new_head,
        ).stdout
    )
    outside = sorted(changed - set(clog_paths), key=os.fsencode)
    if outside:
        raise PlungerError(
            "rewritten history changed non-clog paths: {}".format(
                ", ".join(outside[:5])
            )
        )
    branch_ref = "refs/heads/{}".format(branch)
    run(
        repo,
        "update-ref",
        branch_ref,
        new_head,
        str(state["head_oid"]),
    )
    try:
        if not bare:
            run(repo, "read-tree", "--reset", new_head)
            if fingerprint(repo, dirty_paths) != dirty_before:
                raise PlungerError("dirty clog bytes changed during plunge")
        after = scan(repo, upstream, max_bytes)
        if not after["clear"]:
            raise PlungerError("clogs remain after rewrite")
    except Exception:
        run(repo, "update-ref", branch_ref, str(state["head_oid"]), new_head)
        if not bare:
            run(repo, "read-tree", "--reset", str(state["head_oid"]))
        raise
    result = {
        **state,
        "action": "plunged",
        "repaired": True,
        "branch": branch,
        "old_head": state["head_oid"],
        "new_head": new_head,
        "trap_ref": trap_ref,
        "rewritten_commits": len(commits),
        "signed_commits_stripped": 0,
        "dirty_clog_paths_preserved": sorted(dirty_paths, key=os.fsencode),
        "commit_map": mapping,
        "push_performed": False,
    }
    output = report_path(repo, operation_id)
    output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    result["report"] = str(output)
    output.write_text(json.dumps(result, sort_keys=True, indent=2) + "\n")
    return result


def render(result: Dict[str, object], json_mode: bool) -> None:
    if json_mode:
        print(json.dumps(result, sort_keys=True))
        return
    if result.get("clear"):
        print("🟢 - gittyplunger - drain clear; no oversized unpushed blobs")
        return
    if result.get("repaired"):
        print(
            "🟢 - gittyplunger - {} clog path(s) extracted; {} commit(s) rebuilt".format(
                result["clog_path_count"],
                result["rewritten_commits"],
            )
        )
        print("🟢 - trap - {}".format(result["trap_ref"]))
        for path in result["clog_paths"]:
            print("🔴 - {} - held locally; excluded from outgoing history".format(path))
        return
    print(
        "🔴 - gittyplunger - {} clog path(s) in {} unpushed commit(s)".format(
            result["clog_path_count"],
            result["unpushed_commits"],
        )
    )
    for path in result["clog_paths"]:
        print("🔴 - {} - oversized outgoing-history blob".format(path))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="gittyplunger")
    parser.add_argument("command", nargs="?", choices=("scan", "plunge"), default="scan")
    parser.add_argument("repo", nargs="?", type=Path, default=Path.cwd())
    parser.add_argument("--upstream")
    parser.add_argument(
        "--max-bytes",
        type=int,
        default=int(os.environ.get("GITTY_MAX_FILE_BYTES", DEFAULT_MAX_BYTES)),
    )
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo.resolve()
    try:
        if not repo.exists():
            raise PlungerError("repository path does not exist")
        branch = text(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
        upstream = resolve_upstream(repo, args.upstream, branch)
        if args.command == "scan":
            result = scan(repo, upstream, args.max_bytes)
        else:
            result = plunge(
                repo,
                upstream,
                args.max_bytes,
                args.yes,
            )
        render(result, args.json)
        return 0
    except (OSError, ValueError, PlungerError, json.JSONDecodeError) as exc:
        print("🔴 - gittyplunger - {}".format(exc), file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())

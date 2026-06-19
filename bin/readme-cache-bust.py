#!/usr/bin/env python3
"""Bump ?v= on README.md <img src> URLs."""
import os
import re
import sys
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse

IMG = re.compile(r'(<img\b[^>]*?\bsrc=)(["\'])([^"\']*)(\2)', re.I | re.S)


def bust_url(url: str, v: str) -> str:
    p = urlparse(url)
    q = [(k, val) for k, val in parse_qsl(p.query, keep_blank_values=True) if k != "v"]
    q.append(("v", v))
    return urlunparse((p.scheme, p.netloc, p.path, p.params, urlencode(q), p.fragment))


def main() -> int:
    target = Path(os.environ["TARGET"])
    v = os.environ["V"]
    dry = os.environ.get("DRY_RUN") == "1"
    text = target.read_text(encoding="utf-8")
    count = 0

    def repl(m: re.Match[str]) -> str:
        nonlocal count
        url = bust_url(m.group(3), v)
        if url != m.group(3):
            count += 1
        return f"{m.group(1)}{m.group(2)}{url}{m.group(4)}"

    new_text = IMG.sub(repl, text)
    if count == 0:
        print("unchanged\t0")
        return 0
    if not dry:
        target.write_text(new_text, encoding="utf-8")
    print(f"bumped\t{count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
exec bash "$HERE/apply-file-attrs.sh" "$@"

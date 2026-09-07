# bin/hooks-lib/

Consumer-safe hook scripts shipped in the npm tarball. Installed opt-in via:

    gitty install-hooks --with <name1>,<name2>

Available:
- `check-em-dashes.sh`       normalize em-dashes -> hyphens
- `check-python-venv.sh`     prevent committing venv/ or node_modules/
- `clearmeta.sh`             strip EXIF / metadata from committed files
- `drop-eof-newline-only.sh` drop files whose only diff is trailing whitespace
- `health-check.sh`          pre-push: large-file scan + embedded-repo detection

These scripts are agnostic (no vdutts7 / Cloudinary / README-badge scope).
Maintainer-scoped scripts live in `.hooks/scripts/` and are excluded from
the npm tarball by design (identity-boundary per npm-portability doctrine).

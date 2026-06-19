# Hooks

## npm install only

`npm i -g @vd7/gitty` gives plain `git` commands. **No hooks ship in the package.**

- No shelllock
- No health-check
- Repo hooks still run if the target repo has `core.hooksPath` set

## Repo with `.hooks/`

Many repos use [gh-template](https://github.com/vdutts7/gh-template) hooks:

- `gitty` does **not** pass `--no-verify`
- Pre-commit runs on `git commit`
- Pre-push runs on `git push`

### Hook dashboard

When hooks run, `gitty` prints a pass/fail summary:

```text
── hooks: pre-commit ──
🟢 - enforce-git-identity — passed
🟢 - check-em-dashes — fixed (em dash -> hyphen)
🟢 - clearmeta — metadata stripped
── hooks: pre-push ──
🟢 - shelllock — passed
🟢 - health-check — all checks passed
```

Hook block → 🔴, commit/push stops. Partial holdback does **not** bypass hook failures.

### Optional shelllock

[shelllock](https://github.com/vdutts7/shelllock-macos) Touch ID on pre-push when installed and wired in repo `.hooks/pre-push`.

## Partial commit vs hooks

| Layer | What it does |
|-------|----------------|
| `gitty` partial holdback | Size/submodule/push-reject paths — see [partial-commit.md](partial-commit.md) |
| Repo hooks | Policy gates (identity, venv, health-check, etc.) |

They are independent. A hook block still aborts the whole commit even when partial mode is on.

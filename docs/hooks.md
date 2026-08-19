# Hooks

## npm install only

- `npm i -g @vd7/gitty` gives plain `git` commands
- **no hooks ship in the package**

- no `shelllock`
- no `health-check`
- **repo hooks still run if the target repo has `core.hooksPath` set**

## Repo with `.hooks/`

Many repos use [`gh-template`](https://github.com/vdutts7/gh-template) hooks:

- `gitty` does **not** pass `--no-verify`
- Pre-commit runs on `git commit`
- Pre-push runs on `git push`

### Hook dashboard

When hooks run, `gitty` prints a pass(🟢)/fail(🔴) summary:

```text
── hooks: pre-commit ──
🟢 - enforce-git-identity- passed
🟢 - check-em-dashes- fixed (em dash -> hyphen)
🟢 - clearmeta- metadata stripped
── hooks: pre-push ──
🟢 - health-check- all checks passed
```

Hook block → 🔴, commit/push stops
- partial holdback does **not** bypass hook failures

## Partial commit vs hooks

| Layer | What it does |
|-------|----------------|
| `gitty` partial holdback | Size/submodule/push-reject paths → see [`partial-commit.md`](partial-commit.md) |
| Repo hooks | Policy gates (`identity`, `venv`, `health-check`, etc) |

They are **independent**:
- a hook block still aborts whole commit **even when partial mode is on**

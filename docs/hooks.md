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

## Extending hooks: `.hooks/local.d/` (added v0.6.18)

Repos using `gitty`'s composition runners can extend the hook chain without editing upstream files. The `pre-commit` and `pre-push` runners iterate a consumer namespace after the upstream lane.

```text
.hooks/
├── pre-commit             # runner (v0.6.18+ iterates 3 lanes)
├── pre-push               # runner (v0.6.18+ iterates 2 lanes)
├── pre-commit.d/          # upstream lane (framework checks)
├── pre-push.d/            # upstream lane
└── local.d/
    ├── cosmetic/          # advisory fixers; exit non-zero is ignored
    ├── gates/             # invariant enforcers; exit non-zero blocks commit
    └── pre-push/          # pre-push extensions; exit non-zero blocks push
```

### Order per commit

1. `pre-commit.d/*` - upstream framework
2. `local.d/cosmetic/*` - advisory (wrapped `|| true`)
3. `local.d/gates/*` - blocking

### Order per push

1. `pre-push.d/*` - upstream framework
2. `local.d/pre-push/*` - consumer extensions

### Adding an extension

Drop an executable file in the right lane. Filename prefix controls order (e.g. `10-my-check.sh`, `70-har-scrub.sh`, `90-final-gate.sh`).

```sh
# consumer-owned; not shipped in @vd7/gitty; survives `git pull`
$ chmod +x .hooks/local.d/gates/70-my-check.sh
```

### Preserved by `gitty-refresh.sh` consumers

Consumers who sync `.hooks/` from this repo (e.g. via `rsync -a --delete --exclude='local.d/'`) will keep `local.d/` intact across refreshes. See the `hook_sync` config in `@vd7/gitty` downstream consumers.

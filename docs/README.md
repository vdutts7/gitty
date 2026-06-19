# gitty docs

Reference for [@vd7/gitty](https://www.npmjs.com/package/@vd7/gitty).

| Doc | What it covers |
|-----|----------------|
| [commands.md](commands.md) | `gitty`, `gittylfs`, `gittyembedded`, `gittyhealth` |
| [partial-commit.md](partial-commit.md) | Hold back offenders; commit and push the rest |
| [environment.md](environment.md) | Env vars and repo hooks integration |
| [hooks.md](hooks.md) | Repo `.hooks/` vs npm-only install |
| [publishing.md](publishing.md) | Maintainer release via `npm-publish` |

## Quick start

```bash
npm i -g @vd7/gitty
gitty "checkpoint" /absolute/path/to/repo
```

Default flow: stage → partial holdback → commit → force push.

## When to use which command

| Situation | Command |
|-----------|---------|
| Normal checkpoint | `gitty` |
| Large binary assets (LFS) | `gittylfs` |
| Parent repo + dirty submodules | `gittyembedded` |
| Inspect repo health only | `gittyhealth` |

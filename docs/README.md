# gitty docs

[@vd7/gitty](https://www.npmjs.com/package/@vd7/gitty)

| Doc | Covers |
|---|---|
| [commands.md](commands.md) | all bins |
| [gittysnap.md](gittysnap.md) | snapshot-first multi-machine sync |
| [gittyunion.md](gittyunion.md) | NDJSON/JSONL union merge driver |
| [partial-commit.md](partial-commit.md) | holdback + drip-through |
| [environment.md](environment.md) | env vars |
| [hooks.md](hooks.md) | `.hooks/` vs npm-only |

## Quick start

```bash
npm i -g @vd7/gitty
gitty "checkpoint" /absolute/path/to/repo
```

## Which bin

| Situation | Command |
|---|---|
| Normal checkpoint | `gitty` |
| Large binaries | `gittylfs` |
| Dirty submodules | `gittyembedded` |
| Inspect only | `gittyhealth` |
| Solo laptop↔desktop | `gittysnap` |
| Append-only `.ndjson`/`.jsonl` | `gittyunion install` |

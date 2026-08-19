<p align="center">
  <img
    src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp?v=1782018495"
    alt="gitty icon"
    width="80"
    height="80"
  />
</p>

<div align="center">

<h1 align="center">gitty</h1>
<p align="center"><i><b>diligent backup machine: one command</b></i></p>
<p align="center"><i><b>land everything that can land, every run</b></i></p>

[![GitHub][github-badge]][github-url]
[![npm][npm]][npm-url]

</div>

<br/>

---

<table>
<thead>
<tr>
<th align="left"></th>
<th align="left">Path</th>
<th align="left">You get</th>
<th align="left">Verdict</th>
</tr>
</thead>
<tbody>
<tr>
<td align="left">
<img
src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/git.webp"
width="40"
height="40"
alt="git"
/>
</td>
<td align="left">
<ul><li><code>pull --rebase --autostash</code></li></ul>
</td>
<td align="left">
<ul>
<li>false <code>rc=0</code></li>
<li>stranded worktree</li>
<li>one-machine only</li>
</ul>
</td>
<td align="left">❌<br/><br/>sync theater</td>
</tr>
<tr>
<td align="left">
<img
src="https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp"
width="40"
height="40"
alt="gittysnap"
/>
</td>
<td align="left">
<ul><li><code>gittysnap</code></li></ul>
</td>
<td align="left">
<ul>
<li><code>rc=2</code> on conflict</li>
<li>clean worktree</li>
<li>both on remote first</li>
</ul>
</td>
<td align="left">✅<br/><br/>snapshot-first</td>
</tr>
</tbody>
</table>

<br/>

## Issue

### ❌ Checkpoint friction

- agents touch many repos per session

- `add` + `commit` + `push` per repo burns time

- one oversized / submodule path blocks the whole run

### ❌ Dual-machine strand

- laptop + desktop both edit

- N local commits replay against remote -> same conflict N times

- other machine's work never left that machine

### ❌ All-or-nothing stall

- one conflicted / oversized / submodule path parks the whole checkpoint

- the rest of the tree sits unbacked on that machine

- drip: push the clean subset; hold the rest; never stall the backup

### ❌ Append ledger false conflicts

- two hosts append different `.ndjson` / `.jsonl` lines

- git sees one slot, two lines → conflict

- nothing was edited; both lines should keep

<br/>

## Sync model

`gitty` is a backup machine. Job: get as much of the tree onto remote as possible, every run.

Sync = `additive_git_integrate(origin/$branch)`. One primitive:

- fetch → prefer `merge --ff-only`; else `merge --no-ff <resolved-sha>` (never rebase; never rewrite local history)

- conflict → try `.gitty/additive-resolvers.yaml` classes:
  - `per_host`: `checkout --ours` + `add` for per-host artifacts (byte-authoritative on one host per commit)
  - `semantic_union`: union + dedupe + stable-sort by `key_field` for NDJSON/JSONL ledgers

- drip (`GITTY_PARTIAL=1` default): some paths resolve, some do not → commit the resolved subset; hold unresolved; keep backing up

- park only when nothing can land: `bak/pending-merge-<utc>` + `remote-snapshot/<utc>`; branch untouched; nothing lost; non-fatal exit

Forbidden ops: rebase, stash, amend, force-push, reset --hard, switch branches.

### Config: `.gitty/additive-resolvers.yaml`

```yaml
per_host:
  paths:
    - registry/system-resource/manifest.json
  globs:
    - snapshots/$(hostname)/**
semantic_union:
  globs:
    - "**/*.ndjson"
    - "**/*.jsonl"
  key_field: ts
```

Missing file → empty allowlist → resolvers never fire → conflicts park.

<br/>

## Options

| | Bin | Job | When |
|---|---|---|---|
| ![gitty][i-gitty] | `gitty` | drip + holdback → commit → push | default checkpoint |
| ![lfs][i-lfs] | `gittylfs` | same + LFS track | big binaries |
| ![git][i-git] | `gittyembedded` | submodules then parent | dirty nested repos |
| ![health][i-health] | `gittyhealth` | report only | inspect / mid-op |
| ![snap][i-snap] | `gittysnap` | snap → merge → abort clean | solo multi-machine |
| ![union][i-json] | `gittyunion` | NDJSON union driver | append ledgers |

Separate bins. Same package. Plain `gitty` ≠ `gittysnap`.

<br/>

## Install

```bash
npm i -g @vd7/gitty
```

<br/>

## Run

```bash
gitty "checkpoint" "$HOME/Documents/a/my-repo"
gittysnap
gittysnap snap
gittyunion install
```

```bash
gitty [commit_mssg] [root_dir]
```

Drip + holdback default on (`GITTY_PARTIAL=1`): commit/push whatever can land; hold the rest. Force bulldoze: `GITTY_FORCE=1`. Park-only (no drip): `GITTY_PARTIAL=0`.

<br/>

## Gotchas

| problem | fix | stability | why |
|---|---|---|---|
| N-commit rebase replays same conflict N times | `gitty` uses `merge --no-ff` of resolved SHA once | stable | one merge, one conflict set |
| per-host artifact conflicts every sync | `.gitty/additive-resolvers.yaml` `per_host` | stable | doctrine class; both parents preserved via `--no-ff` |
| `.ndjson` append conflict | `.gitty/additive-resolvers.yaml` `semantic_union` OR `gittyunion install` | stable | union + dedupe + stable-sort |
| fresh clone drops union driver | re-run `gitty` / `gittyunion install` | stable | attrs alone insufficient |
| oversized path blocks push | leave `GITTY_PARTIAL=1` | stable | hold back; push the rest |
| one unresolvable file parks whole merge | drip-through: commit resolved subset; hold the rest | stable | backup as much as possible |
| nothing can land | parked on `bak/pending-merge-*` | stable | first-class ref; nothing lost; non-fatal |

<br/>

## Docs

| Doc | Topic |
|---|---|
| [`docs/README`](docs/README%2Emd) | index |
| [`docs/commands`](docs/commands%2Emd) | all bins |
| [`docs/gittysnap`](docs/gittysnap%2Emd) | snapshot-first sync |
| [`docs/gittyunion`](docs/gittyunion%2Emd) | NDJSON union driver |
| [`docs/partial-commit`](docs/partial-commit%2Emd) | holdback |
| [`docs/environment`](docs/environment%2Emd) | env |
| [`docs/hooks`](docs/hooks%2Emd) | repo hooks |

npm tarball = `bin/` + `README` only. `docs/` is GitHub.

<br/>

## Contact

[![vd7.io][badge-vd7]][vd7-url]
[![/vdutts7][badge-x]][x-url]

[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty
[npm]: https://img.shields.io/badge/npm-@vd7/gitty-CB3837?style=for-the-badge&logo=npm
[npm-url]: https://www.npmjs.com/package/@vd7/gitty
[i-git]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/git.webp
[i-gitty]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/gitty.webp
[i-lfs]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/git-lfs.webp
[i-health]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/infomaniak-kcheck.webp
[i-snap]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/borg-backup.webp
[i-json]: https://raw.githubusercontent.com/vdutts7/squircle/main/webp/json.webp
[badge-vd7]: https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910810/readme-badges/readme-badge-vd7.png?v=1782018495
[badge-x]: https://res.cloudinary.com/ddyc1es5v/image/upload/v1773910817/readme-badges/readme-badge-x.png?v=1782018495
[vd7-url]: https://vd7.io
[x-url]: https://x.com/vdutts7

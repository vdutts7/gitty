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
<p align="center"><i><b>snapshot checkpoint: one command</b></i></p>
<p align="center"><i><b>content first, clean history second</b></i></p>

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

- rebase stops mid-flight: dirty tree, autostash gamble

- other machine's work never left that machine

### ❌ Append ledger false conflicts

- two hosts append different `.ndjson` / `.jsonl` lines

- git sees one slot, two lines → conflict

- nothing was edited; both lines should keep

<br/>

## Options

| | Bin | Job | When |
|---|---|---|---|
| ![gitty][i-gitty] | `gitty` | holdback → commit → push | default checkpoint |
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

Partial holdback default on (`GITTY_PARTIAL=1`). Force bulldoze: `GITTY_FORCE=1`.

<br/>

## Gotchas

| problem | fix | stability | why |
|---|---|---|---|
| rebase strands worktree | `gittysnap` | stable | snap before integrate |
| `--autostash` half-applies | `gitty` uses `bak/*` snapshot refs | stable | stash is not a recoverable ref |
| `.ndjson` append conflict | `gittyunion install` | stable | driver in `.git/config` (not cloned) |
| fresh clone drops union | re-run `gitty` / `gittyunion install` | stable | attrs alone insufficient |
| oversized path blocks push | leave `GITTY_PARTIAL=1` | stable | hold back; push the rest |

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

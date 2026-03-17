<div align="center">

<h1 align="center">gitty</h1>
<p align="center"><i><b>Git add, commit, and force push in one command. Prompts for message and repo root when omitted.</b></i></p>

[![GitHub][github-badge]][github-url]

</div>

<br/>

## ToC

<ol>
    <a href="#about">About</a><br/>
    <a href="#install">Install</a><br/>
    <a href="#usage">Usage</a><br/>
    <a href="#requirements">Requirements</a><br/>
    <a href="#contact">Contact</a>
</ol>

<br/>

## About

One-command workflow: stage all, commit with message, force push. Optional args; prompts for commit message and repo root when not provided.

<br/>

## Install

```bash
npm i -g @vd7/gitty
```

<br/>

## Usage

```bash
gitty [commit_mssg] [root_dir]
```

| Arg | Description |
|-----|-------------|
| `commit_mssg` | Commit message (prompted if omitted; default `..`) |
| `root_dir` | Absolute path to git repo (prompted if omitted; default `$PWD`) |

### Examples

```bash
gitty "fix bug" /path/to/repo
gitty                    # prompts for both
gitty "wip"              # message only; root = $PWD
```

<br/>

## Requirements

- **zsh**
- **git**

<br/>

## Contact

<a href="https://vd7.io"><img src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSI5NyIgaGVpZ2h0PSI0MCIgdmlld0JveD0iMCAwIDk3IDQwIj48ZGVmcz48bGluZWFyR3JhZGllbnQgaWQ9ImNpcmNsZSIgeDE9IjAlIiB5MT0iMCUiIHgyPSIxMDAlIiB5Mj0iMCUiPjxzdG9wIG9mZnNldD0iMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiM1ZGQzZmYiLz48c3RvcCBvZmZzZXQ9IjEwMCUiIHN0eWxlPSJzdG9wLWNvbG9yOiMyMmE4YzkiLz48L2xpbmVhckdyYWRpZW50PjwvZGVmcz48cmVjdCB4PSIwIiB5PSIwIiB3aWR0aD0iOTciIGhlaWdodD0iNDAiIHJ4PSIyMCIgcnk9IjIwIiBmaWxsPSIjMDAwIiBzdHJva2U9InJnYmEoMjU1LDI1NSwyNTUsMC4yKSIgc3Ryb2tlLXdpZHRoPSIxIi8+PGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTMsIDApIj48Y2lyY2xlIGN4PSI5IiBjeT0iMjAiIHI9IjkiIGZpbGw9InVybCgjY2lyY2xlKSIvPjx0ZXh0IHg9IjI2IiB5PSIyNSIgZmlsbD0iI2ZmZiIgZm9udC1mYW1pbHk9IidKZXRCcmFpbnMgTW9ubycsJ1NGIE1vbm8nLCdGaXJhIENvZGUnLG1vbm9zcGFjZSIgZm9udC1zaXplPSIxMyIgZm9udC13ZWlnaHQ9IjUwMCI+dmQ3LmlvPC90ZXh0PjwvZz48L3N2Zz4=" alt="vd7.io" height="40" /></a> &nbsp; <a href="https://x.com/vdutts7"><img src="data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMTgiIGhlaWdodD0iNDAiIHZpZXdCb3g9IjAgMCAxMTggNDAiPjxyZWN0IHg9IjAiIHk9IjAiIHdpZHRoPSIxMTgiIGhlaWdodD0iNDAiIHJ4PSIyMCIgcnk9IjIwIiBmaWxsPSIjMDAwIiBzdHJva2U9InJnYmEoMjU1LDI1NSwyNTUsMC4yKSIgc3Ryb2tlLXdpZHRoPSIxIi8+PGcgdHJhbnNmb3JtPSJ0cmFuc2xhdGUoMTMsIDApIj48ZyB0cmFuc2Zvcm09InRyYW5zbGF0ZSg5LCAyMCkgc2NhbGUoMC41NSkgdHJhbnNsYXRlKC0xMiwgLTEyKSI+PHBhdGggZD0iTTE4LjI0NCAyLjI1aDMuMzA4bC03LjIyNyA4LjI2IDguNTAyIDExLjI0SDE2LjE3bC01LjIxNC02LjgxN0w0Ljk5IDIxLjc1SDEuNjhsNy43My04LjgzNUwxLjI1NCAyLjI1SDguMDhsNC43MTMgNi4yMzF6bS0xLjE2MSAxNy41MmgxLjgzM0w3LjA4NCA0LjEyNkg1LjExN3oiIGZpbGw9IiNmZmYiLz48L2c+PHRleHQgeD0iMjYiIHk9IjI1IiBmaWxsPSIjZmZmIiBmb250LWZhbWlseT0iJ0pldEJyYWlucyBNb25vJywnU0YgTW9ubycsJ0ZpcmEgQ29kZScsbW9ub3NwYWNlIiBmb250LXNpemU9IjEzIiBmb250LXdlaWdodD0iNTAwIj4vdmR1dHRzNzwvdGV4dD48L2c+PC9zdmc+" alt="/vdutts7" height="40" /></a>

---

[github-badge]: https://img.shields.io/badge/gitty-000000?style=for-the-badge&logo=github&logoColor=white
[github-url]: https://github.com/vdutts7/gitty

# Publishing

Maintainer workflow for `@vd7/gitty`.

## Prereqs

- `npm login` on the publish machine
- `jq` on PATH
- Clean git working tree in the package dir
- Remote configured (`origin` → GitHub)

## Release

From the repo root (or with an env var pointing at it):

```bash
npm-publish $GITTY           # patch bump (default)
npm-publish $GITTY --minor
npm-publish $GITTY --major
```

`npm-publish` (`$CURTOOLS/npm-publish.sh`):

1. Verify clean tree
2. Push pending commits
3. `npm version <bump>`
4. Push branch + tag `vX.Y.Z` (**blocks publish if tag push fails**)
5. `npm publish --access public`
6. Global parity: `npm i -g @vd7/gitty@X.Y.Z` when listed in `$CURREGISTRY/npm-publish.json`

## Tarball contents

`package.json` `files`:

```json
["bin", "README.md"]
```

Docs in `docs/` are GitHub-only; not in the npm tarball. Keep README summary current for npm readers.

## Versioning notes

- Tag format: `vX.Y.Z` (created by `npm version`)
- Symlink: some machines alias `$CURTOOLS/git/gitty.sh` → `bin/gitty.sh` in this repo
- After publish, verify: `npm view @vd7/gitty version` and `which gitty`

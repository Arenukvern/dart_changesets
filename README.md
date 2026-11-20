# dart_changesets

A changesets-style release engine for Dart — **GitHub Action + Dart CLI** —
that turns small intent files into version PRs and per-tag pub.dev publish
trains.

## Attribution

Design inspired by [changesets](https://github.com/changesets/changesets) and
its GitHub Action [@changesets/action](https://github.com/changesets/action)
(the original TypeScript implementation for npm monorepos). Differences are
ecosystem-driven: `pubspec.yaml` + `package:pub_semver` instead of
`package.json` semver, the dependency graph from pubspecs, and pub.dev's
automated publishing — which is **ref-gated per package tag**, so one tag
pushes one publish run (ordering emerges from dependency waits plus
skip-existing self-healing; see
[dart.dev automated publishing](https://dart.dev/tools/pub/automated-publishing)).

## Quick start (consumer repository)

1. **Two workflow files** (copy from [example/consumer-workflows](example/consumer-workflows)):
   `release.yml` (push to main) and `publish.yml` (per-tag pub.dev publish).
2. **Write an intent file** inside any PR:

   ```markdown
   ---
   'my_package': minor
   ---

   What changed, as changelog prose.
   ```

3. **Merge to main** → the action opens a `chore: version packages` PR
   (version bumps + dependent-constraint cascades + changelogs).
4. **Merge that PR** → one `<package>-v<version>` tag per release, one
   publish run per tag, ordered by dependency waits.

No conventional-commit discipline is required — release intent lives in
reviewed files, not commit messages.

## How it works

```yaml
# The whole main-side wiring in a consumer repo:
- uses: Arenukvern/dart_changesets@v1
  env: { GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} }
```

- **Assemble mode**: pending `.changesets/*.md` intent files → the engine
  computes the train (declared bumps + transitive dependents whose caret
  constraints no longer admit the new versions, via `package:pub_semver`) →
  applies it onto the version branch → opens/updates the version PR.
- **Release mode** (the push that merged the version PR): the train artifact
  committed by the PR lists one tag per release → the action pushes each tag
  and dispatches the consumer's `publish.yml` once per tag.
- **Publish workflow**: installs the engine via `dart pub global activate`,
  asks it whether the tagged package needs Flutter, installs the SDK, then
  runs static checks → skip-existing → typed BOOTSTRAP gate for never-published
  packages → dependency wait → strict dry-run → `pub publish --force` (OIDC)
  → wait for pub.dev visibility.

## Configuration

`changesets.yaml` at the repository root (all keys optional):

```yaml
packages_dir: pkgs          # where packages live (default: pkgs)
root_package: false         # single-package repos: include the root pubspec
dependent_bump: patch       # bump applied to dependents whose constraint changed
tag_format: '{package}-v{version}'
```

Packages marked `publish_to: none` are private automatically and never
released; the doctor gate fails when a publishable package depends on one.

## CLI

```bash
dart pub global activate git:https://github.com/Arenukvern/dart_changesets
dart_changesets add                # interactive intent file
dart_changesets status             # pending intents → planned releases
dart_changesets version [--check]  # apply (or detect) the version train
dart_changesets doctor [--no-network]  # gates + pub.dev census
dart_changesets tags               # tags for the pending train (JSON)
dart_changesets runner --tag <pkg>-v<semver>   # dart | flutter
dart_changesets publish-tag --tag <pkg>-v<semver> [--execute] [--skip-existing]
```

## Bootstrap (first publish of a new package)

pub.dev cannot automate a package's first release:

1. `dart pub publish` (or `flutter pub publish`) from the package directory —
   sign in with the uploader account in the browser.
2. On pub.dev: package → Admin → **Automated publishing** → enable for the
   consumer repository with tag pattern `<package>-v{{version}}`.
3. Re-run the publish (skip-existing keeps it idempotent).

New-package rate limit is ~12/day (4 in a burst) — spread first publishes
across days.

## This repository releases itself

The action and the reusable publish workflow run this repo's own train
(`.github/workflows/release.yml` + `self_publish.yml`). The engine package
lives at the repository root; write an intent file to release it.

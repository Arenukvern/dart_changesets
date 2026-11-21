# dart_changesets

A changesets-style release engine for Dart — **GitHub Action + Dart CLI** —
that turns small intent files into version PRs and per-tag pub.dev publish
trains.

[![CI](https://github.com/Arenukvern/dart_changesets/actions/workflows/ci.yml/badge.svg)](https://github.com/Arenukvern/dart_changesets/actions/workflows/ci.yml)
[![pub: dart_changesets](https://img.shields.io/pub/v/dart_changesets.svg)](https://pub.dev/packages/dart_changesets)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-dart__changesets-blue?logo=github)](https://github.com/marketplace/actions/dart_changesets)
[![Dart SDK](https://img.shields.io/badge/Dart-%5E3.14.0-blue?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

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

The action is published on the
[GitHub Marketplace](https://github.com/marketplace/actions/dart_changesets) —
pin `@v1` for the current major.

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

**One required repo setting** (GitHub default blocks bot-made PRs):
Settings → Actions → General → Workflow permissions → check
**Allow GitHub Actions to create and approve pull requests**. The version
PR is created by `GITHUB_TOKEN`; with the setting off, assemble runs push
the version branch but cannot open the PR (and the next assemble run
repairs it once the setting is on).

**Required workflow permissions** in your release workflow: `contents:
write`, `pull-requests: write`, and `actions: write` — the last one
because the action starts publish runs via `gh workflow run` (workflow
dispatch creation). Without it, a version-PR merge pushes the tags but
fails to start the publish runs. Repair by re-running the failed release
RUN (a re-run checks out the original merge ref, so release mode
detects again; a fresh dispatch on a moved main head correctly does
nothing), or by dispatching the publish workflow per tag.

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
  decides workspace-aware whether the run needs Flutter (`pub publish`
  inside a pub-workspace member resolves the whole workspace, so any
  `sdk: flutter` member makes the SDK required — pure-Dart repositories
  never install it), installs the SDK from the stable channel (latest by
  default; cache enabled) when needed, then
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

# Optional: one package whose release ALSO gets a product tag + GitHub
# release at the version-PR merge commit (exactly once per train, idempotent).
product_tag:
  package: flutter_mcp_toolkit_server   # pubspec `name:`, not the directory
  format: 'v{version}'

# Optional: version strings outside pubspec that move with a package's
# release. Missing files, drifted versions, and ambiguous patterns fail
# loudly — never touch unrelated occurrences.
version_files:
  flutter_mcp_toolkit_server:
    - path: VERSION
      pattern: '{version}'
    - path: mcp_server_dart/server.json
      pattern: '"version": "{version}"'
```

Packages marked `publish_to: none` are private automatically and never
released; the doctor gate fails when a publishable package depends on one.

### Product tag → GitHub release → binaries

When `product_tag` is configured and that package is in the train, the
version-PR merge creates `v{version}` on the merge commit and a GitHub
release whose notes are that package's new changelog section. Downstream
builds (binaries, registry) must start AFTER the product package's publish
leg succeeds — at merge time the new dependency versions are not on pub.dev
yet, so a build resolving them fails. Two supported wirings:

```yaml
# Option A (recommended): chain in your per-tag workflow — ordering is
# guaranteed by needs:, zero extra engine config.
jobs:
  publish:
    uses: Arenukvern/dart_changesets/.github/workflows/publish.yml@v1
    with: { tag: ${{ github.event.inputs.tag || github.ref_name }}, execute: true }
  binaries:
    needs: publish
    if: startsWith(github.event.inputs.tag || github.ref_name, 'flutter_mcp_toolkit_server-v')
    uses: ./.github/workflows/release.yml
    with: { release_tag: ${{ github.event.inputs.tag || github.ref_name }} }

# Option B: let the reusable publish workflow dispatch for you (fires only
# for the product package's tag, only after publish succeeded):
#   with:
#     product-dispatch-workflow: release.yml
#     product-dispatch-input: release_tag
```

### Token

The action's `token` input (default `github.token`) is used for every
branch push, PR create/edit, tag push, release creation, and dispatch.
Pushes made with `GITHUB_TOKEN` trigger no workflows — so the version PR
runs no CI by default. A PAT (or App token) makes the version PR run full
CI; the action overrides checkout's persisted credential so pushes really
ride that token.

## CLI

One-off, no install — Dart 3.12+ runs any pub.dev executable directly:

```bash
dart run dart_changesets@ status   # pending intents → planned releases
```

Or install globally:

```bash
dart pub global activate dart_changesets
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

## Contributing & community

- [CONTRIBUTING.md](CONTRIBUTING.md) — setup, validation, conventions, PR checklist
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md) — private vulnerability reporting
- [Discussions](https://github.com/Arenukvern/dart_changesets/discussions) — usage questions

Released under the [MIT License](LICENSE).

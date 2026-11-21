# Changelog

## 0.2.0

### Minor Changes

- New optional, backward-compatible release features: `product_tag` config
  gives one package a product-shaped tag (e.g. `v{version}`) plus a GitHub
  release with that package's changelog section as notes, created exactly
  once per train at the version-PR merge commit (idempotent re-runs skip
  what exists); `version_files` config bumps version strings outside
  pubspec per package (VERSION files, JSON version fields, Dart constants)
  with loud failures on missing files, drifted versions, or ambiguous
  patterns; a `token` action input (default `github.token`) drives every
  branch push, PR create/edit, tag push, release, and dispatch — a PAT
  makes the version PR run full CI since GITHUB_TOKEN pushes fire no
  workflows. The reusable publish workflow can dispatch a configured
  downstream workflow AFTER the product package's publish succeeds
  (`product-dispatch-workflow` / `product-dispatch-input`); `tags` gains a
  `--plain` output replacing the action's python one-liner; new
  `product-release` and `release-notes` subcommands keep action.yml thin.
## 0.1.1

### Patch Changes

- `runner` and `publish-tag` now decide the publish runner workspace-aware:
  `pub publish` inside a pub-workspace member resolves the whole workspace, so
  a single `sdk: flutter` member requires the Flutter SDK even when publishing
  a dart-only tag (previously the dart-only fast path crashed at dry-run in
  mixed workspaces). The reusable publish workflow correspondingly installs
  Flutter only when the workspace needs it, drops the redundant workspace
  `pub get` step (publish resolves itself), and stops pinning the Flutter
  version — an empty `flutter-version` input now tracks the latest stable
  release, keeping consumer release trains maintenance-free across the Flutter
  cadence.
## 0.1.0

- Initial standalone release: intent files, workspace graph, semver cascade
  (`package:pub_semver`), version-PR assembly, doctor gates, per-tag pub.dev
  publish train, composite GitHub Action, and reusable publish workflow.
- Extracted from `pkgs/dart_changesets` in `xsoulspace/dart_flutter_packages`
  (ADR 0073 there).



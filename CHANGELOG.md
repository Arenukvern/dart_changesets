# Changelog

## 0.3.0

### Minor Changes

- **Changelog comment banners stay above the new version section.**
  `prependChangelog` now treats top-of-file HTML comments (e.g.
  `<!-- markdownlint-disable … -->`) as part of the header region instead
  of pushing them below the inserted section — consumers keep such banners
  in the first lines on purpose (oka's markdownlint gate requires the
  banner within the first 5 lines; the naive header-insert moved it to
  line 9 and failed the train's contracts job).
- **Declared dependents keep their constraint rewrites regardless of
  planning order.** The plan queue is alphabetical, so a declared dependent
  whose name sorts before its dependency (`oka_app_gallery` before
  `oka_core`) was planned BEFORE the dependency's new version existed — its
  constraint rewrite landed in the never-consumed pending map and the
  version PR shipped a graph that cannot resolve. Rewrites now merge into
  an already-planned release in place.
- Release-train robustness, four production gaps surfaced by the oka
  2026-11-22 release cut:
  
  - **Merge-commit merges now release.** Detect mode recognized only the
    squash message prefix ("chore: version packages"); a merge-commit merge
    of the version PR no-op'd and the train stalled until tags were pushed
    by hand. The action now also identifies the merge by the PR itself
    (`gh pr view` state/mergeCommit == HEAD).
  - **Version-suffixed changelog headings accepted.** `publish-tag` accepts
    a `##` heading that STARTS with the exact version (`## 1.2.3
    (2026-11-22)` counts; `## 1.2.31` does not) and names the headings
    found when the entry is missing, so hand-tended changelogs stop failing
    the publish gate.
  - **Pre-bump drift guard.** The version command refuses to assemble a
    train when a package's pubspec is ahead of its newest release tag
    (pre-bumped pubspec or unpushed tags) instead of double-bumping — the
    pubspec current version is the bump BASE.
  - **Workspace-root constraint cascade.** The workspace ROOT joins the
    graph as a private node (never releases), so root-level constraints on
    members cascade with the train instead of drifting stale.
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




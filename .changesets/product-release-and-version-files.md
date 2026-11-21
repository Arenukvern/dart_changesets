---
'dart_changesets': minor
---

New optional, backward-compatible release features: `product_tag` config
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

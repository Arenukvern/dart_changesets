---
name: dart-changesets-maintainer
description: >-
  Maintain the dart_changesets engine itself: intent files, version PRs,
  per-tag pub.dev publish trains with the dependency wait, reusable workflow
  contract (v1), self-publish dogfooding, and engine ADRs. Use when changing
  the engine CLI or workflows, debugging a consumer train, or moving the v1
  tag.
license: MIT
metadata:
  version: 1.0.0
  author: Arenukvern
compatibility:
  - dart
  - github-actions
---

# dart_changesets maintenance

Single-package repository: the engine AND the released package are the repo
root, released through its own action (`release.yml` + `self_publish.yml`) —
dogfooding is the acceptance test. Read `AGENTS.md` first; it owns the
conventions (pub_semver math, cascade test coverage, action/engine pairing).

## Invariants (do not break)

- **Authorization is tag-pattern OIDC, no GitHub environment** — repository +
  per-package tag pattern + pubspec version (dart.dev rules; dart-lang/core
  publishes the same way). Decision record:
  [doc/decisions/0001-no-github-environment-in-publish-path.md](../doc/decisions/0001-no-github-environment-in-publish-path.md).
  Enabling pub.dev's "Require GitHub Actions environment" checkbox on a
  consumer package makes its publish fail loudly by design.
- **Train convergence is owned by `publish-tag`** — the dependency wait
  (default 15 minutes, progress-logged per poll) holds a dependent run until
  its same-train floors are visible on pub.dev. Configurable via
  `--dependency-wait-minutes` and the reusable workflow's
  `dependency-wait-minutes` input (`0` = fail fast). Decision record:
  [doc/decisions/0002-dependency-wait-owned-by-publish-tag.md](../doc/decisions/0002-dependency-wait-owned-by-publish-tag.md).
- **A tag is pushed only after `verify-tag` passes.** The release step
  checks that the package pubspec at the merge commit still carries the
  tag's version before creating the tag. A consumer workflow that rewrites
  pubspecs on the version PR after `version` applied otherwise leaves a tag
  that publishes nothing and blocks the next train with release drift
  (mcp_flutter, 2026-11-24).
- **The floating `v1` tag is the consumer contract.** Consumers resolve
  `uses: …@v1`; merging a workflow change alone is inert — activation is the
  hand force-move of `v1` to the released commit (CONTRIBUTING). Move it only
  for changes consumers must see, and say so in the PR.

## Workflow

1. `steward doctor --json`, then `dart pub get && dart analyze && dart test`
   — the recorded quality gate. Extend the cascade tests with every engine
   change.
2. Change intent lands as `.changesets/*.md` (verbatim upstream-changesets
   format); the repo releases itself through the same train it provides.
3. For consumer-facing behavior changes: update the README section the
   change touches (consumers read the README, not this repo's issues), add or
   amend an ADR under `doc/decisions/`, then merge and force-move `v1`.
4. Debugging a consumer train: read the failing `dart_changesets publish` run
   — exit 64 usage, 65 bootstrap, 66 dependency-wait expiry (re-dispatch
   after the sibling lands; skip-existing keeps the rest), 67 publish, 68
   visibility. The dependency wait logs pending floors and elapsed/budget
   every poll.
5. Consumer-side wiring lives in each consumer (trigger workflow wrapping
   `publish.yml@v1`); templates: [example/consumer-workflows/](../example/consumer-workflows/README.md).
   Badge snippets for consumer READMEs: engine README, "Show your release
   train".

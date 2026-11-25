# dart_changesets — North Star

**Status:** active · **Audience:** humans, agents, and consumer repositories

## What we are

**dart_changesets** is a **changesets-style release engine for Dart**: a GitHub Action plus CLI that turns reviewed intent files into a version PR, then into **per-package tags and pub.dev publish trains** — without manual release choreography after initial pub.dev setup.

Release intent lives in `.changesets/*.md` merged with application code. On `main`, the engine assembles semver bumps (including dependent constraint cascades via `package:pub_semver`), opens or updates `chore: version packages`, and on merge pushes one `<package>-v<version>` tag per released package and dispatches the consumer’s publish workflow once per tag. Ordering across a train emerges from **dependency wait**, **skip-existing**, and pub.dev’s ref-gated OIDC checks — not from a single job that publishes every package at once.

We are **not** a general CI system, **not** a substitute for pub.dev’s first-publish bootstrap, and **not** a batch publisher that assumes one ref can upload an entire monorepo train.

## Success looks like

| Outcome | Proof |
| --- | --- |
| Intent in a feature PR becomes a reviewable version PR on `main` | Assemble mode in `action.yml` + passing engine tests |
| Merging the version PR pushes tags and starts publish legs without hand-dispatch | Release mode + consumer `release.yml` permissions |
| Concurrent train legs converge on pub.dev without per-repo bash waiters | `publish-tag` dependency wait ([ADR 0002](decisions/0002-dependency-wait-owned-by-publish-tag.md)) |
| Consumers pin `@v1` and receive workflow fixes when maintainers move `v1` | `major-action-ref` on self-release |
| The engine package on pub.dev matches what this repo shipped | **Dogfood:** this repository releases itself via `release.yml` + `self_publish.yml` |
| Layout and API ship cleanly | CI: `dart analyze`, `dart test`, and **strict** `dart pub publish --dry-run` (0 warnings) |

## What we own

| Own | Do not own |
| --- | --- |
| Composite action (`action.yml`) and reusable `publish.yml` | Consumer product code and test suites |
| Semver train planning, constraint cascade, changelog application | Publishing every package from one ref |
| `publish-tag` static checks, bootstrap gate, dependency wait, dry-run | GitHub Environment objects on the publish path ([ADR 0001](decisions/0001-no-github-environment-in-publish-path.md)) |
| Consumer templates under `example/consumer-workflows/` | Enforcing PAT vs `GITHUB_TOKEN` policy in every consumer org |
| Maintainer skill `skills/dart-changesets-maintainer/` | Domain-specific release notes beyond configured `product_tag` |

## Boundaries (non-negotiable)

- **Behavior SSOT is code and workflows** — docs link inward; FAQs compress, they do not replace `lib/src/` or `action.yml`.
- **pub.dev rules are facts** — per-tag automated publishing; first publish of each package is always manual.
- **Versions use `package:pub_semver`** — never regex math on version strings.
- **`action.yml` and `lib/src/apply.dart`** share one version-PR detection contract; change both together.
- **Package docs live under `doc/`** — never create top-level `docs/` (strict publish dry-run fails).
- **Strategic why** → `doc/decisions/` ADR; **standing why** → [DESIGN_FAQ.md](DESIGN_FAQ.md); **how** → [DX_FAQ.md](DX_FAQ.md).

## Archetype

Primary surface: **CLI/tool** (`steward.yaml` → `cli_tool`). Proof is commands (`dart_changesets --help`), tests, typed publish exit codes, and release artifact provenance on pub.dev and GitHub Marketplace.
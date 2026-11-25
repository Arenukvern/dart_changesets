# Design Decisions FAQ — dart_changesets

Standing **why** answers for the release engine. For step-by-step usage see [DX_FAQ.md](DX_FAQ.md). Strategic decisions live in [doc/decisions/](decisions/); this file compresses operational rationale.

## Charter

**Q: Where is the product charter maintained?**
A: [NORTH_STAR.md](NORTH_STAR.md) — outcome, success table, and boundaries. `AGENTS.md` is only the agent map; `steward.yaml` points `vision_source` at the North Star.

## Release model

**Q: Why intent files in `.changesets/` instead of conventional commits?**
A: Release intent is reviewed prose in PRs, not inferred from commit prefixes. The assembler consumes `.changesets/*.md` on push to `main` and builds one version PR — same contract as upstream [changesets](https://github.com/changesets/changesets), adapted for `pubspec.yaml`.

**Q: Why one composite action for both assemble and release?**
A: Modeled on `@changesets/action`: a single push to `main` either applies pending intents onto the version branch (assemble) or, when the merge commit matches the version-PR marker and `.changesets/.pending-train.json` is at HEAD, pushes tags and dispatches publish runs (release). See `action.yml` header comments and `lib/src/apply.dart`.

**Q: How does release mode detect a version-PR merge?**
A: The commit message must match the configured title (default `chore: version packages`) and the pending-train artifact must be present. Changing either detector requires updating **both** `action.yml` and `lib/src/apply.dart` — agents treat that pair as one contract (`AGENTS.md`).

**Q: Why not one CI job that publishes every package in a train?**
A: pub.dev automated publishing is **ref-gated per package tag**; one workflow run publishes one package at one tag ref. Train ordering emerges from per-tag runs plus dependency waits and skip-existing, not from a monolithic publish step (`README.md`, `lib/src/publish.dart`).

## Version math

**Q: Why `package:pub_semver` instead of string bumping?**
A: Caret cascade rules (0.x behavior, private dependents, topo order) are semver facts. Regex version math drifts; tests in `test/plan_and_apply_test.dart` and friends lock the cascade — extend them with every engine change.

**Q: What is the dependent bump for publishable dependents?**
A: When a dependency’s new version no longer satisfies an existing caret constraint, dependents get a configurable bump (`dependent_bump` in `changesets.yaml`, default `patch`). Private packages get constraint rewrites without a pub.dev release.

## Tags and consumer refs

**Q: Why `{package}-v{version}` tags?**
A: Matches pub.dev’s per-package tag pattern input and keeps monorepo packages independent. Configurable via `tag_format` in `changesets.yaml` (default `'{package}-v{version}'`).

**Q: Why a floating `v1` on this repository only?**
A: Consumers pin `uses: Arenukvern/dart_changesets@v1`. Merging workflow changes alone is inert until `major-action-ref` moves `v1` to the released commit (`action.yml`, `CONTRIBUTING.md`). Requires a token with `workflows` permission when workflow files change.

**Q: What is `product_tag` for?**
A: One nominated package also receives a product-shaped tag (e.g. `v1.2.3`) and a GitHub release at version-PR merge. Binary or app builds should chain **after** that package’s publish leg — dependencies are not on pub.dev at merge time (`README.md`).

## Publish path

**Q: Why no GitHub `environment` on the reusable publish workflow?**
A: Authorization is pub.dev’s three checks (repository, tag pattern, pubspec version) — same as dart-lang/core. Declaring an environment auto-creates repo objects consumers never configured; enabling pub.dev’s optional environment checkbox then fails loudly. Full deliberation: [ADR 0001](decisions/0001-no-github-environment-in-publish-path.md).

**Q: Why does `publish-tag` own the dependency wait?**
A: Concurrent per-tag runs often publish siblings whose floors are not visible yet. The engine waits (default 15 minutes, progress-logged) instead of failing after a short silent wait or pushing bash waiters into every consumer. [ADR 0002](decisions/0002-dependency-wait-owned-by-publish-tag.md).

**Q: What do publish exit codes 64–68 mean?**
A: Defined in `lib/src/publish.dart`: 64 usage/static checks, 65 first-publish bootstrap needed, 66 dependency-wait expiry (re-dispatch), 67 publish failure, 68 pub.dev visibility timeout. The maintainer skill lists the same contract.

**Q: Why strict `dart pub publish --dry-run` before real publish?**
A: Warnings (including disallowed top-level names like `docs/`) must block the train. This repo’s `docs/` → `doc/` rename exists because layout warnings prevented the first pub.dev 1.x ship (`CHANGELOG.md`); CI runs dry-run on every PR (`.github/workflows/ci.yml`).

## Tokens and CI side effects

**Q: Why does GITHUB_TOKEN make the version-PR show a failed zero-job CI run?**
A: Pushes from `GITHUB_TOKEN` do not trigger other workflows. The assembler pushes the version branch with the default token, so no workflows run — GitHub often surfaces that as a failed check with zero jobs. Optional `token` input (PAT) makes those pushes run full CI (`README.md`, `action.yml`).

**Q: Why dispatch `publish.yml` per tag when no PAT is set?**
A: `GITHUB_TOKEN` tag pushes also fire no downstream workflows. The action runs `gh workflow run` on each tag ref so OIDC publish can proceed when pub.dev allows workflow_dispatch (`action.yml`).

## Package layout and docs

**Q: Why `doc/` (singular) at the repo root?**
A: `doc/` ships on pub.dev with the package. A plural `docs/` directory triggers package-layout warnings that fail strict dry-run — never add `docs/` at the repo root (`CHANGELOG.md`, `ci.yml`).

**Q: Why does this repo release itself through its own action?**
A: Dogfooding is the acceptance test: engine, `action.yml`, and `publish.yml` must survive real trains. Configuration is `changesets.yaml` with `root_package: true` (`AGENTS.md`).

## Configuration extras

**Q: What are `version_files` for?**
A: Non-pubspec version strings (e.g. `lib/src/version.dart`) bump in lockstep via patterns with a `{version}` placeholder — see `changesets.yaml` and `lib/src/apply.dart` (`bumpVersionFileContent`).

**Q: Where does workspace discovery order come from?**
A: Root `workspace:` in `pubspec.yaml` wins, then `packages_dir` (with `packages/` fallback), then implicit root pubspec when no package tree exists (`README.md`).
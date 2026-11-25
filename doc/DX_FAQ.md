# DX FAQ — dart_changesets

**How** to develop, consume, and debug the engine. For rationale see [DESIGN_FAQ.md](DESIGN_FAQ.md).

## 🧭 Router

```text
CHARTER           → doc/NORTH_STAR.md
WHY / ADRs          → doc/DESIGN_FAQ.md, doc/decisions/
HOW contribute    → this file, ../CONTRIBUTING.md, ../AGENTS.md
Agent invariants  → ../AGENTS.md, skills/dart-changesets-maintainer/SKILL.md
Consumer wiring   → ../README.md, example/consumer-workflows/
Engine source     → action.yml, lib/src/, bin/dart_changesets.dart
```

## 🌱 Local setup

Requirements: Dart SDK `^3.14.0` (`pubspec.yaml`). No Flutter for engine work.

```bash
git clone https://github.com/Arenukvern/dart_changesets
cd dart_changesets
dart pub get
dart analyze    # zero errors
dart test       # cascade + publish fixtures
dart pub publish --dry-run   # zero warnings (CI gate)
```

## 📝 Intent desk

Add a release intent before merging user-facing work (including published `doc/`):

```markdown
---
'dart_changesets': patch
---

Short changelog prose for pub.dev.
```

```bash
dart run dart_changesets add    # interactive
dart run dart_changesets status # pending → planned releases
```

Files live in `.changesets/`; the assembler deletes them when the version PR is applied (`.changesets/README.md`).

## 🔧 CLI map

One-shot without global install:

```bash
dart run dart_changesets status
dart run dart_changesets version [--check]
dart run dart_changesets doctor [--no-network]
dart run dart_changesets tags
dart run dart_changesets publish-tag --tag <pkg>-v<semver> [--execute] [--skip-existing] \
  [--dependency-wait-minutes 15] [--skip-dependency-gate]
```

Every subcommand documents flags via `--help` (`test/cli_test.dart` enforces help exits 0).

## 🚀 Consumer action

Minimal main-side wiring (copy full templates from `example/consumer-workflows/`):

```yaml
# .github/workflows/release.yml
on:
  push:
    branches: [main]
jobs:
  release:
    permissions:
      contents: write
      pull-requests: write
      actions: write   # dispatch publish.yml per tag
    steps:
      - uses: actions/checkout@v5
        with: { fetch-depth: 0 }
      - uses: Arenukvern/dart_changesets@v1
        env: { GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }} }
```

```yaml
# .github/workflows/publish.yml — wrap reusable workflow
jobs:
  publish:
    uses: Arenukvern/dart_changesets/.github/workflows/publish.yml@v1
    permissions:
      id-token: write
      contents: read
    with:
      tag: ${{ github.event.inputs.tag || github.ref_name }}
      execute: true
```

Before first train: enable **Allow GitHub Actions to create and approve pull requests**; configure pub.dev automated publishing per package tag pattern (`README.md` quick start).

## 🏷️ Version PR quirks

| Symptom | Cause | Fix |
| --- | --- | --- |
| Version branch updated, no PR | Workflow permissions | Settings → Actions → allow bot PRs |
| Red CI, **0 jobs** on version PR | Push used `GITHUB_TOKEN` | Expected without PAT; merge if assemble succeeded, or set `token:` for CI on the branch |
| Tags pushed, no publish | Missing `actions: write` | Add to `release.yml` `permissions`; re-run release or dispatch publish per tag |

## 📦 Publish troubleshooting

| Exit / symptom | Likely cause | Fix |
| --- | --- | --- |
| **64** | Bad tag, version mismatch, changelog heading | Match `tag_format`; ensure `## X.Y.Z` in `CHANGELOG.md` |
| **65** | Package never on pub.dev | Manual first `pub publish`, then automated tags |
| **66** | Sibling not visible within budget | Wait and re-dispatch; tune `dependency-wait-minutes` or recover with `skip-dependency-gate` |
| Dry-run FAIL on `docs/` | Wrong doc directory name | Use `doc/` only — rename or remove `docs/` (`CHANGELOG.md`) |
| Layout warning fails CI | Any `pub publish` warning | `dart pub publish --dry-run` locally; fix before merge |

## 🐕 Maintainer self-release

This repo uses `changesets.yaml` with `root_package: true`. Ship engine changes:

1. Add `.changesets/*.md` intent.
2. Merge to `main` → bot opens `chore: version packages` PR.
3. Merge version PR → tags + `self_publish.yml` train.
4. When consumers must see workflow edits, ensure `v1` moves (`major-action-ref` in `.github/workflows/release.yml`).

## ✅ PR checklist (engine)

- [ ] `dart analyze` + `dart test` + `dart pub publish --dry-run` (no warnings)
- [ ] Cascade tests updated if version math changed
- [ ] Intent in `.changesets/` for published changes
- [ ] README for consumer behavior; `doc/DESIGN_FAQ.md` or `doc/DX_FAQ.md` when why/how shifts
- [ ] ADR under `doc/decisions/` for cross-cutting decisions
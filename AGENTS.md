# AGENTS.md — map (not encyclopedia)

You are in **dart_changesets**: a changesets-style Dart release engine (Action + CLI). Read the charter before architectural changes.

## Start here

| I need… | Read |
| --- | --- |
| **Charter, scope, success criteria** | [doc/NORTH_STAR.md](doc/NORTH_STAR.md) |
| **Why** (standing decisions, trade-offs) | [doc/DESIGN_FAQ.md](doc/DESIGN_FAQ.md) · [doc/decisions/](doc/decisions/) |
| **How** (setup, CLI, consumer wiring, debug) | [doc/DX_FAQ.md](doc/DX_FAQ.md) |
| **Consumer onboarding** | [README.md](README.md) · [example/consumer-workflows/](example/consumer-workflows/) |
| **Which FAQ to edit** | [.cursor/rules/faq_usage.mdc](.cursor/rules/faq_usage.mdc) |
| **Engine maintainer procedure** | [skills/dart-changesets-maintainer/SKILL.md](skills/dart-changesets-maintainer/SKILL.md) |

Single-package repo: engine and published package are the repository root; dogfooding via `.github/workflows/release.yml` + `self_publish.yml`.

## Non-negotiables

1. **`dart analyze`, `dart test`, and strict `dart pub publish --dry-run`** (0 warnings) before claiming work is done — matches `.github/workflows/ci.yml`.
2. **Release model is fixed** — intent files → version PR → per-tag publish; never design batch publishing from one ref (see North Star).
3. **Cascade math is `package:pub_semver`** — extend `test/plan_and_apply_test.dart` (and related fixtures) when version logic changes.
4. **`action.yml` + `lib/src/apply.dart`** version-PR detection changes land together.
5. **AGENTS.md stays a map** — update FAQs or README for prose; new strategic why → ADR under `doc/decisions/`.

## Validation

```bash
dart pub get
dart analyze
dart test
dart pub publish --dry-run   # 0 warnings required
```

## File map

| Path | Role |
| --- | --- |
| `action.yml` | Assemble + release composite action |
| `.github/workflows/publish.yml` | Reusable per-tag publish (`workflow_call`) |
| `lib/src/` | Engine: plan, apply, publish-tag, doctor, workspace graph |
| `bin/dart_changesets.dart` | CLI entry |
| `changesets.yaml` | Self-release config (`root_package: true`) |
| `doc/NORTH_STAR.md` | Charter |
| `doc/DESIGN_FAQ.md` / `doc/DX_FAQ.md` | Why / how (published on pub.dev) |
| `doc/decisions/` | ADRs |
| `steward.yaml` | Steward contract (`vision_source` → North Star) |
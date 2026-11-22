# AGENTS.md — dart_changesets

Single-package repository: the engine AND the released package are the repo
root. It releases itself through its own action (`.github/workflows/
release.yml` + `self_publish.yml`) — dogfooding is the acceptance test.

## Validation

```bash
dart pub get
dart analyze
dart test
```

## Conventions

- Design authority: the changesets model (intent files → version PR →
  per-tag publish). Attribution to the TS original lives in README.md.
- pub.dev constraints are facts, not preferences: publishing is ref-gated
  per package tag; the first publish of a package is always manual. Any
  change that assumes batch publishing from one ref is wrong by construction.
- Versions and constraints are computed with `package:pub_semver`, never
  regex math. Tests cover the cascade (0.x carets, private dependents,
  topo order) — extend them with every engine change.
- `action.yml` mode detection keys on the commit prefix + the train artifact;
  changing either requires updating both action.yml and the engine's
  `apply.dart`.

## Files

- `action.yml` — composite action (assemble + tag/dispatch modes).
- `.github/workflows/publish.yml` — reusable per-tag publish workflow
  (workflow_call); consumers wrap it with their own trigger workflow.
- `example/consumer-workflows/` — copy-paste consumer templates.
- `docs/decisions/` — engine ADRs (0001: why the publish path declares no
  GitHub environment).

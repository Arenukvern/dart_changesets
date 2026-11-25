# Contributing

Thank you for your interest in dart_changesets! 🌱

Issues and pull requests live on
[GitHub](https://github.com/Arenukvern/dart_changesets). For behavior
questions, start with the [README](README.md) and [AGENTS.md](AGENTS.md)
(invariants and file map). Security reports go to
[SECURITY.md](SECURITY.md) — never in a public issue.

## Development setup

Requirements: the Dart SDK (`^3.14.0`) on your path. No Flutter needed —
the engine is pure Dart.

```bash
git clone https://github.com/Arenukvern/dart_changesets
cd dart_changesets
dart pub get
```

## Validation

Every change must pass:

```bash
dart analyze   # zero errors
dart test      # engine tests, including the cascade fixtures
```

## Project conventions

- **Design authority is the changesets model**: intent files → assembled
  version PR → per-tag publish. Attribution to the original TypeScript
  [changesets](https://github.com/changesets/changesets) lives in
  [README.md](README.md); ported code (the publish leg) carries attribution
  comments in place.
- **pub.dev constraints are facts, not preferences**: publishing is
  ref-gated per package tag; the first publish of a package is always
  manual. Any change that assumes batch publishing from one ref is wrong by
  construction.
- **Versions are computed with `package:pub_semver`, never regex math.**
  Tests cover the cascade (0.x carets, private dependents, topo order) —
  extend them with every engine change.
- **`action.yml` mode detection is a contract**: it keys on the version-PR
  commit prefix plus the train artifact. Changing either requires updating
  both `action.yml` and `lib/src/apply.dart` together.
- The repository **releases itself** through its own action (dogfood): an
  engine change you want shipped ships via an intent file in
  `.changesets/`.

## Contributor credit

The README contributor table is generated from
[`.all-contributorsrc`](.all-contributorsrc) with
[all-contributors](https://allcontributors.org/). After a merged contribution,
comment on any open pull request (or ask a maintainer to):

```text
@all-contributors please add @<github-login> for code
```

Replace `code` with what actually happened — for example `doc`, `bug`,
`userTesting`, `infra`, `security`, `research`, `maintenance`, or `tutorial`
(see [emoji key](https://allcontributors.org/docs/en/emoji-key)). The bot opens
a PR updating `.all-contributorsrc` and the README table; you can also run
locally:

```bash
npx all-contributors-cli add <github-login> code,doc
npx all-contributors-cli generate
```

Commit both `.all-contributorsrc` and `README.md`.

Install the [all-contributors GitHub App](https://github.com/apps/allcontributors)
on this repository if the bot is not already enabled.

## Pull requests

One logical change per PR. CI runs `dart analyze` + `dart test` on every
pull request.

Checklist:

- [ ] `dart analyze` clean, `dart test` green
- [ ] Cascade fixtures extended if the engine's version math changed
- [ ] Intent file added (`.changesets/`) for user-facing changes
- [ ] Docs updated: README for consumer-facing behavior, AGENTS.md for
      invariants
- [ ] Attribution comment added when porting logic from the TS original or
      intentcall

## Releasing (maintainers)

The action releases this repository: write an intent file, merge to `main`,
merge the `chore: version packages` PR — tags and the pub.dev publish
dispatch follow automatically. The floating major tag `v1` moves to each
released commit so consumers pinning `@v1` receive the release, and a
matching semver release (`v1.x.y`) is published to the
[GitHub Marketplace](https://github.com/marketplace/actions/dart_changesets)
on the same tag.

## Code of conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you agree to uphold it.

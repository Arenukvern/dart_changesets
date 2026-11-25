# ADR 0001 — No GitHub environment in the publish path

- **Status:** Accepted
- **Date:** 2026-11-22
- **Deciders:** Arenukvern (maintainer), reviewed by three independent
  analysis lenses (supply-chain security, release ops, generational
  architecture)

## Context

PR for the reusable publish workflow briefly declared
`environment: pub.dev` on the publish job, staging pub.dev's optional
"Require GitHub Actions environment" hardening. GitHub auto-creates a
repository environment on first reference, so every consumer repo that ran a
publish silently acquired a `pub.dev` environment object — six repos, none
authored by their owners, all with zero protection rules.

Meanwhile pub.dev's per-package "Require GitHub Actions environment"
checkboxes were off everywhere, so the token's environment claim was never
read: the declaration was inert text with one real effect (the silent
auto-creation above). Worse, the staged state failed in the deceptive
direction — a consumer flipping a checkbox would have published successfully
with zero protection, appearing hardened.

The ecosystem reference does not use environments either: dart-lang/core
publishes with plain tag-pattern OIDC (repository + tag pattern + pubspec
version), and the environment's actual purpose in the dart.dev recipe is
anchoring required reviewers — human approval per publish, which defeats
concurrent per-tag trains.

## Decision

1. The reusable publish workflow declares **no** GitHub environment — by
   design. Publishing authorization is exactly the three pub.dev checks.
2. The README's "pub.dev authorization" section documents the deliberate
   absence, including the loud failure mode: enabling the admin checkbox
   makes that package's publish fail with an environment-mismatch error.
3. Repo-local hardening belongs in a tag-protection ruleset (restrict who can
   push `<package>-v*` tags), not in an environment object. Note the exact
   scope: ruleset bypass is unconditional for admins, so a ruleset constrains
   only non-admin collaborators — dormant defense while every write account is
   trusted.
4. An `environment` workflow input may be added later if a consumer genuinely
   wants reviewer-gated publishing; it is a backward-compatible `@v1` change.
   Until then, YAGNI — the interface is pinned by six consumer repos and
   carries no knob nobody uses.

## Consequences

- Consumers flip no checkboxes and inherit no hidden state; the failure mode
  for a wrong admin setting is loud, not silent.
- The publish job is plain OIDC (`id-token: write` on the job; consumers scope
  that grant to the reusable call only — see the consumer template — so their
  helper jobs cannot mint pub.dev tokens).
- Consumers that had stray `pub.dev` environments auto-created deleted them
  (mcp_flutter, oka, ecsly, 2026-11-22).

## References

- Engine PR removing the declaration and the `v1` force-move to it (merging
  alone is inert — `v1` is the hand-moved floating tag consumers resolve)
- Consumer side: Arenukvern/mcp_flutter PR #203 and its ADR
  `docs/decisions/0022_no_github_environment_in_publish_path.mdx`
- [dart.dev automated publishing](https://dart.dev/tools/pub/automated-publishing)
- dart-lang/core `.github/workflows/publish.yaml`

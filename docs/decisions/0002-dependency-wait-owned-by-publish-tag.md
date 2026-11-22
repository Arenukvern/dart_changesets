# ADR 0002 — Dependency wait owned by publish-tag

- **Status:** Accepted
- **Date:** 2026-11-22
- **Deciders:** Arenukvern (maintainer)

## Context

Per-tag publish runs are dispatched concurrently, but pub.dev validates
dependency constraints at upload time: publishing `supervisor 0.12.1`
(requires `core ^0.12.0`) cannot succeed until `core 0.12.0` is visible on
pub.dev. The engine already waited for those floors inside `publish-tag` —
but only for 240 silent seconds, then failed with exit 66 and "re-run this
publish".

The oka 0.12 train (2026-11-22) hit exactly that: a build-heavy sibling
(`oka_core`) took longer than 240s to resolve, dry-run, upload, and become
visible; four consecutive `oka_supervisor` dispatches failed identically and
needed manual re-runs. One consumer (mcp_flutter) had patched the problem
per-repo with a bash waiter (hardcoded package family + directory map) — a
fix that could not generalize.

## Decision

`publish-tag` owns train convergence:

1. The dependency-wait budget defaults to **15 minutes** (the budget proven
   in mcp_flutter's 8.0.0 train), configurable via `--dependency-wait-minutes`
   (CLI) and a `dependency-wait-minutes` input on the reusable publish
   workflow (`0` = fail fast). The publish job's timeout grew to 30 minutes
   to fit worst case.
2. Each poll logs progress — pending floors and elapsed/budget — so a long
   wait is visible in CI instead of looking hung.
3. On expiry the failure names the recovery route explicitly:
   re-dispatch (workflow_dispatch with the tag, execute checked);
   skip-existing keeps completed packages untouched.
4. No consumer-side waiter. Convergence is engine behavior, uniform for every
   consumer; consumers tune it with one input instead of copying scripts.

## Consequences

- Concurrent trains converge by default; the 0.12-style failure mode requires
  a sibling slower than 15 minutes (fail with a readable message, not a
  mystery).
- Consumers lost a redundant local mechanism when mcp_flutter retired its
  bash waiter (mcp_flutter PR #206) — one owner, one knob.
- The wait bounds worst-case publish-job latency to the budget; trains with
  many sequential dependency levels pay the chain's sum only when floors are
  genuinely slow, and progress logs make that visible.

## References

- Engine PR #10 (+ `v1` force-move — the activation step)
- oka run 44980163056 (the four consecutive exit-66 failures)
- mcp_flutter PR #206 (local waiter retired after this landed)
- [ADR 0001](0001-no-github-environment-in-publish-path.md) — authorization model (unchanged)

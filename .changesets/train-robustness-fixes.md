---
'dart_changesets': minor
---

Release-train robustness, four production gaps surfaced by the oka
2026-11-22 release cut:

- **Merge-commit merges now release.** Detect mode recognized only the
  squash message prefix ("chore: version packages"); a merge-commit merge
  of the version PR no-op'd and the train stalled until tags were pushed
  by hand. The action now also identifies the merge by the PR itself
  (`gh pr view` state/mergeCommit == HEAD).
- **Version-suffixed changelog headings accepted.** `publish-tag` accepts
  a `##` heading that STARTS with the exact version (`## 1.2.3
  (2026-11-22)` counts; `## 1.2.31` does not) and names the headings
  found when the entry is missing, so hand-tended changelogs stop failing
  the publish gate.
- **Pre-bump drift guard.** The version command refuses to assemble a
  train when a package's pubspec is ahead of its newest release tag
  (pre-bumped pubspec or unpushed tags) instead of double-bumping — the
  pubspec current version is the bump BASE.
- **Workspace-root constraint cascade.** The workspace ROOT joins the
  graph as a private node (never releases), so root-level constraints on
  members cascade with the train instead of drifting stale.

---
'dart_changesets': minor
---

Dependency wait on publish-tag raised to 15 minutes by default (was 240s), made configurable via a new `--dependency-wait-minutes` CLI flag and a `dependency-wait-minutes` reusable-workflow input, and the poll now logs progress each round (which floors are still pending, elapsed/budget) instead of sitting silent. Root evidence — oka 0.12 train, 2026-11-22: four consecutive `oka_supervisor` publish failures because a build-heavy sibling (`oka_core`) took longer than the old 4-minute budget to resolve, dry-run, upload, and become visible; each run died with exit 66 and needed a manual re-dispatch.

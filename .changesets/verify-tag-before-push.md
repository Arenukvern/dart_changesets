---
'dart_changesets': patch
---

Release step runs `verify-tag` before creating each package tag: refuse (exit 65) when the pubspec at the merge commit no longer carries the tag version, instead of pushing a tag that publishes nothing and blocks the next train with release drift.

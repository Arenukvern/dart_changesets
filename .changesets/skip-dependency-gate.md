---
'dart_changesets': minor
---

`publish-tag` gains `--skip-dependency-gate` (and the reusable workflow a `skip-dependency-gate` input): publish as-is without the dependency-floor gate — a warning names the invisible floors and pub.dev's upload validation remains the arbiter. For recovery flows that intentionally publish against floors that are not visible yet, instead of burning the whole dependency-wait budget on a floor nothing will ever satisfy.

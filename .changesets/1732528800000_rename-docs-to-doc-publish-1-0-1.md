---
'dart_changesets': patch
---

Rename top-level `docs/` to `doc/` so `dart pub publish` passes strict package-layout validation (plural directory names warn and fail publish-tag dry-run). Git tag `dart_changesets-v1.0.0` shipped on GitHub but never landed on pub.dev because of that warning; **1.0.1** is the first 1.x release on pub.dev. CI now runs `dart pub publish --dry-run` on every push and PR so layout warnings cannot recur.
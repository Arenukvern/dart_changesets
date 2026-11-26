---
'dart_changesets': patch
---

A `workflow_dispatch` run no longer re-enters release mode when every tag of the pending train already exists on the remote; it assembles the intents that landed since. Restores the engine's own `product_tag` so each train gets a `v<version>` tag and a GitHub release again.

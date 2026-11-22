---
'dart_changesets': patch
---

**Declared dependents keep their constraint rewrites regardless of
planning order.** The plan queue is alphabetical, so a declared dependent
whose name sorts before its dependency (`oka_app_gallery` before
`oka_core`) was planned BEFORE the dependency's new version existed — its
constraint rewrite landed in the never-consumed pending map and the
version PR shipped a graph that cannot resolve. Rewrites now merge into
an already-planned release in place.

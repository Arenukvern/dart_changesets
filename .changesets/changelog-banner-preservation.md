---
'dart_changesets': patch
---

**Changelog comment banners stay above the new version section.**
`prependChangelog` now treats top-of-file HTML comments (e.g.
`<!-- markdownlint-disable … -->`) as part of the header region instead
of pushing them below the inserted section — consumers keep such banners
in the first lines on purpose (oka's markdownlint gate requires the
banner within the first 5 lines; the naive header-insert moved it to
line 9 and failed the train's contracts job).

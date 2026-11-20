---
'dart_changesets': patch
---

`runner` and `publish-tag` now decide the publish runner workspace-aware:
`pub publish` inside a pub-workspace member resolves the whole workspace, so
a single `sdk: flutter` member requires the Flutter SDK even when publishing
a dart-only tag (previously the dart-only fast path crashed at dry-run in
mixed workspaces). The reusable publish workflow correspondingly installs
Flutter only when the workspace needs it, drops the redundant workspace
`pub get` step (publish resolves itself), and stops pinning the Flutter
version — an empty `flutter-version` input now tracks the latest stable
release, keeping consumer release trains maintenance-free across the Flutter
cadence.

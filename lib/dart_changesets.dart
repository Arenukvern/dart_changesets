/// Changesets-style release engine for Dart repositories.
///
/// Intent files under `.changesets/` become a version train: the engine
/// applies semver bumps and dependent constraint cascades, writes a pending
/// train artifact for CI, and supports per-tag publishing helpers.
///
/// Use the [dart_changesets] CLI locally and the composite GitHub Action
/// (`action.yml`) in CI. Design inspired by
/// [changesets](https://github.com/changesets/changesets) and
/// [@changesets/action](https://github.com/changesets/action).
library;

export 'src/apply.dart';
export 'src/bump.dart';
export 'src/changeset.dart';
export 'src/config.dart';
export 'src/doctor.dart';
export 'src/product.dart';
export 'src/publish.dart';
export 'src/version.dart';
export 'src/workspace_graph.dart';

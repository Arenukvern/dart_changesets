import 'dart:io';

import 'package:yaml/yaml.dart';

/// Product-release configuration: ONE package whose release additionally
/// gets a product-shaped tag (e.g. `v7.2.1`) and a GitHub release at the
/// version-PR merge commit.
final class ProductTagConfig {
  const ProductTagConfig({required this.package, this.format = 'v{version}'});

  /// The package NAME (as declared in its pubspec `name:`, not its
  /// directory). Must exist in the workspace graph — an unknown name is a
  /// configuration error and fails loudly.
  final String package;

  /// Tag template with a `{version}` placeholder, e.g. `v{version}`.
  final String format;

  String tagFor(String version) => format.replaceAll('{version}', version);
}

/// One version string outside pubspec that must move with a package's
/// release: a VERSION file, a JSON version field, a Dart constant. [pattern]
/// is a template where `{version}` stands for the package's CURRENT pubspec
/// version; the pattern must match exactly once or the apply fails loudly.
final class VersionFileConfig {
  const VersionFileConfig({required this.path, required this.pattern});

  /// Path relative to the repository root.
  final String path;
  final String pattern;
}

/// Repository-level configuration, loaded from `changesets.yaml` at the repo
/// root. Every key is optional; absent files use the defaults below.
final class ChangesetsConfig {
  const ChangesetsConfig({
    this.packagesDir = 'pkgs',
    this.dependentBump = DependentBump.patch,
    this.ignore = const <String>{},
    this.tagFormat = '{package}-v{version}',
    this.rootPackage = false,
    this.productTag,
    this.versionFiles = const <String, List<VersionFileConfig>>{},
  });

  /// Directory scanned one level deep for package `pubspec.yaml` files.
  final String packagesDir;

  /// Version bump applied to publishable dependents whose dependency
  /// constraint had to be rewritten during a cascade.
  final DependentBump dependentBump;

  /// Packages this tool must never release (in addition to any package whose
  /// pubspec declares `publish_to: none`, which is always private).
  final Set<String> ignore;

  /// Tag template with `{package}` and `{version}` placeholders. The default
  /// matches pub.dev's per-package automated-publishing tag patterns.
  final String tagFormat;

  /// Include the repository root pubspec as a package (single-package
  /// repositories where the engine and the released package share the root).
  final bool rootPackage;

  /// When set, this package's releases also get a product tag + GitHub
  /// release at the version-PR merge commit (see [ProductTagConfig]).
  final ProductTagConfig? productTag;

  /// Per-package version strings outside pubspec to bump during `version`
  /// (see [VersionFileConfig]).
  final Map<String, List<VersionFileConfig>> versionFiles;

  /// Formats the release tag for [package] at [version].
  String tagFor(String package, String version) => tagFormat
      .replaceAll('{package}', package)
      .replaceAll('{version}', version);

  /// Parses a release tag previously produced by [tagFor]. Returns
  /// `(package, version)` or `null` when the tag does not match the format.
  (String, String)? parseTag(String tag) {
    final packagePlaceholder = tagFormat.indexOf('{package}');
    final versionPlaceholder = tagFormat.indexOf('{version}');
    if (packagePlaceholder < 0 || versionPlaceholder < 0) {
      return null;
    }
    // Split around the placeholders; the literal segments must appear in
    // order with arbitrary package/version values between them.
    final beforePackage = tagFormat.substring(0, packagePlaceholder);
    final between = tagFormat.substring(
      packagePlaceholder + '{package}'.length,
      versionPlaceholder,
    );
    final afterVersion = tagFormat.substring(
      versionPlaceholder + '{version}'.length,
    );
    var rest = tag;
    if (beforePackage.isNotEmpty) {
      if (!rest.startsWith(beforePackage)) return null;
      rest = rest.substring(beforePackage.length);
    }
    if (afterVersion.isNotEmpty) {
      if (!rest.endsWith(afterVersion)) return null;
      rest = rest.substring(0, rest.length - afterVersion.length);
    }
    if (between.isEmpty) return null;
    final betweenIndex = rest.lastIndexOf(between);
    if (betweenIndex < 0) return null;
    final package = rest.substring(0, betweenIndex);
    final version = rest.substring(betweenIndex + between.length);
    if (package.isEmpty || version.isEmpty) return null;
    return (package, version);
  }

  static ChangesetsConfig loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return const ChangesetsConfig();
    }
    final doc = loadYamlNode(file.readAsStringSync());
    if (doc is! YamlMap) {
      throw FormatException('changesets.yaml must be a YAML mapping: $path');
    }
    return ChangesetsConfig(
      packagesDir: (doc['packages_dir'] as String?) ?? 'pkgs',
      dependentBump: DependentBump.fromString(
        (doc['dependent_bump'] as String?) ?? 'patch',
      ),
      ignore: {
        if (doc['ignore'] is YamlList)
          for (final entry in doc['ignore'] as YamlList) entry.toString(),
      },
      tagFormat: (doc['tag_format'] as String?) ?? '{package}-v{version}',
      rootPackage: doc['root_package'] == true,
      productTag: _parseProductTag(doc['product_tag']),
      versionFiles: _parseVersionFiles(doc['version_files']),
    );
  }

  static ProductTagConfig? _parseProductTag(Object? raw) {
    if (raw == null) return null;
    if (raw is! YamlMap) {
      throw FormatException(
        'changesets.yaml: product_tag must be a mapping '
        '(package:, format:)',
      );
    }
    final package = raw['package']?.toString();
    if (package == null || package.isEmpty) {
      throw FormatException(
        'changesets.yaml: product_tag.package is required',
      );
    }
    final format = (raw['format'] as String?) ?? 'v{version}';
    if (!format.contains('{version}')) {
      throw FormatException(
        'changesets.yaml: product_tag.format must contain "{version}": '
        '$format',
      );
    }
    return ProductTagConfig(package: package, format: format);
  }

  static Map<String, List<VersionFileConfig>> _parseVersionFiles(Object? raw) {
    if (raw == null) return const <String, List<VersionFileConfig>>{};
    if (raw is! YamlMap) {
      throw FormatException(
        'changesets.yaml: version_files must map package names to lists of '
        '{path:, pattern:} entries',
      );
    }
    final out = <String, List<VersionFileConfig>>{};
    for (final entry in raw.entries) {
      final pkg = entry.key.toString();
      if (entry.value is! YamlList) {
        throw FormatException(
          'changesets.yaml: version_files.$pkg must be a list of '
          '{path:, pattern:} entries',
        );
      }
      final files = <VersionFileConfig>[];
      for (final item in entry.value as YamlList) {
        if (item is! YamlMap) {
          throw FormatException(
            'changesets.yaml: version_files.$pkg entries must be mappings',
          );
        }
        final path = item['path']?.toString();
        final pattern = item['pattern']?.toString();
        if (path == null || path.isEmpty || pattern == null) {
          throw FormatException(
            'changesets.yaml: version_files.$pkg entries need "path" and '
            '"pattern"',
          );
        }
        if (!pattern.contains('{version}')) {
          throw FormatException(
            'changesets.yaml: version_files.$pkg pattern must contain '
            '"{version}": $pattern',
          );
        }
        files.add(VersionFileConfig(path: path, pattern: pattern));
      }
      if (files.isNotEmpty) out[pkg] = files;
    }
    return out;
  }
}

/// How much to bump a publishable dependent whose dependency constraint was
/// rewritten during a cascade.
enum DependentBump {
  patch,
  minor;

  static DependentBump fromString(String value) => switch (value) {
        'patch' => DependentBump.patch,
        'minor' => DependentBump.minor,
        _ => throw FormatException(
            'changesets.yaml: dependent_bump must be "patch" or "minor", '
            'got "$value"',
          ),
      };

  String get asString => name;
}

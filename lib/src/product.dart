import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'apply.dart';
import 'bump.dart';
import 'config.dart';

/// The product release for a train: the configured product package's
/// product-shaped tag plus the data needed to create the GitHub release.
final class ProductRelease {
  const ProductRelease({
    required this.tag,
    required this.package,
    required this.version,
  });

  final String tag;
  final String package;
  final String version;
}

/// Resolves the product release from the pending train artifact, or `null`
/// when there is no product configured or the product package is not part of
/// this train. Used by the action's release mode (tag + GitHub release,
/// exactly once per train, idempotent).
ProductRelease? resolveProductRelease({
  required ChangesetsConfig config,
  required String changesetsDir,
}) {
  final product = config.productTag;
  if (product == null) return null;
  final file = File(
    '$changesetsDir${Platform.pathSeparator}$pendingTrainFileName',
  );
  if (!file.existsSync()) return null;
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  for (final entry in list) {
    final map = entry as Map<String, dynamic>;
    if (map['package'] == product.package) {
      final version = map['version'] as String;
      return ProductRelease(
        tag: product.tagFor(version),
        package: product.package,
        version: version,
      );
    }
  }
  return null;
}

/// The product tag for a per-package publish tag, or `null` when [tag] does
/// not name the configured product package. Used by the reusable publish
/// workflow to gate the post-publish downstream dispatch (a GITHUB_TOKEN tag
/// push fires no workflows, so the successful publish leg dispatches the
/// product workflow explicitly — AFTER publishing, never at merge time).
String? productTagForPublishTag({
  required ChangesetsConfig config,
  required String tag,
}) {
  final product = config.productTag;
  if (product == null) return null;
  final parsed = config.parseTag(tag.trim());
  if (parsed == null) return null;
  final (package, version) = parsed;
  if (package != product.package) return null;
  return product.tagFor(version);
}

/// Extracts one version section from a changelog for use as GitHub release
/// notes. Handles the engine's `## X.Y.Z` headings, the legacy
/// `## [X.Y.Z] - date` shape, and version-suffixed headings like
/// `## X.Y.Z (2026-11-22)` — anything that STARTS with the exact version
/// (`(?![\d.])` keeps `## X.Y.Z1` from matching). Returns the section body
/// WITHOUT the version heading (subsection headings and bullets kept), or
/// `null` when the changelog has no entry for [version].
String? extractReleaseNotes({
  required String changelog,
  required String version,
}) {
  final lines = const LineSplitter().convert(changelog);
  final heading = RegExp(
    r'^##\s+\[?' + RegExp.escape(version) + r'\]?(?![\d.])[ \t]*.*$',
  );
  var start = -1;
  for (var i = 0; i < lines.length; i++) {
    if (heading.hasMatch(lines[i])) {
      start = i + 1;
      break;
    }
  }
  if (start < 0) return null;
  var end = lines.length;
  for (var i = start; i < lines.length; i++) {
    if (lines[i].startsWith('## ')) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n').trim();
}

/// Drift guard for a train about to be applied.
///
/// **Allows** pubspec **ahead** of the newest release tag: a version PR may
/// have merged without tags being pushed (e.g. 0.3.0 stall). The pubspec
/// version is the bump base, so the next train publishes a newer semver with
/// changelog already on main.
///
/// **Blocks** pubspec **behind** the newest tag — inconsistent with pub.dev.
///
/// Returns one problem line per blocked package; empty means clean.
/// Best-effort: a git failure returns no findings rather than blocking
/// trains on environments without tags.
Future<List<String>> preReleaseDrift({
  required String repoRoot,
  required ReleasePlan plan,
  required ChangesetsConfig config,
}) async {
  if (plan.isEmpty) return const <String>[];
  final run = await Process.run(
    'git',
    const <String>['tag', '--list'],
    workingDirectory: repoRoot,
  );
  // Best-effort: no tags available (fresh clone without tags, no git) —
  // drift cannot be established, so do not block the train.
  if (run.exitCode != 0) return const <String>[];
  final allTags = (run.stdout as String)
      .split('\n')
      .map((raw) => raw.trim())
      .where((tag) => tag.isNotEmpty)
      .toList();
  final problems = <String>[];
  for (final release in plan.releases) {
    final name = release.package.name;
    final tagVersions = <Version>[];
    for (final tag in allTags) {
      final parsed = config.parseTag(tag);
      if (parsed == null) continue;
      final (package, versionRaw) = parsed;
      if (package != name) continue;
      try {
        tagVersions.add(Version.parse(versionRaw));
      } on FormatException {
        continue;
      }
    }
    // First release — no tags to drift against.
    if (tagVersions.isEmpty) continue;
    tagVersions.sort();
    final latest = tagVersions.last;
    if (release.package.version < latest) {
      problems.add(
        '$name: pubspec ${release.package.version} is behind the newest '
        'release tag ($latest). Restore the pubspec to at least $latest or '
        'delete the tag if it was pushed by mistake.',
      );
    }
  }
  return problems;
}

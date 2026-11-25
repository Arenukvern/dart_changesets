import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:dart_changesets/src/apply.dart';
import 'package:dart_changesets/src/bump.dart';
import 'package:dart_changesets/src/changeset.dart';
import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/product.dart';
import 'package:dart_changesets/src/workspace_graph.dart';

import 'fixtures.dart';

Changeset writeChangeset(
  Directory root,
  String name,
  String frontmatter, [
  String body = 'Some change.',
]) {
  final dir = Directory('${root.path}${Platform.pathSeparator}.changesets')
    ..createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name.md');
  file.writeAsStringSync('---\n$frontmatter---\n\n$body\n');
  return Changeset.fromFile(file.path);
}

ChangesetsConfig configFromYaml(String yaml) {
  final dir = Directory.systemTemp.createTempSync('dc_config_');
  try {
    final file = File('${dir.path}/changesets.yaml')
      ..writeAsStringSync(yaml);
    return ChangesetsConfig.loadFromFile(file.path);
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void main() {
  group('config parsing', () {
    test('absent keys behave exactly as before (backward compatible)', () {
      final config = configFromYaml('packages_dir: pkgs\n');
      expect(config.productTag, isNull);
      expect(config.versionFiles, isEmpty);
      expect(config.tagFormat, '{package}-v{version}');
    });

    test('product_tag and version_files parse', () {
      final config = configFromYaml('''
product_tag:
  package: flutter_mcp_toolkit_server
  format: 'v{version}'
version_files:
  flutter_mcp_toolkit_server:
    - path: VERSION
      pattern: '{version}'
    - path: mcp_server_dart/server.json
      pattern: '"version": "{version}"'
''');
      expect(config.productTag?.package, 'flutter_mcp_toolkit_server');
      expect(config.productTag?.tagFor('7.2.1'), 'v7.2.1');
      expect(config.versionFiles['flutter_mcp_toolkit_server']?.length, 2);
      expect(config.versionFiles['flutter_mcp_toolkit_server']![0].path,
          'VERSION');
      expect(config.versionFiles['flutter_mcp_toolkit_server']![1].pattern,
          '"version": "{version}"');
    });

    test('product_tag.format without {version} fails loudly', () {
      expect(
        () => configFromYaml('product_tag:\n  package: x\n  format: v-\n'),
        throwsFormatException,
      );
    });

    test('version_files pattern without {version} fails loudly', () {
      expect(
        () => configFromYaml(
          'version_files:\n  x:\n    - path: VERSION\n      pattern: only-text\n',
        ),
        throwsFormatException,
      );
    });
  });

  group('bumpVersionFileContent', () {
    test('whole-file VERSION string moves', () {
      expect(
        bumpVersionFileContent(
          content: '7.2.1\n',
          pattern: '{version}',
          currentVersion: '7.2.1',
          newVersion: '7.3.0',
        ),
        '7.3.0\n',
      );
    });

    test('server.json version field moves, neighbours untouched', () {
      const content = '{"name": "7.2.1", "version": "7.2.1", "other": 1}';
      expect(
        bumpVersionFileContent(
          content: content,
          pattern: '"version": "{version}"',
          currentVersion: '7.2.1',
          newVersion: '7.3.0',
        ),
        '{"name": "7.2.1", "version": "7.3.0", "other": 1}',
      );
    });

    test('Dart constant moves', () {
      const content = "static const appVersion = '7.2.1';\n";
      expect(
        bumpVersionFileContent(
          content: content,
          pattern: "static const appVersion = '{version}';",
          currentVersion: '7.2.1',
          newVersion: '7.3.0',
        ),
        "static const appVersion = '7.3.0';\n",
      );
    });

    test('drifted file (current version absent) fails loudly', () {
      expect(
        () => bumpVersionFileContent(
          content: '7.2.0\n',
          pattern: '{version}',
          currentVersion: '7.2.1',
          newVersion: '7.3.0',
        ),
        throwsStateError,
      );
    });

    test('ambiguous pattern (multiple matches) fails loudly', () {
      expect(
        () => bumpVersionFileContent(
          content: '"version": "1.0.0" "version": "1.0.0"',
          pattern: '"version": "{version}"',
          currentVersion: '1.0.0',
          newVersion: '1.0.1',
        ),
        throwsStateError,
      );
    });

    test('pattern without placeholder fails loudly', () {
      expect(
        () => bumpVersionFileContent(
          content: 'x',
          pattern: 'no-placeholder',
          currentVersion: '1.0.0',
          newVersion: '1.0.1',
        ),
        throwsStateError,
      );
    });
  });

  group('extractReleaseNotes', () {
    const changelog = '# Changelog\n\n'
        '## 7.3.0\n\n'
        '### Minor Changes\n\n'
        '- New feature.\n'
        '  Continuation line.\n\n'
        '## 7.2.1\n\n'
        '### Patch Changes\n\n'
        '- Old fix.\n';

    test('engine-format section body, heading dropped', () {
      expect(
        extractReleaseNotes(changelog: changelog, version: '7.3.0'),
        '### Minor Changes\n\n- New feature.\n  Continuation line.',
      );
    });

    test('legacy bracketed heading with date is recognized', () {
      const legacy = '## [7.2.1] - 2026-01-01\n\n- Old fix.\n';
      expect(
        extractReleaseNotes(changelog: legacy, version: '7.2.1'),
        '- Old fix.',
      );
    });

    test('missing version returns null', () {
      expect(
        extractReleaseNotes(changelog: changelog, version: '9.9.9'),
        isNull,
      );
    });
  });

  group('product release resolution', () {
    ChangesetsConfig configWithProduct() => const ChangesetsConfig(
          productTag: ProductTagConfig(package: 'server'),
        );

    Directory writeTrain(
      Directory root,
      Map<String, String> releases,
    ) {
      final dir = Directory('${root.path}/.changesets')
        ..createSync(recursive: true);
      File('${dir.path}/$pendingTrainFileName').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<Object?>[
          for (final entry in releases.entries)
            <String, String>{
              'package': entry.key,
              'version': entry.value,
              'tag': '${entry.key}-v${entry.value}',
              'directory': '${root.path}/pkgs/${entry.key}',
            },
        ]),
      );
      return root;
    }

    test('product in train resolves tag/package/version', () async {
      final root = Directory.systemTemp.createTempSync('dc_product_');
      try {
        writeTrain(root, {'server': '7.3.0', 'lib': '1.0.1'});
        final release = resolveProductRelease(
          config: configWithProduct(),
          changesetsDir: '${root.path}/.changesets',
        );
        expect(release, isNotNull);
        expect(release!.tag, 'v7.3.0');
        expect(release.package, 'server');
        expect(release.version, '7.3.0');
      } finally {
        teardownRepo(root);
      }
    });

    test('product not in train → null (do nothing)', () async {
      final root = Directory.systemTemp.createTempSync('dc_product_');
      try {
        writeTrain(root, {'lib': '1.0.1'});
        expect(
          resolveProductRelease(
            config: configWithProduct(),
            changesetsDir: '${root.path}/.changesets',
          ),
          isNull,
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('no product configured → null', () async {
      final root = Directory.systemTemp.createTempSync('dc_product_');
      try {
        writeTrain(root, {'server': '7.3.0'});
        expect(
          resolveProductRelease(
            config: const ChangesetsConfig(),
            changesetsDir: '${root.path}/.changesets',
          ),
          isNull,
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('publish-tag gate: product package yields product tag', () {
      expect(
        productTagForPublishTag(
          config: configWithProduct(),
          tag: 'server-v7.3.0',
        ),
        'v7.3.0',
      );
      expect(
        productTagForPublishTag(
          config: configWithProduct(),
          tag: 'lib-v1.0.1',
        ),
        isNull,
      );
    });

    test('custom product format is honored', () {
      final config = const ChangesetsConfig(
        productTag: ProductTagConfig(package: 'server', format: 'rel-{version}'),
      );
      expect(
        productTagForPublishTag(config: config, tag: 'server-v7.3.0'),
        'rel-7.3.0',
      );
    });
  });

  group('applyPlan version_files', () {
    test('configured version strings move with the release', () async {
      final root = buildFixtureRepo(const {
        'server': FixturePackage(version: '7.2.1'),
      });
      File('${root.path}/VERSION').writeAsStringSync('7.2.1\n');
      Directory('${root.path}/server_meta').createSync();
      File('${root.path}/server_meta/server.json').writeAsStringSync(
        '{"name": "x", "version": "7.2.1"}',
      );
      final changeset = writeChangeset(root, 'one', "'server': minor\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(
            productTag: ProductTagConfig(package: 'server'),
            versionFiles: {
              'server': [
                VersionFileConfig(path: 'VERSION', pattern: '{version}'),
                VersionFileConfig(
                  path: 'server_meta/server.json',
                  pattern: '"version": "{version}"',
                ),
              ],
            },
          ),
        );
        final applied = applyPlan(
          plan: plan,
          consumedChangesetPaths: [changeset.path],
          changesetsDir: '${root.path}/.changesets',
          config: const ChangesetsConfig(
            versionFiles: {
              'server': [
                VersionFileConfig(path: 'VERSION', pattern: '{version}'),
                VersionFileConfig(
                  path: 'server_meta/server.json',
                  pattern: '"version": "{version}"',
                ),
              ],
            },
          ),
          privateRewrites: plan.privateConstraintRewrites,
          repoRoot: root.path,
        );
        expect(applied.writtenFiles, contains('${root.path}/VERSION'));
        expect(File('${root.path}/VERSION').readAsStringSync(), '7.3.0\n');
        expect(
          File('${root.path}/server_meta/server.json').readAsStringSync(),
          '{"name": "x", "version": "7.3.0"}',
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('drifted version file fails loudly', () async {
      final root = buildFixtureRepo(const {
        'server': FixturePackage(version: '7.2.1'),
      });
      File('${root.path}/VERSION').writeAsStringSync('7.2.0\n');
      final changeset = writeChangeset(root, 'one', "'server': minor\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(
            versionFiles: {
              'server': [
                VersionFileConfig(path: 'VERSION', pattern: '{version}'),
              ],
            },
          ),
        );
        expect(
          () => applyPlan(
            plan: plan,
            consumedChangesetPaths: [changeset.path],
            changesetsDir: '${root.path}/.changesets',
            config: const ChangesetsConfig(
              versionFiles: {
                'server': [
                  VersionFileConfig(
                    path: 'VERSION',
                    pattern: '{version}',
                  ),
                ],
              },
            ),
            privateRewrites: plan.privateConstraintRewrites,
            repoRoot: root.path,
          ),
          throwsStateError,
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('missing version file fails loudly', () async {
      final root = buildFixtureRepo(const {
        'server': FixturePackage(version: '7.2.1'),
      });
      final changeset = writeChangeset(root, 'one', "'server': minor\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(
            versionFiles: {
              'server': [
                VersionFileConfig(path: 'VERSION', pattern: '{version}'),
              ],
            },
          ),
        );
        expect(
          () => applyPlan(
            plan: plan,
            consumedChangesetPaths: [changeset.path],
            changesetsDir: '${root.path}/.changesets',
            config: const ChangesetsConfig(
              versionFiles: {
                'server': [
                  VersionFileConfig(
                    path: 'VERSION',
                    pattern: '{version}',
                  ),
                ],
              },
            ),
            privateRewrites: plan.privateConstraintRewrites,
            repoRoot: root.path,
          ),
          throwsStateError,
        );
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('preReleaseDrift', () {
    // A throwaway git repo holding package `a` at [version] with real
    // release tags, so the guard compares against actual tag state.
    Future<Directory> gitFixtureRepo(
      String version, {
      List<String> tags = const <String>[],
    }) async {
      final root =
          buildFixtureRepo({'a': FixturePackage(version: version)});
      for (final command in <List<String>>[
        <String>['init', '--quiet'],
        <String>['config', 'user.email', 'test@example.dev'],
        <String>['config', 'user.name', 'test'],
        // Tags need a HEAD to attach to.
        <String>['commit', '--allow-empty', '--quiet', '-m', 'init'],
        for (final tag in tags) <String>['tag', tag],
      ]) {
        await Process.run('git', command, workingDirectory: root.path);
      }
      return root;
    }

    PlannedRelease planned(WorkspacePackage pkg, String version) =>
        PlannedRelease(
          package: pkg,
          newVersion: Version.parse(version),
          bumpType: BumpType.minor,
          changelogEntries: const <String>[],
          isDependentBump: false,
          constraintRewrites: const <String, String>{},
        );

    Future<List<String>> drift(Directory root, WorkspaceGraph graph) =>
        preReleaseDrift(
          repoRoot: root.path,
          plan: ReleasePlan(
            releases: [planned(graph.packages['a']!, '1.3.0')],
            privateConstraintRewrites: const {},
            errors: const [],
          ),
          config: const ChangesetsConfig(packagesDir: 'pkgs'),
        );

    test('allows pubspec ahead of its newest release tag', () async {
      final root = await gitFixtureRepo('1.1.0', tags: <String>['a-v1.0.0']);
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('flags a pubspec behind its newest release tag', () async {
      final root = await gitFixtureRepo('1.0.0', tags: <String>['a-v1.2.0']);
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, hasLength(1));
        expect(problems.single, contains('behind the newest release tag'));
      } finally {
        teardownRepo(root);
      }
    });

    test('passes when the pubspec matches the newest tag', () async {
      final root = await gitFixtureRepo('1.2.3', tags: <String>['a-v1.2.3']);
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('ignores tags outside tag_format (e.g. v1.0.0)', () async {
      final root = await gitFixtureRepo(
        '0.3.0',
        tags: <String>['v1.0.0', 'a-v0.2.0'],
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('allows prerelease pubspec ahead of release tag', () async {
      final root = await gitFixtureRepo(
        '1.0.0-dev.1',
        tags: <String>['a-v0.9.0'],
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('allows build metadata ahead of release tag (+1)', () async {
      final root = await gitFixtureRepo(
        '1.0.0+1',
        tags: <String>['a-v0.9.0'],
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('passes when git has no tags at all', () async {
      final root = await gitFixtureRepo('1.0.0');
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final problems = await drift(root, graph);
        expect(problems, isEmpty);
      } finally {
        teardownRepo(root);
      }
    });

    test('first release (no tags) passes', () async {
      final root = Directory.systemTemp.createTempSync('dc_drift_fresh_');
      Directory('${root.path}/pkgs/new').createSync(recursive: true);
      File('${root.path}/pkgs/new/pubspec.yaml').writeAsStringSync(
        'name: new\nversion: 0.1.0\nenvironment:\n  sdk: ^3.14.0\n',
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        final plan = ReleasePlan(
          releases: [planned(graph.packages['new']!, '0.2.0')],
          privateConstraintRewrites: const {},
          errors: const [],
        );
        final problems = await preReleaseDrift(
          repoRoot: root.path,
          plan: plan,
          config: const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        expect(problems, isEmpty);
      } finally {
        root.deleteSync(recursive: true);
      }
    });
  });
}

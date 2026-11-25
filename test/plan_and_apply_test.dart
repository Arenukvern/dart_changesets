import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:dart_changesets/src/bump.dart';
import 'package:dart_changesets/src/changeset.dart';
import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/apply.dart';
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

void main() {
  group('bumpVersion', () {
    test('major leaves 0.x via 1.0.0', () {
      expect(
        bumpVersion(Version.parse('0.9.0'), BumpType.major).toString(),
        '1.0.0',
      );
    });

    test('minor rolls y on 0.x', () {
      expect(
        bumpVersion(Version.parse('0.9.0'), BumpType.minor).toString(),
        '0.10.0',
      );
    });

    test('patch increments', () {
      expect(
        bumpVersion(Version.parse('1.2.3'), BumpType.patch).toString(),
        '1.2.4',
      );
    });
  });

  group('computePlan', () {
    test('single declared bump, no dependents', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.2.3')});
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'a': minor\n", 'Add feature.'),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases, hasLength(1));
        expect(plan.releases.first.newVersion.toString(), '1.3.0');
        expect(plan.releases.first.changelogEntries, ['Add feature.']);
        expect(plan.releases.first.isDependentBump, isFalse);
      } finally {
        teardownRepo(root);
      }
    });

    test('0.x minor bump cascades through incompatible caret (0.x semantics)',
        () async {
      final root = buildFixtureRepo(const {
        'interface': FixturePackage(version: '0.9.0'),
        'impl': FixturePackage(
          version: '0.5.0',
          dependencies: {'interface': '^0.9.0'},
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'interface': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name).toList(), [
          'interface',
          'impl',
        ]);
        expect(plan.releases[0].newVersion.toString(), '0.10.0');
        // impl's ^0.9.0 does NOT allow 0.10.0 → dependent patch bump.
        expect(plan.releases[1].newVersion.toString(), '0.5.1');
        expect(plan.releases[1].isDependentBump, isTrue);
        expect(
          plan.releases[1].constraintRewrites['interface'],
          '^0.10.0',
        );
        expect(
          plan.releases[1].changelogEntries,
          ['Updated `interface` dependency constraint to `^0.10.0`.'],
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('satisfied constraint does not cascade', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.2.0'),
        'app': FixturePackage(
          version: '3.0.0',
          dependencies: {'core': '>=1.0.0 <2.0.0'},
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'core': patch\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name), ['core']);
      } finally {
        teardownRepo(root);
      }
    });

    test('private dependent gets constraint rewrite but no release', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.0.0'),
        'internal': FixturePackage(
          version: '1.0.0',
          dependencies: {'core': '^1.0.0'},
          publishToNone: true,
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'core': major\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name), ['core']);
        final rewrites = plan.privateConstraintRewrites;
        expect(rewrites.length, 1);
        final key = rewrites.keys.single;
        expect(key, endsWith('pkgs/internal/pubspec.yaml'));
        expect(rewrites[key]?['core'], '^2.0.0');
      } finally {
        teardownRepo(root);
      }
    });

    test('workspace root joins the graph as a private dependent', () async {
      final root = Directory.systemTemp.createTempSync('dcg_root_cascade_');
      Directory('${root.path}/pkgs/core').createSync(recursive: true);
      File('${root.path}/pkgs/core/pubspec.yaml').writeAsStringSync(
        'name: core\nversion: 1.0.0\nenvironment:\n  sdk: ^3.14.0\n',
      );
      // The root pubspec is a workspace app depending on a member — not a
      // release candidate, but its constraint must cascade.
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: workspace_app\nversion: 2.0.0\nenvironment:\n'
        '  sdk: ^3.14.0\nworkspace:\n  - pkgs/*\ndependencies:\n'
        "  core: '^1.0.0'\n",
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        expect(graph.packages.containsKey('workspace_app'), isTrue);
        expect(graph.packages['workspace_app']!.publishable, isFalse);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'core': major\n"),
          ],
          config: const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        // The root never releases.
        expect(plan.releases.map((r) => r.package.name), ['core']);
        final rewrites = plan.privateConstraintRewrites;
        final key = rewrites.keys
            .singleWhere((k) => k.endsWith('pubspec.yaml') && !k.contains('/pkgs/'));
        expect(rewrites[key]?['core'], '^2.0.0');
      } finally {
        root.deleteSync(recursive: true);
      }
    });

    test('a declared dependent planned before its dependency still gets '
        'the constraint rewrite', () async {
      // `a` sorts before `core` and BOTH are declared: when `a` is planned,
      // core's new version does not exist yet — the rewrite must reach `a`
      // anyway (oka 2026-11-22: oka_app_gallery missed its oka_core bump).
      final root = buildFixtureRepo(const {
        'a': FixturePackage(version: '0.13.0', dependencies: {'core': '^0.13.0'}),
        'core': FixturePackage(version: '0.13.0'),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'a': minor\n'core': minor\n"),
          ],
          config: const ChangesetsConfig(packagesDir: 'pkgs'),
        );
        // 0.x carets: ^0.13.0 does NOT allow 0.14.0 — the rewrite fires.
        final releaseA = plan.releases.singleWhere((r) => r.package.name == 'a');
        expect(releaseA.constraintRewrites['core'], '^0.14.0');
        expect(
          releaseA.changelogEntries.join('\n'),
          contains('Updated `core` dependency constraint to `^0.14.0`.'),
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('applyPlan writes private dependent constraint rewrites by path',
        () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.0.0'),
        'internal': FixturePackage(
          version: '1.0.0',
          dependencies: {'core': '^1.0.0'},
          publishToNone: true,
        ),
      });
      final changeset = writeChangeset(root, 'one', "'core': major\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(),
        );
        applyPlan(
          plan: plan,
          consumedChangesetPaths: [changeset.path],
          changesetsDir: '${root.path}/.changesets',
          config: const ChangesetsConfig(),
          privateRewrites: plan.privateConstraintRewrites,
        );
        final privatePubspec = File(
          '${root.path}/pkgs/internal/pubspec.yaml',
        ).readAsStringSync();
        expect(privatePubspec, contains('core: ^2.0.0'));
        expect(privatePubspec, contains('version: 1.0.0'));
      } finally {
        teardownRepo(root);
      }
    });

    test('unknown package in changeset raises', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.0.0')});
      try {
        final graph = await loadGraph(root.path);
        expect(
          () => computePlan(
            graph: graph,
            changesets: [
              writeChangeset(root, 'one', "'nope': patch\n"),
            ],
            config: const ChangesetsConfig(),
          ),
          throwsA(isA<PlanException>()),
        );
      } finally {
        teardownRepo(root);
      }
    });

    test('higher bump wins across changesets', () async {
      final root = buildFixtureRepo(const {'a': FixturePackage(version: '1.0.0')});
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'a': patch\n"),
            writeChangeset(root, 'two', "'a': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.first.newVersion.toString(), '1.1.0');
      } finally {
        teardownRepo(root);
      }
    });

    test('releases order dependencies before dependents', () async {
      // 0.x carets cascade on minor bumps, so leaf's minor forces mid
      // (dependent patch) while top's declared minor rides along.
      final root = buildFixtureRepo(const {
        'leaf': FixturePackage(version: '0.1.0'),
        'mid': FixturePackage(version: '0.2.0', dependencies: {'leaf': '^0.1.0'}),
        'top': FixturePackage(version: '0.3.0', dependencies: {'mid': '^0.2.0'}),
      });
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [
            writeChangeset(root, 'one', "'top': minor\n'leaf': minor\n"),
          ],
          config: const ChangesetsConfig(),
        );
        expect(plan.releases.map((r) => r.package.name).toList(), [
          'leaf',
          'mid',
          'top',
        ]);
        expect(plan.releases[0].newVersion.toString(), '0.2.0');
        expect(plan.releases[1].newVersion.toString(), '0.2.1');
        expect(plan.releases[2].newVersion.toString(), '0.4.0');
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('applyPlan', () {
    test('writes versions, constraints, changelogs, and the train artifact',
        () async {
      final root = buildFixtureRepo(const {
        'interface': FixturePackage(version: '0.9.0'),
        'impl': FixturePackage(
          version: '0.5.0',
          dependencies: {'interface': '^0.9.0'},
        ),
      });
      final changeset = writeChangeset(root, 'one', "'interface': minor\n");
      try {
        final graph = await loadGraph(root.path);
        final plan = computePlan(
          graph: graph,
          changesets: [changeset],
          config: const ChangesetsConfig(),
        );
        final applied = applyPlan(
          plan: plan,
          consumedChangesetPaths: [changeset.path],
          changesetsDir:
              '${root.path}${Platform.pathSeparator}.changesets',
          config: const ChangesetsConfig(),
          privateRewrites: plan.privateConstraintRewrites,
        );

        final interfacePubspec =
            File('${root.path}/pkgs/interface/pubspec.yaml').readAsStringSync();
        expect(interfacePubspec, contains('version: 0.10.0'));

        final implPubspec =
            File('${root.path}/pkgs/impl/pubspec.yaml').readAsStringSync();
        expect(implPubspec, contains('version: 0.5.1'));
        expect(implPubspec, contains('interface: ^0.10.0'));

        final implChangelog =
            File('${root.path}/pkgs/impl/CHANGELOG.md').readAsStringSync();
        expect(implChangelog, contains('## 0.5.1'));
        expect(implChangelog, contains('Patch Changes'));
        expect(implChangelog, contains('Updated `interface` dependency'));

        expect(File(changeset.path).existsSync(), isFalse);
        final train = File(applied.trainsFilePath).readAsStringSync();
        expect(train, contains('"package": "interface"'));
        expect(train, contains('"version": "0.10.0"'));
      } finally {
        teardownRepo(root);
      }
    });

    test('changelog inserts under an existing header', () {
      const existing = '# Changelog\n\n## 0.9.0\n\n- old\n';
      final updated = prependChangelog(
        existing,
        version: '0.10.0',
        bumpType: BumpType.minor,
        entries: const ['New feature.'],
      );
      expect(
        updated,
        startsWith('# Changelog\n\n## 0.10.0'),
      );
      expect(updated, contains('## 0.9.0'));
    });

    test('single-package 0.3.0 train: major intent wins over minor/patch',
        () async {
      final root = Directory.systemTemp.createTempSync('dc_major_train_');
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: dart_changesets\n'
        'version: 0.3.0\n'
        'description: fixture\n'
        'environment:\n'
        '  sdk: ^3.14.0\n',
      );
      final changesets = [
        writeChangeset(root, 'major-ship', "'dart_changesets': major\n",
            'Ship 1.0.0.'),
        writeChangeset(root, 'oss', "'dart_changesets': patch\n", 'OSS fixes.'),
        writeChangeset(root, 'feat', "'dart_changesets': minor\n", 'Feature.'),
      ];
      try {
        const config = ChangesetsConfig(rootPackage: true);
        final graph = await WorkspaceGraph.load(root.path, config);
        final plan = computePlan(
          graph: graph,
          changesets: changesets,
          config: config,
        );
        expect(plan.releases, hasLength(1));
        expect(plan.releases.first.package.name, 'dart_changesets');
        expect(plan.releases.first.newVersion.toString(), '1.0.0');
        expect(
          config.tagFor('dart_changesets', '1.0.0'),
          'dart_changesets-v1.0.0',
        );
        expect(plan.releases.first.changelogEntries.length, greaterThan(1));
      } finally {
        teardownRepo(root);
      }
    });

    test('changelog keeps a top-of-file comment banner above the section',
        () {
      const existing =
          '# Changelog\n\n<!-- markdownlint-disable MD052 -->\n\n## 0.9.0\n\n- old\n';
      final updated = prependChangelog(
        existing,
        version: '0.10.0',
        bumpType: BumpType.patch,
        entries: const ['Fix.'],
      );
      // The banner stays within the first 5 lines (oka's markdownlint gate).
      expect(updated.split('\n').take(5).join('\n'),
          contains('markdownlint-disable'));
      // And the new section still precedes the old one.
      expect(updated.indexOf('## 0.10.0'), lessThan(updated.indexOf('## 0.9.0')));
    });
  });
}

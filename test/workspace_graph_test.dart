import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/workspace_graph.dart';

import 'fixtures.dart';

void main() {
  group('WorkspaceGraph.load', () {
    test('discovers packages, versions, and publishability', () async {
      final root = buildFixtureRepo(const {
        'a': FixturePackage(version: '1.2.3'),
        'b': FixturePackage(version: '0.9.0', publishToNone: true),
      });
      try {
        final graph = await loadGraph(root.path);
        expect(graph.packages.length, 2);
        expect(graph.packages['a']!.publishable, isTrue);
        expect(graph.packages['a']!.version.toString(), '1.2.3');
        expect(graph.packages['b']!.publishable, isFalse);
        expect(graph.publishable.map((pkg) => pkg.name), ['a']);
      } finally {
        teardownRepo(root);
      }
    });

    test('reads plain hosted, sdk, and path dependency forms', () async {
      final root = buildFixtureRepo(const {
        'core': FixturePackage(version: '1.0.0'),
        'ui': FixturePackage(
          version: '2.0.0',
          dependencies: {
            'core': '^1.0.0',
            'flutter': '{sdk: flutter}',
            'local': '{path: ../core}',
          },
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        final ui = graph.packages['ui']!;
        expect(ui.dependencies['core']!.isHosted, isTrue);
        expect(ui.dependencies['core']!.constraint, '^1.0.0');
        expect(ui.dependencies['flutter']!.isSdk, isTrue);
        expect(ui.dependencies['local']!.isPath, isTrue);
        expect(ui.isFlutter, isTrue);
        expect(graph.reverseDependents('core').map((pkg) => pkg.name), ['ui']);
      } finally {
        teardownRepo(root);
      }
    });

    test('reads nested hosted-url and dev dependency forms', () async {
      final root = Directory.systemTemp.createTempSync('dcg_nested_');
      Directory('${root.path}/pkgs/core').createSync(recursive: true);
      Directory('${root.path}/pkgs/dep').createSync(recursive: true);
      File('${root.path}/pkgs/core/pubspec.yaml').writeAsStringSync(
        'name: core\nversion: 1.0.0\n',
      );
      File('${root.path}/pkgs/dep/pubspec.yaml').writeAsStringSync(
        'name: dep\nversion: 1.0.0\ndev_dependencies:\n  core:\n'
        '    hosted:\n      name: core\n      url: https://example.dev\n'
        '    version: ^1.0.0\n',
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(),
        );
        final dep = graph.packages['dep']!;
        expect(dep.devDependencies['core']!.isHosted, isTrue);
        expect(dep.devDependencies['core']!.hostedUrl, 'https://example.dev');
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('workspace discovery', () {
    // Builds a repo whose packages live in the shapes the Dart `workspace:`
    // declaration can express: one-level globs, nested globs, and plain
    // root-level members — beyond what a one-level packages_dir scan reaches.
    Directory buildWorkspaceFixture() {
      final root = Directory.systemTemp.createTempSync('dcg_workspace_');
      void pkg(String rel, String name, String version, {bool private = false}) {
        final dir = Directory('${root.path}/$rel')..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync(
          'name: $name\nversion: $version\n'
          '${private ? 'publish_to: none\n' : ''}',
        );
      }

      pkg('packages/alpha', 'alpha', '1.0.0');
      pkg('packages/beta', 'beta', '0.9.0', private: true);
      pkg('plugins/ecsly_replay', 'ecsly_replay', '0.2.0');
      pkg('plugins/ecs_camera/ecs_camera_core', 'ecs_camera_core', '0.1.0');
      pkg('tool/cli', 'tool_cli', '0.3.0', private: true);
      pkg('root_member', 'root_member', '1.4.0');
      Directory('${root.path}/packages/empty').createSync(recursive: true);
      Directory('${root.path}/packages/.hidden').createSync(recursive: true);
      File('${root.path}/packages/.hidden/pubspec.yaml')
          .writeAsStringSync('name: hidden\nversion: 0.0.1\n');
      File('${root.path}/pubspec.yaml').writeAsStringSync('''
name: workspace_root
publish_to: none
environment:
  sdk: ^3.14.0
workspace:
  - packages/*
  - plugins/*
  - plugins/*/*
  - tool/cli
  - root_member
  - gone/missing
''');
      return root;
    }

    test('expands workspace globs: nested, plain members, hidden skipped',
        () async {
      final root = buildWorkspaceFixture();
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(),
        );
        expect(
          graph.packages.keys.toSet(),
          {
            'alpha',
            'beta',
            'ecsly_replay',
            'ecs_camera_core',
            'tool_cli',
            'root_member',
          },
        );
        expect(graph.packages['alpha']!.publishable, isTrue);
        expect(graph.packages['beta']!.publishable, isFalse);
        expect(graph.packages['root_member']!.publishable, isTrue);
        expect(graph.packages.containsKey('hidden'), isFalse);
        expect(graph.packages.containsKey('workspace_root'), isFalse);
      } finally {
        teardownRepo(root);
      }
    });

    test('workspace members cascade as dependents via hosted constraints',
        () async {
      final root = buildWorkspaceFixture();
      try {
        // alpha depends on the nested member; the graph must see the edge
        // even though ecs_camera_core sits two levels deep.
        final alphaPubspec =
            File('${root.path}/packages/alpha/pubspec.yaml');
        alphaPubspec.writeAsStringSync(
          '${alphaPubspec.readAsStringSync()}dependencies:\n'
          '  ecs_camera_core: ^0.1.0\n',
        );
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(),
        );
        expect(graph.reverseDependents('ecs_camera_core').map((p) => p.name),
            ['alpha']);
      } finally {
        teardownRepo(root);
      }
    });

    test('falls back to packages_dir scan when no workspace declaration',
        () async {
      final root = buildFixtureRepo(const {
        'a': FixturePackage(version: '1.0.0'),
      });
      try {
        final graph = await loadGraph(root.path);
        expect(graph.packages.keys.toSet(), {'a'});
      } finally {
        teardownRepo(root);
      }
    });

    test('missing packages_dir still throws outside root_package mode',
        () async {
      final root = Directory.systemTemp.createTempSync('dcg_nothrow_');
      try {
        expect(
          () => WorkspaceGraph.load(root.path, const ChangesetsConfig()),
          throwsA(isA<StateError>()),
        );
      } finally {
        teardownRepo(root);
      }
    });
  });

  group('pubspec text rewrites', () {
    test('rewriteVersion preserves comments and formatting', () {
      const content = 'name: x\nversion: 1.2.3 # pinned\nenvironment:\n  sdk: ^3.14.0\n';
      final updated = rewriteVersion(
        content,
        Version.parse('2.0.0'),
      );
      expect(updated, contains('version: 2.0.0 # pinned'));
    });

    test('rewriteConstraint handles plain form', () {
      const content = 'dependencies:\n  core: ^1.0.0\n  http: ^1.6.0\n';
      final updated = rewriteConstraint(content, 'core', '^1.1.0');
      expect(updated, contains('core: ^1.1.0'));
      expect(updated, contains('http: ^1.6.0'));
    });

    test('rewriteConstraint handles nested hosted form', () {
      const content = 'dependencies:\n  core:\n    hosted:\n      name: core\n'
          '      url: https://example.dev\n    version: ^1.0.0\n';
      final updated = rewriteConstraint(content, 'core', '^1.1.0');
      expect(updated, contains('version: ^1.1.0'));
    });

    test('rewriteConstraint returns null when absent', () {
      const content = 'dependencies:\n  other: ^1.0.0\n';
      expect(rewriteConstraint(content, 'core', '^1.1.0'), isNull);
    });
  });

  group('root_package config', () {
    test('includes the repository root pubspec when enabled', () async {
      final root = Directory.systemTemp.createTempSync('dcg_rootpkg_');
      Directory('${root.path}/pkgs/child').createSync(recursive: true);
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: rootpkg\nversion: 1.0.0\n',
      );
      File('${root.path}/pkgs/child/pubspec.yaml').writeAsStringSync(
        'name: child\nversion: 0.1.0\n',
      );
      try {
        final disabled = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(),
        );
        expect(disabled.packages.containsKey('rootpkg'), isFalse);

        final enabled = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(rootPackage: true),
        );
        expect(enabled.packages.containsKey('rootpkg'), isTrue);
        expect(enabled.packages['rootpkg']!.publishable, isTrue);
        expect(enabled.packages['child']!.directory, contains('pkgs'));
      } finally {
        teardownRepo(root);
      }
    });

    test('single-package repo without a packages directory loads the root',
        () async {
      final root = Directory.systemTemp.createTempSync('dcg_nodir_');
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: solo\nversion: 1.0.0\n',
      );
      try {
        final graph = await WorkspaceGraph.load(
          root.path,
          const ChangesetsConfig(rootPackage: true),
        );
        expect(graph.packages['solo']!.publishable, isTrue);
      } finally {
        teardownRepo(root);
      }
    });
  });
}

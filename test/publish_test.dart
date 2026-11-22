import 'dart:io';

import 'package:test/test.dart';

import 'package:dart_changesets/src/config.dart';
import 'package:dart_changesets/src/doctor.dart';
import 'package:dart_changesets/src/publish.dart';

import 'fixtures.dart';

final class FakePubDevClient implements PubDevClient {
  FakePubDevClient(this.packages);

  final Map<String, List<String>> packages;

  @override
  Future<PubDevInfo> lookup(String package) async {
    final versions = packages[package];
    if (versions == null) return PubDevInfo(status: PubDevStatus.newPackage);
    return PubDevInfo(status: PubDevStatus.exists, latestVersion: versions.last);
  }

  @override
  Future<List<String>> versions(String package) async =>
      packages[package] ?? const <String>[];
}

void main() {
  test('publish-tag fails usage on malformed tag', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'garbage',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag fails static check on version mismatch', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync('## 1.0.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v9.9.9',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag fails static check without changelog entry', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['0.1.0'],
        }),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag accepts a version heading with a suffix', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync(
      '## 1.0.0 (2026-11-22)\n\n- x\n',
    );
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['0.1.0'],
        }),
      );
      // Past the changelog gate; the fixture cannot pass a real strict
      // dry-run, so any non-usage code proves the heading was accepted.
      expect(code, isNot(publishExitUsage));
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag does not match a longer version heading', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    // The heading names 1.0.01, not 1.0.0 — the boundary must not match.
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync(
      '## 1.0.01\n\n- x\n',
    );
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['0.1.0'],
        }),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag skips when pub.dev already has the version', () async {
    final root = buildFixtureRepo(const {
      'a': FixturePackage(version: '1.0.0'),
    });
    File('${root.path}/pkgs/a/CHANGELOG.md').writeAsStringSync('## 1.0.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'a-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {
          'a': ['1.0.0'],
        }),
      );
      expect(code, 0);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag reports typed bootstrap for never-published packages',
      () async {
    final root = buildFixtureRepo(const {
      'fresh': FixturePackage(version: '0.1.0'),
    });
    File('${root.path}/pkgs/fresh/CHANGELOG.md').writeAsStringSync('## 0.1.0\n\n- x\n');
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'fresh-v0.1.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitBootstrapNeeded);
    } finally {
      teardownRepo(root);
    }
  });

  test('publish-tag refuses publish_to:none packages', () async {
    final root = buildFixtureRepo(const {
      'private': FixturePackage(version: '1.0.0', publishToNone: true),
    });
    try {
      final graph = await loadGraph(root.path);
      final code = await publishTag(
        root.path,
        config: const ChangesetsConfig(),
        graph: graph,
        tag: 'private-v1.0.0',
        execute: false,
        skipExisting: true,
        pubDevClient: FakePubDevClient(const {}),
      );
      expect(code, publishExitUsage);
    } finally {
      teardownRepo(root);
    }
  });

  group('publishRunner (workspace-aware SDK requirement)', () {
    // Workspace-mode repo (root pubspec with `workspace:`); optionally with
    // a flutter sibling that forces the shared whole-workspace resolution.
    Directory buildRunnerFixture({required bool flutterSibling}) {
      final root = Directory.systemTemp.createTempSync('dc_runner_');
      void pkg(String rel, String content) {
        final dir = Directory('${root.path}/$rel')..createSync(recursive: true);
        File('${dir.path}/pubspec.yaml').writeAsStringSync(content);
      }

      pkg('pkgs/a_dart', 'name: a_dart\nversion: 1.0.0\n');
      if (flutterSibling) {
        pkg(
          'pkgs/b_flutter',
          'name: b_flutter\nversion: 1.0.0\ndependencies:\n'
          '  flutter:\n    sdk: flutter\n',
        );
      }
      File('${root.path}/pubspec.yaml').writeAsStringSync(
        'name: runner_root\npublish_to: none\nworkspace:\n  - pkgs/*\n',
      );
      return root;
    }

    test('mixed workspace: a dart-only tag still needs the Flutter SDK '
        '(pub publish resolves the whole workspace)', () async {
      final root = buildRunnerFixture(flutterSibling: true);
      try {
        final graph = await loadGraph(root.path);
        expect(graph.usesWorkspaceResolution, isTrue);
        expect(publishRunner(graph, graph.packages['a_dart']!), 'flutter');
        expect(publishRunner(graph, graph.packages['b_flutter']!), 'flutter');
      } finally {
        teardownRepo(root);
      }
    });

    test('pure-dart workspace: dart tags stay on dart', () async {
      final root = buildRunnerFixture(flutterSibling: false);
      try {
        final graph = await loadGraph(root.path);
        expect(graph.usesWorkspaceResolution, isTrue);
        expect(publishRunner(graph, graph.packages['a_dart']!), 'dart');
      } finally {
        teardownRepo(root);
      }
    });

    test('packages_dir fallback: per-package detection (no shared '
        'resolution)', () async {
      final root = buildFixtureRepo(const {
        'a_dart': FixturePackage(version: '1.0.0'),
        'b_flutter': FixturePackage(
          version: '1.0.0',
          dependencies: {'flutter': '{sdk: flutter}'},
        ),
      });
      try {
        final graph = await loadGraph(root.path);
        expect(graph.usesWorkspaceResolution, isFalse);
        expect(publishRunner(graph, graph.packages['a_dart']!), 'dart');
        expect(publishRunner(graph, graph.packages['b_flutter']!), 'flutter');
      } finally {
        teardownRepo(root);
      }
    });
  });
}

import 'dart:io';

import 'package:dart_changesets/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fixtures.dart';

void writeIntentFile(Directory root, String name, String frontmatter) {
  final dir = Directory(p.join(root.path, '.changesets'));
  dir.createSync(recursive: true);
  File(p.join(dir.path, '$name.md')).writeAsStringSync(
    '---\n$frontmatter---\n\nChange.\n',
  );
}

void main() {
  final packageRoot = Directory.current.path;

  final entrypoint = p.join(packageRoot, 'bin', 'dart_changesets.dart');

  ProcessResult runCli(
    List<String> args, {
    String? workingDirectory,
  }) {
    return Process.runSync(
      Platform.resolvedExecutable,
      <String>['run', entrypoint, ...args],
      workingDirectory: workingDirectory ?? packageRoot,
    );
  }

  group('CLI', () {
    test('--version prints package version', () {
      final result = runCli(const <String>['--version']);
      expect(result.exitCode, 0);
      expect(result.stdout, 'dart_changesets $packageVersion\n');
    });

    test('--help exits zero and lists commands', () {
      final result = runCli(const <String>['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('Commands:'));
      expect(result.stdout, contains('publish-tag'));
    });

    test('missing command exits 64 without stack trace', () {
      final result = runCli(const <String>[]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('command required'));
      expect(result.stderr, isNot(contains('#0')));
    });

    group('entrypoint in temp repo', () {
      late Directory repo;

      setUp(() {
        repo = buildFixtureRepo({
          'a': const FixturePackage(version: '1.0.0'),
        });
        Directory(p.join(repo.path, '.changesets')).createSync();
        File(p.join(repo.path, 'changesets.yaml')).writeAsStringSync(
          'packages: pkgs/*\n',
        );
        writeIntentFile(repo, 'intent', "'a': patch\n");
      });

      tearDown(() => teardownRepo(repo));

      test('status', () {
        final result = runCli(const ['status'], workingDirectory: repo.path);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stdout, contains('Pending changesets'));
        expect(result.stdout, contains('a: patch'));
      });

      test('tags --plain reads pending train', () {
        final train = File(p.join(repo.path, '.changesets', '.pending-train.json'));
        train.writeAsStringSync(
          '[{"package":"a","version":"1.0.1","tag":"a-v1.0.1","directory":"x"}]',
        );
        final result = runCli(const ['tags', '--plain'], workingDirectory: repo.path);
        expect(result.exitCode, 0, reason: result.stderr);
        expect(result.stdout.trim(), 'a-v1.0.1');
      });

      test('version --check reports due PR', () {
        final result = runCli(const ['version', '--check'], workingDirectory: repo.path);
        expect(result.exitCode, 1);
        expect(result.stderr, isEmpty);
        expect(result.stdout, contains('version PR due'));
        expect(result.stdout, contains('a → 1.0.1'));
      });
    });
  });
}
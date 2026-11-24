import 'dart:io';

import 'package:dart_changesets/src/version.dart';
import 'package:test/test.dart';

void main() {
  final packageRoot = Directory.current.path;

  ProcessResult runCli(List<String> args) {
    return Process.runSync(
      Platform.resolvedExecutable,
      <String>['run', 'bin/dart_changesets.dart', ...args],
      workingDirectory: packageRoot,
    );
  }

  group('CLI', () {
    test('--version prints package version', () {
      final result = runCli(const <String>['--version']);
      expect(result.exitCode, 0);
      expect(result.stdout, 'dart_changesets $packageVersion\n');
    });

    test('--help exits zero', () {
      final result = runCli(const <String>['--help']);
      expect(result.exitCode, 0);
      expect(result.stdout, contains('version'));
    });

    test('missing command exits 64 without stack trace', () {
      final result = runCli(const <String>[]);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('command required'));
      expect(result.stderr, isNot(contains('#0')));
    });
  });
}
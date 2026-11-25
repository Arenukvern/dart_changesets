import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:dart_changesets/dart_changesets.dart';

const changesetsDirName = '.changesets';
const configFileName = 'changesets.yaml';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage.')
    ..addFlag('version', negatable: false, help: 'Print the package version.')
    ..addCommand('add')
    ..addCommand('status')
    ..addCommand(
      'version',
      ArgParser()..addFlag('check', negatable: false, help: 'Exit 1 when a version PR is due; write nothing.'),
    )
    ..addCommand('doctor', ArgParser()
      ..addFlag('no-network', negatable: false, help: 'Skip the pub.dev presence census.'))
    ..addCommand(
      'tags',
      ArgParser()
        ..addFlag('plain', negatable: false, help: 'Print tags space-separated (CI-friendly) instead of JSON.'),
    )
    ..addCommand(
      'product-release',
      ArgParser()
        ..addOption(
          'tag',
          help: 'Per-package publish tag — prints the product tag when the tag names the product package.',
        ),
    )
    ..addCommand(
      'release-notes',
      ArgParser()
        ..addOption('package', help: 'Package whose CHANGELOG section becomes the release notes.')
        ..addOption('version', help: 'Version heading to extract, e.g. 7.2.1.'),
    )
    ..addCommand(
      'runner',
      ArgParser()
        ..addOption('tag', help: 'Release tag, e.g. <package>-v<version>.')
        ..addOption(
          'cwd',
          help: 'Working directory of the consumer repository.',
          defaultsTo: '.',
        ),
    )
    ..addCommand(
      'publish-tag',
      ArgParser()
        ..addOption('tag', help: 'Release tag, e.g. <package>-v<version>. Defaults to GITHUB_REF_NAME.')
        ..addFlag('execute', negatable: false, help: 'Publish for real (omit = preflight only).')
        ..addFlag('skip-existing', defaultsTo: true, help: 'Skip when pub.dev already exposes the version.')
        ..addOption(
          'dependency-wait-minutes',
          defaultsTo: '15',
          help: 'How long to wait for same-train dependency floors to land on pub.dev before failing.',
        )
        ..addFlag(
          'skip-dependency-gate',
          defaultsTo: false,
          help: 'Publish as-is without the dependency gate; pub.dev upload validation remains the arbiter.',
        ),
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } on ArgParserException catch (e) {
    stderr.writeln('dart_changesets: ${e.message}');
    stderr.writeln('');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (args.wasParsed('help') && args['help'] as bool) {
    stdout.writeln(parser.usage);
    exit(0);
  }
  if (args.wasParsed('version') && args['version'] as bool) {
    stdout.writeln('dart_changesets $packageVersion');
    exit(0);
  }
  final command = args.command;
  if (command == null) {
    stderr.writeln('dart_changesets: command required');
    stderr.writeln('');
    stderr.writeln(parser.usage);
    exit(64);
  }

  try {
    final repoRoot = findRepoRoot();
    if (repoRoot == null) {
      stderr.writeln(
        'dart_changesets: no repository root found (looking for '
        '$configFileName or a $changesetsDirName directory upward).',
      );
      exit(64);
    }
    final config = ChangesetsConfig.loadFromFile(
      p.join(repoRoot.path, configFileName),
    );
    final graph = await WorkspaceGraph.load(repoRoot.path, config);
    final changesetsDir = p.join(repoRoot.path, changesetsDirName);

    final code = switch (command.name) {
      'add' => await runAdd(changesetsDir, graph, command),
      'status' => await runStatus(changesetsDir, graph, config),
      'version' => await runVersion(
          repoRoot.path,
          changesetsDir,
          graph,
          config,
          checkOnly: command['check'] as bool,
        ),
      'doctor' => await runDoctorCommand(
          graph,
          config,
          changesetsDir,
          census: !(command['no-network'] as bool),
        ),
      'tags' => runTags(changesetsDir, plain: command['plain'] as bool),
      'product-release' => runProductRelease(
          changesetsDir,
          config,
          tag: command['tag'] as String?,
        ),
      'release-notes' => runReleaseNotes(graph, command),
      'runner' => await runRunner(command),
      'publish-tag' => await runPublishTag(
          repoRoot.path,
          graph,
          config,
          command,
        ),
      _ => () {
          stderr.writeln('dart_changesets: unknown command "${command.name}".');
          return 64;
        }(),
    };
    exit(code);
  } on FormatException catch (e) {
    stderr.writeln('dart_changesets: ${e.message}');
    exit(64);
  } on StateError catch (e) {
    stderr.writeln('dart_changesets: ${e.message}');
    exit(1);
  } on ChangesetParseException catch (e) {
    stderr.writeln('dart_changesets: ${e.message}');
    exit(64);
  }
}

Directory? findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File(p.join(dir.path, configFileName)).existsSync() ||
        Directory(p.join(dir.path, changesetsDirName)).existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

// ---------------------------------------------------------------------------
// add
// ---------------------------------------------------------------------------

Future<int> runAdd(String changesetsDir, WorkspaceGraph graph, ArgResults args) async {
  final publishableNames = graph.publishable.map((pkg) => pkg.name).toList();
  if (publishableNames.isEmpty) {
    stderr.writeln('dart_changesets: no publishable packages found.');
    return 1;
  }

  final package = _promptPackage(publishableNames);
  if (package == null) return 1;
  final bump = _promptBump();
  if (bump == null) return 1;
  stdout.writeln('Summary (one line, empty line to finish):');
  final body = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
  if (body.isEmpty) {
    stderr.writeln('dart_changesets: empty summary — changeset discarded.');
    return 1;
  }

  final slug = _slugify(body);
  final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
  final path = p.join(changesetsDir, '${stamp}_$slug.md');
  Directory(changesetsDir).createSync(recursive: true);
  File(path).writeAsStringSync(
    "---\n'$package': ${bump.name}\n---\n\n$body\n",
  );
  stdout.writeln('OK: wrote $path');
  return 0;
}

String? _promptPackage(List<String> names) {
  stdout.writeln('Packages:');
  for (var i = 0; i < names.length; i++) {
    stdout.writeln('  ${i + 1}. ${names[i]}');
  }
  stdout.write('Pick one (name or number): ');
  final line = stdin.readLineSync(encoding: utf8)?.trim() ?? '';
  if (line.isEmpty) return null;
  final asNumber = int.tryParse(line);
  if (asNumber != null && asNumber >= 1 && asNumber <= names.length) {
    return names[asNumber - 1];
  }
  if (names.contains(line)) return line;
  stderr.writeln('dart_changesets: "$line" is not a publishable package.');
  return null;
}

BumpType? _promptBump() {
  stdout.write('Bump type (major/minor/patch) [patch]: ');
  final line = stdin.readLineSync(encoding: utf8)?.trim().toLowerCase();
  if (line == null || line.isEmpty) return BumpType.patch;
  if (line == 'major' || line == 'minor' || line == 'patch') {
    return BumpType.fromString(line);
  }
  stderr.writeln('dart_changesets: "$line" is not a bump type.');
  return null;
}

String _slugify(String text) {
  final slug = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'changeset' : slug.substring(0, slug.length.clamp(0, 48));
}

// ---------------------------------------------------------------------------
// status
// ---------------------------------------------------------------------------

Future<int> runStatus(
  String changesetsDir,
  WorkspaceGraph graph,
  ChangesetsConfig config,
) async {
  final changesets = Changeset.loadPending(changesetsDir);
  if (changesets.isEmpty) {
    print('No pending changesets in $changesetsDir.');
    return 0;
  }
  print('Pending changesets (${changesets.length}):');
  for (final changeset in changesets) {
    final summary = changeset.bumps.entries
        .map((e) => '${e.key}: ${e.value.name}')
        .join(', ');
    print('  ${p.basename(changeset.path)}: $summary');
  }
  final plan = computePlan(graph: graph, changesets: changesets, config: config);
  if (plan.isEmpty) {
    print('Nothing to release.');
    return 0;
  }
  print('\nPlanned releases (dependency order):');
  for (final release in plan.releases) {
    final marker = release.isDependentBump ? ' (dependent)' : '';
    print(
      '  ${release.package.name} ${release.package.version} → '
      '${release.newVersion}$marker',
    );
    for (final entry in release.changelogEntries) {
      print('    - $entry');
    }
  }
  for (final error in plan.errors) {
    stderr.writeln('warning: $error');
  }
  return 0;
}

// ---------------------------------------------------------------------------
// version
// ---------------------------------------------------------------------------

Future<int> runVersion(
  String repoRoot,
  String changesetsDir,
  WorkspaceGraph graph,
  ChangesetsConfig config, {
  required bool checkOnly,
}) async {
  final changesets = Changeset.loadPending(changesetsDir);
  final plan = computePlan(graph: graph, changesets: changesets, config: config);
  for (final error in plan.errors) {
    stderr.writeln('warning: $error');
  }
  if (plan.isEmpty) {
    print('No pending changesets — nothing to release.');
    return 0;
  }
  if (checkOnly) {
    stdout.writeln('version PR due for ${plan.releases.length} package(s):');
    for (final release in plan.releases) {
      stdout.writeln(
        '  ${release.package.name} → ${release.newVersion.canonicalizedVersion}',
      );
    }
    return 1;
  }
  // Pubspec current version is the bump BASE — assembling on top of a
  // pre-bumped or untagged train double-bumps. Refuse loudly instead.
  final drift = await preReleaseDrift(
    repoRoot: repoRoot,
    plan: plan,
    config: config,
  );
  if (drift.isNotEmpty) {
    stderr.writeln(
      'FAIL: release drift detected — refusing to assemble a train:',
    );
    for (final line in drift) {
      stderr.writeln('  - $line');
    }
    return 65;
  }
  final applied = applyPlan(
    plan: plan,
    consumedChangesetPaths: changesets.map((c) => c.path).toList(),
    changesetsDir: changesetsDir,
    config: config,
    privateRewrites: plan.privateConstraintRewrites,
    repoRoot: repoRoot,
  );
  print('Wrote ${applied.writtenFiles.length} file(s):');
  for (final path in applied.writtenFiles) {
    print('  $path');
  }
  print('Consumed ${applied.consumedChangesets.length} changeset(s).');
  print('Tags for this train: ${File(applied.trainsFilePath).readAsLinesSync().first}');
  return 0;
}

// ---------------------------------------------------------------------------
// doctor
// ---------------------------------------------------------------------------

Future<int> runDoctorCommand(
  WorkspaceGraph graph,
  ChangesetsConfig config,
  String changesetsDir, {
  required bool census,
}) async {
  final report = await runDoctor(
    graph: graph,
    config: config,
    changesetsDir: changesetsDir,
    census: census,
  );
  print('Packages: ${graph.packages.length} total, '
      '${graph.publishable.length} publishable.');
  for (final finding in report.findings) {
    print(finding);
  }
  if (census) {
    final fresh = report.census.values
        .where((i) => i.status == PubDevStatus.newPackage)
        .length;
    final failed = report.census.values
        .where((i) => i.status == PubDevStatus.lookupFailed)
        .length;
    print(
      'pub.dev census: ${report.census.length - fresh - failed} existing, '
      '$fresh never-published (need manual first publish), $failed lookup errors.',
    );
    for (final entry in report.census.entries) {
      if (entry.value.status == PubDevStatus.newPackage) {
        print('  NEW: ${entry.key}');
      }
    }
  }
  if (report.hasErrors) {
    stderr.writeln('doctor: FAIL (${report.errorCount} error(s)).');
    return 1;
  }
  print('doctor: OK.');
  return 0;
}

// ---------------------------------------------------------------------------
// tags
// ---------------------------------------------------------------------------

int runTags(String changesetsDir, {required bool plain}) {
  final file = File(p.join(changesetsDir, pendingTrainFileName));
  if (!file.existsSync()) {
    stderr.writeln(
      'dart_changesets: no pending train ($pendingTrainFileName missing) — '
      'run `version` first.',
    );
    return 1;
  }
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final tags = <String>[
    for (final entry in list)
      (entry as Map<String, dynamic>)['tag'] as String,
  ];
  // Replaces the python JSON one-liner in action.yml: plain output parses
  // with shell word-splitting alone.
  print(plain ? tags.join(' ') : jsonEncode(tags));
  return 0;
}

// ---------------------------------------------------------------------------
// product-release / release-notes
// ---------------------------------------------------------------------------

/// Release mode (no --tag): prints `tag=`, `package=`, `version=` lines when
/// the product package is part of the pending train; prints nothing (exit 0)
/// when there is no product or it is not in this train — the action skips
/// tag/release creation entirely.
///
/// Publish mode (--tag): prints the product tag when the given per-package
/// tag names the product package; prints nothing otherwise. The reusable
/// publish workflow gates its post-publish downstream dispatch on this.
int runProductRelease(
  String changesetsDir,
  ChangesetsConfig config, {
  String? tag,
}) {
  if (tag != null) {
    final productTag = productTagForPublishTag(config: config, tag: tag);
    if (productTag != null) print(productTag);
    return 0;
  }
  final release = resolveProductRelease(
    config: config,
    changesetsDir: changesetsDir,
  );
  if (release != null) {
    print('tag=${release.tag}');
    print('package=${release.package}');
    print('version=${release.version}');
  }
  return 0;
}

/// Prints the release notes (the package's new changelog section) for the
/// version named on the command line.
int runReleaseNotes(WorkspaceGraph graph, ArgResults args) {
  final packageName = args['package'] as String?;
  final version = args['version'] as String?;
  if (packageName == null || packageName.isEmpty) {
    stderr.writeln('dart_changesets: release-notes requires --package.');
    return 64;
  }
  if (version == null || version.isEmpty) {
    stderr.writeln('dart_changesets: release-notes requires --version.');
    return 64;
  }
  final pkg = graph.packages[packageName];
  if (pkg == null) {
    stderr.writeln('dart_changesets: "$packageName" is not a workspace package.');
    return 64;
  }
  final changelogPath =
      '${pkg.directory}${Platform.pathSeparator}CHANGELOG.md';
  final file = File(changelogPath);
  if (!file.existsSync()) {
    stderr.writeln(
      'dart_changesets: no CHANGELOG.md at $changelogPath.',
    );
    return 1;
  }
  final notes = extractReleaseNotes(
    changelog: file.readAsStringSync(),
    version: version,
  );
  if (notes == null) {
    stderr.writeln(
      'dart_changesets: CHANGELOG.md has no section for $version.',
    );
    return 1;
  }
  print(notes);
  return 0;
}

// ---------------------------------------------------------------------------
// publish-tag
// ---------------------------------------------------------------------------

/// Prints `flutter` or `dart` — the publish runner for the tagged package.
/// Workspace-aware (see `publishRunner`): in workspace mode a single Flutter
/// member requires the SDK for every tag. CI uses this to decide which SDK
/// to install before invoking publish-tag.
Future<int> runRunner(ArgResults args) async {
  final cwd = args['cwd'] as String? ?? '.';
  var dir = Directory(cwd.isEmpty ? '.' : cwd).absolute;
  ChangesetsConfig? config;
  while (true) {
    final candidate = File(p.join(dir.path, configFileName));
    if (candidate.existsSync()) {
      config = ChangesetsConfig.loadFromFile(candidate.path);
      break;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  config ??= const ChangesetsConfig();

  final tag = (args['tag'] as String?) ?? Platform.environment['GITHUB_REF_NAME'];
  if (tag == null || tag.isEmpty) {
    stderr.writeln('dart_changesets: runner requires --tag.');
    return publishExitUsage;
  }
  final parsed = config.parseTag(tag.trim());
  if (parsed == null) {
    stderr.writeln(
      'dart_changesets: tag "$tag" does not match tag format "${config.tagFormat}".',
    );
    return publishExitUsage;
  }
  final graph = await WorkspaceGraph.load(dir.path, config);
  final pkg = graph.packages[parsed.$1];
  if (pkg == null) {
    stderr.writeln('dart_changesets: "${parsed.$1}" is not a workspace package.');
    return publishExitUsage;
  }
  print(publishRunner(graph, pkg));
  return 0;
}

Future<int> runPublishTag(
  String repoRoot,
  WorkspaceGraph graph,
  ChangesetsConfig config,
  ArgResults args,
) async {
  final tag =
      (args['tag'] as String?) ?? Platform.environment['GITHUB_REF_NAME'];
  if (tag == null || tag.isEmpty) {
    stderr.writeln(
      'dart_changesets: publish-tag requires --tag (or GITHUB_REF_NAME).',
    );
    return publishExitUsage;
  }
  final waitMinutes =
      int.tryParse(args['dependency-wait-minutes'] as String);
  if (waitMinutes == null || waitMinutes < 0) {
    stderr.writeln(
      'dart_changesets: --dependency-wait-minutes must be a non-negative '
      'integer (got "${args['dependency-wait-minutes']}").',
    );
    return publishExitUsage;
  }
  return publishTag(
    repoRoot,
    config: config,
    graph: graph,
    tag: tag,
    execute: args['execute'] as bool,
    skipExisting: args['skip-existing'] as bool,
    dependencyWait: Duration(minutes: waitMinutes),
    skipDependencyGate: args['skip-dependency-gate'] as bool,
    pubDevClient: HttpPubDevClient(),
  );
}

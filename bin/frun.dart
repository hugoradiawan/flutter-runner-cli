import 'dart:io';

import 'package:args/args.dart';
import 'package:frun/frun.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help and exit.',
    )
    ..addFlag('version', negatable: false, help: 'Print version and exit.');

  final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (args['help'] as bool) {
    stdout.writeln('frun — terminal UI for Flutter development\n');
    stdout.writeln('Usage: frun [options] [path-to-flutter-project]\n');
    stdout.writeln(parser.usage);
    stdout.writeln(
      '\nPositional path is useful in monorepos:\n'
      '  frun apps/client     # start from a workspace sub-project',
    );
    return;
  }

  if (args['version'] as bool) {
    stdout.writeln('frun $frunVersion');
    return;
  }

  String? cwd;
  if (args.rest.isNotEmpty) {
    final raw = args.rest.first;
    cwd = p.isAbsolute(raw)
        ? raw
        : p.normalize(p.join(Directory.current.path, raw));
    final dir = Directory(cwd);
    if (!dir.existsSync()) {
      stderr.writeln('frun: directory does not exist: $cwd');
      exit(64);
    }
  }

  final code = await runFrun(cwd: cwd);
  exit(code);
}

import 'dart:convert';
import 'dart:io';

import '../../domain/entities/launch_entry.dart';

class LaunchConfigParser {
  /// Parse `.vscode/launch.json` (JSONC). Returns entries with `type == "dart"`.
  ///
  /// [workspaceFolder] is substituted for the literal `${workspaceFolder}`
  /// (and `${workspaceFolderBasename}`) in `program`, `cwd`, `args`, and
  /// `toolArgs`. Pass the absolute path to the directory that contains
  /// `.vscode/`. When null, no substitution is performed.
  static List<LaunchEntryEntity> parse(
    String jsonc, {
    String? workspaceFolder,
  }) {
    final stripped = _stripJsonc(jsonc);
    if (stripped.trim().isEmpty) return const <LaunchEntryEntity>[];
    final Object? decoded;
    try {
      decoded = json.decode(stripped);
    } on FormatException {
      return const <LaunchEntryEntity>[];
    }
    if (decoded is! Map) return const <LaunchEntryEntity>[];
    final configs = decoded['configurations'];
    if (configs is! List) return const <LaunchEntryEntity>[];

    String subst(String? value) => _substitute(value, workspaceFolder);
    List<String> substList(Object? value) =>
        _stringList(value).map(subst).toList(growable: false);

    final out = <LaunchEntryEntity>[];
    for (final raw in configs) {
      if (raw is! Map) continue;
      final type = raw['type']?.toString();
      if (type != 'dart') continue;
      final name = raw['name']?.toString() ?? 'unnamed';
      final program = subst(raw['program']?.toString() ?? 'lib/main.dart');
      final cwdRaw = raw['cwd']?.toString();
      final cwd = cwdRaw == null ? null : subst(cwdRaw);
      final deviceId = raw['deviceId']?.toString();
      final mode = raw['flutterMode']?.toString();
      final flavor = raw['flavor']?.toString();
      // Dart Code's `args` is documented as "args for the Dart program
      // entry-point" (i.e. after `--` to `flutter run`), but in practice
      // almost every launch.json in the wild puts Flutter CLI flags there
      // (`--flavor`, `--debug`, etc.). Pushing those after `--` makes them
      // program args, which means Flutter never sees the flag, the build
      // succeeds at the default variant, then the tool fails to locate the
      // expected APK. To match real-world usage we treat `args` as more
      // Flutter flags and append them to `toolArgs`.
      final toolArgs = <String>[
        ...substList(raw['toolArgs']),
        ...substList(raw['args']),
      ];
      out.add(
        LaunchEntryEntity(
          name: name,
          program: program,
          cwd: cwd,
          deviceId: deviceId,
          flutterMode: mode,
          flavor: flavor,
          args: const <String>[],
          toolArgs: toolArgs,
        ),
      );
    }
    return out;
  }

  static List<LaunchEntryEntity> parseFile(
    File file, {
    String? workspaceFolder,
  }) {
    if (!file.existsSync()) return const <LaunchEntryEntity>[];
    return parse(file.readAsStringSync(), workspaceFolder: workspaceFolder);
  }

  static String _substitute(String? input, String? workspaceFolder) {
    if (input == null) return '';
    if (workspaceFolder == null) return input;
    var out = input.replaceAll(r'${workspaceFolder}', workspaceFolder);
    out = out.replaceAll(
      r'${workspaceFolderBasename}',
      _basename(workspaceFolder),
    );
    return out;
  }

  static String _basename(String path) {
    final cleaned = path.endsWith('/') || path.endsWith(r'\')
        ? path.substring(0, path.length - 1)
        : path;
    final i = cleaned.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? cleaned : cleaned.substring(i + 1);
  }

  /// JSONC = JSON + `//` and `/* */` comments + trailing commas.
  /// Quick-and-dirty stripper good enough for VS Code launch.json.
  static String _stripJsonc(String input) {
    final sb = StringBuffer();
    var i = 0;
    var inString = false;
    var escape = false;
    while (i < input.length) {
      final ch = input[i];
      if (inString) {
        sb.write(ch);
        if (escape) {
          escape = false;
        } else if (ch == r'\') {
          escape = true;
        } else if (ch == '"') {
          inString = false;
        }
        i++;
        continue;
      }
      if (ch == '"') {
        inString = true;
        sb.write(ch);
        i++;
        continue;
      }
      if (ch == '/' && i + 1 < input.length) {
        final next = input[i + 1];
        if (next == '/') {
          i += 2;
          while (i < input.length && input[i] != '\n') {
            i++;
          }
          continue;
        }
        if (next == '*') {
          i += 2;
          while (i + 1 < input.length &&
              !(input[i] == '*' && input[i + 1] == '/')) {
            i++;
          }
          i += 2;
          continue;
        }
      }
      sb.write(ch);
      i++;
    }
    return _stripTrailingCommas(sb.toString());
  }

  static String _stripTrailingCommas(String input) {
    final re = RegExp(r',(\s*[}\]])');
    return input.replaceAllMapped(re, (m) => m.group(1)!);
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) return const <String>[];
    return value.map((e) => e.toString()).toList(growable: false);
  }
}

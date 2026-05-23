import 'dart:convert';
import 'dart:io';

/// One launch configuration discovered for `/run`. May come from
/// `.vscode/launch.json` or from a `main()` we found in `lib/`.
class LaunchEntry {
  const LaunchEntry({
    required this.name,
    required this.program,
    this.cwd,
    this.deviceId,
    this.flutterMode,
    this.flavor,
    this.args = const <String>[],
    this.toolArgs = const <String>[],
    this.source = LaunchEntrySource.launchJson,
  });

  final String name;

  /// Dart entry-point. Relative to [cwd] if [cwd] is set, otherwise relative
  /// to the project root.
  final String program;

  /// Working directory for `flutter run`. When null, the Flutter project
  /// root is used. Lets monorepos point `cwd` at the actual sub-project from a
  /// workspace-level launch.json.
  final String? cwd;

  /// Optional device id from launch.json (`deviceId` field). If present,
  /// `/run` will use it instead of the user's currently-selected device.
  final String? deviceId;

  final String? flutterMode; // debug | profile | release
  final String? flavor;
  final List<String> args;
  final List<String> toolArgs;
  final LaunchEntrySource source;

  @override
  String toString() => '$name ($program)';
}

enum LaunchEntrySource { launchJson, mainScanner }

class LaunchConfigParser {
  /// Parse `.vscode/launch.json` (JSONC). Returns entries with `type == "dart"`.
  ///
  /// [workspaceFolder] is substituted for the literal `${workspaceFolder}`
  /// (and `${workspaceFolderBasename}`) in `program`, `cwd`, `args`, and
  /// `toolArgs`. Pass the absolute path to the directory that contains
  /// `.vscode/`. When null, no substitution is performed.
  static List<LaunchEntry> parse(String jsonc, {String? workspaceFolder}) {
    final stripped = _stripJsonc(jsonc);
    if (stripped.trim().isEmpty) return const <LaunchEntry>[];
    final Object? decoded;
    try {
      decoded = json.decode(stripped);
    } on FormatException {
      return const <LaunchEntry>[];
    }
    if (decoded is! Map) return const <LaunchEntry>[];
    final configs = decoded['configurations'];
    if (configs is! List) return const <LaunchEntry>[];

    String subst(String? value) => _substitute(value, workspaceFolder);
    List<String> substList(Object? value) =>
        _stringList(value).map(subst).toList(growable: false);

    final out = <LaunchEntry>[];
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
      out.add(LaunchEntry(
        name: name,
        program: program,
        cwd: cwd,
        deviceId: deviceId,
        flutterMode: mode,
        flavor: flavor,
        args: substList(raw['args']),
        toolArgs: substList(raw['toolArgs']),
      ));
    }
    return out;
  }

  static List<LaunchEntry> parseFile(File file, {String? workspaceFolder}) {
    if (!file.existsSync()) return const <LaunchEntry>[];
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

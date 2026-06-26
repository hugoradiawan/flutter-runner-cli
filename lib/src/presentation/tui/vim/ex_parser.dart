/// Parsed ex command.
///
///   - [name] is the canonical command (`q`, `qa`, `s`, `noh`, …).
///   - [rangeSpec] is the raw range prefix (`%`, `'<,'>` , `1,5`, `''.,$`) or null.
///   - [args] is the remainder after the name (everything for `:cmd args…`).
///   - [substitute] is non-null for `:s/pat/rep/flags` (and `:%s…` variants).
class ExCommand {
  const ExCommand({
    required this.name,
    this.rangeSpec,
    this.args = '',
    this.bang = false,
    this.substitute,
  });
  final String name;
  final String? rangeSpec;
  final String args;
  final bool bang;
  final SubstituteSpec? substitute;
}

class SubstituteSpec {
  const SubstituteSpec({
    required this.pattern,
    required this.replacement,
    required this.flags,
  });
  final String pattern;
  final String replacement;
  final String flags; // 'g', 'c', 'i', ''
  bool get global => flags.contains('g');
  bool get caseInsensitive => flags.contains('i');
  bool get confirm => flags.contains('c');
}

class ExParser {
  static const Map<String, String> _slashAliases = <String, String>{
    'q': 'quit',
    'quit': 'quit',
    'qa': 'quit',
    'qall': 'quit',
    'wq': 'quit',
    'x': 'quit',
    'wqa': 'quit',
    'exit': 'quit',
    'help': 'help',
    'h': 'help',
    'clear': 'clear',
    'cls': 'clear',
    'devices': 'devices',
    'run': 'run',
    'r': 'reload',
    'reload': 'reload',
    'restart': 'restart',
    'R': 'restart',
    'config': 'config',
    'status': 'status',
    'devtools': 'devtools',
    'emulators': 'emulators',
    'inspect': 'inspect',
    'isolates': 'isolates',
    'stop': 'stop',
  };

  /// Translate an ex command name to the matching slash command name, or null
  /// if no alias exists.
  static String? toSlash(String exName) => _slashAliases[exName];

  /// Parse a command line *without* the leading `:`.
  static ExCommand? parse(String raw) {
    var input = raw.trim();
    if (input.isEmpty) return null;

    // Range prefix.
    String? rangeSpec;
    final rangeMatch = RegExp(
      r'''^([%]|(?:\.|\$|\d+|'[a-zA-Z<>])(?:\s*,\s*(?:\.|\$|\d+|'[a-zA-Z<>]))?)''',
    ).firstMatch(input);
    if (rangeMatch != null) {
      rangeSpec = rangeMatch.group(1);
      input = input.substring(rangeMatch.end).trimLeft();
    }

    if (input.isEmpty) return null;

    // Substitute shortcut: `s/pat/rep/flags`.
    if (input.startsWith('s/') || input.startsWith('s ') || input == 's') {
      final body = input.startsWith('s/')
          ? input.substring(1)
          : input.substring(2);
      final sub = _parseSubstitute(body);
      if (sub == null) return null;
      return ExCommand(name: 's', rangeSpec: rangeSpec, substitute: sub);
    }

    // Command name + bang + args.
    final cmdMatch = RegExp(
      r'^([A-Za-z][A-Za-z0-9_]*)(!)?\s*(.*)$',
    ).firstMatch(input);
    if (cmdMatch == null) return null;
    final name = cmdMatch.group(1)!;
    final bang = cmdMatch.group(2) == '!';
    final args = cmdMatch.group(3) ?? '';
    return ExCommand(name: name, rangeSpec: rangeSpec, bang: bang, args: args);
  }

  /// Parse `/pat/rep/flags` (any single delimiter). Returns null on malformed.
  static SubstituteSpec? _parseSubstitute(String body) {
    if (body.isEmpty) return null;
    final delim = body[0];
    if (!RegExp(r'[\/\|,;:!@#]').hasMatch(delim)) return null;

    final parts = <String>[];
    var buf = StringBuffer();
    var i = 1;
    while (i < body.length && parts.length < 2) {
      final ch = body[i];
      if (ch == r'\' && i + 1 < body.length) {
        buf.write(ch);
        buf.write(body[i + 1]);
        i += 2;
        continue;
      }
      if (ch == delim) {
        parts.add(buf.toString());
        buf = StringBuffer();
        i++;
        continue;
      }
      buf.write(ch);
      i++;
    }
    // Whatever remains is the third part (replacement when pattern was found,
    // or flags when both were found).
    final tail = i < body.length ? body.substring(i) : '';
    // Trailing flags may include a delimiter prefix; split once more.
    if (parts.length == 1) {
      // Only pattern terminated — tail is `rep[delim flags]`.
      final j = _findUnescaped(tail, delim);
      if (j < 0) {
        return SubstituteSpec(pattern: parts[0], replacement: tail, flags: '');
      }
      return SubstituteSpec(
        pattern: parts[0],
        replacement: tail.substring(0, j),
        flags: tail.substring(j + 1),
      );
    } else if (parts.length == 2) {
      return SubstituteSpec(
        pattern: parts[0],
        replacement: parts[1],
        flags: tail,
      );
    }
    // Only pattern, no terminator.
    return SubstituteSpec(pattern: buf.toString(), replacement: '', flags: '');
  }

  static int _findUnescaped(String s, String delim) {
    for (var i = 0; i < s.length; i++) {
      if (s[i] == r'\') {
        i++;
        continue;
      }
      if (s[i] == delim) return i;
    }
    return -1;
  }
}

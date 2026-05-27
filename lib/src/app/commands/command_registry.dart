import 'command.dart';

class CommandRegistry {
  final Map<String, Command> _byName = <String, Command>{};

  void register(Command command) {
    _byName[command.name] = command;
    for (final alias in command.aliases) {
      _byName[alias] = command;
    }
  }

  Command? lookup(String name) => _byName[name];

  /// All commands sorted by primary name, with aliases deduped.
  List<Command> get all {
    final seen = <Command>{};
    final out = <Command>[];
    final names = _byName.keys.toList()..sort();
    for (final n in names) {
      final c = _byName[n]!;
      if (seen.add(c)) out.add(c);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Commands whose name starts with [prefix] (without the slash).
  List<Command> suggestions(String prefix) {
    final lower = prefix.toLowerCase();
    final matches = <Command>{};
    for (final entry in _byName.entries) {
      if (entry.key.startsWith(lower)) matches.add(entry.value);
    }
    final list = matches.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}

import 'command.dart';

class CommandRegistry {
  final Map<String, SlashCommand> _byName = <String, SlashCommand>{};

  void register(SlashCommand command) {
    _byName[command.name] = command;
    for (final alias in command.aliases) {
      _byName[alias] = command;
    }
  }

  SlashCommand? lookup(String name) => _byName[name];

  /// All commands sorted by primary name, with aliases deduped.
  List<SlashCommand> get all {
    final seen = <SlashCommand>{};
    final out = <SlashCommand>[];
    final names = _byName.keys.toList()..sort();
    for (final n in names) {
      final c = _byName[n]!;
      if (seen.add(c)) out.add(c);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// Commands whose name starts with [prefix] (without the slash).
  List<SlashCommand> suggestions(String prefix) {
    final lower = prefix.toLowerCase();
    final matches = <SlashCommand>{};
    for (final entry in _byName.entries) {
      if (entry.key.startsWith(lower)) matches.add(entry.value);
    }
    final list = matches.toList()..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}

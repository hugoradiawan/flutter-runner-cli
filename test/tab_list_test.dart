import 'package:frun/src/data/models/launch_config.dart';
import 'package:frun/src/presentation/app/run_tab.dart';
import 'package:frun/src/presentation/app/tab_list.dart';
import 'package:test/test.dart';

/// Builds a throwaway [RunTab] identified by [name]. No session is attached, so
/// [RunTab.isRunning] is false — [TabList] is pure index bookkeeping and never
/// inspects session state.
RunTab _tab(String name) => RunTab(
  id: 0,
  entry: LaunchEntry(name: name, program: '$name.dart'),
  deviceId: 'dev-$name',
);

/// The launch entry's name, used to assert *which* tab is active by identity.
String? _name(RunTab? tab) => tab?.entry.name;

void main() {
  group('TabList', () {
    test('starts empty', () {
      final list = TabList();
      expect(list.isEmpty, isTrue);
      expect(list.hasTabs, isFalse);
      expect(list.length, 0);
      expect(list.activeIndex, -1);
      expect(list.active, isNull);
    });

    test('add appends and makes the new tab active', () {
      final list = TabList();
      final a = _tab('a');
      final b = _tab('b');
      final c = _tab('c');

      list.add(a);
      expect(list.length, 1);
      expect(list.activeIndex, 0);
      expect(list.active, same(a));

      list.add(b);
      expect(list.activeIndex, 1);
      expect(list.active, same(b));

      list.add(c);
      expect(list.activeIndex, 2);
      expect(list.active, same(c));
    });

    test('nextId is monotonic from 1 and survives clear', () {
      final list = TabList();
      expect(list.nextId(), 1);
      expect(list.nextId(), 2);
      list.clear();
      expect(list.nextId(), 3);
    });

    test('tabs getter is an unmodifiable view', () {
      final list = TabList()..add(_tab('a'));
      expect(() => list.tabs.add(_tab('b')), throwsUnsupportedError);
    });

    test('removing the active (last) tab clamps to the new last', () {
      final list = TabList();
      final a = _tab('a');
      final b = _tab('b');
      final c = _tab('c');
      list
        ..add(a)
        ..add(b)
        ..add(c); // active = c (index 2)

      list.remove(c);
      expect(list.length, 2);
      expect(list.activeIndex, 1);
      expect(_name(list.active), 'b');
    });

    test(
      'removing the active (middle) tab keeps the index, advancing active',
      () {
        final list = TabList();
        final a = _tab('a');
        final b = _tab('b');
        final c = _tab('c');
        list
          ..add(a)
          ..add(b)
          ..add(c);
        list.setActiveIndex(1); // active = b

        list.remove(b);
        // [a, c]; index 1 still valid -> the tab that shifted in (c) is active.
        expect(list.activeIndex, 1);
        expect(_name(list.active), 'c');
      },
    );

    test('removing a tab before the active one decrements the index', () {
      final list = TabList();
      final a = _tab('a');
      final b = _tab('b');
      final c = _tab('c');
      list
        ..add(a)
        ..add(b)
        ..add(c);
      list.setActiveIndex(1); // active = b

      list.remove(a);
      // [b, c]; active follows b to its new index 0.
      expect(list.activeIndex, 0);
      expect(_name(list.active), 'b');
    });

    test('removing a tab after the active one leaves the index unchanged', () {
      final list = TabList();
      final a = _tab('a');
      final b = _tab('b');
      final c = _tab('c');
      list
        ..add(a)
        ..add(b)
        ..add(c);
      list.setActiveIndex(0); // active = a

      list.remove(c);
      expect(list.activeIndex, 0);
      expect(_name(list.active), 'a');
    });

    test('removing the last remaining tab empties the list', () {
      final list = TabList()..add(_tab('a'));
      list.remove(list.active!);
      expect(list.isEmpty, isTrue);
      expect(list.activeIndex, -1);
      expect(list.active, isNull);
    });

    test('removing a tab not in the list is a no-op', () {
      final list = TabList();
      final a = _tab('a');
      final b = _tab('b');
      list
        ..add(a)
        ..add(b); // active = b (index 1)

      list.remove(_tab('stray'));
      expect(list.length, 2);
      expect(list.activeIndex, 1);
      expect(_name(list.active), 'b');
    });

    test(
      'rollback: add then remove the just-added tab restores prior active',
      () {
        // Mirrors startOrFocus's catch branch: a tab is added (and made active)
        // then removed when the launch throws.
        final list = TabList();
        final a = _tab('a');
        final b = _tab('b');
        list
          ..add(a)
          ..add(b); // active = b (index 1)

        final c = _tab('c');
        list.add(c); // active = c (index 2)
        list.remove(c); // launch failed
        expect(list.length, 2);
        expect(list.activeIndex, 1);
        expect(_name(list.active), 'b');
      },
    );

    test('clear empties the list and resets the active index', () {
      final list = TabList();
      list
        ..add(_tab('a'))
        ..add(_tab('b'))
        ..add(_tab('c'));

      list.clear();
      expect(list.isEmpty, isTrue);
      expect(list.length, 0);
      expect(list.activeIndex, -1);
      expect(list.active, isNull);
    });

    test('cycle forward wraps around', () {
      final list = TabList();
      list
        ..add(_tab('a'))
        ..add(_tab('b'))
        ..add(_tab('c')); // active = c (2)

      list.cycle(); // 2 -> 0
      expect(_name(list.active), 'a');
      list.cycle(); // 0 -> 1
      expect(_name(list.active), 'b');
      list.cycle(); // 1 -> 2
      expect(_name(list.active), 'c');
    });

    test('cycle backward wraps around', () {
      final list = TabList();
      list
        ..add(_tab('a'))
        ..add(_tab('b'))
        ..add(_tab('c')); // active = c (2)

      list.cycle(forward: false); // 2 -> 1
      expect(_name(list.active), 'b');
      list.cycle(forward: false); // 1 -> 0
      expect(_name(list.active), 'a');
      list.cycle(forward: false); // 0 -> 2
      expect(_name(list.active), 'c');
    });

    test('cycle is a no-op with fewer than two tabs', () {
      final empty = TabList();
      empty.cycle();
      expect(empty.activeIndex, -1);

      final one = TabList()..add(_tab('a'));
      one.cycle();
      expect(one.activeIndex, 0);
      one.cycle(forward: false);
      expect(one.activeIndex, 0);
    });

    test('setActiveIndex ignores out-of-range indices', () {
      final list = TabList();
      list
        ..add(_tab('a'))
        ..add(_tab('b')); // active = b (index 1)

      list.setActiveIndex(-1);
      expect(list.activeIndex, 1);
      list.setActiveIndex(5);
      expect(list.activeIndex, 1);

      list.setActiveIndex(0);
      expect(list.activeIndex, 0);
      expect(_name(list.active), 'a');
    });
  });
}

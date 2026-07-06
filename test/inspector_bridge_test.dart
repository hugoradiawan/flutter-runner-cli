import 'dart:async';

import 'package:frun/src/data/datasources/inspector_bridge.dart';
import 'package:frun/src/domain/value_objects/source_location.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart' as vm;

vm.Event _selectionEvent(String fileUri, int line, int column) => vm.Event(
  kind: vm.EventKind.kExtension,
  extensionKind: 'Flutter.Selection',
  extensionData: vm.ExtensionData.parse(<String, dynamic>{
    'creationLocation': <String, dynamic>{
      'file': fileUri,
      'line': line,
      'column': column,
    },
  }),
  timestamp: 0,
);

void main() {
  late StreamController<vm.Event> events;
  late InspectorBridge bridge;
  late List<SourceLocation> jumps;

  setUp(() {
    events = StreamController<vm.Event>.broadcast();
    bridge = InspectorBridge(extensionEvents: events.stream);
    jumps = <SourceLocation>[];
    bridge.selectionJumps.listen(jumps.add);
  });

  tearDown(() async {
    await bridge.detach();
    await events.close();
  });

  test('selection events emit jumps immediately (bypass priming)', () async {
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');

    events.add(_selectionEvent('file:///proj/lib/a.dart', 10, 2));
    await pumpEventQueue();

    expect(jumps, hasLength(1));
    expect(jumps.single.line, 10);
    expect(jumps.single.column, 2);
  });

  test('repeated selection of the same location is deduped', () async {
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');

    events.add(_selectionEvent('file:///proj/lib/a.dart', 10, 2));
    events.add(_selectionEvent('file:///proj/lib/a.dart', 10, 2));
    await pumpEventQueue();

    expect(jumps, hasLength(1));

    events.add(_selectionEvent('file:///proj/lib/b.dart', 3, 1));
    await pumpEventQueue();

    expect(jumps, hasLength(2));
  });

  test('unresolvable URIs are dropped', () async {
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');

    events.add(_selectionEvent('package:unknown/a.dart', 1, 1));
    await pumpEventQueue();

    expect(jumps, isEmpty);
  });

  test(
    'first poll observation primes without emitting; the next change emits',
    () async {
      var selected = <String, dynamic>{
        'result': <String, dynamic>{
          'creationLocation': <String, dynamic>{
            'file': 'file:///proj/lib/pre_existing.dart',
            'line': 1,
            'column': 1,
          },
        },
      };
      Future<Object?> caller(String method, Map<String, Object?> params) async {
        return selected;
      }

      bridge.attach(serviceExtension: () => caller, projectRoot: '/proj');

      // First poll (500 ms cadence) sees the pre-existing selection — primed,
      // not emitted.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(jumps, isEmpty);

      selected = <String, dynamic>{
        'result': <String, dynamic>{
          'creationLocation': <String, dynamic>{
            'file': 'file:///proj/lib/clicked.dart',
            'line': 42,
            'column': 7,
          },
        },
      };
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(jumps, hasLength(1));
      expect(jumps.single.line, 42);
    },
  );

  test('dedupe survives re-attach; detach clears it', () async {
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');
    events.add(_selectionEvent('file:///proj/lib/a.dart', 1, 1));
    await pumpEventQueue();
    expect(jumps, hasLength(1));

    // Re-attach keeps the last-seen key — the same location stays deduped.
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');
    events.add(_selectionEvent('file:///proj/lib/a.dart', 1, 1));
    await pumpEventQueue();
    expect(jumps, hasLength(1));

    // Detach clears it — the same location emits again after re-attach.
    await bridge.detach();
    bridge.attach(serviceExtension: () => null, projectRoot: '/proj');
    events.add(_selectionEvent('file:///proj/lib/a.dart', 1, 1));
    await pumpEventQueue();
    expect(jumps, hasLength(2));
  });
}

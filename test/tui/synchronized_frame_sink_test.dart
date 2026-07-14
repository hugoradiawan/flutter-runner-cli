import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:frun/src/presentation/tui/synchronized_frame_sink.dart';
import 'package:test/test.dart';

const String beginSync = '\x1b[?2026h';
const String endSync = '\x1b[?2026l';

/// Records everything the [SynchronizedFrameSink] pushes downstream so tests
/// can assert on write boundaries and ordering.
final class _RecordingSink implements IOSink {
  final List<String> writes = <String>[];
  final List<List<int>> adds = <List<int>>[];

  /// Interleaved log of operations ("write" / "add") to assert ordering.
  final List<String> ops = <String>[];
  int flushCount = 0;
  int closeCount = 0;

  @override
  Encoding encoding = utf8;

  @override
  void write(Object? object) {
    writes.add('$object');
    ops.add('write');
  }

  @override
  void writeln([Object? object = '']) => write('$object\n');

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void add(List<int> data) {
    adds.add(data);
    ops.add('add');
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      add(chunk);
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> flush() {
    flushCount++;
    return Future<void>.value();
  }

  @override
  Future<void> close() {
    closeCount++;
    return Future<void>.value();
  }

  @override
  Future<dynamic> get done => Future<void>.value();
}

void main() {
  late _RecordingSink inner;
  late SynchronizedFrameSink sink;

  setUp(() {
    inner = _RecordingSink();
    sink = SynchronizedFrameSink(inner);
  });

  test('coalesces synchronous writes into one downstream write', () async {
    sink.write('\x1b[1;1Hrow one\x1b[K');
    sink.write('\x1b[2;1Hrow two\x1b[K');
    sink.writeln('tail');
    expect(inner.writes, isEmpty,
        reason: 'nothing should reach the terminal mid-burst');

    await null; // pump the microtask queue

    expect(inner.writes, hasLength(1));
    expect(
      inner.writes.single,
      '\x1b[1;1Hrow one\x1b[K\x1b[2;1Hrow two\x1b[Ktail\n',
    );
  });

  test('separate bursts produce separate writes', () async {
    sink.write('frame1');
    await null;
    sink.write('frame2');
    await null;

    expect(inner.writes, <String>['frame1', 'frame2']);
  });

  test('syncUpdates: true brackets each batch in DEC 2026', () async {
    final syncInner = _RecordingSink();
    final syncSink = SynchronizedFrameSink(syncInner, syncUpdates: true);

    syncSink.write('frame1');
    await null;
    syncSink.write('frame2');
    await null;

    expect(syncInner.writes, <String>[
      '${beginSync}frame1$endSync',
      '${beginSync}frame2$endSync',
    ]);
  });

  test('flush drains synchronously and the leftover microtask is a no-op',
      () async {
    sink.write('frame');
    final pending = sink.flush();

    // Drained before the microtask queue was pumped.
    expect(inner.writes, <String>['frame']);

    await pending;
    await null; // scheduled microtask fires here

    expect(inner.writes, hasLength(1),
        reason: 'the leftover microtask must not emit a second write');
    expect(inner.flushCount, 1);
  });

  test('flush with empty buffer only flushes downstream', () async {
    await sink.flush();
    expect(inner.writes, isEmpty);
    expect(inner.flushCount, 1);
  });

  test('close drains and flushes but never closes the wrapped sink',
      () async {
    sink.write('bye');
    await sink.close();

    expect(inner.writes, <String>['bye']);
    expect(inner.flushCount, 1);
    expect(inner.closeCount, 0);

    sink.write('after close');
    await null;
    expect(inner.writes, hasLength(1),
        reason: 'writes after close are dropped');
  });

  test('add() drains buffered text first to preserve ordering', () {
    sink.write('a');
    sink.add(<int>[1, 2, 3]);

    expect(inner.ops, <String>['write', 'add']);
    expect(inner.writes, <String>['a']);
    expect(inner.adds, <List<int>>[
      <int>[1, 2, 3],
    ]);
  });

  test('empty writes never schedule output', () async {
    sink.write('');
    sink.write(null);
    await null;
    expect(inner.writes, isEmpty);
  });

  test('writeAll and writeCharCode are buffered like write', () async {
    sink.writeAll(<String>['a', 'b', 'c'], ',');
    sink.writeCharCode(0x21);
    await null;
    expect(inner.writes, <String>['a,b,c!']);
  });
}

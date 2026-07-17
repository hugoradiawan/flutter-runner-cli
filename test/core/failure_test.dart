import 'package:frun/src/core/error/failure.dart';
import 'package:test/test.dart';

class _TestFailure extends AppFailure {
  const _TestFailure({required super.message, super.cause, super.stackTrace});

  @override
  String get failureType => 'TestFailure';
}

void main() {
  test('toString includes type and message', () {
    const f = _TestFailure(message: 'it broke');
    expect(f.toString(), 'TestFailure(message: it broke)');
  });

  test('toString appends cause when present', () {
    const f = _TestFailure(message: 'it broke', cause: 'io error');
    expect(f.toString(), contains('cause: io error'));
  });

  test('toString appends the stack trace when present', () {
    final f = _TestFailure(
      message: 'it broke',
      stackTrace: StackTrace.fromString('#0 somewhere'),
    );
    expect(f.toString(), contains('#0 somewhere'));
  });
}

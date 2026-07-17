import 'package:frun/src/core/result.dart';
import 'package:test/test.dart';

void main() {
  const success = Success<String, int>(42);
  const failure = Failure<String, int>('boom');

  test('static factories build the right variants', () {
    expect(Result.success<String, int>(42), isA<Success<String, int>>());
    expect(Result.failure<String, int>('x'), isA<Failure<String, int>>());
  });

  test('isSuccess / isFailure', () {
    expect(success.isSuccess, isTrue);
    expect(success.isFailure, isFalse);
    expect(failure.isSuccess, isFalse);
    expect(failure.isFailure, isTrue);
  });

  test('when dispatches to the matching branch', () {
    expect(
      success.when(success: (v) => 'got $v', failure: (e) => 'err $e'),
      'got 42',
    );
    expect(
      failure.when(success: (v) => 'got $v', failure: (e) => 'err $e'),
      'err boom',
    );
  });

  test('fold dispatches to the matching branch', () {
    expect(success.fold((e) => 'err', (v) => v * 2), 84);
    expect(failure.fold((e) => 'err $e', (v) => 'ok'), 'err boom');
  });

  test('map transforms only the success value', () {
    expect((success.map((v) => '$v!') as Success<String, String>).value, '42!');
    final mappedFailure = failure.map((v) => '$v!');
    expect((mappedFailure as Failure<String, String>).error, 'boom');
  });

  test('mapFailure transforms only the error', () {
    final mapped = failure.mapFailure((e) => e.length);
    expect((mapped as Failure<int, int>).error, 4);
    final untouched = success.mapFailure((e) => e.length);
    expect((untouched as Success<int, int>).value, 42);
  });
}

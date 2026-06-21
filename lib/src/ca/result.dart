sealed class Result<F, S> {
  const Result();

  static Result<F, S> success<F, S>(S value) => Success<F, S>(value);

  static Result<F, S> failure<F, S>(F error) => Failure<F, S>(error);

  bool get isSuccess => this is Success<F, S>;
  bool get isFailure => this is Failure<F, S>;

  R when<R>({
    required R Function(S value) success,
    required R Function(F error) failure,
  }) => switch (this) {
    Success<F, S>(value: final S value) => success(value),
    Failure<F, S>(error: final F error) => failure(error),
  };

  R fold<R>(
    R Function(F error) onFailure,
    R Function(S value) onSuccess,
  ) => switch (this) {
    Success<F, S>(value: final S value) => onSuccess(value),
    Failure<F, S>(error: final F error) => onFailure(error),
  };

  Result<F, T> map<T>(T Function(S value) transform) => switch (this) {
    Success<F, S>(value: final S value) => Success<F, T>(transform(value)),
    Failure<F, S>(error: final F error) => Failure<F, T>(error),
  };

  Result<T, S> mapFailure<T>(T Function(F error) transform) => switch (this) {
    Success<F, S>(value: final S value) => Success<T, S>(value),
    Failure<F, S>(error: final F error) => Failure<T, S>(transform(error)),
  };
}

final class Success<F, S> extends Result<F, S> {
  const Success(this.value);

  final S value;
}

final class Failure<F, S> extends Result<F, S> {
  const Failure(this.error);

  final F error;
}

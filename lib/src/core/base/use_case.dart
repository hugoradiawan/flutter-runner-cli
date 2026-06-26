import '../result.dart' show Result;
import 'params.dart' show Params;

abstract class UseCase<F, S, P extends Params> {
  const UseCase();

  Future<Result<F, S>> call([P? params]);

  Future<Result<F, P?>> validate(P? params) async => Result.success(params);
}

abstract class StreamUseCase<F, S, P extends Params> {
  const StreamUseCase();

  Stream<Result<F, S>> call([P? params]);

  Future<Result<F, P?>> validate(P? params) async => Result.success(params);
}

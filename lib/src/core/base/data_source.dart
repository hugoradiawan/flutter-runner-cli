import '../error/failure.dart' show AppFailure;

abstract class DataSource<F extends AppFailure> {
  const DataSource();
}

abstract class RemoteDataSource<F extends AppFailure> extends DataSource<F> {
  const RemoteDataSource();
}

abstract class LocalDataSource<F extends AppFailure> extends DataSource<F> {
  const LocalDataSource();
}

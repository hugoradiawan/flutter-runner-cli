import '../error/failure.dart' show AppFailure;

abstract class DataSource<F extends AppFailure> {
  const DataSource();
}

abstract class LocalDataSource<F extends AppFailure> extends DataSource<F> {
  const LocalDataSource();
}
